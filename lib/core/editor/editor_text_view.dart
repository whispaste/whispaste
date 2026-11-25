/// The text view of the three editors — recordings, notes and snippets
/// (#648): text size, line length and line spacing. One view for all three,
/// remembered across restarts; the per-entry zoom of #678 is replaced by it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';

/// How long a line of editor text may get, in characters (#648).
///
/// A measure in characters rather than pixels, so a larger text keeps the
/// same number of words on a line instead of squeezing them into a fixed
/// width. [full] sets no cap: the text uses the whole panel, as before.
enum EditorLineLength {
  full(null),
  wide(110),
  medium(85),
  narrow(65);

  const EditorLineLength(this.characters);

  /// Characters per line, or `null` for no cap.
  final int? characters;
}

/// Line spacing of editor text, as a factor of the font size (#648).
enum EditorLineSpacing {
  compact(1.4),
  normal(1.65),
  relaxed(2.0);

  const EditorLineSpacing(this.factor);

  final double factor;
}

class EditorTextView {
  const EditorTextView({
    this.textSize = standardTextSize,
    this.lineLength = EditorLineLength.full,
    this.lineSpacing = EditorLineSpacing.normal,
  });

  /// The fixed text sizes in percent, smallest first. Ctrl/Cmd+Plus and
  /// Minus walk them one step; 0 goes back to [standardTextSize].
  static const textSizes = <int>[
    80,
    90,
    100,
    110,
    125,
    150,
    175,
    200,
    250,
    300,
  ];

  static const standardTextSize = 100;

  /// What the editors looked like before the setting existed: 100 %, the
  /// full panel width, 1.65 line height.
  static const standard = EditorTextView();

  /// Text size in percent, always one of [textSizes]. It multiplies the
  /// system text size; it never replaces it.
  final int textSize;
  final EditorLineLength lineLength;
  final EditorLineSpacing lineSpacing;

  double get textScale => textSize / 100;

  bool get isStandardTextSize => textSize == standardTextSize;

  bool get canGrow => textSize < textSizes.last;
  bool get canShrink => textSize > textSizes.first;

  /// One fixed step larger (+1) or smaller (-1), held at the ends.
  EditorTextView stepTextSize(int direction) {
    final index = textSizes.indexOf(textSize);
    final next = (index + direction).clamp(0, textSizes.length - 1);
    return copyWith(textSize: textSizes[next]);
  }

  EditorTextView copyWith({
    int? textSize,
    EditorLineLength? lineLength,
    EditorLineSpacing? lineSpacing,
  }) => EditorTextView(
    textSize: textSize ?? this.textSize,
    lineLength: lineLength ?? this.lineLength,
    lineSpacing: lineSpacing ?? this.lineSpacing,
  );

  /// Stored form, e.g. `125:wide:relaxed`.
  String encode() => '$textSize:${lineLength.name}:${lineSpacing.name}';

  /// Reads [encode]'s form. Each part that is missing or unknown falls back
  /// to its standard on its own, so one bad part never resets the others.
  static EditorTextView decode(String? raw) {
    if (raw == null || raw.isEmpty) return standard;
    final parts = raw.split(':');
    String? part(int i) => i < parts.length ? parts[i] : null;
    final size = int.tryParse(part(0) ?? '');
    return EditorTextView(
      textSize: size != null && textSizes.contains(size)
          ? size
          : standardTextSize,
      lineLength:
          EditorLineLength.values.asNameMap()[part(1)] ?? standard.lineLength,
      lineSpacing:
          EditorLineSpacing.values.asNameMap()[part(2)] ?? standard.lineSpacing,
    );
  }

  /// Width in logical pixels that holds [lineLength]'s characters of text
  /// whose rendered size is [renderedFontSize]; `null` for no cap.
  ///
  /// 0.53 em per character is the average advance of the app's prose font;
  /// it puts 85 characters at 16 dp on the 720 dp reading measure (#197).
  double? maxWidthFor(double renderedFontSize) {
    final characters = lineLength.characters;
    if (characters == null) return null;
    return characters * renderedFontSize * 0.53;
  }

  @override
  bool operator ==(Object other) =>
      other is EditorTextView &&
      other.textSize == textSize &&
      other.lineLength == lineLength &&
      other.lineSpacing == lineSpacing;

  @override
  int get hashCode => Object.hash(textSize, lineLength, lineSpacing);
}

/// The remembered editor view. A view preference like the list sorts, so it
/// lives in the raw `app_settings` key-value table and stays out of the
/// settings export and import.
class EditorTextViewNotifier extends AsyncNotifier<EditorTextView> {
  static const settingKey = 'editor_text_view';

  @override
  Future<EditorTextView> build() async {
    final db = ref.read(historyDatabaseProvider);
    return EditorTextView.decode(await db.readAppSetting(settingKey));
  }

  /// Shows [view] at once in every editor and stores it for the next start.
  Future<void> choose(EditorTextView view) async {
    if (state.value == view) return;
    state = AsyncData(view);
    final db = ref.read(historyDatabaseProvider);
    await db.writeAppSetting(settingKey, view.encode());
  }
}

final editorTextViewProvider =
    AsyncNotifierProvider<EditorTextViewNotifier, EditorTextView>(
      EditorTextViewNotifier.new,
    );
