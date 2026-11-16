import 'dart:ui' as ui;

/// Liquid-glass simulation as a backdrop filter: the fragment shader in
/// `assets/shaders/glass_backdrop.frag`, used as an [ui.ImageFilter] over the
/// backdrop. Only for the gallery and for platforms without native glass; the
/// live overlay keeps the native backdrop or the painter.
abstract final class WpGlassBackdropShader {
  static const String assetPath = 'assets/shaders/glass_backdrop.frag';

  // Float indices as the shader declares them. Index 0 and 1 are the vec2
  // uSize, which the engine fills in itself.
  static const int _pillIndex = 2; // x0, y0, x1, y1 (four floats)
  static const int _blurIndex = 6;
  static const int _saturationIndex = 7;
  static const int _darkIndex = 8;
  static const int _lensIndex = 9;

  /// Blur used when the shader is unavailable (no Impeller, failed load).
  static const double fallbackSigma = 7;

  static Future<ui.FragmentProgram?> loadProgram() async {
    try {
      return await ui.FragmentProgram.fromAsset(assetPath);
    } on Object {
      return null;
    }
  }

  /// Builds the filter for a capsule. [area] is the size of the filtered
  /// region, [pill] the capsule inside it, both in the same units.
  static ui.ImageFilter filter({
    required ui.FragmentProgram? program,
    required ui.Size area,
    required ui.Rect pill,
    required bool dark,
    double? blur,
    double saturation = 1.3,
    double lens = 0.10,
  }) {
    if (program == null) {
      return ui.ImageFilter.blur(sigmaX: fallbackSigma, sigmaY: fallbackSigma);
    }
    final shader = program.fragmentShader()
      ..setFloat(_pillIndex, pill.left / area.width)
      ..setFloat(_pillIndex + 1, pill.top / area.height)
      ..setFloat(_pillIndex + 2, pill.right / area.width)
      ..setFloat(_pillIndex + 3, pill.bottom / area.height)
      ..setFloat(_blurIndex, blur ?? (dark ? 0.14 : 0.40))
      ..setFloat(_saturationIndex, saturation)
      ..setFloat(_darkIndex, dark ? 1 : 0)
      ..setFloat(_lensIndex, lens);
    try {
      return ui.ImageFilter.shader(shader);
    } on Object {
      return ui.ImageFilter.blur(sigmaX: fallbackSigma, sigmaY: fallbackSigma);
    }
  }
}
