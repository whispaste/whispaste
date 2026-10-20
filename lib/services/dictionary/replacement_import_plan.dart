/// Plans a replacement-package import against the list that already exists
/// (R-08, `.scratch/dictionary-packs/01-spec.md` section 7). Pure: no
/// database, no file access. The preview and the write both use this plan, so
/// the numbers the user sees are the numbers that get written.
library;

import 'dart:math' as math;

import '../replacements/text_replacement_matcher.dart'
    show TextReplacementMatchMode;
import 'replacement_csv.dart';
import 'replacement_duplicates.dart';

/// What to do with a row that collides with an existing trigger.
enum ReplacementImportStrategy {
  /// Leave the conflicting row out. Existing entries stay as they are.
  skip,

  /// Remove the colliding triggers from the existing entries, then add the row.
  overwrite,

  /// Add the row next to the existing entries. The earlier entry wins for a
  /// trigger both entries share.
  keepBoth,
}

enum ReplacementImportStatus {
  /// No collision: the row is added.
  added,

  /// Every trigger is already present with the same replacement and mode.
  duplicate,

  /// Collision, skipped by the chosen strategy.
  conflictSkipped,

  /// Collision, the row replaces the colliding triggers of the existing entries.
  conflictReplaced,

  /// Collision, the row is added next to the existing entry.
  conflictKept,

  /// Collision with an earlier row of the same file, which a later row of the
  /// file then overwrote. Nothing is written for it.
  supersededInFile,

  /// The row closes a loop of at least two triggers (A to B and back). Never
  /// written, whatever the strategy.
  circular,
}

/// An entry that is already in the list, as the planner needs it.
class ReplacementImportExisting {
  const ReplacementImportExisting({
    required this.id,
    required this.triggers,
    required this.replacement,
    this.matchMode = TextReplacementMatchMode.exact,
    this.fuzzyThreshold,
  });

  final String id;
  final List<String> triggers;
  final String replacement;
  final TextReplacementMatchMode matchMode;
  final double? fuzzyThreshold;
}

/// New trigger list for an existing entry. The list is never empty; an entry
/// that loses all its triggers is in [ReplacementImportPlan.deleteIds].
class ReplacementImportUpdate {
  const ReplacementImportUpdate({required this.id, required this.triggers});

  final String id;
  final List<String> triggers;
}

class ReplacementImportPlan {
  const ReplacementImportPlan({
    required this.statuses,
    required this.inserts,
    required this.updates,
    required this.deleteIds,
  });

  /// One status per input row, in input order.
  final List<ReplacementImportStatus> statuses;

  /// Entries to create, each as the row it was read from (triggers already
  /// reduced to the ones that are written).
  final List<ReplacementCsvRow> inserts;

  /// Existing entries that keep at least one trigger but lose some.
  final List<ReplacementImportUpdate> updates;

  /// Existing entries that lose their last trigger.
  final List<String> deleteIds;

  int count(ReplacementImportStatus status) =>
      statuses.where((s) => s == status).length;

  /// Rows that collide with an existing trigger, whatever the strategy.
  int get conflictCount =>
      count(ReplacementImportStatus.conflictSkipped) +
      count(ReplacementImportStatus.conflictReplaced) +
      count(ReplacementImportStatus.conflictKept) +
      count(ReplacementImportStatus.supersededInFile);

  /// Existing entries that a write changes or removes.
  int get changedExistingCount => updates.length + deleteIds.length;

  /// Number of entries the write creates.
  int get writeCount => inserts.length;
}

/// Plans the import of [rows] into a list that already holds [existing].
ReplacementImportPlan planReplacementImport({
  required List<ReplacementCsvRow> rows,
  required List<ReplacementImportExisting> existing,
  required ReplacementImportStrategy strategy,
}) {
  final state = _PlanState();
  for (final e in existing) {
    state.add(_PlanEntry.existing(e));
  }

  final rowEntry = <_PlanEntry?>[];
  final rowStatus = <ReplacementImportStatus>[];
  for (final row in rows) {
    final outcome = _planRow(state, row, strategy);
    rowEntry.add(outcome.entry);
    rowStatus.add(outcome.status);
  }

  final circular = state.circularNewEntries();
  final statuses = [
    for (var i = 0; i < rows.length; i++)
      _finalStatus(rowStatus[i], rowEntry[i], circular),
  ];

  final inserts = <ReplacementCsvRow>[];
  final updates = <ReplacementImportUpdate>[];
  final deleteIds = <String>[];
  for (final entry in state.entries) {
    if (entry.isNew) {
      if (!entry.dead && !circular.contains(entry)) {
        inserts.add(entry.toRow());
      }
    } else if (entry.dead) {
      deleteIds.add(entry.id!);
    } else if (entry.triggersChanged) {
      updates.add(
        ReplacementImportUpdate(id: entry.id!, triggers: entry.triggerList),
      );
    }
  }

  return ReplacementImportPlan(
    statuses: statuses,
    inserts: inserts,
    updates: updates,
    deleteIds: deleteIds,
  );
}

