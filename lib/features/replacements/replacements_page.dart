import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/config/settings_provider.dart';
import '../../core/data/reloadable_list_notifier.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../services/replacements/text_replacement_matcher.dart'
    show
        TextReplacementMatchMode,
        fuzzyMinTriggerLength,
        fuzzyThresholdStrict,
        fuzzyThresholdStandard,
        fuzzyThresholdTolerant;
import '../../services/dictionary/replacement_duplicates.dart';
import '../../services/replacements/correction_learning_service.dart';
import '../../services/replacements/vocabulary_import_service.dart';
import '../../services/telemetry_service.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/wp_list_tile_surface.dart';
import '../../widgets/wp_row_action.dart';
import '../../widgets/dialog.dart';
import '../../widgets/searchable_list_page.dart';
import '../../widgets/toast.dart';
import '../../widgets/trigger_chip.dart';
import '../../widgets/wp_accent_badge.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/wp_favourite_star.dart';
import '../../widgets/wp_segmented_selector.dart';
import '../../widgets/wp_text_field.dart';
import '../settings/settings_widgets.dart' show SettingRow, settingsToggle;
import 'correction_cards.dart';
import 'vocabulary_import_review_page.dart';
import 'package:whispaste/core/data/database.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

class Replacement {
  const Replacement({
    required this.id,
    required this.triggers,
    required this.replacement,
    this.matchMode = TextReplacementMatchMode.exact,
    this.fuzzyThreshold,
    this.origin = 'manual',
    this.isFavorite = false,
    this.usageCount = 0,
  });

