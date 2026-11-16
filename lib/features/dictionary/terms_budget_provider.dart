/// Where the term list stops reaching the active recognition (issue #622).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_provider.dart';
import '../../services/dictionary/term_budget.dart';
import '../../services/stt/stt_bundle.dart';
import 'role_terms.dart';

/// Index of the first term the active recognition leaves out, or null.
/// Recomputed when the terms, the recognition or the loaded model change.
final termsLeftOutFromProvider = FutureProvider.autoDispose<int?>((ref) async {
  final settings = ref.watch(settingsProvider).value;
  if (settings == null) return null;
  // The loaded model decides the exact count: follow its state.
  ref.watch(localSttBundleProvider);
  final stored = settings.stt.customVocabulary;
  return firstLeftOutTerm(
    vocabularyTerms(stored),
    provider: settings.sttProviderType,
    engine: settings.onDeviceEngine,
    style: stored,
    countTokens: ref
        .read(localSttBundleProvider.notifier)
        .countPromptTokensOrNull,
  );
});
