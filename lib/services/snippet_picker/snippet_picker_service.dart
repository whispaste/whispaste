import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_provider.dart';
import '../../core/logging/app_logger.dart';
import '../../features/snippets/snippets_page.dart' show SnippetItem;
import '../floating_platform_service_base.dart';
import '../paste/paster.dart';
import '../telemetry_service.dart';
import 'snippet_picker_controller.dart';
import 'snippet_picker_events.dart';

final _log = AppLogger('SnippetPickerService');

/// Outcome of [SnippetPickerService.show] — distinguishes "panel is open"
/// from the two fall-through cases so the caller can react differently to
/// "the user has no snippets yet" (worth telling them about) versus "the
/// platform has no picker at all" (nothing the user can do mid-dictation).
enum SnippetPickerShowResult {
  /// Panel is open; the dictation was consumed by the picker.
  shown,

  /// Trigger matched but there are no snippets to offer — the caller falls
  /// back to the normal pipeline and should surface why the picker stayed
  /// closed.
  emptyList,

  /// No native picker on this platform — silent fallback to the normal
  /// pipeline.
  unavailable,
}

/// Manages the native Snippet-Picker panel lifecycle (dictation-automations
/// ticket 06).
///
/// Layer 3 — business logic, built on [FloatingPlatformServiceBase] exactly
/// like [FloatingButtonService]/[FloatingOverlayService]: [show] opens the
/// panel and returns immediately (see [SnippetPickerController] docs on why
/// this must not await the user's pick), and [onEvent] reacts to the
/// eventual selection asynchronously, entirely decoupled from the recording
/// pipeline that triggered [show].
///
/// **Never calls `paster.prime()`.** [_insert] deliberately calls
/// [Paster.paste] directly against whatever target the pipeline already
/// captured before recording started — re-priming here would either recapture
/// a stale target or, worse, clear it outright (native `captureTarget()`
/// clears the stored target whenever WhisPaste itself is frontmost, which it
/// is while this panel holds keyboard focus for search). [Paster.paste]
/// never calls [Paster.prime] either, so this holds regardless of which
/// native mechanism ends up delivering the snippet. This is the mechanism
/// behind ticket 06's "never triggers a re-capture" AC. The voice path
/// primes at `startRecording()`; the systemwide Snippet-Picker hotkey
/// (ticket 26, `RecordingOrchestrator.openSnippetPickerViaHotkey`) primes at
/// key-down, before calling [show] — this class must stay uninvolved in
/// priming for either caller.
class SnippetPickerService
    extends
        FloatingPlatformServiceBase<
          SnippetPickerController,
          SnippetPickerEvent
        > {
  /// The snippets shown by the most recent [show] call, keyed by id — used
  /// to resolve a selected id back to its body without a second DB read or
  /// round-tripping the body through the native event.
  Map<String, SnippetItem> _shown = const {};

  bool _isOpen = false;

  /// Whether the panel is currently open (a [show] call succeeded and
  /// neither a selection nor a cancellation event has arrived yet). Read by
  /// [RecordingOrchestrator.openSnippetPickerViaHotkey] (ticket 26) to avoid
  /// opening a second panel on a repeated hotkey press.
  bool get isOpen => _isOpen;

  @override
  SnippetPickerController? createController() =>
      ref.read(snippetPickerControllerProvider);

  @override
  Stream<SnippetPickerEvent> eventsFrom(SnippetPickerController controller) =>
      controller.events;

  @override
  Future<void> disposeController(SnippetPickerController controller) {
    _isOpen = false;
    return controller.dispose();
  }

  @override
  void onEvent(SnippetPickerEvent event) {
    switch (event) {
      case SnippetPickerItemSelected(:final id):
        _isOpen = false;
        unawaited(_insert(id));
      case SnippetPickerCancelled():
        _isOpen = false;
        _log.debug('Snippet-Picker cancelled without a selection');
      case SnippetPickerRenderEngineDiagnostic(:final message, :final isError):
        if (isError) {
          _log.error('Snippet-Picker render engine: $message');
        } else {
          _log.debug('Snippet-Picker render engine: $message');
        }
    }
  }

  /// Opens the panel near the current mouse position with [items].
  ///
  /// The native host reads the cursor position itself (see
  /// [SnippetPickerController.show] docs) — this layer only forwards the
  /// item list.
  ///
  /// Shows nothing when the platform is unsupported
  /// ([SnippetPickerShowResult.unavailable]) or [items] is empty
  /// ([SnippetPickerShowResult.emptyList]) — the caller falls back to the
  /// normal dictation pipeline in both cases, never silently discarding the
  /// dictation.
  Future<SnippetPickerShowResult> show({
    required List<SnippetItem> items,
  }) async {
    final c = controller;
    if (c == null) return SnippetPickerShowResult.unavailable;
    if (items.isEmpty) return SnippetPickerShowResult.emptyList;

    _shown = {for (final item in items) item.id: item};
    await c.show(
      items: [
        for (final item in items)
          {'id': item.id, 'title': item.title, 'body': item.body},
      ],
    );
    _isOpen = true;
    return SnippetPickerShowResult.shown;
  }

  Future<void> _insert(String id) async {
    final snippet = _shown[id];
    if (snippet == null) {
      _log.warning('Snippet-Picker selected unknown id: $id');
      return;
    }
    final paster = ref.read(pasterProvider);
    if (paster == null) return;

    final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
    final options = PasteOptions(
      autoPasteDelayMs: settings.behavior.autoPasteDelay,
      blocklist: settings.behavior.autoPasteBlocklist,
    );
    final outcome = await paster.paste(snippet.body, options);
    // paste() may still be mid clipboard-restore delay (≥500ms) when the
    // panel/provider is disposed in the meantime — guard the post-await
    // ref use per Riverpod's own advice.
    if (!ref.mounted) return;
    if (outcome == PasteOutcome.success) {
      ref
          .read(telemetrySessionAggregatorProvider)
          .count(category: 'snippets', action: 'insert');
    } else {
      _log.warning('Snippet insert failed: $outcome');
    }
  }
}

final snippetPickerServiceProvider =
    NotifierProvider<SnippetPickerService, void>(SnippetPickerService.new);