class _RowOutcome {
  const _RowOutcome(this.status, this.entry);

  final ReplacementImportStatus status;

  /// The entry this row created, when it was written into the plan.
  final _PlanEntry? entry;
}

_RowOutcome _planRow(
  _PlanState state,
  ReplacementCsvRow row,
  ReplacementImportStrategy strategy,
) {
  final incoming = _uniqueTriggers(row.triggers);
  final incomingKeys = [
    for (final key in incoming.keys)
      if (_isCollidable(key)) key,
  ];
  final owners = <_PlanEntry>{
    for (final key in incomingKeys) ...state.owners(key),
  };
  if (owners.isEmpty) {
    return _RowOutcome(
      ReplacementImportStatus.added,
      _addNew(state, row, incoming),
    );
  }

  final identity = _identity(
    row.replacement,
    row.matchMode,
    row.fuzzyThreshold,
  );
  final coveredKeys = <String>{
    for (final owner in owners) ...owner.collidableKeys,
  };
  final isDuplicate =
      owners.every((owner) => owner.identity == identity) &&
      incomingKeys.every(coveredKeys.contains);
  if (isDuplicate) {
    return const _RowOutcome(ReplacementImportStatus.duplicate, null);
  }

  switch (strategy) {
    case ReplacementImportStrategy.skip:
      return const _RowOutcome(ReplacementImportStatus.conflictSkipped, null);
    case ReplacementImportStrategy.keepBoth:
      return _RowOutcome(
        ReplacementImportStatus.conflictKept,
        _addNew(state, row, incoming),
      );
    case ReplacementImportStrategy.overwrite:
      for (final owner in owners) {
        state.removeKeys(owner, incomingKeys.toSet());
      }
      return _RowOutcome(
        ReplacementImportStatus.conflictReplaced,
        _addNew(state, row, incoming),
      );
  }
}

/// A row written into the plan can still be undone by a later row of the
/// same file (overwrite) or be part of a loop; that decides its final status.
ReplacementImportStatus _finalStatus(
  ReplacementImportStatus status,
  _PlanEntry? entry,
  Set<_PlanEntry> circular,
) {
  if (entry == null || !entry.isNew) return status;
  if (entry.dead) return ReplacementImportStatus.supersededInFile;
  if (circular.contains(entry)) return ReplacementImportStatus.circular;
  return status;
}

_PlanEntry _addNew(
  _PlanState state,
  ReplacementCsvRow row,
  Map<String, String> incoming,
) {
  final entry = _PlanEntry.fromRow(row, incoming.values.toList());
  state.add(entry);
  return entry;
}

/// Prefix of the key of a phrase without letters or digits. Such a phrase
/// cannot collide with anything, but it must still survive a rewrite of its
/// entry, so it gets a key of its own.
const _keylessPrefix = '\u0000';

bool _isCollidable(String key) => !key.startsWith(_keylessPrefix);

/// Unique trigger phrases, keyed by normalised key, first spelling kept.
Map<String, String> _uniqueTriggers(List<String> triggers) {
  final out = <String, String>{};
  for (final trigger in triggers) {
    final normalised = normalizeTriggerKey(trigger);
    final key = normalised.isEmpty ? '$_keylessPrefix$trigger' : normalised;
    out.putIfAbsent(key, () => trigger);
  }
  return out;
}

String _identity(
  String replacement,
  TextReplacementMatchMode mode,
  double? threshold,
) {
  final thresholdPart = mode == TextReplacementMatchMode.fuzzy
      ? '${threshold ?? ''}'
      : '';
  return '${replacement.trim()}\u001f${mode.name}\u001f$thresholdPart';
}

class _PlanEntry {
  _PlanEntry._({
    required this.id,
    required List<String> triggers,
    required this.identity,
    required this.row,
  }) : _triggers = _uniqueTriggers(triggers),
       _originalKeys = _uniqueTriggers(triggers).keys.toSet();

  factory _PlanEntry.existing(ReplacementImportExisting e) => _PlanEntry._(
    id: e.id,
    triggers: e.triggers,
    identity: _identity(e.replacement, e.matchMode, e.fuzzyThreshold),
    row: ReplacementCsvRow(
      triggers: e.triggers,
      replacement: e.replacement,
      matchMode: e.matchMode,
      fuzzyThreshold: e.fuzzyThreshold,
    ),
  );

  factory _PlanEntry.fromRow(ReplacementCsvRow row, List<String> triggers) =>
      _PlanEntry._(
        id: null,
        triggers: triggers,
        identity: _identity(row.replacement, row.matchMode, row.fuzzyThreshold),
        row: row,
      );

  /// Null for an entry that comes from the file.
  final String? id;
  final String identity;

