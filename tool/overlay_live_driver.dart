/// Live driver — a dev harness, NOT part of the shipped app.
///
/// Drives the REAL native floating shells (macOS NSPanel / Windows WS_POPUP /
/// Linux GTK) through the production `FloatingOverlayController` /
/// `FloatingButtonController`, feeding them a fixed recording-style snapshot.
/// The native shell lazily creates its always-on-top window and boots the
/// second Flutter engine that paints the shared `FloatingOverlayView` /
/// `FloatingButtonView` (ADR 0002). This shows the genuine on-desktop overlay
/// and button — the real integration — WITHOUT the mic/Whisper recording
/// pipeline, so it can be screenshot deterministically on every OS.
///
/// The driver's own main window is hidden, so a full-screen capture shows only
/// the native floating surfaces.
///
/// Run (pick state/theme via dart-define):
///   flutter run -t tool/overlay_live_driver.dart \
///     --dart-define=STATE=recording --dart-define=THEME=dark
///
/// STATE ∈ {recording, transcribing, done, error}; THEME ∈ {dark, light};
/// COMPACT ∈ {true, false}.
library;

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/floating_button_render_entrypoint.dart';
import 'package:whispaste/floating_overlay_render_entrypoint.dart';
import 'package:whispaste/services/floating_button/floating_button_controller.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller.dart';

// The native shells boot their second render engine by NAME, resolved against
// the ROOT library — which, under `flutter run -t tool/overlay_live_driver.dart`,
// is THIS file (not main.dart). So the two named entrypoints must be re-declared
// here, delegating to the same shared engine boots the production app uses.
@pragma('vm:entry-point')
void floatingOverlayMain() => runFloatingOverlayEngine();

@pragma('vm:entry-point')
void floatingButtonMain() => runFloatingButtonEngine();

const String _stateName = String.fromEnvironment(
  'STATE',
  defaultValue: 'recording',
);
const String _themeName = String.fromEnvironment('THEME', defaultValue: 'dark');
const bool _compact = bool.fromEnvironment('COMPACT', defaultValue: false);

OverlayVisualState get _state => OverlayVisualState.values.firstWhere(
  (s) => s.name == _stateName,
  orElse: () => OverlayVisualState.recording,
);

FloatingButtonVisualState get _buttonState => switch (_state) {
  OverlayVisualState.recording => FloatingButtonVisualState.recording,
  OverlayVisualState.transcribing => FloatingButtonVisualState.transcribing,
  OverlayVisualState.done => FloatingButtonVisualState.done,
  OverlayVisualState.error => FloatingButtonVisualState.error,
};

Future<void> main(List<String> args) async {
  // Linux GTK embedder has no named-entrypoint API — the native shells boot
  // their second engine via entrypoint ARGUMENTS instead. Branch exactly like
  // main.dart so those engines run the shared render apps. (macOS/Windows boot
  // the named pragma entrypoints above and never pass these args.)
  if (args.contains('--floating-overlay')) {
    runFloatingOverlayEngine();
    return;
  }
  if (args.contains('--floating-button')) {
    runFloatingButtonEngine();
    return;
  }

  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  // Keep the driver's own window out of the screenshot.
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(size: Size(420, 120), title: 'overlay-live-driver'),
    () async {
      await windowManager.hide();
    },
  );

  // Minimal root so the main engine keeps pumping frames while the native
  // shells render in their own windows/engines.
  runApp(const SizedBox.shrink());

  const isDark = _themeName != 'light';

  final overlay = createFloatingOverlayController();
  final button = createFloatingButtonController();

  if (overlay != null) {
    await overlay.setPosition(420, 200, OverlayAnchorMode.topLeft);
    await overlay.updateSnapshot(
      FloatingOverlaySnapshot(
        visible: true,
        state: _state,
        isDark: isDark,
        compact: _compact,
        label: switch (_state) {
          OverlayVisualState.recording => 'Recording',
          OverlayVisualState.transcribing => 'Transcribing…',
          OverlayVisualState.done => 'Pasted',
          OverlayVisualState.error => 'Error',
        },
        elapsed: _state == OverlayVisualState.recording ? '1:30' : '',
        errorMessage: _state == OverlayVisualState.error
            ? 'Network timeout'
            : null,
        doneMessage: _state == OverlayVisualState.done ? 'Pasted' : null,
        progress: _state == OverlayVisualState.recording ? 0.4 : 0.0,
      ),
    );
    await overlay.setWaveformBars(
      List<double>.generate(
        OverlayDesignSpec.waveform.barCount,
        (i) => (i % 7) / 7.0,
      ),
    );
  }

  if (button != null) {
    await button.setTheme(isDark: isDark);
    await button.show(x: 480, y: 360, size: 56);
    await button.setState(_buttonState);
  }

  // The process stays alive (no exit); the native windows remain on screen for
  // an external screenshot. Stop it with `q` in `flutter run` or by killing it.
}
