/// Lifecycle controller for the local automation API (ticket 03,
/// `internal-notes`).
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
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../../core/config/settings_provider.dart';
import '../../core/data/database.dart';
import '../../core/data/history_providers.dart';
import '../../core/logging/app_logger.dart';
import '../../features/history/data/history_lock.dart';
import '../../core/recording/recording_state.dart'
    show isDictationBusy, recordingPhaseProvider;
import '../../features/history/data/history_detail_provider.dart';
import '../../features/notes/data/notes_actions.dart';
import '../snippet_picker/snippet_picker_service.dart';
import '../transcription/transcriber.dart';
import 'automation_api_dictation_status_routes.dart';
import 'automation_api_pipeline.dart';
import 'automation_api_port.dart';
import 'automation_api_history_routes.dart';
import 'automation_api_notes_routes.dart';
import 'automation_api_router.dart';
import 'automation_api_server.dart';
import 'automation_api_snippet_list_routes.dart';
import 'automation_api_snippet_routes.dart';
import 'automation_api_status_routes.dart';
import 'automation_api_token_store.dart';
import 'automation_api_transcribe_routes.dart';
import 'multiline_paste_confirmation.dart';
import 'automation_snippet_render.dart';

export 'automation_api_port.dart' show kAutomationApiDefaultPort;

