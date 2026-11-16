import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/config/settings_provider.dart';
import '../../core/theme/overlay_design_spec.dart' show FloatingButtonSpec;
import '../../core/theme/overlay_customization.dart' show FloatingButtonLook;
import '../../core/logging/app_logger.dart';
import '../../core/platform/display_bounds.dart';
import '../../core/platform/macos_lifecycle_channel.dart';
import '../../core/platform/window_position_clamp.dart';
import '../../core/recording/recording_state.dart';
import '../floating_overlay/floating_overlay_controller_interface.dart'
    show RenderEngineRecovery;
import '../floating_overlay/overlay_render_recovery.dart';
import '../app_commands/native_menu_adapter.dart';
import '../app_commands/tray_command_catalog.dart';
import '../floating_platform_service_base.dart';
import '../recording_orchestrator.dart';
import '../telemetry_service.dart';
import '../tray_service.dart';
import 'floating_button_controller.dart';
import 'floating_button_events.dart';

final _log = AppLogger('FloatingButtonService');

/// Scales the done/error flash of the button. Tests shorten it so they do not
/// wait real seconds (#1491); production always runs at 1.
@visibleForTesting
double flashDurationScale = 1;

/// Maps [RecordingPhase] to the native button's visual state.
FloatingButtonVisualState _mapPhase(RecordingPhase phase) => switch (phase) {
  RecordingPhase.idle => FloatingButtonVisualState.idle,
  RecordingPhase.recording => FloatingButtonVisualState.recording,
  RecordingPhase.transcribing => FloatingButtonVisualState.transcribing,
  // Smart Mode v2's refining phase (ticket 02) has no dedicated visual state
  // here — the floating button keeps showing "transcribing" while it runs,
  // the same busy indicator the user already saw a moment ago.
  RecordingPhase.refining => FloatingButtonVisualState.transcribing,
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
        >
    with ScreenListener {
  Timer? _autoResetTimer;

  /// The app's appearance as the native menu takes it (`system`, `light`,
  /// `dark`); the menu is re-sent when it changes.
  String _menuAppearance = 'system';

  /// How long the shown button may go without a painted frame before the
  /// stall recovery acts. Defaults to the overlay's threshold; tests shorten it.
  Duration get renderFrameDeadline => kRenderFrameDeadline;

  /// Extra time a cold-booted render engine (first show, every re-boot) gets
  /// before its frame deadline counts. Tests shorten it.
  Duration get renderBootGrace => kRenderFirstBootGrace;

  /// Frame-heartbeat recovery for the button's render engine (the macOS,
  /// Windows and Linux controllers implement [RenderEngineRecovery]). The first missed
  /// deadline re-pushes the latest look and phase; a second one re-boots the
  /// engine, within the same session budget the overlay uses.
  late final RenderRecoveryMachine _renderRecovery = RenderRecoveryMachine(
    frameDeadline: renderFrameDeadline,
    sessionBudget: kRenderRebootBudget,
    repushBeforeReboot: true,
    firstEpisodeGrace: renderBootGrace,
  );
  Timer? _renderFrameTimer;

  /// Whether the native button is shown. The heartbeat runs only while it is:
  /// a hidden panel may not paint, and it must not be re-booted for that.
  bool _buttonVisible = false;

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

    // The right-click menu is the tray's command tree (#393): same groups,
    // names, checkmarks and ids. The tray rebuilds it on every state change
    // (recording, choices, recent recordings, PIN lock) and publishes it.
    ref.listen(trayMenuSnapshotProvider, (_, next) => _sendContextMenu(next));
    _sendContextMenu(ref.read(trayMenuSnapshotProvider));

    // Apply initial settings if already loaded.
    final settings = ref.read(settingsProvider);
    settings.whenData((s) => _syncSettings(s));

    // Clean up the auto-reset timer on dispose.
    ref.onDispose(() => _autoResetTimer?.cancel());
    ref.onDispose(() => _renderFrameTimer?.cancel());

    // Re-clamp the button position on monitor connect/disconnect/resolution
    // change — the button (unlike the transient overlay) stays visible for
    // the whole session, so it needs live protection, not just a clamp at
    // the next settings sync.
    ScreenRetriever.instance.addListener(this);
    ref.onDispose(() => ScreenRetriever.instance.removeListener(this));
  }

  @override
  void onScreenEvent(String eventName) => unawaited(_reclampButtonPosition());

  Future<void> _reclampButtonPosition() async {
    final c = controller;
    if (c == null) return;
    try {
      final current = await c.getPosition();
      if (current == null) return;
      final size =
          ref.read(settingsProvider).value?.floatingButtonLook.diameter ??
          FloatingButtonSpec.buttonDiameter;
      final displays = await currentDisplayBounds();
      final clamped = WindowPositionClamp.clamp(
        position: Offset(current.x, current.y),
        size: Size(size, size),
        displays: displays,
      );
      if (clamped.dx != current.x || clamped.dy != current.y) {
        await c.setPosition(clamped.dx, clamped.dy);
        await _savePosition(clamped.dx, clamped.dy);
      }
    } catch (e, st) {
      _log.error('Failed to re-clamp floating button position', e, st);
    }
  }

  @override
  void onEvent(FloatingButtonEvent event) => _onEvent(event);

  // ── Settings sync ─────────────────────────────────────────────────────────

  Future<void> _syncSettings(AppSettings s) async {
    final c = controller;
    if (c == null) return;
    final appearance = nativeMenuAppearance(s.interface_.appearance);
    if (appearance != _menuAppearance) {
      _menuAppearance = appearance;
      _sendContextMenu(ref.read(trayMenuSnapshotProvider));
    }
    // Latest write wins: a sync still awaiting its display lookup when a newer
    // settings write arrives must not push its now-stale appearance after it.
    final generation = ++_settingsGeneration;
    bool superseded() => generation != _settingsGeneration;

    try {
      if (s.showFloatingButton) {
        final look = s.floatingButtonLook;
        final diameter = look.diameter;
        final size = diameter.toInt();
        // A position saved before its monitor was unplugged (or restored
        // from a settings backup made on different hardware) must never show
        // the button off every currently connected display.
        final displays = await currentDisplayBounds();
        if (superseded()) return;
        final clampedPosition = WindowPositionClamp.clamp(
          position: Offset(s.floatingButtonX, s.floatingButtonY),
          size: Size(diameter, diameter),
          displays: displays,
        );
        final x = clampedPosition.dx;
        final y = clampedPosition.dy;
        if (x != s.floatingButtonX || y != s.floatingButtonY) {
          unawaited(_savePosition(x, y));
        }

        // Native show/setSize/setTheme resize and repaint the panel. Only
        // send them when the geometry or theme actually changed: an unrelated
        // settings write (e.g. during a recording) must not churn the native
        // panel, which is what stalls its render engine.
        final applied = (
          x: x,
          y: y,
          size: size,
          background: s.overlayBackgroundType.value,
          wave: s.overlayWaveType.value,
          look: look,
        );
        if (_appliedGeometry != applied) {
          // The look goes first: the ring and colours are paint-only, and
          // must not wait behind a slow native resize/show round trip.
          await c.setTheme(
            background: applied.background,
            wave: applied.wave,
            look: look,
          );
          if (superseded()) return;
          await c.show(x: x, y: y, size: size);
          if (!_buttonVisible) {
            // The tray lists microphones only after it enumerated them; the
            // button's menu needs them before its first right-click.
            unawaited(ref.read(trayMenuSnapshotProvider.notifier).refresh());
          }
          _buttonVisible = true;
          _armRenderFrame(c);
          if (superseded()) return;
          await c.setSize(size);
          if (superseded()) return;
          _appliedGeometry = applied;
        }

        // Send current recording phase.
        await _push(c, _visualStateNow(), 'settings-sync');
      } else {
        _appliedGeometry = null;
        _buttonVisible = false;
        _disarmRenderFrame();
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

    // Drop the pending done/error flash before anything else: a new phase must
    // never be overwritten by a reset that was scheduled for the old one.
    _autoResetTimer?.cancel();
    _autoResetTimer = null;
    final flash = switch (phase) {
      RecordingPhase.done => const Duration(seconds: 2) * flashDurationScale,
      RecordingPhase.error => const Duration(seconds: 3) * flashDurationScale,
      _ => null,
    };
    if (flash != null) {
      _autoResetTimer = Timer(flash, () => _resetFlash(phase));
    }

    if (phase == RecordingPhase.recording) _restoreSpentRenderBudget(c);
    await _push(c, _mapPhase(phase), 'phase:${phase.name}');
  }

  /// A new recording restores a fully spent re-boot budget (#977). Without it
  /// a button whose engine gave up stayed blank until the app restarted. The
  /// restore is tied to the user's action, never to the engine's own `ready`
  /// or frames, so it cannot cascade (see [RenderRecoveryMachine]).
  void _restoreSpentRenderBudget(FloatingButtonController c) {
    if (c is! RenderEngineRecovery) return;
    if (!_renderRecovery.restoreSpentBudget()) return;
    _log.info(
      'Floating button re-boot budget restored for the new recording '
      '($kRenderRebootBudget re-boots available again)',
    );
  }

  /// Pushes [state] to the native button and logs the push and its native
  /// acknowledgement, so a stale button can be traced to the exact call. The
  /// logic is shared by every platform controller, so the log is identical on
  /// macOS, Windows and Linux.
  int _pushSeq = 0;
  int _settingsGeneration = 0;

  /// Geometry and theme last applied to the native panel; null while hidden.
  ({
    double x,
    double y,
    int size,
    String background,
    String wave,
    FloatingButtonLook look,
  })?
  _appliedGeometry;

  Future<void> _push(
    FloatingButtonController c,
    FloatingButtonVisualState state,
    String reason,
  ) async {
    final seq = ++_pushSeq;
    final sw = Stopwatch()..start();
    _log.debug('push #$seq ${state.name} reason=$reason');
    if (_buttonVisible) _armRenderFrame(c);
    try {
      await c.setState(state);
      _log.debug('ack #$seq ${state.name} after ${sw.elapsedMilliseconds}ms');
    } catch (e, st) {
      _log.error(
        'push #$seq ${state.name} failed after ${sw.elapsedMilliseconds}ms',
        e,
        st,
      );
    }
  }

  /// Ends the done/error flash, but only while [flashedPhase] is still the
  /// current phase. Any newer phase has already pushed its own visual state.
  void _resetFlash(RecordingPhase flashedPhase) {
    _autoResetTimer = null;
    final current = ref.read(recordingPhaseProvider);
    if (current != flashedPhase) {
      _log.debug(
        'flash reset skipped: flashed=${flashedPhase.name} current=${current.name}',
      );
      return;
    }
    final c = controller;
    if (c != null) {
      unawaited(_push(c, FloatingButtonVisualState.idle, 'flash-reset'));
    }
  }

  // ── Render-engine frame heartbeat ─────────────────────────────────────────
  // Deadlines read `clock.now()` (the wall clock in the app), so tests in
  // fake time see the same instants as the timers that check them (#1491).

  /// Arms the stall deadline for the next frame. Once per pending episode: a
  /// second message while the deadline runs keeps the original instant, so a
  /// stalled engine cannot postpone its own recovery by receiving more pushes.
  void _armRenderFrame(FloatingButtonController c) {
    if (c is! RenderEngineRecovery) return;
    _renderRecovery.onShown(clock.now());
    if (_renderFrameTimer != null) return;
    _scheduleRenderFrameTimer();
  }

  void _disarmRenderFrame() {
    _renderRecovery.onHidden();
    _renderFrameTimer?.cancel();
    _renderFrameTimer = null;
  }

  void _scheduleRenderFrameTimer() {
    final due = _renderRecovery.deadline;
    if (due == null) return;
    final wait = due.difference(clock.now());
    _renderFrameTimer = Timer(
      wait.isNegative ? Duration.zero : wait,
      _onRenderFrameDeadline,
    );
  }

  void _onRenderFrameAck() {
    final wasStalled = _renderRecovery.stalled;
    _renderRecovery.onFrame();
    _renderFrameTimer?.cancel();
    _renderFrameTimer = null;
    if (wasStalled) {
      _log.info(
        'Floating button render engine painted again — stall recovered '
        '(re-boots so far: ${_renderRecovery.reboots}/$kRenderRebootBudget)',
      );
    }
  }

  void _onRenderFrameDeadline() {
    _renderFrameTimer = null;
    final c = controller;
    final ms = renderFrameDeadline.inMilliseconds;
    final now = clock.now();
    final due = _renderRecovery.deadline;
    final lag = due == null ? Duration.zero : now.difference(due);
    switch (_renderRecovery.onDeadline(now, lag: lag)) {
      case RenderRecoveryAction.none:
        break;
      case RenderRecoveryAction.repush:
        _log.warning(
          'Floating button painted no frame within $ms ms of its last state '
          'change — re-pushing its look and phase',
        );
        if (c != null) unawaited(_repushLatest(c));
      case RenderRecoveryAction.reboot:
        _log.warning(
          'Floating button render engine still painted no frame after the '
          're-push — re-booting it '
          '(${_renderRecovery.reboots}/$kRenderRebootBudget)',
        );
        if (c case final RenderEngineRecovery recovery) {
          recovery.rebootRenderEngine().catchError((e, st) {
            _log.error(
              'Floating button render engine re-boot request failed',
              e,
              st,
            );
          });
        }
      case RenderRecoveryAction.budgetExhausted:
        _log.error(
          'Floating button render engine stalled again; the session re-boot '
          'budget ($kRenderRebootBudget) is spent — the button stays as is '
          'until the next recording restores the budget',
        );
    }
    if (_renderRecovery.armed) _scheduleRenderFrameTimer();
  }

  /// Re-sends the latest appearance and phase, so a stalled engine that
  /// recovers paints what the user last configured, not a stale frame.
  Future<void> _repushLatest(FloatingButtonController c) async {
    final applied = _appliedGeometry;
    try {
      if (applied != null) {
        await c.setTheme(
          background: applied.background,
          wave: applied.wave,
          look: applied.look,
        );
      }
    } catch (e, st) {
      _log.error('Failed to re-push floating button look', e, st);
    }
    if (_buttonVisible) {
      await _push(c, _visualStateNow(), 'stall-repush');
    }
  }

  /// The visual state the button should show for the current phase. A done or
  /// error phase whose flash has already ended shows idle, so a re-push (for
  /// example after a settings change) cannot resurrect the finished flash.
  FloatingButtonVisualState _visualStateNow() {
    final phase = ref.read(recordingPhaseProvider);
    final flashOver =
        _autoResetTimer == null &&
        (phase == RecordingPhase.done || phase == RecordingPhase.error);
    return flashOver ? FloatingButtonVisualState.idle : _mapPhase(phase);
  }

  // ── Event handling ────────────────────────────────────────────────────────

  void _onEvent(FloatingButtonEvent event) {
    switch (event) {
      case FloatingButtonClicked():
        _log.debug('Floating button clicked → toggleRecording');
        ref.read(recordingOrchestratorProvider.notifier).toggleRecording();
        ref
            .read(telemetrySessionAggregatorProvider)
            .count(category: 'ui', action: 'fab_click');

      case FloatingButtonSecondaryClicked():
        _log.debug('Floating button secondary click → show main window');
        _bringMainWindowToFront();

      case FloatingButtonRenderFrame():
        _onRenderFrameAck();

      case FloatingButtonContextMenuSelected(id: final id):
        _log.debug('Context menu item selected: $id');
        _handleContextMenuAction(id);

      case FloatingButtonDragEnded(x: final x, y: final y):
        _log.debug('Floating button dragged to ($x, $y)');
        _savePosition(x, y);

      case FloatingButtonRenderEngineDiagnostic(
        message: final message,
        isError: final isError,
      ):
        if (isError) {
          _log.error('Render engine: $message');
        } else {
          _log.warning('Render engine: $message');
        }
    }
  }

  /// Runs a menu entry through the tray's command handler, so an id does the
  /// same thing in both menus. A recent recording is copied here instead, to
  /// flash the button's copy feedback (UIA-SHL-11).
  void _handleContextMenuAction(String id) {
    final tray = ref.read(trayServiceProvider.notifier);
    final recentId = trayRecentIdFromKey(id);
    if (recentId != null) {
      unawaited(_copyRecent(tray, recentId));
      return;
    }
    tray.activateCommand(id);
    if (id != TrayCommandIds.quit) {
      // Devices may have come or gone since the menu was built.
      unawaited(ref.read(trayMenuSnapshotProvider.notifier).refresh());
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

  Future<void> _savePosition(double x, double y) => saveSettingsSafely(
    _log,
    'Failed to save floating button position',
    () => ref
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWith(floatingButtonX: x, floatingButtonY: y),
        ),
  );

  // ── Context menu ──────────────────────────────────────────────────────────

  void _sendContextMenu(TrayMenuSnapshot? snapshot) {
    final c = controller;
    if (c == null || snapshot == null) return;
    final labels = snapshot.labels;
    final items = nativeMenuItems(
      snapshot.commands,
      labelOf: (key) => labels[key] ?? key,
    );
    c.setContextMenuItems(items, appearance: _menuAppearance).catchError((
      Object e,
      StackTrace st,
    ) {
      _log.error('Failed to update context menu items', e, st);
    });
  }

  Future<void> _copyRecent(TrayService tray, String recordingId) async {
    try {
      await tray.copyRecentRecording(recordingId);
      _log.info('Copied recent recording to clipboard: $recordingId');
      _flashButton(FloatingButtonVisualState.done, const Duration(seconds: 2));
    } catch (e, st) {
      _log.error('Failed to copy to clipboard', e, st);
      _flashButton(FloatingButtonVisualState.error, const Duration(seconds: 3));
    }
  }

  /// Shows [state] on the button for [hold], then returns it to idle
  /// (UIA-SHL-11). Skipped while a dictation runs, because the recording
  /// visuals own the button then.
  void _flashButton(FloatingButtonVisualState state, Duration hold) {
    if (isDictationBusy(ref.read(recordingPhaseProvider))) return;
    final c = controller;
    if (c == null) return;
    _autoResetTimer?.cancel();
    c
        .setState(state)
        .catchError(
          (Object e, StackTrace st) =>
              _log.error('Failed to show copy feedback', e, st),
        );
    _autoResetTimer = Timer(hold, () {
      final idleTarget = controller;
      if (idleTarget == null) return;
      unawaited(
        _push(
          idleTarget,
          FloatingButtonVisualState.idle,
          'copy-feedback-reset',
        ),
      );
    });
  }
}

/// Provider for the floating button service (keepAlive — lives for app lifetime).
final floatingButtonServiceProvider =
    NotifierProvider<FloatingButtonService, void>(FloatingButtonService.new);
