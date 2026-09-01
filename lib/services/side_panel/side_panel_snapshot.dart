/// Which of the panel's three sections a row belongs to.
enum SidePanelSection { transcriptions, snippets, clipboardHistory }

/// Visual kind of a row's content preview.
enum SidePanelRowKind { text, image }

/// One pre-resolved, ready-to-render row.
///
/// Dart owns all state -- by the time a row reaches the render engine
/// (issue 04+), every field is already formatted/truncated; the render side
/// never re-derives anything from a raw domain model (HistoryEntry,
/// SnippetItem, ClipboardHistoryEntry). [id] round-trips back through a
/// click event so the owning [SidePanelService] can resolve it against the
/// live data it was built from.
class SidePanelRow {
  const SidePanelRow({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.content = '',
    this.kind = SidePanelRowKind.text,
    this.imageBytes,
    this.colorSlot,
  });

  final String id;
  final String title;
  final String subtitle;
  final SidePanelRowKind kind;

  /// The full, unabridged insertable text for this row -- e.g. a
  /// transcription's complete content or a snippet's complete body, as
  /// opposed to [title], which may be a short display label (a snippet's
  /// name) rather than what actually gets inserted.
  ///
  /// Populated for [SidePanelRowKind.text] rows so a later synchronous
  /// native drag (issue 11) can read it straight from the snapshot without a
  /// round-trip to the main engine (see PRD.md issue 10). Empty for
  /// [SidePanelRowKind.image] rows, which carry their full content in
  /// [imageBytes] instead.
  final String content;

  /// Pre-downscaled thumbnail bytes -- present only when [kind] is
  /// [SidePanelRowKind.image]. The panel never decodes a full-size image
  /// per row (see PRD.md "Ring-Buffer-Limits").
  final List<int>? imageBytes;

  /// Index into `WpCategorySlot.categories`, for rows whose underlying
  /// domain model carries a persisted color slot (currently only
  /// `HistoryEntry.colorSlot`) -- lets the row's avatar match the same
  /// entry's avatar in the main window instead of always reading as
  /// uncategorised. Null for row kinds with no such persisted slot
  /// (snippets, clipboard history), which render with the neutral slot.
  final int? colorSlot;

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'content': content,
    'kind': kind.name,
    'imageBytes': imageBytes,
    'colorSlot': colorSlot,
  };

  factory SidePanelRow.fromMap(Map<dynamic, dynamic> map) => SidePanelRow(
    id: map['id'] as String? ?? '',
    title: map['title'] as String? ?? '',
    subtitle: map['subtitle'] as String? ?? '',
    content: map['content'] as String? ?? '',
    kind: SidePanelRowKind.values.firstWhere(
      (k) => k.name == map['kind'],
      orElse: () => SidePanelRowKind.text,
    ),
    imageBytes: (map['imageBytes'] as List?)?.cast<int>(),
    colorSlot: map['colorSlot'] as int?,
  );
}

/// Immutable snapshot of everything the side panel needs to render.
///
/// Mirrors [FloatingOverlaySnapshot]'s "Dart owns all state, native is a
/// dumb renderer" contract.
class SidePanelSnapshot {
  const SidePanelSnapshot({
    this.visible = false,
    this.transcriptions = const [],
    this.snippets = const [],
    this.clipboardHistory = const [],
  });

  final bool visible;
  final List<SidePanelRow> transcriptions;
  final List<SidePanelRow> snippets;
  final List<SidePanelRow> clipboardHistory;

  Map<String, dynamic> toMap() => {
    'visible': visible,
    'transcriptions': transcriptions.map((r) => r.toMap()).toList(),
    'snippets': snippets.map((r) => r.toMap()).toList(),
    'clipboardHistory': clipboardHistory.map((r) => r.toMap()).toList(),
  };

  factory SidePanelSnapshot.fromMap(Map<dynamic, dynamic> map) {
    List<SidePanelRow> rowsOf(String key) => (map[key] as List? ?? const [])
        .map((e) => SidePanelRow.fromMap(e as Map))
        .toList();
    return SidePanelSnapshot(
      visible: map['visible'] as bool? ?? false,
      transcriptions: rowsOf('transcriptions'),
      snippets: rowsOf('snippets'),
      clipboardHistory: rowsOf('clipboardHistory'),
    );
  }
}