  final String id;

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
      await db.upsertReplacementWithTriggers(
        id: id,
        triggers: [trigger],
        replacement: replacement,
        createdAt: now,
      );
    }
  }

  // Deliberately not further extracted: shares its "generate a uuid,
  // upsert, reload" shape with SnippetsNotifier.add. A shared
  // `createThenReload(persist)` helper was tried on ReloadableListNotifier:
  // it replaced this direct, linear code with a persist-callback closure for
  // no net line reduction — not worth the indirection for three lines.
  Future<void> add(
    List<String> triggers,
    String replacement, {
    TextReplacementMatchMode matchMode = TextReplacementMatchMode.exact,
    double? fuzzyThreshold,
    String origin = 'manual',
  }) async {
    final db = ref.read(historyDatabaseProvider);
    final id = generateV4Uuid();
    await db.upsertReplacementWithTriggers(
      id: id,
      triggers: triggers,
      replacement: replacement,
      createdAt: DateTime.now(),
      matchMode: matchMode.name,
      fuzzyThreshold: fuzzyThreshold,
      origin: origin,
    );
    await reload();
  }

  Future<void> updateReplacement(
    String id, {
    required List<String> triggers,
    required String replacement,
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
      createdAt: DateTime.now(),
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
          id: '${now.millisecondsSinceEpoch}_$i',
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

  /// Adds several entries in one transaction (CSV batch import, C-M-4): a
  /// failing row adds none of them.
  Future<void> addAll(
    Iterable<
      ({
        List<String> triggers,
        String replacement,
        TextReplacementMatchMode matchMode,
        double? fuzzyThreshold,
      })
    >
    entries,
  ) async {
    final db = ref.read(historyDatabaseProvider);
    final now = DateTime.now();
    await db.writeReplacements([
      for (final e in entries)
        ReplacementWrite(
          id: generateV4Uuid(),
          triggers: e.triggers,
          replacement: e.replacement,
          createdAt: now,
          matchMode: e.matchMode.name,
          fuzzyThreshold: e.fuzzyThreshold,
        ),
    ]);
    await reload();
  }

  static Replacement _fromDb(ReplacementWithTriggers joined) => Replacement(
    id: joined.row.id,
    triggers: joined.triggers,
    replacement: joined.row.replacement,
    matchMode: joined.row.matchMode == 'fuzzy'
        ? TextReplacementMatchMode.fuzzy
        : TextReplacementMatchMode.exact,
    fuzzyThreshold: joined.row.fuzzyThreshold,
    origin: joined.row.origin,
    isFavorite: joined.row.isFavorite,
    usageCount: joined.row.usageCount,
  );
}

final replacementsProvider =
    AsyncNotifierProvider<ReplacementsNotifier, List<Replacement>>(
      ReplacementsNotifier.new,
    );

/// Overridable in tests (fake folder picker / extraction) so the import flow
/// can be exercised without a real native folder-choose dialog.
final vocabularyImportServiceProvider = Provider<VocabularyImportService>(
  (ref) => VocabularyImportService(),
);

/// Every correction candidate currently eligible for review (ticket 01
/// `.scratch/vocab-learning-corrections/`). `autoDispose` so a stale list
/// isn't kept alive once the Replacements page (its only consumer) is
/// popped -- re-fetched fresh next time it's opened.
final pendingCorrectionCandidatesProvider =
    FutureProvider.autoDispose<List<CorrectionCandidate>>((ref) {
      final service = ref.read(correctionLearningServiceProvider);
      final db = ref.read(historyDatabaseProvider);
      return service.pendingCandidates(db);
    });

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

/// Replacements page — auto-replace words during dictation.
class ReplacementsPage extends ConsumerStatefulWidget {
  const ReplacementsPage({super.key, this.showSuggestionCards = true});

  /// Whether the correction-learning switch and the pending-suggestions card
  /// sit above the list. The dictionary's Suggestions tab shows them instead,
  /// so the Replacements tab passes `false` to avoid showing them twice.
  final bool showSuggestionCards;

  @override
  ConsumerState<ReplacementsPage> createState() => _ReplacementsPageState();
}

class _ReplacementsPageState extends ConsumerState<ReplacementsPage> {
  bool _importing = false;
  bool _reviewingCorrections = false;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    // Narrowed to the one field this page renders: `settingsProvider` emits
    // on every settings write anywhere in the app, and watching the whole
    // value here rebuilt this entire page (list included) for changes that
    // have nothing to do with the replacements master switch.
    final enabled =
        ref.watch(
          settingsProvider.select((s) => s.value?.textReplacementsEnabled),
        ) ??
        true;
    final correctionLearningEnabled =
        ref.watch(
          settingsProvider.select(
            (s) => s.value?.behavior.correctionLearningEnabled,
          ),
        ) ??
        true;
    final pendingCorrectionCandidates = ref
        .watch(pendingCorrectionCandidatesProvider)
        .maybeWhen(data: (c) => c, orElse: () => const <CorrectionCandidate>[]);
    final allReplacements = ref
        .watch(replacementsProvider)
        .maybeWhen(data: (r) => r, orElse: () => const <Replacement>[]);
    final duplicateIds = duplicateReplacementIds([
      for (final r in allReplacements)
        TriggerOwner(id: r.id, triggers: r.triggers),
    ]);

    return WpSearchableListPage<Replacement>(
      // The master switch lives in a header card, not in the toolbar.
      //
      // In the toolbar it was a bare `Text` next to an unlabelled `Switch`:
      // measured on the semantics tree, the switch node carried an empty
      // label while its caption merged into the page-level focus node far
      // away from it — a screen reader announced "switch, on" with no clue
      // what it switches. It also broke the house tooltip rule by putting a
      // Tooltip on a control that already had a visible caption.
      //
      // `SettingRow` is the shape the app already uses for "labelled control
      // with an explanatory subtitle", it names the switch correctly by
      // construction (see no_double_announcement_test), and it puts this
      // screen's own setting exactly where the sibling Snippets screen puts
      // its picker-trigger field. That leaves all three screens with the
      // same toolbar: search plus the add button, nothing else.
      //
      // Unlike the Snippets header this one is not platform-gated —
      // replacements run on all three platforms.
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ReplacementsToggleCard(
            enabled: enabled,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .updateSettings((s) => s.copyWith(textReplacementsEnabled: v)),
          ),
          _VocabularyImportCard(
            onImport: _importFromFolder,
            importing: _importing,
          ),
          if (widget.showSuggestionCards)
            CorrectionLearningToggleCard(
              enabled: correctionLearningEnabled,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings(
                    (s) => s.copyWithSections(
                      behavior: s.behavior.copyWith(
                        correctionLearningEnabled: v,
                      ),
                    ),
                  ),
            ),
          if (widget.showSuggestionCards &&
              pendingCorrectionCandidates.isNotEmpty)
            CorrectionCandidatesCard(
              count: pendingCorrectionCandidates.length,
              reviewing: _reviewingCorrections,
              onReview: () =>
                  _reviewCorrectionCandidates(pendingCorrectionCandidates),
            ),
        ],
      ),
      asyncAll: ref.watch(replacementsProvider),
      // ⚡ Bolt: Use precompiled case-insensitive RegExp to match fields instead
      // of allocating lowercased strings repeatedly in tight loops.
      searchMatches: (r, q) =>
          r.triggers.any((t) => q.hasMatch(t)) || q.hasMatch(r.replacement),
      searchHint: l10n.replacementsSearch,
      searchFieldLabel: l10n.replacementsSearchFieldLabel,
      addLabel: l10n.replacementsAdd,
      onAdd: () => _showAddEditDialog(),
      onRetry: () => ref.invalidate(replacementsProvider),
      emptyIcon: LucideIcons.replace,
      emptyTitle: l10n.replacementsEmpty,
      emptyHint: l10n.replacementsEmptyHint,
      // Same string as the empty state's hint — see the Snippets call site.
      subtitle: l10n.replacementsEmptyHint,
      emptyActionLabel: l10n.replacementsAdd,
      noMatchesTitle: l10n.replacementsNoMatches,
      noMatchesHint: l10n.replacementsNoMatchesHint,
      // Content — dimmed when disabled so users can still see their shortcuts
      contentWrapper: (context, child) => AnimatedOpacity(
        duration: WpMotion.durationFor(context, WpMotion.normal),
        opacity: enabled ? 1.0 : 0.5,
        child: child,
      ),
      onItemActivate: (r) => _showAddEditDialog(existing: r),
      onItemDelete: _confirmDelete,
      itemBuilder: (context, r, isCursor) {
        // loam-ignore: a11y-interactive-semantics – semantics provided in _ReplacementTileState.build
        return _ReplacementTile(
          replacement: r,
          isCursor: isCursor,
          isDuplicate: duplicateIds.contains(r.id),
          onTap: () => _showAddEditDialog(existing: r),
          onCopy: () => _copyReplacement(r),
          onDuplicate: () => _duplicateReplacement(r),
          onDelete: () => _confirmDelete(r),
          onToggleFavourite: () => ref
              .read(replacementsProvider.notifier)
              .setFavourite(r.id, value: !r.isFavorite),
        );
      },
    );
  }

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
        await notifier.updateReplacement(
          existing.id,
          triggers: triggers,
          replacement: replacement,
          matchMode: matchMode,
          fuzzyThreshold: fuzzyThreshold,
          origin: existing.origin,
        );
      } else {
        await notifier.add(
          triggers,
          replacement,
          matchMode: matchMode,
          fuzzyThreshold: fuzzyThreshold,
        );
        ref
            .read(telemetrySessionAggregatorProvider)
            .count(category: 'replacements', action: 'create');
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Vocabulary import ─────────────────────────────────────────────────

  Future<void> _importFromFolder() async {
    if (_importing) return;
    final l10n = L10n.of(context);
    setState(() => _importing = true);
    try {
      final notifier = ref.read(replacementsProvider.notifier);
      final scanResult = await notifier.scanFolderForImport();
      if (scanResult == null || !mounted) return;
      if (scanResult.candidates.isEmpty) {
        WpToast.show(
          context,
          message: l10n.replacementsImportNothingFound,
          type: WpToastType.info,
        );
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
      WpToast.show(
        context,
        message: l10n.replacementsImportSummary(
          scanResult.candidates.length,
          added,
          scanResult.skipped,
        ),
        type: WpToastType.success,
      );
    } catch (_) {
      if (!mounted) return;
      WpToast.show(
        context,
        message: l10n.replacementsImportError,
        type: WpToastType.error,
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  // ── Correction-learning review ────────────────────────────────────────

  /// Pushes the exact same review page the vocabulary-import flow uses
  /// (PRD.md decision: "reuses the existing vocabulary-import review flow"),
  /// just fed each candidate's `"source → target"` display text instead of
  /// a bare identifier. That page only knows how to hand back the strings
  /// the user selected, so [_candidates] doubles as the lookup from a
  /// selected display string back to its candidate id.
  ///
  /// The review page has no separate per-candidate "reject" action — only
  /// "select some and commit" or "cancel entirely" (see
  /// `VocabularyImportReviewPage`). So committing treats every candidate
  /// that was shown but not selected as rejected; cancelling leaves every
  /// candidate untouched (still pending, offered again next time).
  Future<void> _reviewCorrectionCandidates(
    List<CorrectionCandidate> candidates,
  ) async {
    if (_reviewingCorrections || candidates.isEmpty) return;
    final l10n = L10n.of(context);
    setState(() => _reviewingCorrections = true);
    try {
      final byDisplayText = {for (final c in candidates) c.displayText: c};

      final selected = await Navigator.of(context).push<List<String>>(
        MaterialPageRoute(
          builder: (_) => VocabularyImportReviewPage(
            candidates: [for (final c in candidates) c.displayText],
            title: l10n.correctionCandidatesReviewTitle,
            subtitleBuilder: l10n.correctionCandidatesReviewSubtitle,
          ),
        ),
      );
      if (selected == null || !mounted) return;

      final service = ref.read(correctionLearningServiceProvider);
      final db = ref.read(historyDatabaseProvider);
      final added = await service.commit(
        shownIds: [for (final c in candidates) c.id],
        acceptedIds: [for (final s in selected) byDisplayText[s]!.id],
        db: db,
      );

      ref.invalidate(pendingCorrectionCandidatesProvider);
      await ref.read(replacementsProvider.notifier).reload();
      if (!mounted) return;
      WpToast.show(
        context,
        message: l10n.correctionCandidatesCommitSummary(added),
        type: WpToastType.success,
      );
    } finally {
      if (mounted) setState(() => _reviewingCorrections = false);
    }
  }

  // ── Copy action ──────────────────────────────────────────────────────

  void _copyReplacement(Replacement r) {
    copyToClipboardWithToast(
      context: context,
      ref: ref,
      text: r.replacement,
      category: 'replacements',
    );
  }

  Future<void> _duplicateReplacement(Replacement r) async {
    final firstTrigger = r.triggers.isNotEmpty ? r.triggers.first : 'trigger';
    await ref
        .read(replacementsProvider.notifier)
        .add(
          ['$firstTrigger (copy)'],
          r.replacement,
          matchMode: r.matchMode,
          fuzzyThreshold: r.fuzzyThreshold,
        );
  }

  // ── Delete confirmation ──────────────────────────────────────────────

  Future<void> _confirmDelete(Replacement r) {
    final l10n = L10n.of(context);
    return showWpDeleteConfirmDialog(
      context: context,
      title: l10n.replacementsDeleteTitle,
      message: l10n.replacementsDeleteMessage(r.triggers.join(', ')),
      onConfirm: () => ref.read(replacementsProvider.notifier).remove(r.id),
    );
  }
}

// ---------------------------------------------------------------------------
// Master switch
// ---------------------------------------------------------------------------

/// Header card above the replacement list: the single switch that turns
/// automatic text replacement on or off during dictation.
///
/// Lives on this page rather than in Settings because it only matters in the
/// context of the list it governs — the same placement rule that keeps the
/// Snippets picker-trigger field on the Snippets page. Card geometry is
/// deliberately identical to `_SnippetPickerTriggerField`'s so switching
/// between the two sibling screens never nudges the toolbar below it.
class _ReplacementsToggleCard extends StatelessWidget {
  const _ReplacementsToggleCard({
    required this.enabled,
    required this.onChanged,
  });

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WpSpacing.xl,
        WpSpacing.sm,
        WpSpacing.xl,
        0,
      ),
      child: Container(
        padding: const EdgeInsets.all(WpSpacing.xxs),
        // Card material, same correction as the snippets header opposite it:
        // a plate on the content plane, frost rather than an opaque band.
        decoration: BoxDecoration(
          color: WpColors.cardFill,
          borderRadius: WpRadius.borderMd,
          border: Border.all(color: WpColors.borderSubtle),
        ),
        child: SettingRow(
          icon: LucideIcons.replace,
          label: l10n.replacementsToggleLabel,
          // The subtitle states the current state in words, which is what
          // the toolbar's caption used to do — except a screen reader now
          // gets it too, and `semanticToggledValue` adds the on/off state to
          // the row's own announcement. No Tooltip: the row is labelled on
          // screen, so one would only repeat what is already there.
          subtitle: enabled
              ? l10n.replacementsToggleEnabled
              : l10n.replacementsToggleDisabled,
          semanticToggledValue: enabled,
          trailing: settingsToggle(value: enabled, onChanged: onChanged),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Vocabulary import entry point
// ---------------------------------------------------------------------------

/// "Import from folder" card (PRD.md vocabulary-fuzzy-replacements, UI
/// requirement (a)) — same card geometry as [_ReplacementsToggleCard] right
/// above it, so the two headers read as one stacked group.
class _VocabularyImportCard extends StatelessWidget {
  const _VocabularyImportCard({
    required this.onImport,
    required this.importing,
  });

  final VoidCallback onImport;
  final bool importing;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WpSpacing.xl,
        WpSpacing.xxs,
        WpSpacing.xl,
        0,
      ),
      child: Container(
        padding: const EdgeInsets.all(WpSpacing.xxs),
        decoration: BoxDecoration(
          color: WpColors.cardFill,
          borderRadius: WpRadius.borderMd,
          border: Border.all(color: WpColors.borderSubtle),
        ),
        child: SettingRow(
          icon: LucideIcons.folderInput,
          label: l10n.replacementsImportFromFolder,
          subtitle: importing
              ? l10n.replacementsImportScanning
              : l10n.replacementsImportHint,
          // loam-ignore: a11y-interactive-semantics – semantics provided in WpButton.build
          trailing: WpButton(
            key: const ValueKey('replacements-import-folder'),
            label: l10n.replacementsImportFromFolder,
            variant: WpButtonVariant.secondary,
            size: WpButtonSize.dense,
            isLoading: importing,
            onPressed: importing ? null : onImport,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Correction-learning (ticket 01 `.scratch/vocab-learning-corrections/`)
// ---------------------------------------------------------------------------

/// Global on/off switch for automatic correction-candidate detection — same
/// card geometry as [_ReplacementsToggleCard]/[_VocabularyImportCard] above
/// it. Turning this off only stops new candidates from being *observed*; it
/// never touches already-learned entries or candidates already pending
/// review (see `BehaviorSettings.correctionLearningEnabled` doc comment).
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
  bool _saving = false;

  /// Maximum height of the trigger list before it scrolls, so the dialog
  /// stays on screen when a shortcut has many trigger phrases. Derived from
  /// the row height rather than guessed, so it always ends on a row edge
  /// instead of cutting one in half: four 48 dp fields plus the three 4 dp
  /// gaps between them.
  static const double _triggerListMaxHeight =
      WpLayout.minTouchTarget * 4 + WpSpacing.xxs * 3;

  final List<TextEditingController> _triggerCtrls = [];
  final List<FocusNode> _triggerFocusNodes = [];
  late final TextEditingController _replacementCtrl;
  late TextReplacementMatchMode _matchMode;
  late double _fuzzyThreshold;

  bool get _isValid =>
      _triggerCtrls.any((c) => c.text.trim().isNotEmpty) &&
      _replacementCtrl.text.trim().isNotEmpty;

  bool get _isEditing => widget.existing != null;

  /// PRD.md: trigger phrases below [fuzzyMinTriggerLength] are locked out of
  /// fuzzy mode in the UI — too short and every dictated word becomes a
  /// false hit, even at the strictest threshold.
  bool get _fuzzyAllowed =>
      _triggerCtrls.any((c) => c.text.trim().length >= fuzzyMinTriggerLength);

  @override
  void initState() {
    super.initState();
    final existingTriggers = widget.existing?.triggers ?? const [];
    for (final trigger
        in existingTriggers.isNotEmpty ? existingTriggers : const ['']) {
      _triggerCtrls.add(TextEditingController(text: trigger));
      _triggerFocusNodes.add(FocusNode());
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
      node.dispose();
    }
    _replacementCtrl.dispose();
    super.dispose();
  }

  void _addTrigger() {
    final node = FocusNode();
    setState(() {
      _triggerCtrls.add(TextEditingController());
      _triggerFocusNodes.add(node);
    });
    // Focus the new field after it has been built; the surrounding
    // Scrollable auto-scrolls it into view.
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

  Future<void> _submit() async {
    if (!_isValid || _saving) return;
    final triggers = _triggerCtrls
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    // A Similar entry whose trigger fell below the minimum is not saved as
    // exact behind the user's back: the mode switches visibly and the save
    // stops until they look at it (UIA-DIC-05).
    if (_matchMode == TextReplacementMatchMode.fuzzy && !_fuzzyAllowed) {
      setState(() => _matchMode = TextReplacementMatchMode.exact);
      WpToast.show(
        context,
        message: L10n.of(
          context,
        ).replacementsFuzzyTooShortWarning(fuzzyMinTriggerLength),
        type: WpToastType.warning,
      );
      return;
    }
    final clash = widget.findClash(triggers);
    if (clash != null) {
      WpToast.show(
        context,
        message: L10n.of(
          context,
        ).replacementsDuplicateTrigger(clash.trigger, clash.replacement),
        type: WpToastType.error,
      );
      return;
    }
    // A trigger edit that drops below the fuzzy minimum length must not
    // leave a stale fuzzy mode behind it.
    final matchMode = _fuzzyAllowed
        ? _matchMode
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
      WpToast.show(
        context,
        message: L10n.of(context).errorGeneric,
        type: WpToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textMuted = WpColors.textMuted;
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
          // Trigger phrases — dynamic list, one text field per phrase
          Text(
            l10n.replacementsTriggerLabel,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: WpSpacing.xxs),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: _triggerListMaxHeight),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                            // Full 48 dp tap target, spelled as the token so it
                            // moves with it. Costs no height: the row is already
                            // 48 dp tall because the neighbouring
                            // `WpTextField.form` is, and `_triggerListMaxHeight`
                            // above already counts 48 dp per row.
                            IconButton(
                              key: ValueKey('replacements-trigger-remove-$i'),
                              tooltip: l10n.replacementsRemoveTrigger,
                              icon: Icon(
                                LucideIcons.x,
                                size: WpIconSize.sm,
                                color: textMuted,
                              ),
                              onPressed: () => _removeTrigger(i),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: WpLayout.minTouchTarget,
                                minHeight: WpLayout.minTouchTarget,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: WpSpacing.xxs),
          Align(
            alignment: AlignmentDirectional.centerStart,
            // loam-ignore: a11y-interactive-semantics – semantics provided in WpButton.build
            child: WpButton(
              key: const ValueKey('replacements-trigger-add'),
              label: l10n.replacementsAddTrigger,
              variant: WpButtonVariant.ghost,
              size: WpButtonSize.dense,
              icon: LucideIcons.plus,
              onPressed: _addTrigger,
            ),
          ),
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
            selected: _matchMode,
            onChanged: (value) => setState(() => _matchMode = value),
          ),
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
          if (_matchMode == TextReplacementMatchMode.fuzzy) ...[
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
          // loam-ignore: a11y-interactive-semantics – semantics provided in WpButton.build
          WpButton(
            key: const ValueKey('replacements-cancel'),
            label: l10n.actionCancel,
            variant: WpButtonVariant.ghost,
            tone: WpButtonTone.neutral,
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: WpSpacing.sm),
          // loam-ignore: a11y-interactive-semantics – semantics provided in WpButton.build
          WpButton(
            key: const ValueKey('replacements-save'),
            label: _isEditing ? l10n.actionSave : l10n.replacementsAdd,
            variant: WpButtonVariant.primary,
            onPressed: _isValid ? _submit : null,
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
    required this.replacement,
    required this.isCursor,
    required this.isDuplicate,
    required this.onTap,
    required this.onCopy,
    required this.onDuplicate,
    required this.onDelete,
    required this.onToggleFavourite,
  });

  final Replacement replacement;

  /// This row is the list's arrow cursor — same contract, same two outlets
  /// and same reasoning as `_SnippetTile.isCursor`, which see.
  final bool isCursor;

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
  /// cursor, for the reason spelled out on `_SnippetTile._isActive`.
  bool get _isActive => _isHovered || _isFocused || widget.isCursor;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      // Delete/Backspace on the focused row — same binding, same reasoning
      // and same row-scoping as _SnippetTile, which see.
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
      // same reasoning and same shape as _SnippetTile, which see. The label
      // used to repeat the trigger phrases the chips already render, and a
      // Semantics label is prepended to its subtree's text rather than
      // substituted for it, so each row announced "Ersetzung bearbeiten:
      // mfg, mfg, …". MergeSemantics is not an option: the delete action
      // mounts as a second interactive node once the row is active.
      hint: L10n.of(context).replacementsEditShortcut,
      // The arrow cursor's row reports as selected — same flag, same reason
      // as `_SnippetTile`, which see.
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
              isFocused: _isFocused || widget.isCursor,
              isSelected: widget.isCursor,
              actions: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: L10n.of(context).dictionaryFavouriteLabel,
                    child: WpFavouriteStar(
                      isFavourite: widget.replacement.isFavorite,
                      semanticsLabel: L10n.of(context).dictionaryFavouriteLabel,
                      onToggle: widget.onToggleFavourite,
                    ),
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
                      // loam-ignore: a11y-interactive-semantics – semantics provided in _WpRowActionState.build
                      WpRowAction(
                        key: ValueKey(
                          'replacements-copy-${widget.replacement.id}',
                        ),
                        icon: LucideIcons.copy,
                        tooltip: L10n.of(context).actionCopy,
                        onTap: widget.onCopy,
                      ),
                      // loam-ignore: a11y-interactive-semantics – semantics provided in _WpRowActionState.build
                      WpRowAction(
                        key: ValueKey(
                          'replacements-duplicate-${widget.replacement.id}',
                        ),
                        icon: LucideIcons.files,
                        tooltip: L10n.of(context).actionDuplicate,
                        onTap: widget.onDuplicate,
                      ),
                      // loam-ignore: a11y-interactive-semantics – semantics provided in _WpRowActionState.build
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
                  if (widget.replacement.origin == 'imported') ...[
                    const SizedBox(width: WpSpacing.xxs),
                    WpAccentBadge(
                      label: L10n.of(context).replacementsImportedBadge,
                    ),
                  ],
                  if (widget.replacement.origin == 'learned') ...[
                    const SizedBox(width: WpSpacing.xxs),
                    WpAccentBadge(
                      label: L10n.of(context).replacementsLearnedBadge,
                      tone: WpAccentBadgeTone.highlight,
                    ),
                  ],
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
