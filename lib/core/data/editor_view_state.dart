/// Where someone was in an entry (#678): caret/selection, scroll anchor,
/// text size and the folded sections. Kept beside the text, never in it —
/// restoring or forgetting a view state cannot change a single character.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show listEquals;

import '../logging/app_logger.dart';
import 'content_metadata.dart';

export 'content_metadata.dart' show ContentKind, ContentKey;

typedef ViewStateWriter = Future<void> Function(Future<void> Function() action);

/// One entry's remembered view. Offsets are UTF-16 offsets into the entry's
/// text, like [TextSelection]; [anchorBlock] is a paragraph index (a row of
/// the long-note editor) and [anchorOffset] the pixels of that paragraph that
/// lay above the top of the viewport, so the same line comes back under the
/// same edge even when the text above it was re-wrapped.
class EditorViewState {
  const EditorViewState({
    this.selectionBase = 0,
    this.selectionExtent = 0,
    this.anchorBlock = 0,
    this.anchorOffset = 0,
    this.zoom = 1.0,
    this.folded = const [],
  });

  static const minZoom = 0.5;
  static const maxZoom = 3.0;
  static const zoomStep = 0.1;

  /// Bump when the meaning of a field changes; older rows are then ignored.
  static const version = 1;

  final int selectionBase;
  final int selectionExtent;
  final int anchorBlock;
  final double anchorOffset;
  final double zoom;

  /// Indices of folded sections. Reserved for folding (follow-up of #678);
  /// nothing writes it yet, but stored rows keep it.
  final List<int> folded;

  bool get isDefaultZoom => (zoom - 1.0).abs() < 0.001;

  EditorViewState copyWith({
    int? selectionBase,
    int? selectionExtent,
    int? anchorBlock,
    double? anchorOffset,
    double? zoom,
    List<int>? folded,
  }) => EditorViewState(
    selectionBase: selectionBase ?? this.selectionBase,
    selectionExtent: selectionExtent ?? this.selectionExtent,
    anchorBlock: anchorBlock ?? this.anchorBlock,
    anchorOffset: anchorOffset ?? this.anchorOffset,
    zoom: zoom ?? this.zoom,
    folded: folded ?? this.folded,
  );

  /// The state made safe for [text] as it is now: the text may have changed
  /// elsewhere (sync, import, a restored version) since the state was saved.
  EditorViewState clampedTo(String text) {
    final length = text.length;
    final blocks = paragraphCount(text);
    return EditorViewState(
      selectionBase: selectionBase.clamp(0, length),
      selectionExtent: selectionExtent.clamp(0, length),
      anchorBlock: anchorBlock.clamp(0, blocks - 1),
      anchorOffset: math.max(0, anchorOffset),
      zoom: clampZoom(zoom),
      folded: [
        for (final i in folded)
          if (i >= 0 && i < blocks) i,
      ],
    );
  }

  /// One step larger (+1) or smaller (-1), rounded to whole steps.
  static double stepZoom(double zoom, int direction) =>
      clampZoom(((zoom / zoomStep).round() + direction) * zoomStep);

  static double clampZoom(double zoom) => zoom.isFinite
      ? double.parse(zoom.clamp(minZoom, maxZoom).toStringAsFixed(2))
      : 1.0;

  Map<String, Object> toJson() => {
    'v': version,
    'base': selectionBase,
    'extent': selectionExtent,
    'block': anchorBlock,
    'offset': anchorOffset,
    'zoom': zoom,
    'folded': folded,
  };

