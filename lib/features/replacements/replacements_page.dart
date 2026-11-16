import 'dart:async';

import '../../core/search/search_ranker.dart';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/config/settings_provider.dart';
import '../../core/data/reloadable_list_notifier.dart';
import '../../core/sorting/list_sort.dart';
import '../../core/sorting/list_sort_preference.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/l10n/ltr_isolate.dart';
import '../../services/replacements/text_replacement_matcher.dart'
    show
        TextReplacementMatchMode,
        exactFallbackTriggers,
        exactTriggerNeverFires,
        newEntryMatch,
        fuzzyMinTriggerLength,
        fuzzyThresholdStrict,
        fuzzyThresholdStandard,
        fuzzyThresholdTolerant;
import '../../services/dictionary/entry_validation.dart';
import '../../services/dictionary/replacement_duplicates.dart';
import '../../services/dictionary/replacement_import_plan.dart';
import '../../services/replacements/correction_learning_service.dart';
import '../../services/replacements/correction_log.dart';
import '../../services/replacements/symbol_template_pack.dart';
import '../../services/replacements/vocabulary_import_service.dart';
import '../dictionary/role_terms.dart' show vocabularyTerms;
import '../../services/telemetry_service.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/wp_list_tile_surface.dart';
import '../../widgets/wp_row_action.dart';
import '../../widgets/dialog.dart';
import '../../widgets/list_reveal.dart';
import '../../widgets/searchable_list_page.dart';
import '../../widgets/trigger_chip.dart';
import '../../widgets/wp_accent_badge.dart';
import '../../widgets/wp_banner.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/wp_page_notice.dart';
import '../dictionary/dictionary_notice.dart';
import '../dictionary/dictionary_tab_target.dart';
import '../../widgets/wp_favourite_star.dart';
import '../../widgets/wp_segmented_selector.dart';
import '../../widgets/wp_sort_menu_button.dart';
import '../../widgets/wp_text_field.dart';
import 'vocabulary_import_review_page.dart';
import '../../services/dictionary/replacement_order.dart';
import '../../widgets/wp_icon_button.dart';
import 'package:whispaste/core/data/database.dart';

import '../../widgets/wp_copy_feedback.dart';

part 'replacement_order_dialog.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

class Replacement implements ListSortable {
  const Replacement({
    required this.id,
    required this.triggers,
    required this.replacement,
    required this.createdAt,
    this.updatedAt,
    this.matchMode = TextReplacementMatchMode.exact,
    this.fuzzyThreshold,
    this.origin = 'manual',
    this.isFavorite = false,
    this.usageCount = 0,
  });

  final String id;

  /// When the entry was created. Kept on edit, see [ReplacementsNotifier].
  final DateTime createdAt;

  /// Last content change, `null` for rows from before schema v32.
  final DateTime? updatedAt;

  /// Every trigger phrase that fires this replacement. Always non-empty.
  final List<String> triggers;
  final String replacement;

  /// `exact` (legacy behavior) or `fuzzy` (similarity-based, PRD.md
  /// vocabulary-fuzzy-replacements).
  final TextReplacementMatchMode matchMode;

  /// Only meaningful when [matchMode] is `fuzzy` — one of the three named
  /// UI steps (Strict 0.92 / Standard 0.85 / Tolerant 0.75).
  final double? fuzzyThreshold;

  /// `manual` (user-created) or `imported` (via vocabulary-folder import) —
  /// display-only, no behavioral difference (PRD.md User Story 11).
  final String origin;

  /// Pinned by the user in the dictionary (schema v26). Display only.
  final bool isFavorite;

  /// Dictations this entry changed so far (schema v26). Display only.
  final int usageCount;

  @override
  String get sortId => id;

  /// The first trigger is the entry's name for sorting, see `list_sort.dart`.
  @override
  String get sortTitle => triggers.isEmpty ? '' : triggers.first;

  @override
  String get sortResult => replacement;

  @override
  DateTime get sortCreatedAt => createdAt;

  @override
  DateTime get sortChangedAt => updatedAt ?? createdAt;
}

// ---------------------------------------------------------------------------
// State management (Riverpod AsyncNotifier — persisted in Drift DB)
// ---------------------------------------------------------------------------

/// app_settings key recording that the first-start samples were handled.
const _kSamplesSeededKey = 'replacementsSamplesSeeded';

