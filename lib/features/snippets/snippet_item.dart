import '../../core/sorting/list_sort.dart';

/// UI-facing snippet — named separately from the drift-generated [Snippet]
/// row class to avoid a name collision.
class SnippetItem implements UsageSortable {
  const SnippetItem({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.updatedAt,
    this.kind = 'static',
    this.fields = const [],
    this.isFavorite = false,
    this.useCount = 0,
    this.lastUsedAt,
    this.sourceNoteId,
  });

  final String id;
  final String title;
  final String body;

  /// Starred by the user; favourites are listed first.
  final bool isFavorite;

  /// How often the snippet was inserted (picker or page); local only.
  final int useCount;

  /// When it was last inserted, `null` if never.
  final DateTime? lastUsedAt;

  /// The note this snippet was saved from ("save selection as
  /// Textbaustein"), `null` otherwise. Drives the back-reference (#664).
  final String? sourceNoteId;

  /// When the snippet was created. Kept on edit, see [SnippetsNotifier].
  final DateTime createdAt;

  /// Last content change, `null` for rows from before schema v32.
  final DateTime? updatedAt;

  /// `static` (default — [body] is inserted verbatim) or `interactive`
  /// (interactive-snippets PRD — [fields] names the guided recording
  /// sequence's fields in order; [body] holds the user-authored template,
  /// with an `{{fieldName}}` placeholder for each field's dictated text —
  /// see `interactive_snippet_composer.dart`).
  final String kind;

  /// Ordered field names for an `interactive` snippet. Empty for `static`.
  final List<String> fields;

  bool get isInteractive => kind == 'interactive';

  @override
  String get sortId => id;

  @override
  String get sortTitle => title;

  /// Snippets have no result column; the body is never sorted on.
  @override
  String get sortResult => '';

  @override
  DateTime get sortCreatedAt => createdAt;

  @override
  DateTime get sortChangedAt => updatedAt ?? createdAt;

  @override
  DateTime? get sortUsedAt => lastUsedAt;
}

/// Favourites first, otherwise the order [items] already has.
List<SnippetItem> favouritesFirst(List<SnippetItem> items) => [
  ...items.where((s) => s.isFavorite),
  ...items.where((s) => !s.isFavorite),
];
