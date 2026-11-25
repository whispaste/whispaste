/// Saved views ("Ansichten", #658): a named set of rules that narrows a list
/// of notes or recordings. One rule engine for both pages.
///
/// Pure Dart: no database, no widgets. A view never touches content: it only
/// decides which items a list shows. The page feeds every item as a
/// [SmartViewItem]; [smartViewMatches] answers per item.
library;

import 'dart:convert';

/// The page a view belongs to. Notes and recordings keep their own views,
/// since some rules only make sense on one of them (a quick note is a note).
enum SmartViewScope { notes, recordings }

/// Whether every rule must hold ("alle") or one is enough ("beliebige").
enum SmartViewMatch { all, any }

/// Where an item's text came from.
///
/// - [dictation]: a recording dictated with the main hotkey.
/// - [audioImport]: a recording made from an imported audio file.
/// - [quickNote]: a note that took quick-note dictations (the marked quick
///   note, or a note with quick-note dictation marks).
/// - [fromRecording]: a note taken over from a recording.
enum SmartViewSource { dictation, audioImport, quickNote, fromRecording }

/// The sources a rule can name on [scope].
List<SmartViewSource> sourcesFor(SmartViewScope scope) => switch (scope) {
  SmartViewScope.notes => const [
    SmartViewSource.quickNote,
    SmartViewSource.fromRecording,
  ],
  SmartViewScope.recordings => const [
    SmartViewSource.dictation,
    SmartViewSource.audioImport,
  ],
};

/// A rolling period counted in calendar days, today included.
enum SmartViewPeriod {
  today(1),
  week(7),
  month(30);

  const SmartViewPeriod(this.days);

  /// Calendar days the period spans, today included.
  final int days;

  /// Whether [at] falls into the period seen from [now].
  bool contains(DateTime at, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final start = DateTime(today.year, today.month, today.day - (days - 1));
    return !at.isBefore(start);
  }
}

/// One condition of a view.
sealed class SmartRule {
  const SmartRule();

  bool matches(SmartViewItem item, DateTime now);

  Map<String, Object?> toJson();

  /// Null for an unknown or broken rule: a view written by a newer app
  /// version loses that rule instead of failing as a whole.
  static SmartRule? fromJson(Object? json) {
    if (json is! Map) return null;
    final type = json['type'];
    switch (type) {
      case 'tag':
        final id = json['tagId'];
        final name = json['tagName'];
        if (id is! String || id.isEmpty) return null;
        return TagRule(tagId: id, tagName: name is String ? name : '');
      case 'untagged':
        return const UntaggedRule();
      case 'period':
        final p = _byName(SmartViewPeriod.values, json['period']);
        return p == null ? null : PeriodRule(p);
      case 'source':
        final s = _byName(SmartViewSource.values, json['source']);
        return s == null ? null : SourceRule(s);
      case 'checklist':
        return const ChecklistRule();
      case 'pinned':
        return const PinnedRule();
      case 'folder':
        final id = json['folderId'];
        final name = json['folderName'];
        if (id is! String || id.isEmpty) return null;
        return FolderRule(folderId: id, folderName: name is String ? name : '');
    }
    return null;
  }
}

/// The item carries the tag. Matched by id, else by name: recordings know
/// their tags by name.
final class TagRule extends SmartRule {
  const TagRule({required this.tagId, required this.tagName});

  final String tagId;

  /// The name when the rule was made; only a fallback for items that carry
  /// names, not ids.
  final String tagName;

  @override
  bool matches(SmartViewItem item, DateTime now) =>
      item.tagIds.contains(tagId) ||
      (tagName.isNotEmpty && item.tagNames.contains(tagName.toLowerCase()));

  @override
  Map<String, Object?> toJson() => {
    'type': 'tag',
    'tagId': tagId,
    'tagName': tagName,
  };

  @override
  bool operator ==(Object other) => other is TagRule && other.tagId == tagId;

  @override
  int get hashCode => Object.hash('tag', tagId);
}

/// The item carries no tag at all.
final class UntaggedRule extends SmartRule {
  const UntaggedRule();

  @override
  bool matches(SmartViewItem item, DateTime now) =>
      item.tagIds.isEmpty && item.tagNames.isEmpty;

  @override
  Map<String, Object?> toJson() => {'type': 'untagged'};

  @override
  bool operator ==(Object other) => other is UntaggedRule;

  @override
  int get hashCode => 'untagged'.hashCode;
}

/// The item's date (last edit of a note, time of a recording) lies in the
/// period.
final class PeriodRule extends SmartRule {
  const PeriodRule(this.period);

  final SmartViewPeriod period;

  @override
  bool matches(SmartViewItem item, DateTime now) =>
      period.contains(item.date, now);

  @override
  Map<String, Object?> toJson() => {'type': 'period', 'period': period.name};

  @override
  bool operator ==(Object other) =>
      other is PeriodRule && other.period == period;

  @override
  int get hashCode => Object.hash('period', period);
}

/// The item's text came from [source].
final class SourceRule extends SmartRule {
  const SourceRule(this.source);

  final SmartViewSource source;

  @override
  bool matches(SmartViewItem item, DateTime now) =>
      item.sources.contains(source);

  @override
  Map<String, Object?> toJson() => {'type': 'source', 'source': source.name};

  @override
  bool operator ==(Object other) =>
      other is SourceRule && other.source == source;

  @override
  int get hashCode => Object.hash('source', source);
}

/// The item's text holds at least one checklist item.
final class ChecklistRule extends SmartRule {
  const ChecklistRule();

  @override
  bool matches(SmartViewItem item, DateTime now) => item.hasChecklist;

  @override
  Map<String, Object?> toJson() => {'type': 'checklist'};