class ReplacementsNotifier extends AsyncNotifier<List<Replacement>>
    with ReloadableListNotifier<Replacement> {
  @override
  Future<List<Replacement>> readAll() async {
    final db = ref.read(historyDatabaseProvider);
    return (await db.readAllReplacements()).map(_fromDb).toList();
  }

  @override
  Future<List<Replacement>> build() async {
    final db = ref.read(historyDatabaseProvider);
    final rows = await db.readAllReplacements();
    // Samples are a first-start courtesy only. Once the flag is set, an empty
    // list stays empty; otherwise clearing it would bring the samples back
    // the next time the page loads (UIA-DIC-04).
    final settings = await db.readAppSettings();
    if (settings[_kSamplesSeededKey] != '1') {
      if (rows.isEmpty) {
        await _insertSampleData(db);
      }
      await db.writeAppSettings({_kSamplesSeededKey: '1'});
      if (rows.isEmpty) return readAll();
    }
    return rows.map(_fromDb).toList();
  }

  Future<void> _insertSampleData(HistoryDatabase db) async {
    final now = DateTime.now();
    const samples = [
      ('mfg', 'Mit freundlichen Grüßen'),
      ('lg', 'Liebe Grüße'),
      ('tel', '+49 123 456789'),
    ];
    for (final (trigger, replacement) in samples) {
      final id = '${now.millisecondsSinceEpoch}_$trigger';
      final match = newEntryMatch([trigger]);
      await db.upsertReplacementWithTriggers(
        id: id,
        triggers: [trigger],
        replacement: replacement,
        createdAt: now,
        matchMode: match.mode.name,
        fuzzyThreshold: match.fuzzyThreshold,
      );
    }
  }

  // Deliberately not further extracted: shares its "generate a uuid,
  // upsert, reload" shape with SnippetsNotifier.add. A shared
  // `createThenReload(persist)` helper was tried on ReloadableListNotifier:
  // it replaced this direct, linear code with a persist-callback closure for
  // no net line reduction — not worth the indirection for three lines.
  /// Creates an entry and returns its id, so the page can reveal it.
  /// Without [matchMode] the entry gets [newEntryMatch] for its triggers.
  Future<String> add(
    List<String> triggers,
    String replacement, {
    TextReplacementMatchMode? matchMode,
    double? fuzzyThreshold,
    String origin = 'manual',
  }) async {
    final db = ref.read(historyDatabaseProvider);
    final id = generateV4Uuid();
    final match = matchMode == null
        ? newEntryMatch(triggers)
        : (mode: matchMode, fuzzyThreshold: fuzzyThreshold);
    await db.upsertReplacementWithTriggers(
      id: id,
      triggers: triggers,
      replacement: replacement,
      createdAt: DateTime.now(),
      matchMode: match.mode.name,
      fuzzyThreshold: match.fuzzyThreshold,
      origin: origin,
    );
    await reload();
    return id;
  }

  /// Edits an entry. [createdAt] is the entry's existing creation time; the
  /// database keeps the stored value whatever is passed, so an edit never
  /// moves an entry in the "added" order.
  Future<void> updateReplacement(
    String id, {
    required List<String> triggers,
    required String replacement,
    required DateTime createdAt,
    TextReplacementMatchMode matchMode = TextReplacementMatchMode.exact,
    double? fuzzyThreshold,
    // Not user-editable in the dialog — callers pass the existing row's
    // origin through unchanged so an edit never turns an imported entry
    // into a manual one (or vice versa).
    String origin = 'manual',
  }) async {
    final db = ref.read(historyDatabaseProvider);
    await db.upsertReplacementWithTriggers(
      id: id,
      triggers: triggers,
      replacement: replacement,
      createdAt: createdAt,
      matchMode: matchMode.name,
      fuzzyThreshold: fuzzyThreshold,
      origin: origin,
    );
    await reload();
  }

  /// Opens the native folder picker and, if the user chooses a folder,
  /// scans it for identifiers -- nothing is written to the database yet, the
  /// caller shows the candidates for review and calls [commitImport] with
  /// only the terms the user actually picked (PRD.md
  /// vocabulary-fuzzy-replacements, "Import-Scan-Mechanismus"). Returns
  /// `null` if the user cancelled the picker.
  Future<VocabularyImportScanResult?> scanFolderForImport() async {
    final service = ref.read(vocabularyImportServiceProvider);
    final folder = await service.pickFolder();
    if (folder == null) return null;
    final db = ref.read(historyDatabaseProvider);
    return service.scan(folder, db);
  }

  /// Writes exactly [terms] (a user-reviewed subset of a prior
  /// [scanFolderForImport] result) as new fuzzy replacement entries.
  Future<int> commitImport(List<String> terms) async {
    final service = ref.read(vocabularyImportServiceProvider);
    final db = ref.read(historyDatabaseProvider);
    final added = await service.commit(terms, db);
    await reload();
    return added;
  }

  /// Adds the ready-made symbol rules that do not clash with an existing
  /// trigger (see [planSymbolPack]). Returns the plan, so the caller can tell
  /// the user how many were added and how many were already there.
  Future<SymbolPackPlan> addSymbolPack() async {
    final db = ref.read(historyDatabaseProvider);
    final existing = (await db.readAllReplacements()).expand((r) => r.triggers);
    final plan = planSymbolPack(existing);
    final now = DateTime.now();
    await db.writeReplacements([
      for (final template in plan.toAdd)
        ReplacementWrite(
          id: generateV4Uuid(),
          triggers: template.triggers,
          replacement: template.replacement,
          createdAt: now,
          matchMode: newEntryMatch(template.triggers).mode.name,
          fuzzyThreshold: newEntryMatch(template.triggers).fuzzyThreshold,
        ),
    ]);
    await reload();
    return plan;
  }

  Future<void> remove(String id) async {
    final db = ref.read(historyDatabaseProvider);
    await db.deleteReplacement(id);
    await reload();
  }

  Future<void> setFavourite(String id, {required bool value}) async {
    final db = ref.read(historyDatabaseProvider);
    await db.setReplacementFavourite(id, value: value);
    await reload();
  }

  /// Saves [orderedIds] as the order the rules are applied in (#1004).
  Future<void> reorder(List<String> orderedIds) async {
    final db = ref.read(historyDatabaseProvider);
    await db.reorderReplacements(orderedIds);
    await reload();
  }

  /// Replaces the entire set of replacements with [items] — used by settings
  /// import (Cluster 5 portability) so the imported file becomes the exact
  /// new contents rather than being merged with existing entries.
  // Deliberately not further extracted: shares its "clear, loop with an
  // index-ordered id, upsert, reload" shape with SnippetsNotifier.replaceAll;
  // same closure-indirection trade-off as [add] above, evaluated and
  // rejected for the same reason.
  Future<void> replaceAll(List<Replacement> items) async {
    final db = ref.read(historyDatabaseProvider);
    final now = DateTime.now();
    await db.writeReplacements([
      for (var i = 0; i < items.length; i++)
        ReplacementWrite(
          // Zero-padded, so ids of one import sort in import order too.
          id: '${now.millisecondsSinceEpoch}_${i.toString().padLeft(6, '0')}',
          triggers: items[i].triggers,
          replacement: items[i].replacement,
          createdAt: now,
          matchMode: items[i].matchMode.name,
          fuzzyThreshold: items[i].fuzzyThreshold,
          origin: items[i].origin,
        ),
    ], replaceAll: true);
    await reload();
  }

  /// Writes a planned import (R-08) in one transaction. Entries the plan does
  /// not touch keep their favourite flag and usage count.
  Future<void> applyImportPlan(ReplacementImportPlan plan) async {
    final db = ref.read(historyDatabaseProvider);
    final now = DateTime.now();
    await db.applyReplacementImport(
      updates: [for (final u in plan.updates) (id: u.id, triggers: u.triggers)],
      deleteIds: plan.deleteIds,
      inserts: [
        for (final r in plan.inserts)
          ReplacementWrite(
            id: generateV4Uuid(),
            triggers: r.triggers,
            replacement: r.replacement,
            createdAt: now,
            matchMode: r.matchMode.name,
            fuzzyThreshold: r.fuzzyThreshold,
          ),
      ],
    );
    await reload();
  }

  static Replacement _fromDb(ReplacementWithTriggers joined) => Replacement(
    id: joined.row.id,
    triggers: joined.triggers,
    replacement: joined.row.replacement,
    createdAt: joined.row.createdAt,
    updatedAt: joined.row.updatedAt,
    matchMode: joined.row.matchMode == 'fuzzy'
        ? TextReplacementMatchMode.fuzzy
        : TextReplacementMatchMode.exact,
    fuzzyThreshold: joined.row.fuzzyThreshold,
    origin: joined.row.origin,
    isFavorite: joined.row.isFavorite,
    usageCount: joined.row.usageCount,
  );
}

/// Starred entries first, otherwise the order [items] already has — the same
/// rule as favourites in Snippets and pinned notes (#892).
List<Replacement> replacementFavouritesFirst(List<Replacement> items) => [
  ...items.where((r) => r.isFavorite),
  ...items.where((r) => !r.isFavorite),
];

final replacementsProvider =
    AsyncNotifierProvider<ReplacementsNotifier, List<Replacement>>(
      ReplacementsNotifier.new,
    );

/// Overridable in tests (fake folder picker / extraction) so the import flow
/// can be exercised without a real native folder-choose dialog.
final vocabularyImportServiceProvider = Provider<VocabularyImportService>(
  (ref) => VocabularyImportService(),
);

/// Every word-level correction candidate currently eligible for review
/// (issue #144). Read by the Dictionary › Suggestions tab; `autoDispose` so a
/// stale list isn't kept alive once that tab is gone -- re-fetched fresh the
/// next time it's shown.
final pendingCorrectionCandidatesProvider =
    FutureProvider.autoDispose<List<CorrectionCandidate>>((ref) {
      final service = ref.read(correctionLearningServiceProvider);
      final db = ref.read(historyDatabaseProvider);
      final terms = ref.watch(
        settingsProvider.select((s) => s.value?.stt.customVocabulary ?? ''),
      );
      return service.pendingCandidates(
        db,
        existingTerms: vocabularyTerms(terms).toSet(),
      );
    });

