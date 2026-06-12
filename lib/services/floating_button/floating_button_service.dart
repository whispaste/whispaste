import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/navigation/page_state.dart' show activePageProvider;
import '../../core/config/settings_provider.dart';
import '../../core/data/database.dart';
import '../../core/data/history_providers.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/logging/app_logger.dart';
import '../../core/platform/macos_lifecycle_channel.dart';
import '../../core/recording/recording_state.dart';
import '../floating_platform_service_base.dart';
import '../floating_theme_brightness.dart';
import '../recording_orchestrator.dart';
import '../stt/stt_bundle.dart';
import 'floating_button_context_menu.dart';
import 'floating_button_controller.dart';
import 'floating_button_events.dart';

final _log = AppLogger('FloatingButtonService');

/// Maps [RecordingPhase] to the native button's visual state.
FloatingButtonVisualState _mapPhase(RecordingPhase phase) => switch (phase) {
  RecordingPhase.idle => FloatingButtonVisualState.idle,
  RecordingPhase.recording => FloatingButtonVisualState.recording,
  RecordingPhase.transcribing => FloatingButtonVisualState.transcribing,
  RecordingPhase.done => FloatingButtonVisualState.done,
  RecordingPhase.error => FloatingButtonVisualState.error,
};

/// Manages the native floating button lifecycle.
///
/// Layer 3 — business logic. Watches settings and recording state,
/// forwards visual commands to the platform controller (Layer 2),
/// and handles events (click → toggle recording, drag → save position).
///
/// Extends [FloatingPlatformServiceBase] which handles controller creation,
/// event-stream subscription, and cleanup in [ref.onDispose].
class FloatingButtonService
    extends
        FloatingPlatformServiceBase<
          FloatingButtonController,
          FloatingButtonEvent
        > {
  Timer? _autoResetTimer;

  /// Cached history entries for context menu (last 5).
  List<({String id, String content})> _menuEntries = [];

  /// Localizations for the right-click context menu, resolved from the system
  /// locale (the native button window has no [BuildContext] of its own).
  L10n? _l10n;

  // ── FloatingPlatformServiceBase contract ──────────────────────────────────

  @override
  FloatingButtonController? createController() =>
      createFloatingButtonController();

  @override
  Stream<FloatingButtonEvent> eventsFrom(FloatingButtonController controller) =>
      controller.events;

  @override
  Future<void> disposeController(FloatingButtonController controller) =>
      controller.dispose();

  @override
  void onControllerReady(FloatingButtonController controller) {
    // Watch settings for show/hide + configuration.
    ref.listen(settingsProvider, (_, next) {
      next.whenData((s) => _syncSettings(s));
    });

    // Watch recording phase for visual state changes.
    ref.listen(recordingPhaseProvider, (prev, next) {
      _syncPhase(next);
    });

    // Watch history entries for context menu updates.
    ref.listen(historyEntriesProvider, (_, next) {
      next.whenData((entries) => _updateContextMenu(entries));
    });

    // Apply initial settings if already loaded.
    final settings = ref.read(settingsProvider);
    settings.whenData((s) => _syncSettings(s));

    // Clean up the auto-reset timer on dispose.
    ref.onDispose(() => _autoResetTimer?.cancel());
  }

  @override
  void onEvent(FloatingButtonEvent event) => _onEvent(event);

  // ── Settings sync ─────────────────────────────────────────────────────────

  Future<void> _syncSettings(AppSettings s) async {
    final c = controller;
    if (c == null) return;

    try {
      if (s.showFloatingButton) {
        final size = s.floatingButtonSizeType.pixels;
        final x = s.floatingButtonX;
        final y = s.floatingButtonY;

        await c.show(x: x, y: y, size: size);
        await c.setSize(size);

        // Send theme. ThemeMode.system derives from the live platform
        // brightness via the shared resolver — the same path the overlay uses,
        // so both surfaces never disagree (issue 08, bug D5).
        final isDark = resolveFloatingSurfaceIsDark(s.themeMode);
        await c.setTheme(isDark: isDark);

        // Send current recording phase.
        final phase = ref.read(recordingPhaseProvider);
        await c.setState(_mapPhase(phase));
      } else {
        await c.hide();
      }
    } catch (e, st) {
      _log.error('Failed to sync floating button settings', e, st);
    }
  }

  // ── Recording phase sync ──────────────────────────────────────────────────

  Future<void> _syncPhase(RecordingPhase phase) async {
    final c = controller;
    if (c == null) return;

    try {
      await c.setState(_mapPhase(phase));

      // Auto-reset done/error back to idle after a delay.
      _autoResetTimer?.cancel();
      if (phase == RecordingPhase.done) {
        _autoResetTimer = Timer(const Duration(seconds: 2), () {
          controller?.setState(FloatingButtonVisualState.idle);
        });
      } else if (phase == RecordingPhase.error) {
        _autoResetTimer = Timer(const Duration(seconds: 3), () {
          controller?.setState(FloatingButtonVisualState.idle);
        });
      }
    } catch (e, st) {
      _log.error('Failed to sync recording phase', e, st);
    }
  }

  // ── Event handling ────────────────────────────────────────────────────────

  void _onEvent(FloatingButtonEvent event) {
    switch (event) {
      case FloatingButtonClicked():
        _log.debug('Floating button clicked → toggleRecording');
        ref.read(recordingOrchestratorProvider.notifier).toggleRecording();

      case FloatingButtonSecondaryClicked():
        _log.debug('Floating button secondary click → show main window');
        _bringMainWindowToFront();

      case FloatingButtonContextMenuSelected(id: final id):
        _log.debug('Context menu item selected: $id');
        _handleContextMenuAction(id);

      case FloatingButtonDragEnded(x: final x, y: final y):
        _log.debug('Floating button dragged to ($x, $y)');
        _savePosition(x, y);
    }
  }

  void _handleContextMenuAction(String id) {
    switch (id) {
      case '__open__':
        _bringMainWindowToFront();
      case '__new_recording__':
        _bringMainWindowToFront().then((_) {
          ref.read(recordingOrchestratorProvider.notifier).toggleRecording();
        });
      case '__history__':
        _bringMainWindowToFront().then((_) {
          ref.read(activePageProvider.notifier).setPage('history');
        });
      case '__settings__':
        _bringMainWindowToFront().then((_) {
          ref.read(activePageProvider.notifier).setPage('settings');
        });
      case '__quit__':
        unawaited(_quit());
      default:
        // History entry ID → copy to clipboard.
        _copyEntryToClipboard(id);
    }
  }

  Future<void> _bringMainWindowToFront() async {
    try {
      // On macOS, restore Dock presence before showing the window.
      await MacOSLifecycleChannel.setRegular();
      await windowManager.show();
      await windowManager.focus();
    } catch (e, st) {
      _log.error('Failed to bring main window to front', e, st);
    }
  }

  Future<void> _quit() async {
    try {
      ref.read(localSttBundleProvider.notifier).stop();
    } catch (_) {
      // Best-effort shutdown of STT subprocess.
    }

    // Explicitly close the Drift database before engine teardown.
    // Without this, open SQLite prepared statements (Drift stream watchers)
    // survive into the Dart isolate shutdown phase, causing
    // sqlite3LeaveMutexAndCloseZombie to assert and send SIGABRT.
    try {
      await ref
          .read(historyDatabaseProvider)
          .close()
          .timeout(const Duration(seconds: 2));
    } catch (_) {}

    await windowManager.destroy();
  }

  Future<void> _savePosition(double x, double y) async {
    try {
      await ref
          .read(settingsProvider.notifier)
          .updateSettings(
            (s) => s.copyWith(floatingButtonX: x, floatingButtonY: y),
          );
    } catch (e, st) {
      _log.error('Failed to save floating button position', e, st);
    }
  }

  // ── Context menu ──────────────────────────────────────────────────────────

  void _updateContextMenu(List<HistoryEntry> entries) {
    final c = controller;
    if (c == null) return;

    // Take the 5 most recent entries.
    final recent = entries.take(5).toList();
    _menuEntries = recent.map((e) => (id: e.id, content: e.content)).toList();

    final l10n = _l10n ??= _resolveL10n();
    final items = buildFloatingButtonContextMenu(
      l10n: l10n,
      entries: _menuEntries,
    );

    c.setContextMenuItems(items).catchError((e, st) {
      _log.error('Failed to update context menu items', e, st);
    });
  }

  /// Resolves localizations from the system locale, falling back to English.
  L10n _resolveL10n() {
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    try {
      return lookupL10n(locale);
    } catch (_) {
      return lookupL10n(const Locale('en'));
    }
  }

  Future<void> _copyEntryToClipboard(String id) async {
    final entry = _menuEntries.where((e) => e.id == id).firstOrNull;
    if (entry == null) return;

    try {
      await Clipboard.setData(ClipboardData(text: entry.content));
      _log.info('Copied history entry to clipboard: ${entry.id}');
    } catch (e, st) {
      _log.error('Failed to copy to clipboard', e, st);
    }
  }
}

/// Provider for the floating button service (keepAlive — lives for app lifetime).
final floatingButtonServiceProvider =
    NotifierProvider<FloatingButtonService, void>(FloatingButtonService.new);
