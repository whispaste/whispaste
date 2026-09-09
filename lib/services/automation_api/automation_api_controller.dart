/// Lifecycle controller for the local automation API (ticket 03,
/// `.scratch/local-automation-api/`).
///
/// Ties together [AutomationApiServer] (transport), [AutomationApiRouter]
/// (routes), [bearerTokenAuth] (auth), and [AutomationApiTokenStore]
/// (credential persistence) behind one Riverpod [Notifier] the settings UI
/// and app startup/shutdown both drive:
///   - `app.dart` calls [syncWithSettings] whenever [AppSettings] changes,
///     starting/stopping the server to match `settings.automationApi.enabled`
///     (single-instance, same process, tied to app lifecycle — no separate
///     background service).
///   - The settings section reads [state] to show status/port/token and
///     calls [regenerateToken].
///
/// The dictation-trigger route calls [triggerDictation], which `main.dart`
/// wires to the exact use case the main hotkey calls
/// (`RecordingOrchestrator.toggleRecording`) via a provider override — so no
/// dictation logic is duplicated in the HTTP layer. This file deliberately
/// does not import `recording_orchestrator.dart` itself: that file (via
/// `system_attention_service.dart`) imports
/// `core/platform/macos_lifecycle_channel.dart`, which imports
/// `graceful_shutdown.dart`, which imports *this* file to call [shutdown] —
/// importing `recording_orchestrator.dart` here would close that into an
/// import cycle. Injecting the trigger function instead (same seam
/// `RecordingTriggerHandler` uses for the hotkey path, see
/// `lib/services/recording_trigger_handler.dart` and its wiring in
/// `lib/widgets/service_bootstrap.dart`) keeps this module decoupled.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shelf/shelf.dart';

import '../../core/config/settings_provider.dart';
import '../../core/data/history_providers.dart';
import '../../core/logging/app_logger.dart';
import '../../features/history/data/history_detail_provider.dart';
import '../snippet_picker/snippet_picker_service.dart';
import 'automation_api_auth_middleware.dart';
import 'automation_api_history_routes.dart';
import 'automation_api_router.dart';
import 'automation_api_server.dart';
import 'automation_api_snippet_routes.dart';
import 'automation_api_token_store.dart';

final _log = AppLogger('AutomationApiController');

/// Default port the automation API targets when the user hasn't set
/// [AutomationApiSettings.customPort] — high enough to avoid the most
/// common local dev-server collisions (3000/5173/8080/…).
///
/// This is only the *first* port tried: if binding to the target port
/// (`customPort ?? kAutomationApiDefaultPort`) fails — most commonly
/// `EADDRINUSE` — [AutomationApiController] automatically tries the next
/// [kAutomationApiPortFallbackAttempts] consecutive ports before giving up.
const kAutomationApiDefaultPort = 8765;

/// Number of consecutive ports (starting at the target port) that
/// [AutomationApiController] tries to bind before entering
/// [AutomationApiRunState.error].
const kAutomationApiPortFallbackAttempts = 20;

enum AutomationApiRunState { stopped, running, error }

class AutomationApiState {
  const AutomationApiState({
    this.runState = AutomationApiRunState.stopped,
    this.port,
    this.requestedPort,
    this.token,
  });

  final AutomationApiRunState runState;

  /// The bound port while [runState] is `running`; `null` otherwise.
  final int? port;

  /// The target port (`customPort ?? kAutomationApiDefaultPort`) the
  /// current start attempt was configured for — set whenever [runState] is
  /// `running` or `error`, `null` while `stopped`. Differs from [port] only
  /// when the target was already taken and a fallback port bound instead.
  final int? requestedPort;

  /// The current bearer token, once one has ever been generated — kept
  /// visible across a stop/start cycle so settings can still show/copy it
  /// while the server is off.
  final String? token;

  bool get isRunning => runState == AutomationApiRunState.running;
}

class AutomationApiController extends Notifier<AutomationApiState> {
  AutomationApiController({
    AutomationApiServer? server,
    this.port = kAutomationApiDefaultPort,
    Future<void> Function(Ref ref)? triggerDictation,
  }) : _server = server ?? AutomationApiServer(),
       _triggerDictation = triggerDictation ?? _unconfiguredTriggerDictation;

