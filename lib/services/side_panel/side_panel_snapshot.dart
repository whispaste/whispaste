import '../../core/logging/app_logger.dart';

final _log = AppLogger('SidePanelSnapshot');

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
    this.createdAt,
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

  /// When the row's content was created, in local time. Null for row kinds
  /// without a date (snippets, clipboard history); those render ungrouped.
  final DateTime? createdAt;

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'content': content,
    'kind': kind.name,
    'imageBytes': imageBytes,
    'colorSlot': colorSlot,
    'createdAt': createdAt?.millisecondsSinceEpoch,
  };

  /// Parses one row. Every field is checked by type: a value of the wrong
  /// type is dropped, not thrown, so one bad field never costs the row.
  factory SidePanelRow.fromMap(Map<dynamic, dynamic> map) {
    final created = _tolerantInt(map['createdAt']);
    return SidePanelRow(
      id: _tolerantString(map['id']),
      title: _tolerantString(map['title']),
      subtitle: _tolerantString(map['subtitle']),
      content: _tolerantString(map['content']),
      kind: SidePanelRowKind.values.firstWhere(
        (k) => k.name == map['kind'],
        orElse: () => SidePanelRowKind.text,
      ),
      imageBytes: _tolerantBytes(map['imageBytes']),
      colorSlot: _tolerantInt(map['colorSlot']),
      // Outside the DateTime range the row renders without a day header.
      createdAt: created == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(created),
    );
  }

  static String _tolerantString(Object? value) => value is String ? value : '';

  /// Finite numbers only; NaN and infinities have no integer value. Also
  /// bounded to the DateTime range, so a timestamp can always be converted.
  static int? _tolerantInt(Object? value) {
    if (value is! num || !value.isFinite) return null;
    if (value.abs() > _maxEpochMillis) return null;
    return value.toInt();
  }

  /// The image is all-or-nothing: one non-byte element drops the image, the
  /// row stays as text.
  static List<int>? _tolerantBytes(Object? value) {
    if (value is! List || !value.every((e) => e is int && e >= 0 && e < 256)) {
      return null;
    }
    return value.cast<int>();
  }

  /// Largest epoch millisecond `DateTime` accepts (8.64e15).
  static const double _maxEpochMillis = 8.64e15;
}

/// Immutable snapshot of everything the side panel needs to render.
///
/// Mirrors [FloatingOverlaySnapshot]'s "Dart owns all state, native is a
/// dumb renderer" contract.
Set<SidePanelSection> _sectionsOf(Object? raw) {
  if (raw is! List) return const {};
  return {
    for (final name in raw)
      for (final section in SidePanelSection.values)
        if (section.name == name) section,
  };
}

class SidePanelSnapshot {
  const SidePanelSnapshot({
    this.visible = false,
    this.transcriptions = const [],
    this.snippets = const [],
    this.clipboardHistory = const [],
    this.edge = 'left',
    this.clipboardLocked = false,
    this.failedSections = const {},
  });

  final bool visible;
  final List<SidePanelRow> transcriptions;
  final List<SidePanelRow> snippets;
  final List<SidePanelRow> clipboardHistory;

  /// Which screen edge the panel docks to: `'left'` or `'right'` (issue
  /// #150). Kept as a plain string rather than importing
  /// `core/config/settings_enums.dart`'s `SidePanelEdge` here -- this file is
  /// shared with the render isolate/native hosts and stays decoupled from
  /// the settings-model layer, mirroring how [SidePanelRowKind] etc. are
  /// re-derived rather than imported.
  final String edge;

  /// True while a PIN lock hides copied text (GS-125). The clipboard rows are
  /// then empty and the panel shows the locked hint instead of "nothing copied".
  final bool clipboardLocked;

  /// Sections whose data could not be loaded. The panel says so instead of
  /// showing the empty state, which would read as "nothing recorded".
  final Set<SidePanelSection> failedSections;

  Map<String, dynamic> toMap() => {
    'visible': visible,
    'clipboardLocked': clipboardLocked,
    'transcriptions': transcriptions.map((r) => r.toMap()).toList(),
    'snippets': snippets.map((r) => r.toMap()).toList(),
    'clipboardHistory': clipboardHistory.map((r) => r.toMap()).toList(),
    'edge': edge,
    'failedSections': [for (final s in failedSections) s.name],
  };

  /// Never throws for a malformed value: a row that is not a map, or that
  /// fails to parse, is dropped alone, and every other row still renders.
  factory SidePanelSnapshot.fromMap(Map<dynamic, dynamic> map) {
    List<SidePanelRow> rowsOf(String key) {
      final raw = map[key];
      if (raw is! List) return const [];
      final rows = <SidePanelRow>[];
      for (final entry in raw) {
        if (entry is! Map) continue;
        try {
          rows.add(SidePanelRow.fromMap(entry));
        } on Object catch (e) {
          // Drop this row only; the rest of the snapshot still renders.
          _log.warning('Dropped a malformed side panel row: $e');
        }
      }
      return rows;
    }

    final edge = map['edge'];
    return SidePanelSnapshot(
      visible: map['visible'] is bool && map['visible'] as bool,
      transcriptions: rowsOf('transcriptions'),
      snippets: rowsOf('snippets'),
      clipboardHistory: rowsOf('clipboardHistory'),
      edge: edge is String ? edge : 'left',
      clipboardLocked: map['clipboardLocked'] is bool
          ? map['clipboardLocked'] as bool
          : false,
      failedSections: _sectionsOf(map['failedSections']),
    );
  }
}
