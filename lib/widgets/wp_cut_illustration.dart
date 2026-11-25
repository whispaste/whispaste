import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/theme/colors.dart';

/// The empty-state motifs in the paper-cut style
/// (`design-tokens/illustration/STYLE.md`, #1595), one per collection page.
enum WpEmptyMotif {
  /// No recordings yet: the resting pill above a card with three rows.
  recordings('assets/illustrations/empty_recordings.svg'),

  /// No notes yet: a document card with text bars and a cursor.
  notes('assets/illustrations/empty_notes.svg'),

  /// No snippets yet: a card with text and cursor above three plain keys.
  snippets('assets/illustrations/empty_snippets.svg');

  const WpEmptyMotif(this.asset);

  /// The SVG source, drawn in the light palette (STYLE.md §2).
  final String asset;
}

/// A paper-cut empty-state motif, tinted from [WpColors].
///
/// The SVG sources in `assets/illustrations/` are drawn with the light
/// palette hexes of STYLE.md §2; [WpCutColorMapper] swaps each for the role
/// of the active colour set, so light, dark and Marine each draw it in their
/// own tones and no colour lives outside the theme. Decorative, the title
/// beside it says what is empty, so it is excluded from semantics.
///
/// Static by design (STYLE.md §10: the app moves an image only where the
/// motion explains, as in onboarding), so "reduce motion" needs no branch and
/// macOS, Windows and Linux draw the same frame.
class WpCutIllustration extends StatelessWidget {
  const WpCutIllustration({
    super.key,
    required this.motif,
    this.size = defaultSize,
  });

  final WpEmptyMotif motif;

  /// Edge length of the square tile.
  final double size;

  /// The empty-state size STYLE.md §11 checks the motifs at.
  static const double defaultSize = 160;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SvgPicture.asset(
        motif.asset,
        width: size,
        height: size,
        colorMapper: WpCutColorMapper.of(WpColors.current),
        // Keeps the box while the asset loads, so the title does not jump.
        placeholderBuilder: (_) => SizedBox.square(dimension: size),
      ),
    );
  }
}

/// Maps the palette hexes of the paper-cut SVG sources to [WpThemeColors]
/// roles. Value equality over the resolved colours keeps the SVG cache apart
/// per colour set.
@immutable
class WpCutColorMapper extends ColorMapper {
  const WpCutColorMapper({
    required this.ground,
    required this.back,
    required this.carrier,
    required this.line,
    required this.rest,
    required this.mark,
  });

  /// The roles for [colors]. On light sets (light, Marine) every role lands
  /// on the exact STYLE.md hex. On dark the layers follow the navy stage
  /// (E1 navy 800) and the carrier steps one tone up instead of white, which
  /// would glare in a dark empty pane.
  factory WpCutColorMapper.of(WpThemeColors colors) {
    final dark = colors.brightness == Brightness.dark;
    return WpCutColorMapper(
      ground: colors.surface,
      back: dark ? colors.surfaceElevated : colors.active,
      carrier: dark ? colors.active : colors.surfaceElevated,
      line: colors.textMuted,
      rest: dark ? colors.textSecondary : colors.borderDefault,
      mark: colors.highlight,
    );
  }

  /// Source hexes, STYLE.md §2.
  static const Color sourceGround = Color(0xFFF3F7FB); // glacier.50
  static const Color sourceBack = Color(0xFFD6E2F0); // glacier.200
  static const Color sourceCarrier = Color(0xFFFFFFFF); // white
  static const Color sourceLine = Color(0xFF52607A); // glacier.600
  static const Color sourceRest = Color(0xFFBFCFE3); // glacier.300
  static const Color sourceMark = Color(0xFFFFB547); // amber.400

  final Color ground;
  final Color back;
  final Color carrier;
  final Color line;
  final Color rest;
  final Color mark;

  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color color,
  ) {
    final argb = color.toARGB32();
    if (argb == sourceGround.toARGB32()) return ground;
    if (argb == sourceBack.toARGB32()) return back;
    if (argb == sourceCarrier.toARGB32()) return carrier;
    if (argb == sourceLine.toARGB32()) return line;
    if (argb == sourceRest.toARGB32()) return rest;
    if (argb == sourceMark.toARGB32()) return mark;
    return color;
  }

  @override
  bool operator ==(Object other) =>
      other is WpCutColorMapper &&
      other.ground == ground &&
      other.back == back &&
      other.carrier == carrier &&
      other.line == line &&
      other.rest == rest &&
      other.mark == mark;

  @override
  int get hashCode => Object.hash(ground, back, carrier, line, rest, mark);
}
