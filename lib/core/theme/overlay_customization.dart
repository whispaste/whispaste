/// Overlay customization policies (WP-95, ADR 0024 addendum).
///
/// Pure Dart: no widget, platform or native calls. The persisted names are
/// the contract with the native shells, so they must not be renamed.
///
/// Every option defaults to today's look (see [OverlayCustomization.defaults]).
library;

import 'package:flutter/painting.dart';

import 'overlay_design_spec.dart';

/// Shape of the recording overlay window.
enum OverlayForm {
  /// Full pill, the default and today's look.
  pill('pill'),

  /// Pill with smaller corner radius.
  roundedRect('rounded-rect'),

  /// 44 x 44 circle: pegelring around a stop button, Esc cancels.
  compactCircle('compact-circle'),

  /// 44 px thick bar, docked to a screen edge, laid out vertically at the sides.
  edgeBar('edge-bar');

  const OverlayForm(this.value);

  /// Persisted name (`overlay_form`).
  final String value;

  /// Unknown or null falls back to [pill].
  static OverlayForm fromValue(String? name) =>
      values.firstWhere((v) => v.value == name, orElse: () => OverlayForm.pill);
}

/// Drawing style of the waveform.
enum OverlayWaveStyle {
  /// Vertical level bars, the default and today's look.
  bars('bars'),

  /// One continuous line through the level samples.
  line('line'),

  /// One dot per level sample.
  dots('dots');

  const OverlayWaveStyle(this.value);

  /// Persisted name (`overlay_wave_style`).
  final String value;

  /// Unknown or null falls back to [bars].
  static OverlayWaveStyle fromValue(String? name) => values.firstWhere(
    (v) => v.value == name,
    orElse: () => OverlayWaveStyle.bars,
  );
}

/// Fill opacity of the overlay chrome, in a few fixed steps.
///
/// Only the fill is affected. Text, icons and the waveform keep their own
/// contrast, see [OverlayOpacityGate].
enum OverlayOpacity {
  full(100),
  reduced(80),
  subtle(60);

  const OverlayOpacity(this.percent);

  /// Persisted value (`overlay_opacity`), the percentage as a string.
  final int percent;

  double get alpha => percent / 100;

  /// Unknown or null falls back to [full].
  static OverlayOpacity fromValue(String? raw) {
    final parsed = int.tryParse(raw ?? '');
    return values.firstWhere(
      (v) => v.percent == parsed,
      orElse: () => OverlayOpacity.full,
    );
  }
}

/// Resolution rules that depend on the platform or the system settings.
abstract final class OverlayPolicy {
  /// Edge bar needs a window that stays above other windows and can be docked
  /// to a screen edge. Wayland gives no such guarantee for normal windows, so
  /// there the bar falls back to [OverlayForm.pill]. The settings screen
  /// explains the fallback.
  static OverlayForm effectiveForm(
    OverlayForm requested, {
    required bool edgeDockingSupported,
  }) {
    if (requested == OverlayForm.edgeBar && !edgeDockingSupported) {
      return OverlayForm.pill;
    }
    return requested;
  }

  /// The fluid, speech-reactive edge is motion. With "reduce motion" set in
  /// the system, it is always off and the outline is static.
  static bool effectiveWaveFluid({
    required bool setting,
    required bool reduceMotion,
  }) => setting && !reduceMotion;

  /// The stop control is never hidden: the timer and cancel toggles may be
  /// turned off, but stopping stays reachable (hotkey and Esc).
  static const bool stopAlwaysVisible = true;
}

/// Contrast gate for the opacity setting (ADR 0024: wave and symbols >= 3:1).
///
/// The fill is drawn over the desktop, which is unknown. The gate therefore
/// checks against both extremes, white and black, and takes the worse result.
abstract final class OverlayOpacityGate {
  static const double minimumContrast = 3.0;

  static const List<Color> worstCaseBackdrops = [
    Color(0xFFFFFFFF),
    Color(0xFF000000),
  ];