  /// Null for anything that is not a state this build understands.
  static EditorViewState? fromJson(Object? json) {
    if (json is! Map || json['v'] != version) return null;
    int integer(String key) => (json[key] as num?)?.toInt() ?? 0;
    final folded = json['folded'];
    return EditorViewState(
      selectionBase: integer('base'),
      selectionExtent: integer('extent'),
      anchorBlock: integer('block'),
      anchorOffset: (json['offset'] as num?)?.toDouble() ?? 0,
      zoom: clampZoom((json['zoom'] as num?)?.toDouble() ?? 1.0),
      folded: folded is List
          ? [for (final i in folded.whereType<num>()) i.toInt()]
          : const [],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EditorViewState &&
      other.selectionBase == selectionBase &&
      other.selectionExtent == selectionExtent &&
      other.anchorBlock == anchorBlock &&
      other.anchorOffset == anchorOffset &&
      other.zoom == zoom &&
      listEquals(other.folded, folded);

  @override
  int get hashCode => Object.hash(
    selectionBase,
    selectionExtent,
    anchorBlock,
    anchorOffset,
    zoom,
    Object.hashAll(folded),
  );

  /// Paragraphs are separated by a line break; an empty text has one.
  static int paragraphCount(String text) => '\n'.allMatches(text).length + 1;

  /// The paragraph [offset] lies in.
  static int paragraphAt(String text, int offset) {
    final end = offset.clamp(0, text.length);
    var count = 0;
    for (var i = 0; i < end; i++) {
      if (text.codeUnitAt(i) == 0x0A) count++;
    }
    return count;
  }

  /// The offset where paragraph [index] begins (clamped to the text).
  static int paragraphStart(String text, int index) {
    if (index <= 0) return 0;
    var seen = 0;
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0A && ++seen == index) return i + 1;
    }
    return text.length;
  }
}

/// Persists [EditorViewState]s per [ContentKey] in a table of its own. SQL
/// triggers drop a state together with its entry, notes and snippets alike,
/// and a sweep on open removes anything a past build left behind.
class EditorViewStateStore {
  EditorViewStateStore(this._db, this._write);

  final GeneratedDatabase _db;
  final ViewStateWriter _write;
  bool _ready = false;
  static final _log = AppLogger('EditorViewStateStore');

  static const _table = 'editor_view_states';

  Future<void> initialize() async {
    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS $_table (
        kind TEXT NOT NULL, id TEXT NOT NULL, state TEXT NOT NULL,
        updated_at INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (kind, id)
      )
    ''');
    for (final MapEntry(key: table, value: kinds) in _owners.entries) {
      final names = kinds.map((k) => "'${k.name}'").join(', ');
      await _db.customStatement('''
        CREATE TRIGGER IF NOT EXISTS view_state_${table}_delete
        AFTER DELETE ON $table BEGIN
          DELETE FROM $_table WHERE kind IN ($names) AND id = old.id;
        END
      ''');
      await _db.customStatement(
        'DELETE FROM $_table WHERE kind IN ($names) '
        'AND id NOT IN (SELECT id FROM $table)',
      );
    }
    final known = ContentKind.values.map((k) => "'${k.name}'").join(', ');
    await _db.customStatement('DELETE FROM $_table WHERE kind NOT IN ($known)');
    _ready = true;
  }

  Future<EditorViewState?> read(ContentKey key) async {
    if (!_ready) return null;
    try {
      final row = await _db
          .customSelect(
            'SELECT state FROM $_table WHERE kind = ? AND id = ?',
            variables: [Variable(key.kind.name), Variable(key.id)],
          )
          .getSingleOrNull();
      if (row == null) return null;
      return EditorViewState.fromJson(jsonDecode(row.read<String>('state')));
    } on Object catch (e) {
      // A view state is a convenience: a broken row opens the entry at its
      // default place instead of failing to open it.
      _log.warning('read failed: $e');
      return null;
    }
  }

  /// Stores [state] only while the entry exists, so a save racing a delete
  /// cannot leave a state behind for an id that is gone.
  Future<void> save(ContentKey key, EditorViewState state) async {
    if (!_ready) return;
    final owner = _ownerOf(key.kind);
    await _write(
      () => _db.customStatement(
        'INSERT INTO $_table(kind, id, state, updated_at) '
        'SELECT ?, ?, ?, ? WHERE EXISTS (SELECT 1 FROM $owner WHERE id = ?) '
        'ON CONFLICT(kind, id) DO UPDATE SET '
        'state = excluded.state, updated_at = excluded.updated_at',
        [
          key.kind.name,
          key.id,
          jsonEncode(state.toJson()),
          DateTime.now().millisecondsSinceEpoch,
          key.id,
        ],
      ),
    );
  }

  static const _owners = {
    'history_entries': [ContentKind.recording, ContentKind.recordingEdited],
    'notes': [ContentKind.note],
    'snippets': [ContentKind.snippet],
  };

  static String _ownerOf(ContentKind kind) => switch (kind) {
    ContentKind.recording || ContentKind.recordingEdited => 'history_entries',
    ContentKind.note => 'notes',
    ContentKind.snippet => 'snippets',
  };
}
