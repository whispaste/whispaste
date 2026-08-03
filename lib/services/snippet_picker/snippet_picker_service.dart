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
/// [Paster.typeText] directly against whatever target the pipeline already
/// captured before recording started — re-priming here would either recapture
/// a stale target or, worse, clear it outright (native `captureTarget()`
/// clears the stored target whenever WhisPaste itself is frontmost, which it
/// is while this panel holds keyboard focus for search). This is the
/// mechanism behind ticket 06's "never triggers a re-capture" AC.
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

  @override
  SnippetPickerController? createController() =>
      ref.read(snippetPickerControllerProvider);

  @override
  Stream<SnippetPickerEvent> eventsFrom(SnippetPickerController controller) =>
      controller.events;

  @override
  Future<void> disposeController(SnippetPickerController controller) =>
      controller.dispose();

  @override
  void onEvent(SnippetPickerEvent event) {
    switch (event) {
      case SnippetPickerItemSelected(:final id):
        unawaited(_insert(id));
      case SnippetPickerCancelled():
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
  /// Returns `false` (and shows nothing) when the platform is unsupported or
  /// [items] is empty — the caller falls back to the normal dictation
  /// pipeline in both cases, same "never silently discard the dictation"
  /// contract as [AutomationDispatchService].
  Future<bool> show({required List<SnippetItem> items}) async {
    final c = controller;
    if (c == null || items.isEmpty) return false;

    _shown = {for (final item in items) item.id: item};
    await c.show(
      items: [
        for (final item in items)
          {'id': item.id, 'title': item.title, 'body': item.body},
      ],
    );
    return true;
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
    final outcome = await paster.typeText(
      snippet.body,
      PasteOptions(
        autoPasteDelayMs: settings.behavior.autoPasteDelay,
        blocklist: settings.behavior.autoPasteBlocklist,
      ),
    );
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
