import '../../core/theme/overlay_customization.dart';
import '../../core/theme/overlay_design_spec.dart';
import 'floating_button_controller_interface.dart';

/// Prefix of the entrypoint arguments that carry the boot state.
const String kButtonBootArgPrefix = '--button-boot-';

/// The render state a native button shell hands a freshly booted button
/// engine as entrypoint arguments (#977).
///
/// Every engine boot, and above all a heartbeat re-boot, used to paint nothing
/// until the shell's `ready` flush delivered `setTheme`. A re-boot during a
/// recording therefore hid the stop button for as long as the new engine took
/// to reach `ready`, and an engine that never got there stayed blank. With the
/// boot state the engine paints the last known state in its first frame.
///
/// The shells pass flat `--button-boot-<key>=<value>` arguments, so no JSON
/// escaping is needed in Swift, C++ or C. The theme keys match the `setTheme`
/// payload and are sent only once the shell has received a theme, which keeps
/// the #369 guard: no frame in default colours before the real theme is known.
class FloatingButtonBootState {
  const FloatingButtonBootState({this.state, this.diameter, this.theme});

  /// No boot state: the first boot of the session, or an older shell.
  static const FloatingButtonBootState empty = FloatingButtonBootState();

  /// The last visual state the shell relayed, if any.
  final FloatingButtonVisualState? state;

  /// The last disc diameter in logical pixels, if any.
  final double? diameter;

  /// The last theme the shell relayed; null until the shell received one.
  final FloatingButtonBootTheme? theme;

  /// Parses the entrypoint [args]. Unknown keys and malformed values are
  /// ignored, so a newer shell never breaks an older engine and vice versa.
  factory FloatingButtonBootState.parse(List<String> args) {
    final values = <String, String>{};
    for (final arg in args) {
      if (!arg.startsWith(kButtonBootArgPrefix)) continue;
      final eq = arg.indexOf('=');
      if (eq < 0) continue;
      values[arg.substring(kButtonBootArgPrefix.length, eq)] = arg.substring(
        eq + 1,
      );
    }
    if (values.isEmpty) return empty;

    FloatingButtonVisualState? state;
    final rawState = values['state'];
    if (rawState != null) {
      for (final s in FloatingButtonVisualState.values) {
        if (s.name == rawState) state = s;
      }
    }

    final diameter = double.tryParse(values['diameter'] ?? '');

    FloatingButtonBootTheme? theme;
    final background = values['background'];
    final wave = values['wave'];
    if (background != null && wave != null) {
      theme = FloatingButtonBootTheme(
        background: OverlayBackground.fromValue(background),
        wave: OverlayWave.fromValue(wave),
        look: FloatingButtonLook.fromThemeMap({
          'shape': values['shape'],
          'ring': _parseBool(values['ring']),
          'idleOpacity': double.tryParse(values['idleOpacity'] ?? ''),
          'idleCapsule': _parseBool(values['idleCapsule']),
        }),
      );
    }

    return FloatingButtonBootState(
      state: state,
      diameter: diameter != null && diameter > 0 ? diameter : null,
      theme: theme,
    );
  }

  static bool? _parseBool(String? raw) => switch (raw) {
    'true' || '1' => true,
    'false' || '0' => false,
    _ => null,
  };
}

/// The theme part of [FloatingButtonBootState], decoded like `setTheme`.
class FloatingButtonBootTheme {
  const FloatingButtonBootTheme({
    required this.background,
    required this.wave,
    required this.look,
  });

  final OverlayBackground background;
  final OverlayWave wave;
  final FloatingButtonLook look;
}