/// Every observed word-level correction with the reason it is or is not
/// suggested (#383). Read by the learning log in the Suggestions tab.
final correctionLogProvider =
    FutureProvider.autoDispose<List<CorrectionLogEntry>>((ref) {
      final service = ref.read(correctionLearningServiceProvider);
      final db = ref.read(historyDatabaseProvider);
      final terms = ref.watch(
        settingsProvider.select((s) => s.value?.stt.customVocabulary ?? ''),
      );
      return service.log(db, existingTerms: vocabularyTerms(terms).toSet());
    });

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

/// Replacements page — auto-replace words during dictation.
class ReplacementsPage extends ConsumerStatefulWidget {
  const ReplacementsPage({super.key, this.leadingMenuActions = const []});

  /// Actions the parent adds in front of this page's own overflow entries.
  final List<WpListMenuAction> leadingMenuActions;

  @override
  ConsumerState<ReplacementsPage> createState() => _ReplacementsPageState();
}

/// How many short triggers the one-time hint names before it trails off.
const int _kExactHintShown = 5;

class _ReplacementsPageState extends ConsumerState<ReplacementsPage>
    with WpListRevealMixin<ReplacementsPage> {
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    // The terms tab's banner sends the user here to write the replacement.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!ref.read(dictionaryNewReplacementRequestProvider)) return;
      ref.read(dictionaryNewReplacementRequestProvider.notifier).set(false);
      _showAddEditDialog();
    });
  }

  /// Persists the one-time hint as seen; it never returns (#204).
  void _dismissExactTriggerHint() {
    ref
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWithSections(
            onboarding: s.onboarding.copyWith(exactTriggerHintDismissed: true),
          ),
        );
  }

  Future<void> _chooseSort(ListSort sort) => saveListSort(
    context,
    save: () => ref.read(replacementsSortProvider.notifier).choose(sort),
    orderLabel: (l10n) => _sortOrderLabel(l10n, sort),
  );

  String _sortOrderLabel(L10n l10n, ListSort sort) => wpSortOrderLabel(
    l10n,
    fieldLabel: _fieldLabel(l10n, sort.field),
    isDate:
        sort.field == ListSortField.added ||
        sort.field == ListSortField.changed,
    reversed: sort.reversed,
  );

  String _fieldLabel(L10n l10n, ListSortField field) => switch (field) {
    ListSortField.trigger => l10n.listSortFieldTrigger,
    ListSortField.result => l10n.listSortFieldResult,
    ListSortField.added => l10n.listSortFieldAdded,
    ListSortField.changed => l10n.listSortFieldChanged,
    // Not offered by this list.
    ListSortField.title || ListSortField.used => l10n.listSortFieldTitle,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final sortAsync = ref.watch(replacementsSortProvider);
    final sort = sortAsync.value ?? kReplacementsDefaultSort;
    // Narrowed to the one field this page renders: `settingsProvider` emits
    // on every settings write anywhere in the app, and watching the whole
    // value here rebuilt this entire page (list included) for changes that
    // have nothing to do with the replacements master switch.
    final enabled =
        ref.watch(
          settingsProvider.select((s) => s.value?.textReplacementsEnabled),
        ) ??
        true;
    final cascade =
        ref.watch(
          settingsProvider.select((s) => s.value?.behavior.replacementsCascade),
        ) ??
        true;
    final allReplacements = ref
        .watch(replacementsProvider)
        .maybeWhen(data: (r) => r, orElse: () => const <Replacement>[]);
    // Sorted before the shell sees it. Loading until the saved sort is read,
    // so the list never shows the default order for a frame.
    final asyncAll = sortAsync.isLoading && !sortAsync.hasValue
        ? const AsyncValue<List<Replacement>>.loading()
        : ref
              .watch(replacementsProvider)
              .whenData(
                (items) =>
                    replacementFavouritesFirst(sortListItems(items, sort)),
              );
    final hintDismissed =
        ref.watch(
          settingsProvider.select(
            (s) => s.value?.onboarding.exactTriggerHintDismissed,
          ),
        ) ??
        true;
    final exactTriggers = hintDismissed
        ? const <String>[]
        : [
            for (final r in allReplacements)
              ...exactFallbackTriggers(r.matchMode, r.triggers),
          ];
    final duplicateIds = duplicateReplacementIds([
      for (final r in allReplacements)
        TriggerOwner(id: r.id, triggers: r.triggers),
    ]);

    return WpSearchableListPage<Replacement>(
      // Header and toolbar, top to bottom: the explanation scrolls away with
      // the rows; the search and Add row stays fixed. The master switch is no
      // longer a card above the list: it sits in the overflow menu, and while
      // it is off a banner offers to turn it on, so the list keeps the space.
      listKey: const ValueKey('replacements-list'),
      identifierPrefix: 'replacements',
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (exactTriggers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                WpSpacing.xl,
                0,
                WpSpacing.xl,
                WpSpacing.xs,
              ),
              child: Semantics(
                identifier: 'replacements-exact-trigger-hint',
                child: WpBanner(
                  key: const ValueKey('replacements-exact-trigger-hint'),
                  tone: WpBannerTone.info,
                  message: l10n.replacementsExactTriggerHint(
                    exactTriggers.take(_kExactHintShown).join(', ') +
                        (exactTriggers.length > _kExactHintShown ? ' …' : ''),
                  ),
                  action: Semantics(
                    identifier: 'replacements-exact-trigger-hint-dismiss',
                    child: WpButton(
                      key: const ValueKey(
                        'replacements-exact-trigger-hint-dismiss',
                      ),
                      label: l10n.actionDismiss,
                      variant: WpButtonVariant.secondary,
                      size: WpButtonSize.dense,
                      onPressed: _dismissExactTriggerHint,
                    ),
                  ),
                ),
              ),
            ),
          // How the rules interact (#1004): one quiet line, only where order
          // can matter (feature on, two rules or more), with the way to
          // change the order right next to the explanation.
          if (enabled && allReplacements.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                WpSpacing.xl,
                0,
                WpSpacing.xl,
                WpSpacing.xs,
              ),
              child: Semantics(
                identifier: 'replacements-cascade-hint',
                child: WpBanner(
                  key: const ValueKey('replacements-cascade-hint'),
                  tone: WpBannerTone.info,
                  message: cascade
                      ? l10n.replacementsCascadeOnHint
                      : l10n.replacementsCascadeOffHint,
                  action: Semantics(
                    identifier: 'replacements-order-open',
                    child: WpButton(
                      key: const ValueKey('replacements-order-open'),
                      label: l10n.replacementsOrderAction,
                      variant: WpButtonVariant.secondary,
                      size: WpButtonSize.dense,
                      onPressed: () => showReplacementOrderDialog(context),
                    ),
                  ),
                ),
              ),
            ),
          // Only shown while the feature is off: when it is on, the list
          // starts right under the toolbar and the header costs no space.
          if (!enabled)
            Padding(
              // First element under the page title: the shell owns the gap.
              padding: const EdgeInsets.fromLTRB(
                WpSpacing.xl,
                0,
                WpSpacing.xl,
                WpSpacing.xs,
              ),
              // Live region: the banner appears after a tap elsewhere (the
              // menu toggle), so screen readers must hear the state change.
              child: Semantics(
                liveRegion: true,
                child: WpBanner(
                  tone: WpBannerTone.warning,
                  message: l10n.replacementsToggleDisabled,
                  action: Semantics(
                    identifier: 'replacements-enable',
                    child: WpButton(
                      key: const ValueKey('replacements-enable'),
                      label: l10n.replacementsToggleLabel,
                      variant: WpButtonVariant.secondary,
                      size: WpButtonSize.dense,
                      onPressed: () => _setEnabled(true),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      asyncAll: asyncAll,
      itemId: (r) => r.id,
      revealId: revealedId,
      sortControl: WpSortMenuButton<ListSortField>(
        testId: 'replacements-sort',
        tooltip: l10n.listSortMenuTooltip(_sortOrderLabel(l10n, sort)),
        current: sort.field,
        options: [
          WpSortOption(
            value: ListSortField.trigger,
            id: 'trigger',
            label: l10n.listSortFieldTrigger,
            icon: LucideIcons.arrowRightLeft,
          ),
          WpSortOption(
            value: ListSortField.result,
            id: 'result',
            label: l10n.listSortFieldResult,
            icon: LucideIcons.textCursorInput,
          ),
          WpSortOption(
            value: ListSortField.added,
            id: 'added',
            label: l10n.listSortFieldAdded,
            icon: LucideIcons.calendarPlus,
          ),
          WpSortOption(
            value: ListSortField.changed,
            id: 'changed',
            label: l10n.listSortFieldChanged,
            icon: LucideIcons.pencilLine,
          ),
        ],
        onChanged: (field) => _chooseSort(ListSort(field)),
        reversed: sort.reversed,
        reverseLabel: l10n.listSortReverse,
        onReversedChanged: (reversed) =>
            _chooseSort(ListSort(sort.field, reversed: reversed)),
      ),
      searchFields: (r) => [
        for (final t in r.triggers) SearchField(t, SearchWeight.title),
        SearchField(r.replacement, SearchWeight.body),
      ],
      searchHint: l10n.replacementsSearch,
      searchFieldLabel: l10n.replacementsSearchFieldLabel,
      addLabel: l10n.replacementsAdd,
      onAdd: () => _showAddEditDialog(),
      onRetry: () => ref.invalidate(replacementsProvider),
      emptyIcon: LucideIcons.replace,
      emptyTitle: l10n.replacementsEmpty,
      emptyHint: l10n.replacementsEmptyHint,
      // Same string as the empty state's hint — see the Snippets call site.
      emptyActionLabel: l10n.replacementsAdd,
      // Rows stay visible but dimmed while disabled, so the shortcuts can
      // still be read.
      dimContent: !enabled,
      menuKey: const ValueKey('replacements-more'),
      menuTooltip: l10n.dockOverflow,
      menuActions: [
        ...widget.leadingMenuActions,
        WpListMenuAction(
          itemKey: const ValueKey('replacements-import-folder'),
          label: l10n.replacementsImportFromFolder,
          hint: _importing
              ? l10n.replacementsImportScanning
              : l10n.replacementsImportHint,
          icon: LucideIcons.folderInput,
          enabled: !_importing,
          onSelected: _importFromFolder,
        ),
        WpListMenuAction(
          itemKey: const ValueKey('replacements-symbol-pack'),
          label: l10n.replacementsSymbolPackAction,
          hint: l10n.replacementsSymbolPackHint,
          icon: LucideIcons.hash,
          onSelected: _addSymbolPack,
        ),
        WpListMenuAction(
          itemKey: const ValueKey('replacements-toggle'),
          label: l10n.replacementsToggleLabel,
          icon: LucideIcons.replace,
          hint: enabled
              ? l10n.replacementsToggleEnabled
              : l10n.replacementsToggleDisabled,
          checked: enabled,
          onSelected: () => _setEnabled(!enabled),
        ),
        WpListMenuAction(
          itemKey: const ValueKey('replacements-cascade-toggle'),
          label: l10n.replacementsCascadeToggleLabel,
          icon: LucideIcons.layers,
          hint: cascade
              ? l10n.replacementsCascadeOnHint
              : l10n.replacementsCascadeOffHint,
          checked: cascade,
          onSelected: () => _setCascade(!cascade),
        ),
        WpListMenuAction(
          itemKey: const ValueKey('replacements-order-menu'),
          label: l10n.replacementsOrderAction,
          hint: l10n.replacementsOrderActionHint,
          icon: LucideIcons.arrowUpDown,
          enabled: allReplacements.length > 1,
          onSelected: () => showReplacementOrderDialog(context),
        ),
      ],
      onItemActivate: (r) => _showAddEditDialog(existing: r),
      onItemDelete: _confirmDelete,
      itemBuilder: (context, r, isCursor) {
        return WpCopyAnchor(
          target: 'replacement-${r.id}',
          child: _ReplacementTile(
            key: ValueKey('replacements-row-${r.id}'),
            replacement: r,
            isCursor: isCursor,
            isHighlighted: r.id == highlightedId,
            isDuplicate: duplicateIds.contains(r.id),
            onTap: () => _showAddEditDialog(existing: r),
            onCopy: () => _copyReplacement(r),
            onDuplicate: () => _duplicateReplacement(r),
            onDelete: () => _confirmDelete(r),
            onToggleFavourite: () => ref
                .read(replacementsProvider.notifier)
                .setFavourite(r.id, value: !r.isFavorite),
          ),
        );
      },
    );
  }

  void _setEnabled(bool value) => ref
      .read(settingsProvider.notifier)
      .updateSettings((s) => s.copyWith(textReplacementsEnabled: value));

  void _setCascade(bool value) => ref
      .read(settingsProvider.notifier)
      .updateSettings(
        (s) => s.copyWithSections(
          behavior: s.behavior.copyWith(replacementsCascade: value),
        ),
      );

  // ── Add / Edit dialog ────────────────────────────────────────────────

  Future<void> _showAddEditDialog({Replacement? existing}) async {
    await showWpFormDialog<void>(
      context: context,
      builder: (_, a) => _ReplacementDialog(
        animation: a,
        existing: existing,
        onSave: (draft) => _saveReplacement(existing, draft),
        findClash: (triggers) => _findTriggerClash(existing?.id, triggers),
      ),
    );
  }

  /// Another entry that already owns one of [triggers]. Compared with the same
  /// normalisation the list uses to flag duplicates, so the dialog and the
  /// list never disagree about what collides (UIA-DIC-06).
  ({String trigger, String replacement})? _findTriggerClash(
    String? ownId,
    List<String> triggers,
  ) {
    final keys = {for (final t in triggers) normalizeTriggerKey(t)}..remove('');
    final others = ref.read(replacementsProvider).value ?? const [];
    for (final entry in others) {
      if (entry.id == ownId) continue;
      for (final trigger in entry.triggers) {
        if (keys.contains(normalizeTriggerKey(trigger))) {
          return (trigger: trigger, replacement: entry.replacement);
        }
      }
    }
    return null;
  }

  /// Writes the dialog's draft. Returns `false` when the write fails, so the
  /// dialog stays open with the typed input and the user is told (UIA-DIC-03).
  Future<bool> _saveReplacement(
    Replacement? existing,
    _ReplacementDraft draft,
  ) async {
    final (triggers, replacement, matchMode, fuzzyThreshold) = draft;
    final notifier = ref.read(replacementsProvider.notifier);
    try {
      if (existing != null) {
        // A save without a change is no edit: "changed" keeps its old time.
        if (_isUnchanged(existing, draft)) return true;
        await notifier.updateReplacement(
          existing.id,
          triggers: triggers,
          replacement: replacement,
          createdAt: existing.createdAt,
          matchMode: matchMode,
          fuzzyThreshold: fuzzyThreshold,
          origin: existing.origin,
        );
      } else {
        final id = await notifier.add(
          triggers,
          replacement,
          matchMode: matchMode,
          fuzzyThreshold: fuzzyThreshold,
        );
        reveal(id);
        ref
            .read(telemetrySessionAggregatorProvider)
            .count(category: 'replacements', action: 'create');
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool _isUnchanged(Replacement existing, _ReplacementDraft draft) {
    final (triggers, replacement, matchMode, fuzzyThreshold) = draft;
    return listEquals(existing.triggers, triggers) &&
        existing.replacement == replacement &&
        existing.matchMode == matchMode &&
        existing.fuzzyThreshold == fuzzyThreshold;
  }

  // ── Vocabulary import ─────────────────────────────────────────────────

  /// Says a result or error on the Dictionary page, where this page lives.
  void _say(
    String id,
    String message, {
    String? nextStep,
    WpBannerTone tone = WpBannerTone.info,
  }) => showWpPageNotice(
    context,
    page: dictionaryNoticePage,
    notice: WpPageNotice(
      id: id,
      message: message,
      nextStep: nextStep,
      tone: tone,
    ),
  );

  Future<void> _addSymbolPack() async {
    final l10n = L10n.of(context);
    final plan = await ref.read(replacementsProvider.notifier).addSymbolPack();
    if (!mounted) return;
    _say(
      'symbol-pack-result',
      plan.toAdd.isEmpty
          ? l10n.replacementsSymbolPackNothingNew
          : l10n.replacementsSymbolPackAdded(plan.toAdd.length),
    );
  }

  Future<void> _importFromFolder() async {
    if (_importing) return;
    final l10n = L10n.of(context);
    setState(() => _importing = true);
    try {
      final notifier = ref.read(replacementsProvider.notifier);
      final scanResult = await notifier.scanFolderForImport();
      if (scanResult == null || !mounted) return;
      if (scanResult.candidates.isEmpty) {
        _say('import-nothing-found', l10n.replacementsImportNothingFound);
        return;
      }

      final selected = await Navigator.of(context).push<List<String>>(
        MaterialPageRoute(
          builder: (_) =>
              VocabularyImportReviewPage(candidates: scanResult.candidates),
        ),
      );
      if (selected == null || selected.isEmpty || !mounted) return;

      final added = await notifier.commitImport(selected);
      if (!mounted) return;
      _say(
        'import-summary',
        l10n.replacementsImportSummary(
          scanResult.candidates.length,
          added,
          scanResult.skipped,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      _say(
        'import-failed',
        l10n.replacementsImportError,
        nextStep: l10n.replacementsImportErrorNext,
        tone: WpBannerTone.error,
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  // ── Copy action ──────────────────────────────────────────────────────

  void _copyReplacement(Replacement r) {
    unawaited(
      copyWithFeedback(
        context,
        text: r.replacement,
        target: 'replacement-${r.id}',
        category: 'replacements',
      ),
    );
  }

  /// A copy keeps the original's match settings: it is the same entry.
  Future<void> _duplicateReplacement(Replacement r) async {
    final firstTrigger = r.triggers.isNotEmpty ? r.triggers.first : 'trigger';
    final id = await ref
        .read(replacementsProvider.notifier)
        .add(
          ['$firstTrigger (copy)'],
          r.replacement,
          matchMode: r.matchMode,
          fuzzyThreshold: r.fuzzyThreshold,
        );
    if (!mounted) return;
    // Confirms at the original row and marks the copy in place; no scroll,
    // so the list stays where the pointer is.
    confirmAtTrigger(context, target: 'replacement-${r.id}');
    highlight(id);
  }

  // ── Delete confirmation ──────────────────────────────────────────────

  Future<void> _confirmDelete(Replacement r) async {
    final l10n = L10n.of(context);
    final confirmed = await showWpConfirmDialog(
      context: context,
      title: l10n.replacementsDeleteTitle,
      message: l10n.replacementsDeleteMessage(r.triggers.join(', ')),
      confirmLabel: l10n.actionDelete,
      cancelLabel: l10n.actionCancel,
      destructive: true,
    );
    if (confirmed) ref.read(replacementsProvider.notifier).remove(r.id);
  }
}

// ---------------------------------------------------------------------------
// Add / Edit dialog
// ---------------------------------------------------------------------------

/// What the add/edit dialog hands to the page: trigger phrases, replacement
/// text, match mode and fuzzy threshold.
typedef _ReplacementDraft = (
  List<String>,
  String,
  TextReplacementMatchMode,
  double?,
);

class _ReplacementDialog extends StatefulWidget {
  const _ReplacementDialog({
    required this.animation,
    required this.onSave,
    required this.findClash,
    this.existing,
  });

  final Animation<double> animation;
  final Replacement? existing;

  /// Returns whether the draft was stored; the dialog closes only then.
  final Future<bool> Function(_ReplacementDraft draft) onSave;

  /// The other entry that already owns one of [triggers], if any (UIA-DIC-06).
  final ({String trigger, String replacement})? Function(List<String> triggers)
  findClash;

  @override
  State<_ReplacementDialog> createState() => _ReplacementDialogState();
}

class _ReplacementDialogState extends State<_ReplacementDialog> {
  (String, String, WpBannerTone)? _problem;
  bool _saving = false;

  final List<TextEditingController> _triggerCtrls = [];
  final List<FocusNode> _triggerFocusNodes = [];
  late final TextEditingController _replacementCtrl;
  late TextReplacementMatchMode _matchMode;
  late double _fuzzyThreshold;

  /// True once the user picked a match mode. Until then a new entry shows and
  /// saves [_settledMode].
  bool _modeChosen = false;

  /// [newEntryMatch] for the triggers as they were when a trigger field last
  /// lost focus (UX-124). Settled on leaving the field, never per keystroke,
  /// so the mode does not jump while the user types. Null until then: the
  /// entry shows and saves Exact.
  TextReplacementMatchMode? _settledMode;

  List<String> get _typedTriggers => [
    for (final c in _triggerCtrls)
      if (c.text.trim().isNotEmpty) c.text.trim(),
  ];

  TextReplacementMatchMode get _effectiveMode => _isEditing || _modeChosen
      ? _matchMode
      : _settledMode ?? TextReplacementMatchMode.exact;

  /// The default chose Similar for the user, so the dialog says what that
  /// means before they save.
  bool get _showsSimilarDefault =>
      !_isEditing &&
      !_modeChosen &&
      _settledMode == TextReplacementMatchMode.fuzzy;

  FocusNode _triggerFocusNode() => FocusNode()..addListener(_settleDefaultMode);

  void _settleDefaultMode() {
    if (_isEditing || _modeChosen || !mounted) return;
    if (_triggerFocusNodes.any((n) => n.hasFocus)) return;
    final triggers = _typedTriggers;
    if (triggers.isEmpty) return;
    final mode = newEntryMatch(triggers).mode;
    if (mode != _settledMode) setState(() => _settledMode = mode);
  }

  bool get _isValid =>
      _triggerCtrls.any((c) => c.text.trim().isNotEmpty) &&
      _replacementCtrl.text.trim().isNotEmpty;

  bool get _isEditing => widget.existing != null;

  /// PRD.md: trigger phrases below [fuzzyMinTriggerLength] are locked out of
  /// fuzzy mode in the UI — too short and every dictated word becomes a
  /// false hit, even at the strictest threshold.
  bool get _fuzzyAllowed =>
      _triggerCtrls.any((c) => c.text.trim().length >= fuzzyMinTriggerLength);

  /// A single punctuation trigger is saved but never fires, so the dialog
  /// says so next to the trigger list. It is a hint only, never a block.
  bool get _hasSilentTrigger =>
      _triggerCtrls.any((c) => exactTriggerNeverFires(c.text));

  @override
  void initState() {
    super.initState();
    final existingTriggers = widget.existing?.triggers ?? const [];
    for (final trigger
        in existingTriggers.isNotEmpty ? existingTriggers : const ['']) {
      _triggerCtrls.add(TextEditingController(text: trigger));
      _triggerFocusNodes.add(_triggerFocusNode());
    }
    _replacementCtrl = TextEditingController(
      text: widget.existing?.replacement ?? '',
    );
    _matchMode = widget.existing?.matchMode ?? TextReplacementMatchMode.exact;
    _fuzzyThreshold =
        widget.existing?.fuzzyThreshold ??
        vocabularyImportDefaultFuzzyThreshold;
    _openedDraft = _draftText;
  }

  late final String _openedDraft;

  String get _draftText => [
    for (final c in _triggerCtrls) c.text,
    _replacementCtrl.text,
  ].join('\u0000');

  /// Typed text that a dismiss would throw away (UIA-CMP-03).
  bool get _hasUnsavedInput => _draftText != _openedDraft;

  @override
  void dispose() {
    for (final ctrl in _triggerCtrls) {
      ctrl.dispose();
    }
    for (final node in _triggerFocusNodes) {
      node
        ..removeListener(_settleDefaultMode)
        ..dispose();
    }
    _replacementCtrl.dispose();
    super.dispose();
  }

  void _addTrigger() {
    final node = _triggerFocusNode();
    setState(() {
      _triggerCtrls.add(TextEditingController());
      _triggerFocusNodes.add(node);
    });
    // Focus the new field after it has been built; the dialog's scroll body
    // auto-scrolls it into view.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) node.requestFocus();
    });
  }

  void _removeTrigger(int index) {
    final ctrl = _triggerCtrls[index];
    final node = _triggerFocusNodes[index];
    setState(() {
      _triggerCtrls.removeAt(index);
      _triggerFocusNodes.removeAt(index);
    });
    // Dispose after the frame so the outgoing TextField no longer uses them.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ctrl.dispose();
      node.dispose();
    });
  }

  /// The problem stays at the top of the form until the next save attempt;
  /// the page behind the dialog could not be seen.
  void _showProblem(
    String id,
    String message, {
    String? nextStep,
    WpBannerTone tone = WpBannerTone.error,
  }) {
    setState(
      () => _problem = (
        id,
        nextStep == null ? message : '$message $nextStep',
        tone,
      ),
    );
  }

  Future<void> _submit() async {
    if (!_isValid || _saving) return;
    setState(() => _problem = null);
    final triggers = _triggerCtrls
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    // A Similar entry whose trigger fell below the minimum is not saved as
    // exact behind the user's back: the mode switches visibly and the save
    // stops until they look at it (UIA-DIC-05).
    if (_effectiveMode == TextReplacementMatchMode.fuzzy && !_fuzzyAllowed) {
      setState(() {
        _matchMode = TextReplacementMatchMode.exact;
        // The switch shown here is the mode that gets saved.
        _modeChosen = true;
      });
      _showProblem(
        'fuzzy-too-short',
        L10n.of(
          context,
        ).replacementsFuzzyTooShortWarning(fuzzyMinTriggerLength),
        tone: WpBannerTone.warning,
      );
      return;
    }
    // The same rules and sentences as the dictionary's quick add path
    // (#623), so an entry is not refused here and accepted there (#892).
    final draftProblem = checkReplacementDraft(triggers, _replacementCtrl.text);
    if (draftProblem != null) {
      final l10n = L10n.of(context);
      final (id, message) = switch (draftProblem.problem) {
        ReplacementDraftProblem.tooLong => (
          'too-long',
          l10n.dictionaryTermsTooLong,
        ),
        ReplacementDraftProblem.duplicateTrigger => (
          'repeated-trigger',
          l10n.dictionaryTermsDuplicate(draftProblem.trigger),
        ),
        ReplacementDraftProblem.sameAsReplacement => (
          'same-as-replacement',
          l10n.dictionaryTermsRightSame,
        ),
      };
      _showProblem(id, message);
      return;
    }
    final clash = widget.findClash(triggers);
    if (clash != null) {
      final l10n = L10n.of(context);
      _showProblem(
        'duplicate-trigger',
        l10n.replacementsDuplicateTrigger(clash.trigger, clash.replacement),
        nextStep: l10n.replacementsDuplicateTriggerNext,
      );
      return;
    }
    // A trigger edit that drops below the fuzzy minimum length must not
    // leave a stale fuzzy mode behind it.
    final matchMode = _fuzzyAllowed
        ? _effectiveMode
        : TextReplacementMatchMode.exact;
    _saving = true;
    final saved = await widget.onSave((
      triggers,
      _replacementCtrl.text.trim(),
      matchMode,
      matchMode == TextReplacementMatchMode.fuzzy ? _fuzzyThreshold : null,
    ));
    _saving = false;
    if (!mounted) return;
    if (saved) {
      Navigator.of(context).pop();
    } else {
      _showProblem('save-failed', L10n.of(context).errorGeneric);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);

    return WpUnsavedInputGuard(
      dirty: _hasUnsavedInput,
      child: WpFormDialogShell(
        animation: widget.animation,
        title: _isEditing
            ? l10n.replacementsEditShortcut
            : l10n.replacementsNewShortcut,
        subtitle: l10n.replacementsDialogHint,
        fields: [
          if (_problem case (final id, final text, final tone)) ...[
            Semantics(
              identifier: 'replacements-dialog-problem-$id',
              liveRegion: true,
              child: WpBanner(
                key: ValueKey('replacements-dialog-problem-$id'),
                tone: tone,
                message: text,
              ),
            ),
            const SizedBox(height: WpSpacing.sm),
          ],
          // Trigger phrases — dynamic list, one text field per phrase
          Text(
            l10n.replacementsTriggerLabel,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: WpSpacing.xxs),
          // The trigger rows live in the form's own scroll body: the dialog
          // shell owns the scrolling once, so a long trigger list never nests
          // a second scroll box inside it (consistency 133, like UX-028).
          for (var i = 0; i < _triggerCtrls.length; i++)
            Padding(
              key: ObjectKey(_triggerCtrls[i]),
              padding: EdgeInsets.only(top: i == 0 ? 0 : WpSpacing.xxs),
              child: Row(
                children: [
                  Expanded(
                    child: WpTextField(
                      key: ValueKey('replacements-trigger-field-$i'),
                      controller: _triggerCtrls[i],
                      variant: WpTextFieldVariant.form,
                      focusNode: _triggerFocusNodes[i],
                      autofocus: i == 0,
                      hintText: l10n.replacementsTriggerHint,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                  // The last remaining trigger cannot be
                  // removed — a shortcut always keeps at
                  // least one phrase.
                  if (_triggerCtrls.length > 1) ...[
                    const SizedBox(width: WpSpacing.xxs),
                    // Quiet ghost button: 40 px visual inside the
                    // 48 dp touch target of `WpTouchTarget`. Costs no
                    // height: the row is already 48 dp tall because
                    // the neighbouring `WpTextField.form` is.
                    WpIconButton.ghost(
                      key: ValueKey('replacements-trigger-remove-$i'),
                      testId: 'replacements-trigger-remove-$i',
                      icon: LucideIcons.x,
                      tooltip: l10n.replacementsRemoveTrigger,
                      onPressed: () => _removeTrigger(i),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: WpSpacing.xxs),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: WpButton(
              key: const ValueKey('replacements-trigger-add'),
              label: l10n.replacementsAddTrigger,
              variant: WpButtonVariant.ghost,
              size: WpButtonSize.dense,
              icon: LucideIcons.plus,
              onPressed: _addTrigger,
            ),
          ),
          if (_hasSilentTrigger) ...[
            const SizedBox(height: WpSpacing.xxs),
            Text(
              l10n.replacementsSingleSymbolTriggerHint(
                ltrIsolate(':)'),
                ltrIsolate('...'),
              ),
              key: const ValueKey('replacements-single-symbol-hint'),
              style: TextStyle(
                color: WpColors.textMuted,
                fontSize: WpTypography.caption,
              ),
            ),
          ],
          const SizedBox(height: WpSpacing.md),

          // Replacement field
          Text(
            l10n.replacementsReplacementLabel,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: WpSpacing.xxs),
          WpTextField(
            key: const ValueKey('replacements-replacement-field'),
            controller: _replacementCtrl,
            variant: WpTextFieldVariant.form,
            hintText: l10n.replacementsReplacementHint,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: WpSpacing.xxs),
          Text(
            l10n.replacementsReplacementHelper,
            key: const Key('replacementsReplacementHelper'),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: WpSpacing.md),

          // Match mode: Exact / Similar (PRD.md vocabulary-fuzzy-replacements)
          Text(
            l10n.replacementsMatchModeLabel,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: WpSpacing.xxs),
          WpSegmentedChoice<TextReplacementMatchMode>(
            key: const ValueKey('replacements-match-mode-choice'),
            options: [
              WpSegmentOption(
                value: TextReplacementMatchMode.exact,
                label: l10n.replacementsMatchModeExact,
              ),
              WpSegmentOption(
                value: TextReplacementMatchMode.fuzzy,
                label: l10n.replacementsMatchModeFuzzy,
                enabled: _fuzzyAllowed,
              ),
            ],
            selected: _effectiveMode,
            onChanged: (value) => setState(() {
              _matchMode = value;
              _modeChosen = true;
            }),
          ),
          if (_showsSimilarDefault) ...[
            const SizedBox(height: WpSpacing.xxs),
            Text(
              l10n.replacementsSimilarDefaultHint,
              key: const ValueKey('replacements-similar-default-hint'),
              style: TextStyle(
                color: WpColors.textMuted,
                fontSize: WpTypography.caption,
              ),
            ),
          ],
          if (!_fuzzyAllowed) ...[
            const SizedBox(height: WpSpacing.xxs),
            Text(
              l10n.replacementsFuzzyTooShortWarning(fuzzyMinTriggerLength),
              style: TextStyle(
                color: WpColors.textMuted,
                fontSize: WpTypography.caption,
              ),
            ),
          ],
          if (_effectiveMode == TextReplacementMatchMode.fuzzy) ...[
            const SizedBox(height: WpSpacing.md),
            Text(
              l10n.replacementsFuzzyToleranceLabel,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: WpSpacing.xxs),
            WpSegmentedChoice<double>(
              key: const ValueKey('replacements-fuzzy-tolerance-choice'),
              options: [
                WpSegmentOption(
                  value: fuzzyThresholdStrict,
                  label: l10n.replacementsFuzzyToleranceStrict,
                ),
                WpSegmentOption(
                  value: fuzzyThresholdStandard,
                  label: l10n.replacementsFuzzyToleranceStandard,
                ),
                WpSegmentOption(
                  value: fuzzyThresholdTolerant,
                  label: l10n.replacementsFuzzyToleranceTolerant,
                ),
              ],
              selected: _fuzzyThreshold,
              onChanged: (value) => setState(() => _fuzzyThreshold = value),
            ),
            const SizedBox(height: WpSpacing.xxs),
            Text(
              l10n.replacementsFuzzyToleranceHint,
              style: TextStyle(
                color: WpColors.textMuted,
                fontSize: WpTypography.caption,
              ),
            ),
          ],
          // Says why save is off, as visible text (UIA-DIC-07).
          if (!_isValid) ...[
            const SizedBox(height: WpSpacing.xs),
            Text(
              _triggerCtrls.any((c) => c.text.trim().isNotEmpty)
                  ? l10n.replacementsMissingReplacement
                  : l10n.replacementsMissingTrigger,
              style: TextStyle(
                color: WpColors.textMuted,
                fontSize: WpTypography.caption,
              ),
            ),
          ],
        ],
        actions: [
          WpDialogAction(
            label: l10n.actionCancel,
            testId: 'replacements-cancel',
            role: WpDialogActionRole.cancel,
          ),
          WpDialogAction(
            label: _isEditing ? l10n.actionSave : l10n.replacementsAdd,
            testId: 'replacements-save',
            role: WpDialogActionRole.primary,
            enabled: _isValid,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Replacement tile
// ---------------------------------------------------------------------------

class _ReplacementTile extends StatefulWidget {
  const _ReplacementTile({
    super.key,
    required this.replacement,
    required this.isCursor,
    required this.isHighlighted,
    required this.isDuplicate,
    required this.onTap,
    required this.onCopy,
    required this.onDuplicate,
    required this.onDelete,
    required this.onToggleFavourite,
  });

  final Replacement replacement;

  /// This row is the list's arrow cursor — same contract, same two outlets
  /// and same reasoning as `_SnippetRow.isCursor`, which see.
  final bool isCursor;

  /// The entry was just created: drawn with the focus treatment for a moment.
  final bool isHighlighted;

  /// Another entry uses one of this entry's trigger phrases (matrix 4.5).
  final bool isDuplicate;
  final VoidCallback onTap;
  final VoidCallback onCopy;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback onToggleFavourite;

  @override
  State<_ReplacementTile> createState() => _ReplacementTileState();
}

class _ReplacementTileState extends State<_ReplacementTile> {
  bool _isHovered = false;
  bool _isFocused = false;

  /// The row is "active" for pointer and for keyboard alike — the
  /// delete action is revealed by either, so a keyboard user can reach
  /// it at all (an unmounted button cannot be focused). Includes the arrow
  /// cursor, for the reason spelled out on `WpCollectionListItem`.
  bool get _isActive => _isHovered || _isFocused || widget.isCursor;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      // Delete/Backspace on the focused row — same binding, same reasoning
      // and same row-scoping as WpCollectionListItem, which see.
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.delete): widget.onDelete,
        const SingleActivator(LogicalKeyboardKey.backspace): widget.onDelete,
      },
      child: _buildRow(context),
    );
  }

  Widget _buildRow(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Semantics(
      button: true,
      // Affordance as `hint:`, identity from the rendered trigger chips —
      // same reasoning and same shape as WpCollectionListItem, which see. The label
      // used to repeat the trigger phrases the chips already render, and a
      // Semantics label is prepended to its subtree's text rather than
      // substituted for it, so each row announced "Ersetzung bearbeiten:
      // mfg, mfg, …". MergeSemantics is not an option: the delete action
      // mounts as a second interactive node once the row is active.
      hint: L10n.of(context).replacementsEditShortcut,
      // The arrow cursor's row reports as selected — same flag, same reason
      // as `WpCollectionListItem`, which see.
      selected: widget.isCursor,
      child: FocusableActionDetector(
        onShowFocusHighlight: (value) {
          if (_isFocused == value) return;
          setState(() => _isFocused = value);
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: widget.onTap,
            child: WpListTileSurface(
              // Dictionary rows rest flat with an indented rule; only the
              // current row becomes a white card (spec §3, COMPONENTS.md).
              variant: WpListTileVariant.panel,
              isHovered: _isHovered,
              // The cursor is drawn through isFocused (keyboard contract, see
              // searchable_list_keyboard_cursor_test); isSelected only makes
              // the row a card.
              isFocused: _isFocused || widget.isCursor || widget.isHighlighted,
              isSelected: widget.isCursor,
              actions: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  WpFavouriteStar(
                    key: ValueKey(
                      'replacements-favourite-${widget.replacement.id}',
                    ),
                    testId: 'replacements-favourite-${widget.replacement.id}',
                    isFavourite: widget.replacement.isFavorite,
                    onToggle: widget.onToggleFavourite,
                    dense: false,
                  ),
                  // Trailing chevron: the row opens an editor on tap, so it
                  // carries the same cue as other navigable list rows.
                  const SizedBox(width: WpSpacing.xxs),
                  Icon(
                    rtl ? LucideIcons.chevronLeft : LucideIcons.chevronRight,
                    size: WpIconSize.sm,
                    color: WpColors.textMuted,
                  ),
                  WpRowActions(
                    visible: _isActive,
                    children: [
                      WpRowAction(
                        key: ValueKey(
                          'replacements-copy-${widget.replacement.id}',
                        ),
                        icon: LucideIcons.copy,
                        tooltip: L10n.of(context).actionCopy,
                        onTap: widget.onCopy,
                      ),
                      WpRowAction(
                        key: ValueKey(
                          'replacements-duplicate-${widget.replacement.id}',
                        ),
                        icon: LucideIcons.files,
                        tooltip: L10n.of(context).actionDuplicate,
                        onTap: widget.onDuplicate,
                      ),
                      WpRowAction(
                        key: ValueKey(
                          'replacements-delete-${widget.replacement.id}',
                        ),
                        icon: LucideIcons.trash2,
                        tooltip: L10n.of(context).actionDelete,
                        onTap: widget.onDelete,
                        isDestructive: true,
                      ),
                    ],
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.arrowRightLeft,
                    size: WpIconSize.sm,
                    color: WpColors.accent,
                  ),
                  const SizedBox(width: WpSpacing.sm),
                  // Trigger phrases — one chip per phrase, wrapping onto
                  // additional lines when a shortcut has many triggers.
                  Flexible(
                    child: Wrap(
                      spacing: WpSpacing.xxs,
                      runSpacing: WpSpacing.xxs,
                      children: [
                        for (final trigger in widget.replacement.triggers)
                          WpTriggerChip(label: trigger),
                      ],
                    ),
                  ),
                  // Similar entries also replace other spellings; the list
                  // says so, so nobody has to open each entry (UX-125).
                  if (widget.replacement.matchMode ==
                      TextReplacementMatchMode.fuzzy) ...[
                    const SizedBox(width: WpSpacing.xxs),
                    WpAccentBadge(
                      key: ValueKey(
                        'replacements-row-${widget.replacement.id}-similar',
                      ),
                      label: L10n.of(context).replacementsMatchModeFuzzy,
                    ),
                  ],
                  // Every entry says where it came from, so a list mixing
                  // typed, learned and imported entries reads at a glance
                  // (#892). Hand-typed entries get the quiet grey tone.
                  const SizedBox(width: WpSpacing.xxs),
                  _OriginBadge(
                    key: ValueKey(
                      'replacements-row-${widget.replacement.id}-origin',
                    ),
                    origin: widget.replacement.origin,
                  ),
                  if (widget.isDuplicate) ...[
                    const SizedBox(width: WpSpacing.xxs),
                    Tooltip(
                      message: L10n.of(context).dictionaryDuplicateHint,
                      child: WpAccentBadge(
                        label: L10n.of(context).dictionaryDuplicateBadge,
                        tone: WpAccentBadgeTone.highlight,
                      ),
                    ),
                  ],
                  const SizedBox(width: WpSpacing.sm),
                  Icon(
                    // Lucide glyphs do not mirror on their own: pick the
                    // direction of the reading flow.
                    rtl ? LucideIcons.arrowLeft : LucideIcons.arrowRight,
                    size: WpIconSize.xs,
                    color: WpColors.textMuted,
                  ),
                  const SizedBox(width: WpSpacing.sm),
                  // Replacement
                  Flexible(
                    child: Text(
                      '"${widget.replacement.replacement}"',
                      style: TextStyle(
                        color: WpColors.textSecondary,
                        fontSize: WpTypography.body,
                      ),
                      // `maxLines` is load-bearing, not cosmetic: without a
                      // cap `overflow: ellipsis` still lets the text wrap to
                      // as many lines as it likes (the Row leaves its cross
                      // axis unbounded), so a long replacement grew the row
                      // without limit.
                      //
                      // Why 1 here while the snippet row's preview now takes 2
                      // (ticket 03): the two are not the same slot. A snippet
                      // tile stacks a *title* over a secondary body preview,
                      // and the second preview line is what makes an otherwise
                      // anonymous "Signature", "Address" row identifiable. A
                      // replacement row has no title — the trigger chips to
                      // the left are the identity, and this text is the
                      // primary content sharing their line. Giving it a second
                      // line would push the chips off-centre against their own
                      // arrow glyph for no gain in recognisability.
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.replacement.usageCount > 0) ...[
                    const SizedBox(width: WpSpacing.sm),
                    Text(
                      L10n.of(
                        context,
                      ).dictionaryUsageCount(widget.replacement.usageCount),
                      style: TextStyle(
                        color: WpColors.textMuted,
                        fontSize: WpTypography.small,
                      ),
                      maxLines: 1,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The origin marker of a replacement row: manual, learned or imported.
class _OriginBadge extends StatelessWidget {
  const _OriginBadge({super.key, required this.origin});

  final String origin;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final (label, tone) = switch (origin) {
      'imported' => (l10n.replacementsImportedBadge, WpAccentBadgeTone.accent),
      'learned' => (l10n.replacementsLearnedBadge, WpAccentBadgeTone.highlight),
      _ => (l10n.replacementsManualBadge, WpAccentBadgeTone.muted),
    };
    return Semantics(
      identifier: 'replacements-origin-$origin',
      child: WpAccentBadge(label: label, tone: tone),
    );
  }
}
