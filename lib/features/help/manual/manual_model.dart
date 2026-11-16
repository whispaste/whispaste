import '../../../core/l10n/generated/app_localizations.dart';

/// Resolves one piece of handbook text from the localized strings.
///
/// Every handbook string is an ARB key read through a getter, so the data
/// below holds lambdas and is therefore never `const`.
typedef ManualText = String Function(L10n l10n);

/// One block of content inside a handbook section.
sealed class ManualBlock {
  const ManualBlock();
}

/// A plain paragraph.
final class ManualParagraph extends ManualBlock {
  const ManualParagraph(this.text);

  final ManualText text;
}

/// A bulleted list. Each item is one short sentence.
final class ManualBullets extends ManualBlock {
  const ManualBullets(this.items);

  final List<ManualText> items;
}

/// A tip box for a useful detail the reader would otherwise miss.
final class ManualTip extends ManualBlock {
  const ManualTip(this.text);

  final ManualText text;
}

/// Quotes a message exactly as the app shows it.
///
/// [text] points at the app's own ARB key, not a copy, so the quoted wording
/// cannot drift from what the user actually sees.
final class ManualNotice extends ManualBlock {
  const ManualNotice(this.text);

  final ManualText text;
}

/// A bold label followed by text, for example "Cause:" and its explanation.
final class ManualLabelled extends ManualBlock {
  const ManualLabelled(this.label, this.text);

  final ManualText label;
  final ManualText text;
}

/// A shell command, shown in monospace with a copy button. [id] names the
/// command for tests and keys; it must be unique within the handbook.
final class ManualCode extends ManualBlock {
  const ManualCode(this.id, this.text);

  final String id;
  final ManualText text;
}

/// A titled part of a chapter, made of one or more blocks.
class ManualSection {
  const ManualSection({required this.heading, required this.blocks});

  final ManualText heading;
  final List<ManualBlock> blocks;
}

/// One chapter of the handbook. [slug] feeds the stable test id
/// `manual-chapter-<slug>`.
class ManualChapter {
  const ManualChapter({
    required this.slug,
    required this.title,
    required this.sections,
  });

  final String slug;
  final ManualText title;
  final List<ManualSection> sections;
}