  final AutomationApiServer _server;
  final int port;
  final Future<void> Function(Ref ref) _triggerDictation;

  /// Safe-fails loudly if `main.dart` forgot to override this provider with
  /// the real use case — tests always pass their own [triggerDictation]
  /// (see `test/services/automation_api/automation_api_controller_test.dart`),
  /// so this only ever fires from a genuine production wiring mistake.
  static Future<void> _unconfiguredTriggerDictation(Ref ref) => Future.error(
    StateError(
      'AutomationApiController.triggerDictation was never configured — '
      'override automationApiControllerProvider at app startup.',
    ),
  );

  @override
  AutomationApiState build() {
    ref.onDispose(() {
      unawaited(_server.stop());
    });
    return const AutomationApiState();
  }

  /// Reconciles the running server with `settings.automationApi.enabled`.
  /// A no-op when the desired state already matches the actual one, so
  /// callers can invoke this on every settings change without worrying
  /// about redundant start/stop churn.
  Future<void> syncWithSettings(AppSettings settings) async {
    final shouldRun = settings.automationApi.enabled;
    _log.info(
      'syncWithSettings: shouldRun=$shouldRun currentRunState=${state.runState} '
      'serverIsRunning=${_server.isRunning}',
    );
    if (!shouldRun) {
      // `_server.isRunning` only ever reflects a *successful* bind, so it
      // stays false throughout a failed start (state.runState == error).
      // Comparing shouldRun against it alone would short-circuit here and
      // never call _stop(), leaving that error state stuck forever even
      // though the setting is now off. Compare against our own state
      // instead — it's the only thing that actually tracks "error".
      if (state.runState == AutomationApiRunState.stopped) return;
      _log.info('syncWithSettings: stopping (settings.enabled=false)');
      await _stop();
      return;
    }
    if (_server.isRunning) return;
    _log.info('syncWithSettings: starting (settings.enabled=true)');
    await _start(settings);
  }

  Future<void> _start(AppSettings settings) async {
    final tokenStore = ref.read(automationApiTokenStoreProvider);
    var token = await tokenStore.readToken();
    token ??= await tokenStore.regenerate();

    final router = buildAutomationApiRouter([
      dictationTriggerRoutes(triggerDictation: () => _triggerDictation(ref)),
      historyLatestRoutes(fetchLatestEntry: _fetchLatestHistoryEntry),
      snippetInsertRoutes(insertSnippetByName: _insertSnippetByName),
    ]);
    final handler = const Pipeline()
        .addMiddleware(bearerTokenAuth(currentToken: tokenStore.readToken))
        .addHandler(router.handler);

    final targetPort = settings.automationApi.customPort ?? port;

    // Try the target port first, then fall back to the next consecutive
    // ports (most commonly needed after `EADDRINUSE`) before giving up —
    // see the doc comment on [kAutomationApiPortFallbackAttempts].
    for (
      var attempt = 0;
      attempt < kAutomationApiPortFallbackAttempts;
      attempt++
    ) {
      try {
        final boundPort = await _server.start(
          port: targetPort + attempt,
          handler: handler,
        );
        state = AutomationApiState(
          runState: AutomationApiRunState.running,
          port: boundPort,
          requestedPort: targetPort,
          token: token,
        );
        _log.info('_start: bound port $boundPort (requested $targetPort)');
        return;
      } catch (e) {
        // Bind failed (most likely the port is already in use) — log at
        // `debug` (this is the *expected* path whenever the target port is
        // taken, not an error) and try the next one.
        _log.debug('Bind to port ${targetPort + attempt} failed', e);
      }
    }

    state = AutomationApiState(
      runState: AutomationApiRunState.error,
      requestedPort: targetPort,
      token: token,
    );
    _log.warning(
      '_start: exhausted all $kAutomationApiPortFallbackAttempts fallback '
      'ports starting at $targetPort',
    );
  }

