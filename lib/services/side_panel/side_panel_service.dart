import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_provider.dart';
import '../../core/data/history_providers.dart';
import '../../core/logging/app_logger.dart';
import '../../features/snippets/snippets_page.dart'
    show SnippetItem, snippetsProvider;
import '../clipboard_history/clipboard_history_entry.dart';
import '../clipboard_history/clipboard_history_provider.dart';
import '../floating_platform_service_base.dart';
import '../paste/paster.dart';
import '../telemetry_service.dart';
import 'side_panel_controller_interface.dart';
import 'side_panel_controller_provider.dart';
import 'side_panel_events.dart';
import 'side_panel_snapshot.dart';

final _log = AppLogger('SidePanelService');

/// Manages the native side-panel lifecycle (clipboard-quick-paste,
/// issues 03-06).
///
/// Layer 3, built on [FloatingPlatformServiceBase] exactly like
/// `SnippetPickerService`/`FloatingButtonService`. Watches the three source
/// providers (history, snippets, clipboard history) and pushes a fresh
/// [SidePanelSnapshot] to the native host whenever any of them change while
/// the panel is open, and resolves row clicks back to their content before
/// pasting.
///
/// **Never calls `paster.prime()` from a row click** -- same reasoning as
/// `SnippetPickerService._insert`: the paste target is captured exactly
/// once, in [open], before the panel takes keyboard/mouse focus away from
/// whatever app the user was in. Re-priming on click would capture
/// WhisPaste's own window instead.
class SidePanelService
    extends FloatingPlatformServiceBase<SidePanelController, SidePanelEvent> {
  Map<String, String> _transcriptionContent = const {};
  Map<String, String> _snippetContent = const {};
  Map<String, ClipboardHistoryEntry> _clipboardEntries = const {};

  bool _isOpen = false;

  @override
  SidePanelController? createController() =>
      ref.read(sidePanelControllerProvider);

  @override
  Stream<SidePanelEvent> eventsFrom(SidePanelController controller) =>
      controller.events;

  @override
  Future<void> disposeController(SidePanelController controller) {
    _isOpen = false;
    return controller.dispose();
  }

  @override
  void onControllerReady(SidePanelController controller) {
    ref.listen(historyEntriesProvider, (_, _) => unawaited(_pushIfOpen()));
    ref.listen(snippetsProvider, (_, _) => unawaited(_pushIfOpen()));
    ref.listen(clipboardHistoryProvider, (_, _) => unawaited(_pushIfOpen()));
  }

  @override
  void onEvent(SidePanelEvent event) {
    switch (event) {
      case SidePanelRowClicked(:final section, :final id):
        _log.info('Row clicked: ${section.name}/$id');
        unawaited(_activate(section, id));
      case SidePanelHoverLeft():
        unawaited(close());
      case SidePanelHoverEntered():
        unawaited(open());
    }
  }

  /// Captures the paste target and shows the panel with a fresh snapshot.
  ///
  /// Mirrors `RecordingOrchestrator.openSnippetPickerViaHotkey`'s
  /// prime-before-show sequencing: capture must happen while the app the
  /// user was working in is still frontmost, before this panel's own window
  /// appears and steals that.
  Future<void> open() async {
    final c = controller;
    if (c == null) return;
    _log.info('open() called');
    await ref.read(pasterProvider)?.prime();
    await _awaitInitialData();
    _isOpen = true;
    await c.updateSnapshot(_buildSnapshot(visible: true));
  }

  /// Waits for the history/snippets streams' first value.
  ///
  /// [_buildSnapshot] reads both via `ref.read(...).value`, which is null
  /// while a [StreamProvider]/[AsyncNotifierProvider] is still in its
  /// initial loading state. Without this, the first panel open after a cold
  /// app start (before anything else has watched these providers) shows an
  /// empty transcriptions/snippets list that pops in a moment later once the
  /// stream's first event lands -- exactly the flicker the panel exists to
  /// avoid. `onControllerReady` already holds a live `ref.listen` on both by
  /// the time `open()` can run, so these reads resolve instead of hanging.
  ///
  /// Swallows a failing read instead of propagating it: if the history or
  /// snippets query throws (e.g. a DB error), [_buildSnapshot] falls back to
  /// an empty list for that source via `.value ?? const []`. Letting the
  /// error escape here would leave `open()` never setting `_isOpen = true`
  /// and the panel never appearing at all, which is worse than one section
  /// starting empty.
  Future<void> _awaitInitialData() async {
    try {
      await Future.wait([
        ref.read(historyEntriesProvider.future),
        ref.read(snippetsProvider.future),
      ]);
    } catch (e, st) {
      _log.warning(
        'Initial history/snippets load failed, opening anyway',
        e,
        st,
      );
    }
  }

  /// Hides the panel. The next [open] rebuilds fresh content, so nothing
  /// needs to be cached across a close.
  Future<void> close() async {
    final c = controller;
    if (c == null || !_isOpen) return;
    _log.info('close() called');
    _isOpen = false;
    await c.updateSnapshot(_buildSnapshot(visible: false));
  }

  Future<void> _pushIfOpen() async {
    final c = controller;
    if (c == null || !_isOpen) return;
    await c.updateSnapshot(_buildSnapshot(visible: true));
  }

  SidePanelSnapshot _buildSnapshot({required bool visible}) {
    final history = ref.read(historyEntriesProvider).value ?? const [];
    final snippets = ref.read(snippetsProvider).value ?? const <SnippetItem>[];
    final clipboard = ref.read(clipboardHistoryProvider);

    _transcriptionContent = {for (final e in history) e.id: e.content};
    _snippetContent = {for (final s in snippets) s.id: s.body};
    _clipboardEntries = {
      for (var i = 0; i < clipboard.length; i++) 'clip-$i': clipboard[i],
    };

    return SidePanelSnapshot(
      visible: visible,
      transcriptions: [
        for (final e in history)
          SidePanelRow(
            id: e.id,
            title: e.title.isNotEmpty ? e.title : e.content,
            subtitle: _timeLabel(e.timestamp),
            colorSlot: e.colorSlot,
          ),
      ],
      snippets: [
        for (final s in snippets) SidePanelRow(id: s.id, title: s.title),
      ],
      clipboardHistory: [
        for (final entry in _clipboardEntries.entries)
          _rowFor(entry.key, entry.value),
      ],
    );
  }

  static SidePanelRow _rowFor(String id, ClipboardHistoryEntry entry) {
    if (entry.kind == ClipboardEntryKind.image) {
      return SidePanelRow(
        id: id,
        title: 'Image',
        kind: SidePanelRowKind.image,
        imageBytes: entry.imageBytes,
      );
    }
    return SidePanelRow(id: id, title: entry.textValue ?? '');
  }

  static String _timeLabel(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  Future<void> _activate(SidePanelSection section, String id) async {
    final content = switch (section) {
      SidePanelSection.transcriptions => _transcriptionContent[id],
      SidePanelSection.snippets => _snippetContent[id],
      SidePanelSection.clipboardHistory => _clipboardEntries[id]?.textValue,
    };
    if (content == null) {
      _log.warning(
        'Side panel row activated with unresolved content: '
        '${section.name}/$id',
      );
      return;
    }

    final paster = ref.read(pasterProvider);
    if (paster == null) {
      // Silent from the user's perspective otherwise: no paste target, no
      // panel close, nothing -- exactly the "I clicked and nothing
      // happened" symptom, so this is worth a warning even though it's
      // expected to be rare (desktopPasteControllerProvider unavailable).
      _log.warning(
        'Row activation aborted: no paster available for '
        '${section.name}/$id',
      );
      return;
    }

    final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
    final options = PasteOptions(
      autoPasteDelayMs: settings.behavior.autoPasteDelay,
      blocklist: settings.behavior.autoPasteBlocklist,
    );
    final stopwatch = Stopwatch()..start();
    final outcome = await paster.paste(content, options);
    _log.info(
      'Row activation paste() for ${section.name}/$id returned $outcome '
      'after ${stopwatch.elapsedMilliseconds}ms',
    );
    // paste() may still be mid clipboard-restore delay (>=500ms) when the
    // panel/provider is disposed in the meantime -- guard the post-await ref
    // use per Riverpod's own advice (same guard as SnippetPickerService).
    if (!ref.mounted) return;
    if (outcome == PasteOutcome.success) {
      ref
          .read(telemetrySessionAggregatorProvider)
          .count(category: 'side_panel', action: 'insert_${section.name}');
      unawaited(close());
    } else {
      _log.warning('Side panel insert failed: $outcome');
    }
  }
}

final sidePanelServiceProvider = NotifierProvider<SidePanelService, void>(
  SidePanelService.new,
);