  /// Lowest contrast of [accent] against [fill] at [alpha] over each backdrop.
  static double worstContrast({
    required Color fill,
    required Color accent,
    required double alpha,
    Iterable<Color> backdrops = worstCaseBackdrops,
  }) {
    var worst = double.infinity;
    for (final backdrop in backdrops) {
      final composite = _over(fill, alpha, backdrop);
      final ratio = contrastRatio(accent, composite);
      if (ratio < worst) worst = ratio;
    }
    return worst;
  }

  /// Returns [requested] when the accent keeps 3:1 at its alpha. Otherwise
  /// it moves to the next more opaque step that passes. At full opacity the
  /// fill is the token colour itself, so full is the final fallback even when
  /// the token pairing is below 3:1 (the token tests guard that case).
  static OverlayOpacity clamp({
    required OverlayOpacity requested,
    required Color fill,
    required Color accent,
    Iterable<Color> backdrops = worstCaseBackdrops,
  }) {
    final candidates =
        OverlayOpacity.values
            .where((o) => o.percent >= requested.percent)
            .toList()
          ..sort((a, b) => a.percent.compareTo(b.percent));
    for (final candidate in candidates) {
      final contrast = worstContrast(
        fill: fill,
        accent: accent,
        alpha: candidate.alpha,
        backdrops: backdrops,
      );
      if (contrast >= minimumContrast) return candidate;
    }
    return OverlayOpacity.full;
  }

  static Color _over(Color fg, double alpha, Color backdrop) => Color.from(
    alpha: 1,
    red: fg.r * alpha + backdrop.r * (1 - alpha),
    green: fg.g * alpha + backdrop.g * (1 - alpha),
    blue: fg.b * alpha + backdrop.b * (1 - alpha),
  );
}

/// The WP-95 appearance options as one value, carried by the overlay snapshot.
///
/// Defaults equal today's look, so a snapshot without this value renders as
/// before. Persisted names are read by [fromValues] and written by the
/// snapshot's map form.
class OverlayAppearance {
  const OverlayAppearance({
    this.form = OverlayForm.pill,
    this.waveStyle = OverlayWaveStyle.bars,
    this.waveFluid = true,
    this.showTimer = true,
    this.showCancel = true,
    this.opacity = OverlayOpacity.full,
  });

  static const OverlayAppearance defaults = OverlayAppearance();

  final OverlayForm form;
  final OverlayWaveStyle waveStyle;

  /// The requested fluid outline. Reduce motion is applied by the renderer
  /// through [OverlayPolicy.effectiveWaveFluid].
  final bool waveFluid;
  final bool showTimer;

  /// The cancel glyph only. [OverlayPolicy.stopAlwaysVisible] keeps the stop
  /// control, and Esc keeps cancelling.
  final bool showCancel;

  /// The requested opacity step. The rendered step comes from
  /// [OverlayOpacityGate.clamp] for the active background and wave.
  final OverlayOpacity opacity;

  /// Builds the value from persisted settings strings and flags.
  factory OverlayAppearance.fromValues({
    String? form,
    String? waveStyle,
    bool waveFluid = true,
    bool showTimer = true,
    bool showCancel = true,
    String? opacity,
  }) => OverlayAppearance(
    form: OverlayForm.fromValue(form),
    waveStyle: OverlayWaveStyle.fromValue(waveStyle),
    waveFluid: waveFluid,
    showTimer: showTimer,
    showCancel: showCancel,
    opacity: OverlayOpacity.fromValue(opacity),
  );

  /// Writes the flat keys read by the overlay render engine.
  Map<String, Object> toMap() => {
    'form': form.value,
    'waveStyle': waveStyle.value,
    'waveFluid': waveFluid,
    'showTimer': showTimer,
    'showCancel': showCancel,
    'opacity': '${opacity.percent}',
  };