  /// The entry's own settings; only the trigger list changes during planning.
  final ReplacementCsvRow row;

  /// Trigger key to the phrase as it is written, in order.
  final Map<String, String> _triggers;
  final Set<String> _originalKeys;

  bool dead = false;

  bool get isNew => id == null;

  Set<String> get keys => _triggers.keys.toSet();

  Iterable<String> get collidableKeys => _triggers.keys.where(_isCollidable);

  List<String> get triggerList => _triggers.values.toList();

  bool get triggersChanged => !_setEquals(keys, _originalKeys);

  bool get isEmpty => _triggers.isEmpty;

  ReplacementCsvRow toRow() => ReplacementCsvRow(
    triggers: triggerList,
    replacement: row.replacement,
    matchMode: row.matchMode,
    fuzzyThreshold: row.fuzzyThreshold,
  );

  void removeKeys(Set<String> removed) {
    for (final key in removed) {
      _triggers.remove(key);
    }
  }

  /// Keys of the live triggers that can collide, for the owner index.
  Iterable<String> get liveKeys => collidableKeys;
}

bool _setEquals(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

/// The live entries and an index from trigger key to the entries that own it.
class _PlanState {
  final List<_PlanEntry> entries = [];
  final Map<String, Set<_PlanEntry>> _ownersByKey = {};

  void add(_PlanEntry entry) {
    entries.add(entry);
    for (final key in entry.liveKeys) {
      _ownersByKey.putIfAbsent(key, () => <_PlanEntry>{}).add(entry);
    }
  }

  Set<_PlanEntry> owners(String key) => _ownersByKey[key] ?? const {};

  /// Removes [keys] from [entry]. An entry with no trigger left is dead.
  void removeKeys(_PlanEntry entry, Set<String> keys) {
    final present = keys.where(entry.keys.contains).toSet();
    if (present.isEmpty) return;
    entry.removeKeys(present);
    for (final key in present) {
      _ownersByKey[key]?.remove(entry);
    }
    if (entry.isEmpty) entry.dead = true;
  }

  /// New entries that take part in a loop of at least two keys. A key edge
  /// runs from a trigger key to the key of its replacement (self loops are
  /// allowed: "gmbh" to "GmbH" changes nothing).
  Set<_PlanEntry> circularNewEntries() {
    final live = [
      for (final e in entries)
        if (!e.dead) e,
    ];
    final nodes = <String>{for (final e in live) ...e.collidableKeys};
    final graph = <String, List<String>>{};
    for (final e in live) {
      final target = normalizeTriggerKey(e.row.replacement);
      if (target.isEmpty || !nodes.contains(target)) continue;
      for (final key in e.collidableKeys) {
        if (key == target) continue;
        graph.putIfAbsent(key, () => []).add(target);
      }
    }
    final component = _stronglyConnectedComponents(graph);

    final circular = <_PlanEntry>{};
    for (final e in live) {
      if (!e.isNew) continue;
      final target = normalizeTriggerKey(e.row.replacement);
      if (!nodes.contains(target)) continue;
      for (final key in e.collidableKeys) {
        if (key == target) continue;
        final from = component[key];
        if (from != null && from == component[target]) {
          circular.add(e);
          break;
        }
      }
    }
    return circular;
  }
}

/// Iterative Tarjan: maps each node that has outgoing edges to the id of its
/// strongly connected component. Components of one node are not in the map
/// when the node is on no loop of its own; callers only compare equal ids.
Map<String, int> _stronglyConnectedComponents(Map<String, List<String>> graph) {
  final index = <String, int>{};
  final low = <String, int>{};
  final onStack = <String>{};
  final stack = <String>[];
  final component = <String, int>{};
  var counter = 0;
  var componentCount = 0;

  for (final root in graph.keys) {
    if (index.containsKey(root)) continue;
    final work = <(String, int)>[(root, 0)];
    index[root] = low[root] = counter++;
    stack.add(root);
    onStack.add(root);
    while (work.isNotEmpty) {
      final (node, next) = work.last;
      final successors = graph[node] ?? const <String>[];
      if (next < successors.length) {
        work[work.length - 1] = (node, next + 1);
        final target = successors[next];
        if (!index.containsKey(target)) {
          index[target] = low[target] = counter++;
          stack.add(target);
          onStack.add(target);
          work.add((target, 0));
        } else if (onStack.contains(target)) {
          low[node] = math.min(low[node]!, index[target]!);
        }
        continue;
      }
      work.removeLast();
      if (work.isNotEmpty) {
        final parent = work.last.$1;
        low[parent] = math.min(low[parent]!, low[node]!);
      }
      if (low[node] == index[node]) {
        String member;
        do {
          member = stack.removeLast();
          onStack.remove(member);
          component[member] = componentCount;
        } while (member != node);
        componentCount++;
      }
    }
  }
  return component;
}
