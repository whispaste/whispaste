/// Keeps the recogniser's term hint (`SttSettings.customVocabulary`, the one
/// text every engine reads) filled from the replacements (#1969), after the
/// one-time step of the old hand-kept term list into replacements.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_provider.dart';
import '../../core/data/database.dart';
import '../../core/logging/app_logger.dart';
import '../../services/dictionary/auto_terms.dart';
import '../../services/dictionary/contact_terms.dart';
import '../../services/replacements/text_replacement_matcher.dart'
    show newEntryMatch;
import '../replacements/replacements_page.dart';

final _log = AppLogger('AutoTermsSync');

/// Watched once by the app. Runs the migration when it is due and rewrites
/// the term hint whenever the replacements change.
final autoTermsSyncProvider = Provider<void>((ref) {
  var busy = false;
  var again = false;
  Future<void> run() async {
    if (busy) {
      again = true;
      return;
    }
    busy = true;
    try {
      do {
        again = false;
        await syncAutoTerms(ref.container);
      } while (again);
    } catch (e) {
      // Retried on the next change; the engines keep the previous hint.
      _log.debug(
        'Term hint not synced (${errorKind(e)}), retried on next change',
      );
    } finally {
      busy = false;
    }
  }

  ref.listen(replacementsProvider, (_, _) => run());
  ref.listen(settingsProvider, (_, _) => run());
  Future.microtask(run);
});

/// One pass: migrate the hand-kept terms once, then write the term hint
/// from the replacements if it differs. Idempotent.
Future<void> syncAutoTerms(ProviderContainer container) async {
  final settings = await container.read(settingsProvider.future);
  final notifier = container.read(settingsProvider.notifier);
  var replacements = await container.read(replacementsProvider.future);

  if (!settings.stt.termsMigrated) {
    final manual = settings.stt.customVocabulary;
    final add = termMigrationPlan(
      manual,
      existingTriggers: [for (final r in replacements) ...r.triggers],
    );
    final db = container.read(historyDatabaseProvider);
    final now = DateTime.now();
    for (final term in add) {
      final match = newEntryMatch([term]);
      await db.upsertReplacementWithTriggers(
        id: generateV4Uuid(),
        triggers: [term],
        replacement: term,
        createdAt: now,
        matchMode: match.mode.name,
        fuzzyThreshold: match.fuzzyThreshold,
      );
    }
    // Done only after every entry is written: a crash in between repeats
    // the step, and the trigger check keeps it from adding twice.
    await notifier.updateSettings(
      (s) => s.copyWithSections(
        stt: s.stt.copyWith(
          termsMigrated: true,
          manualVocabularyArchive: manual,
        ),
      ),
    );
    if (add.isNotEmpty) {
      await container.read(replacementsProvider.notifier).reload();
      replacements = await container.read(replacementsProvider.future);
    }
  }

  // Contact names (#2036) never enter this text: every engine reads it,
  // cloud engines included. Local engines get them from
  // `contactTermsProvider` behind the own terms.
  final hint = autoTermsVocabulary([
    for (final r in replacements)
      if (r.importGroupId == null)
        (
          replacement: r.replacement,
          usageCount: r.usageCount,
          isTerm: isTermEntry(r.triggers, r.replacement),
          changed: r.updatedAt ?? r.createdAt,
        ),
  ]);
  container
      .read(contactTermsProvider.notifier)
      .set(
        contactHintTerms([
          for (final r in replacements)
            if (r.importGroupId != null)
              (
                name: r.replacement,
                usageCount: r.usageCount,
                changed: r.updatedAt ?? r.createdAt,
              ),
        ]),
      );
  final current = await container.read(settingsProvider.future);
  if (current.stt.customVocabulary != hint) {
    await notifier.updateSettings(
      (s) => s.copyWithSections(stt: s.stt.copyWith(customVocabulary: hint)),
    );
  }
}