  /// Reads the flat keys; any missing or unknown key takes the default.
  factory OverlayAppearance.fromMap(Map<dynamic, dynamic> map) =>
      OverlayAppearance.fromValues(
        form: map['form'] as String?,
        waveStyle: map['waveStyle'] as String?,
        waveFluid: map['waveFluid'] as bool? ?? true,
        showTimer: map['showTimer'] as bool? ?? true,
        showCancel: map['showCancel'] as bool? ?? true,
        opacity: map['opacity'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is OverlayAppearance &&
      other.form == form &&
      other.waveStyle == waveStyle &&
      other.waveFluid == waveFluid &&
      other.showTimer == showTimer &&
      other.showCancel == showCancel &&
      other.opacity == opacity;

  @override
  int get hashCode =>
      Object.hash(form, waveStyle, waveFluid, showTimer, showCancel, opacity);
}

/// The floating button's look (WP-95 button customisation).
///
/// [size] reaches the native shell through `setSize` (the window and disc
/// diameter); [toThemeMap] carries the render-only parts (shape, recording
/// ring, resting opacity) through `setTheme`. Unknown stored values take the
/// defaults, like [OverlayAppearance].
class FloatingButtonLook {
  /// Creates a look from already-validated values.
  const FloatingButtonLook({
    this.size = 'medium',
    this.square = false,
    this.ring = true,
    this.idleOpacity = '100',
  });

  /// Reads the persisted strings and bools; unknown values fall back.
  factory FloatingButtonLook.fromValues({
    String? size,
    String? shape,
    bool? ring,
    String? idleOpacity,
  }) => FloatingButtonLook(
    size: _sizes.contains(size) ? size! : defaults.size,
    square: shape == 'square',
    ring: ring ?? defaults.ring,
    idleOpacity: _idleOpacities.contains(idleOpacity)
        ? idleOpacity!
        : defaults.idleOpacity,
  );

  /// Reads the render-only `setTheme` keys (see [toThemeMap]). The resting
  /// opacity arrives as a fraction; it is mapped to the nearest preset.
  factory FloatingButtonLook.fromThemeMap(Map<dynamic, dynamic> map) {
    final alpha = map['idleOpacity'];
    return FloatingButtonLook.fromValues(
      shape: map['shape'] as String?,
      ring: map['ring'] as bool?,
      idleOpacity: alpha is num ? '${(alpha * 100).round()}' : null,
    );
  }

  /// Today's button: medium disc, round, recording ring, fully opaque.
  static const FloatingButtonLook defaults = FloatingButtonLook();

  static const Set<String> _sizes = {'small', 'medium', 'large'};
  static const Set<String> _idleOpacities = {'100', '70', '40'};

  /// 'small', 'medium' or 'large'.
  final String size;

  /// Rounded square instead of the round disc.
  final bool square;

  /// Coloured recording ring while recording.
  final bool ring;

  /// Resting opacity percentage: '100', '70' or '40'.
  final String idleOpacity;

  /// Disc diameter in logical pixels: 44, 56 or 80.
  double get diameter => switch (size) {
    'small' => 44,
    'large' => 80,
    _ => 56,
  };

  /// Opacity applied while the button is idle (1.0 = fully opaque).
  double get idleAlpha => switch (idleOpacity) {
    '70' => 0.7,
    '40' => 0.4,
    _ => 1.0,
  };

  /// Render-only fields for the `setTheme` payload. The keys are the contract
  /// with the native shells (`shape`, `ring`, `idleOpacity`).
  Map<String, Object> toThemeMap() => {
    'shape': square ? 'square' : 'round',
    'ring': ring,
    'idleOpacity': idleAlpha,
  };

  @override
  bool operator ==(Object other) =>
      other is FloatingButtonLook &&
      other.size == size &&
      other.square == square &&
      other.ring == ring &&
      other.idleOpacity == idleOpacity;

  @override
  int get hashCode => Object.hash(size, square, ring, idleOpacity);
}