final _log = AppLogger('AutomationApiController');

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
    Future<DictationTriggerResult> Function(
      Ref ref, {
      bool wait,
      String? language,
      String? smartModePreset,
      double? silenceTimeout,
    })?
    triggerDictation,
  }) : _server = server ?? AutomationApiServer(),
       _triggerDictation = triggerDictation ?? _unconfiguredTriggerDictation;

  final AutomationApiServer _server;
  final int port;
  final Future<DictationTriggerResult> Function(
    Ref ref, {
    bool wait,
    String? language,
    String? smartModePreset,
    double? silenceTimeout,
  })
  _triggerDictation;

  /// Safe-fails loudly if `main.dart` forgot to override this provider with
  /// the real use case — tests always pass their own [triggerDictation]
  /// (see `test/services/automation_api/automation_api_controller_test.dart`),
  /// so this only ever fires from a genuine production wiring mistake.
  static Future<DictationTriggerResult> _unconfiguredTriggerDictation(
    Ref ref, {
    bool wait = false,
    String? language,
    String? smartModePreset,
    double? silenceTimeout,
  }) => Future.error(
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

  /// Serializes [syncWithSettings]/[shutdown] against each other. Both call
  /// into [_start]/[_stop], which are not reentrant (they mutate the shared
  /// [_server] and [state] across several `await` points) — without this,
  /// `app.dart`'s settings listener firing a second time (e.g. the autosave
  /// scheduler's debounced write-back touching an unrelated section) while
  /// the first call's [_start] is still awaiting its token/bind work would
  /// run a second, concurrent [_start] that either double-binds a port or
  /// (once the first bind has landed) fails all of its own fallback
  /// attempts against the now-already-running [_server] and overwrites the
  /// correctly-running state with a false "error".
  Future<void> _queue = Future.value();

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = _queue.then((_) => operation());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Reconciles the running server with `settings.automationApi.enabled`.
  /// A no-op when the desired state already matches the actual one, so
  /// callers can invoke this on every settings change without worrying
  /// about redundant start/stop churn.
  Future<void> syncWithSettings(AppSettings settings) =>
      _serialized(() => _syncWithSettingsSerialized(settings));

  Future<void> _syncWithSettingsSerialized(AppSettings settings) async {
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
      await _stop(reason: 'settings disabled');
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

    final handler = buildAutomationApiHandler(
      currentToken: tokenStore.readToken,
      routeGroups: [
        dictationTriggerRoutes(
          triggerDictation:
              ({wait = false, language, smartModePreset, silenceTimeout}) =>
                  _triggerDictation(
                    ref,
                    wait: wait,
                    language: language,
                    smartModePreset: smartModePreset,
                    silenceTimeout: silenceTimeout,
                  ),
        ),
        dictationStatusRoutes(readStatus: _readDictationStatus),
        historyLatestRoutes(
          fetchLatestEntry: _fetchLatestHistoryEntry,
          isHistoryLocked: () => ref.read(historyContentHiddenProvider),
        ),
        snippetInsertRoutes(insertSnippetByName: _insertSnippetByName),
        automationStatusRoutes(readStatus: _readApiStatus),
        automationNotesRoutes(
          listNotes: _listNotes,
          createNote: _createNote,
          isHistoryLocked: () => ref.read(historyContentHiddenProvider),
        ),
        automationSnippetCatalogRoutes(
          listSnippets: _listSnippets,
          renderSnippet: _renderSnippet,
        ),
        automationTranscribeRoutes(transcribe: _transcribeWav),
      ],
    );

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

  /// [reason] names the caller in the log (settings vs. app shutdown); a
  /// captured stack trace did that before and read like a crash in every
  /// shutdown log.
  Future<void> _stop({required String reason}) async {
    _log.info('_stop: stopping server ($reason, was ${state.runState})');
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
  /// [historyEntriesProvider] and [historyDetailProvider] are both read via
  /// a one-shot [Ref.listen] (rather than `.future`/`ref.read`) because
  /// neither provider has anything else keeping it alive on this headless
  /// path (the History page normally does that while it's open):
  /// [historyEntriesProvider]'s underlying stream subscription is paused
  /// without an active listener, so `ref.read(provider.future)` alone would
  /// await forever; [historyDetailProvider] is `autoDispose` and can be
  /// torn down between its own internal `await`s (its `build()` reads the
  /// database twice) once nothing is listening — a bare `ref.read(...future)`
  /// doesn't count, and hit exactly that "Ref used after dispose" failure in
  /// production once the DB round-trip (a real background isolate, unlike
  /// tests' in-memory one) took long enough for the gap to matter.
  Future<Map<String, Object?>?> _fetchLatestHistoryEntry() async {
    final entries = await _readOnce(historyEntriesProvider);
    if (entries.isEmpty) return null;

    final detail = await _readOnce(historyDetailProvider(entries.first.id));
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
  /// [_fetchLatestHistoryEntry]'s doc comment on why `.future`/`ref.read`
  /// alone is not enough here.
  Future<T> _readOnce<T>(ProviderListenable<AsyncValue<T>> provider) {
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

  /// Backs `GET /v1/dictation/status` — reports the current recording phase
  /// so automation callers can check before triggering (e.g. avoid firing a
  /// `POST /v1/dictation/trigger` that would unexpectedly *stop* an
  /// already-running recording instead of starting a new one). Reads the
  /// existing [recordingPhaseProvider] directly rather than through
  /// [_triggerDictation]'s injection seam — safe here because
  /// `core/recording/recording_state.dart` has no import path back to this
  /// file (see the doc comment at the top of this file for why
  /// `recording_orchestrator.dart` itself can't be imported directly).
  Map<String, Object?> _readDictationStatus() {
    final phase = ref.read(recordingPhaseProvider);
    return {'phase': phase.name, 'busy': isDictationBusy(phase)};
  }

  /// Backs `GET /v1/status`: API version, dictation phase, history lock.
  Map<String, Object?> _readApiStatus() => {
    'dictation': _readDictationStatus(),
    'history_locked': ref.read(historyContentHiddenProvider),
  };

  /// Backs `GET /v1/notes`: newest-first, pinned first, as the Notizen page
  /// orders them. Reads the stream once; never writes.
  Future<List<Map<String, Object?>>> _listNotes(int limit) async {
    final notes = await ref.read(historyDatabaseProvider).watchNotes().first;
    return [for (final note in notes.take(limit)) _noteJson(note)];
  }

  /// Backs `POST /v1/notes`. Uses a [NotesActions] without the app's change
  /// notifier, so an API write never fires a `note.changed` hook (this is
  /// the loop guard: a hook that writes a note cannot re-trigger itself).
  Future<Map<String, Object?>> _createNote(String content) async {
    final db = ref.read(historyDatabaseProvider);
    final actions = NotesActions(db);
    final created = await actions.create();
    await actions.save(created.id, content);
    final stored = await db.getNote(created.id);
    return _noteJson(stored ?? created);
  }

  Map<String, Object?> _noteJson(Note note) => {
    'id': note.id,
    'content': note.content,
    'pinned': note.pinned,
    'updated_at': note.updatedAt.toIso8601String(),
  };

  /// Backs `GET /v1/snippets`: every snippet by title, with its kind and
  /// declared field names. Read-only.
  Future<List<Map<String, Object?>>> _listSnippets() async {
    final rows = await ref
        .read(historyDatabaseProvider)
        .readAllSnippetsWithFields();
    return [
      for (final row in rows)
        {'name': row.row.title, 'kind': row.row.kind, 'fields': row.fields},
    ];
  }

  /// Backs `POST /v1/snippets/render`. Returns the text only; the paste
  /// path is deliberately not involved. `null` means no snippet has that
  /// exact title.
  Future<SnippetRenderOutcome?> _renderSnippet(
    String name,
    Map<String, String> values,
  ) async {
    final rows = await ref
        .read(historyDatabaseProvider)
        .readAllSnippetsWithFields();
    for (final row in rows) {
      if (row.row.title != name) continue;
      return renderSnippetBody(
        kind: row.row.kind,
        body: row.row.body,
        fieldNames: row.fields,
        values: values,
      );
    }
    return null;
  }

  /// Backs `POST /v1/transcriptions`: the same transcriber adapter the
  /// hotkey path uses, prepared and released around one call. Only WAV
  /// bytes reach this point; the route checks the format first. A dictation
  /// that is recording or transcribing owns the transcriber, so the call is
  /// refused as busy instead of queued behind it.
  Future<String> _transcribeWav(List<int> wavBytes) async {
    if (isDictationBusy(ref.read(recordingPhaseProvider))) {
      throw const AutomationTranscriptionBusyException();
    }
    final transcriber = ref.read(transcriberProvider);
    await transcriber.prepare();
    // A dictation may have started while prepare() was awaited. Re-check
    // before using the transcriber, so the call never runs beside it.
    if (isDictationBusy(ref.read(recordingPhaseProvider))) {
      transcriber.release();
      throw const AutomationTranscriptionBusyException();
    }
    try {
      return await transcriber.transcribe(wavBytes);
    } finally {
      transcriber.release();
    }
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
        .insertByName(
          name,
          confirmMultiline: (body) => ref
              .read(multilinePasteConfirmationProvider.notifier)
              .request(body, timeout: kAutomationPreviewWait),
        );
    switch (result) {
      case SnippetInsertByNameResult.success:
        return AutomationApiSnippetInsertOutcome.success;
      case SnippetInsertByNameResult.notFound:
        return AutomationApiSnippetInsertOutcome.notFound;
      case SnippetInsertByNameResult.interactiveNotSupported:
        return AutomationApiSnippetInsertOutcome.interactiveNotSupported;
      case SnippetInsertByNameResult.pasteFailed:
        return AutomationApiSnippetInsertOutcome.pasteFailed;
      case SnippetInsertByNameResult.previewCancelled:
        return AutomationApiSnippetInsertOutcome.previewCancelled;
    }
  }

  /// Unconditionally stops the server, regardless of the current settings
  /// value — used by `graceful_shutdown.dart` on app quit, where the intent
  /// is "close every socket now", not "reconcile with settings". Goes
  /// through the same [_serialized] queue as [syncWithSettings] so it can't
  /// race an in-flight [_start].
  Future<void> shutdown() => _serialized(() => _stop(reason: 'app shutdown'));

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