  @override
  bool operator ==(Object other) => other is ChecklistRule;

  @override
  int get hashCode => 'checklist'.hashCode;
}

/// The item is pinned (a favourite).
final class PinnedRule extends SmartRule {
  const PinnedRule();

  @override
  bool matches(SmartViewItem item, DateTime now) => item.pinned;

  @override
  Map<String, Object?> toJson() => {'type': 'pinned'};

  @override
  bool operator ==(Object other) => other is PinnedRule;

  @override
  int get hashCode => 'pinned'.hashCode;
}

/// The note sits in the folder or in one of its subfolders (#659). Only
/// notes have folders; a recording never matches.
final class FolderRule extends SmartRule {
  const FolderRule({required this.folderId, required this.folderName});

  final String folderId;

  /// The name when the rule was made, shown while the folder is gone.
  final String folderName;

  @override
  bool matches(SmartViewItem item, DateTime now) =>
      item.folderIds.contains(folderId);

  @override
  Map<String, Object?> toJson() => {
    'type': 'folder',
    'folderId': folderId,
    'folderName': folderName,
  };

  @override
  bool operator ==(Object other) =>
      other is FolderRule && other.folderId == folderId;

  @override
  int get hashCode => Object.hash('folder', folderId);
}

/// What the rules read of one note or recording.
class SmartViewItem {
  const SmartViewItem({
    required this.date,
    this.tagIds = const <String>{},
    this.tagNames = const <String>{},
    this.sources = const <SmartViewSource>{},
    this.hasChecklist = false,
    this.pinned = false,
    this.folderIds = const <String>{},
  });

  /// Last edit of a note, time of a recording.
  final DateTime date;
  final Set<String> tagIds;

  /// Lower-cased tag names (recordings know their tags by name).
  final Set<String> tagNames;
  final Set<SmartViewSource> sources;
  final bool hasChecklist;
  final bool pinned;

  /// The note's folder and, for a subfolder, its parent (#659); empty at the
  /// top level and for recordings.
  final Set<String> folderIds;
}

/// A saved view. Built-in views carry no [name] (the page shows a translated
/// one) and cannot be renamed or deleted.
class SmartView {
  const SmartView({
    required this.id,
    required this.rules,
    this.name = '',
    this.match = SmartViewMatch.all,
    this.builtIn = false,
  });

  final String id;
  final String name;
  final SmartViewMatch match;
  final List<SmartRule> rules;
  final bool builtIn;

  SmartView copyWith({
    String? name,
    SmartViewMatch? match,
    List<SmartRule>? rules,
  }) => SmartView(
    id: id,
    name: name ?? this.name,
    match: match ?? this.match,
    rules: rules ?? this.rules,
    builtIn: builtIn,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'match': match.name,
    'rules': [for (final r in rules) r.toJson()],
  };

  /// Null for a broken entry or one without any rule left.
  static SmartView? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    if (id is! String || id.isEmpty || name is! String) return null;
    final rawRules = json['rules'];
    final rules = <SmartRule>[
      if (rawRules is List)
        for (final r in rawRules) ?SmartRule.fromJson(r),
    ];
    if (rules.isEmpty) return null;
    return SmartView(
      id: id,
      name: name,
      match:
          _byName(SmartViewMatch.values, json['match']) ?? SmartViewMatch.all,
      rules: rules,
    );
  }
}

/// Whether [item] belongs to [view] at [now]. A view without rules shows
/// nothing: it cannot be saved, and a broken one must not look like "all".
bool smartViewMatches(SmartView view, SmartViewItem item, DateTime now) {
  if (view.rules.isEmpty) return false;
  return switch (view.match) {
    SmartViewMatch.all => view.rules.every((r) => r.matches(item, now)),
    SmartViewMatch.any => view.rules.any((r) => r.matches(item, now)),
  };
}

/// Ids of the built-in views.
abstract final class BuiltInSmartViews {
  static const recent = 'builtin-recent';
  static const pinned = 'builtin-pinned';
  static const untagged = 'builtin-untagged';
  static const quickNotes = 'builtin-quick-notes';
  static const checklist = 'builtin-checklist';
}

/// The built-in views of [scope], in display order. "Zuletzt" is the last
/// seven days. Recordings have no quick notes.
List<SmartView> builtInSmartViews(SmartViewScope scope) => [
  const SmartView(
    id: BuiltInSmartViews.recent,
    rules: [PeriodRule(SmartViewPeriod.week)],
    builtIn: true,
  ),
  const SmartView(
    id: BuiltInSmartViews.pinned,
    rules: [PinnedRule()],
    builtIn: true,
  ),
  const SmartView(
    id: BuiltInSmartViews.untagged,
    rules: [UntaggedRule()],
    builtIn: true,
  ),
  if (scope == SmartViewScope.notes)
    const SmartView(
      id: BuiltInSmartViews.quickNotes,
      rules: [SourceRule(SmartViewSource.quickNote)],
      builtIn: true,
    ),
  const SmartView(
    id: BuiltInSmartViews.checklist,
    rules: [ChecklistRule()],
    builtIn: true,
  ),
];

/// Stored form of the user's own views (an `app_settings` value).
String encodeSmartViews(List<SmartView> views) => jsonEncode([
  for (final v in views)
    if (!v.builtIn) v.toJson(),
]);

/// The user's own views from [raw]; broken entries and repeated ids are
/// dropped, never the whole list.
List<SmartView> decodeSmartViews(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return const [];
  }
  if (decoded is! List) return const [];
  final seen = <String>{};
  return [
    for (final entry in decoded)
      if (SmartView.fromJson(entry) case final view?)
        if (seen.add(view.id)) view,
  ];
}

T? _byName<T extends Enum>(List<T> values, Object? name) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}
