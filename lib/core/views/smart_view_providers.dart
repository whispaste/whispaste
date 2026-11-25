/// State of saved views (#658): the user's own views per page, stored in
/// `app_settings`, and the view a page shows now.
///
/// Views only narrow a list. Saving, renaming or deleting one never touches
/// a note or a recording.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:whispaste/core/data/content_metadata.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/logging/app_logger.dart';

import 'smart_view.dart';

final _log = AppLogger('SmartViews');

/// The user's own views of one page, oldest first.
class SmartViewsNotifier extends AsyncNotifier<List<SmartView>> {
  SmartViewsNotifier(this._scope);

  final SmartViewScope _scope;

  String get _key => 'smart_views_${_scope.name}';

  @override
  Future<List<SmartView>> build() async {
    final raw = await ref.read(historyDatabaseProvider).readAppSetting(_key);
    return decodeSmartViews(raw);
  }

  /// Saves a new view and returns it. Blank names and empty rule lists are
  /// refused by the dialog before they get here.
  Future<SmartView> add({
    required String name,
    required SmartViewMatch match,
    required List<SmartRule> rules,
  }) async {
    final view = SmartView(
      id: generateV4Uuid(),
      name: name.trim(),
      match: match,
      rules: List.unmodifiable(rules),
    );
    await _write([...await future, view]);
    return view;
  }

  /// Replaces name, match and rules of view [id].
  Future<void> edit(
    String id, {
    required String name,
    required SmartViewMatch match,
    required List<SmartRule> rules,
  }) async {
    final views = await future;
    await _write([
      for (final v in views)
        v.id == id
            ? v.copyWith(
                name: name.trim(),
                match: match,
                rules: List.unmodifiable(rules),
              )
            : v,
    ]);
  }

  /// Removes the view, never the items it shows.
  Future<void> delete(String id) async {
    final views = await future;
    await _write([
      for (final v in views)
        if (v.id != id) v,
    ]);
    final active = ref.read(activeSmartViewProvider(_scope).notifier);
    if (ref.read(activeSmartViewProvider(_scope)) == id) active.clear();
  }

  Future<void> _write(List<SmartView> views) async {
    state = AsyncData(views);
    try {
      await ref
          .read(historyDatabaseProvider)
          .writeAppSetting(_key, encodeSmartViews(views));
    } on Object catch (e, st) {
      _log.warning('Could not save the views', e, st);
    }
  }
}

final smartViewsProvider =
    AsyncNotifierProvider.family<
      SmartViewsNotifier,
      List<SmartView>,
      SmartViewScope
    >(SmartViewsNotifier.new);

/// Id of the view a page shows now, or null for the plain list. Not
/// remembered: like the tag filter, a view that outlives the session hides
/// items the user forgot about.
class ActiveSmartViewNotifier extends Notifier<String?> {
  ActiveSmartViewNotifier(this._scope);

  // Kept for the family key; the state needs no scope.
  // ignore: unused_field
  final SmartViewScope _scope;

  @override
  String? build() => null;

  /// Shows view [id]; the same id again goes back to the plain list.
  void toggle(String id) => state = state == id ? null : id;

  void show(String id) => state = id;

  void clear() => state = null;
}

final activeSmartViewProvider =
    NotifierProvider.family<ActiveSmartViewNotifier, String?, SmartViewScope>(
      ActiveSmartViewNotifier.new,
    );

/// Built-in views first, then the user's own, for the page [scope].
final allSmartViewsProvider = Provider.family<List<SmartView>, SmartViewScope>(
  (ref, scope) => [
    ...builtInSmartViews(scope),
    ...?ref.watch(smartViewsProvider(scope)).value,
  ],
);

/// The view page [scope] shows now, or null. A deleted or unknown id counts
/// as no view, so the list never ends up empty for a stale id.
final shownSmartViewProvider = Provider.family<SmartView?, SmartViewScope>((
  ref,
  scope,
) {
  final id = ref.watch(activeSmartViewProvider(scope));
  if (id == null) return null;
  for (final v in ref.watch(allSmartViewsProvider(scope))) {
    if (v.id == id) return v;
  }
  return null;
});

/// Documents whose text holds a checklist item, read only while a view is
/// shown that needs them.
final checklistDocumentsProvider = StreamProvider.autoDispose<Set<ContentKey>>(
  (ref) => ref.watch(historyDatabaseProvider).contentIndex.watchWithChecklist(),
);

/// Ids of the notes that took quick-note dictations.
final noteIdsWithAppendsProvider = StreamProvider.autoDispose<Set<String>>(
  (ref) => ref.watch(historyDatabaseProvider).watchNoteIdsWithAppends(),
);

/// Whether [view] needs the checklist index.
bool smartViewNeedsChecklists(SmartView view) =>
    view.rules.any((r) => r is ChecklistRule);