  Future<void> _stop() async {
    _log.info(
      '_stop: stopping server (was ${state.runState})',
      null,
      StackTrace.current,
    );
    await _server.stop();
    state = AutomationApiState(
      runState: AutomationApiRunState.stopped,
      token: state.token,
    );
  }

  /// Backs `GET /v1/history/latest` (ticket 04). "Most recent" is exactly
  /// the order the History feature itself already shows
  /// ([historyEntriesProvider]: pinned first, then newest-timestamp) — its
  /// first entry, if any — and the entry payload is read through
  /// [historyDetailProvider], the same detail-panel data source the History
  /// UI uses, so no history query logic is duplicated here.
  ///
  /// [historyEntriesProvider] is read via a one-shot [Ref.listen] (rather
  /// than `.future`) because a `StreamProvider`'s underlying subscription is
  /// paused while it has no active listener — `ref.read(provider.future)`
  /// alone never becomes one, so it would await forever on a provider
  /// nothing else in this process is currently watching (as this endpoint
  /// is, whenever the History page itself is closed).
  Future<Map<String, Object?>?> _fetchLatestHistoryEntry() async {
    final entries = await _readOnce(historyEntriesProvider);
    if (entries.isEmpty) return null;

    final detail = await ref.read(
      historyDetailProvider(entries.first.id).future,
    );
    final entry = detail.entry;
    return {
      'id': entry.id,
      'title': entry.title,
      'content': entry.content,
      'timestamp': entry.timestamp.toIso8601String(),
      'tags': [for (final tag in detail.tags) tag.name],
    };
  }

  /// Resolves to [provider]'s next emitted value, holding an active
  /// listener for exactly long enough to receive it — see
  /// [_fetchLatestHistoryEntry]'s doc comment on why `.future` alone is not
  /// enough for a `StreamProvider`.
  Future<T> _readOnce<T>(StreamProvider<T> provider) {
    final completer = Completer<T>();
    final subscription = ref.listen<AsyncValue<T>>(provider, (previous, next) {
      next.when(
        data: (value) {
          if (!completer.isCompleted) completer.complete(value);
        },
        error: (error, stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
        },
        loading: () {},
      );
    }, fireImmediately: true);
    return completer.future.whenComplete(subscription.close);
  }

  /// Backs `POST /v1/snippets/insert` (ticket 04) — delegates entirely to
  /// [SnippetPickerService.insertByName], the same lookup-and-paste path a
  /// Snippet-Picker selection uses, and maps its result onto the
  /// HTTP-agnostic [AutomationApiSnippetInsertOutcome] the route file
  /// expects.
  Future<AutomationApiSnippetInsertOutcome> _insertSnippetByName(
    String name,
  ) async {
    final result = await ref
        .read(snippetPickerServiceProvider.notifier)
        .insertByName(name);
    switch (result) {
      case SnippetInsertByNameResult.success:
        return AutomationApiSnippetInsertOutcome.success;
      case SnippetInsertByNameResult.notFound:
        return AutomationApiSnippetInsertOutcome.notFound;
      case SnippetInsertByNameResult.interactiveNotSupported:
        return AutomationApiSnippetInsertOutcome.interactiveNotSupported;
      case SnippetInsertByNameResult.pasteFailed:
        return AutomationApiSnippetInsertOutcome.pasteFailed;
    }
  }

  /// Unconditionally stops the server, regardless of the current settings
  /// value — used by `graceful_shutdown.dart` on app quit, where the intent
  /// is "close every socket now", not "reconcile with settings".
  Future<void> shutdown() => _stop();

  /// Generates a fresh token, immediately invalidating the previous one —
  /// the auth middleware reads the token store on every request, so this
  /// takes effect without a server restart. Returns the new token for the
  /// settings UI to display/copy.
  Future<String> regenerateToken() async {
    final tokenStore = ref.read(automationApiTokenStoreProvider);
    final token = await tokenStore.regenerate();
    state = AutomationApiState(
      runState: state.runState,
      port: state.port,
      requestedPort: state.requestedPort,
      token: token,
    );
    return token;
  }
}

final automationApiControllerProvider =
    NotifierProvider<AutomationApiController, AutomationApiState>(
      AutomationApiController.new,
    );
