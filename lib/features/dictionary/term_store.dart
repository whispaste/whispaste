import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_provider.dart';

/// Settings reports persistence errors through its failure counter rather
/// than throwing. A dictionary decision must not claim success in that case.
Future<void> saveDictionaryVocabulary(
  ProviderContainer container,
  String Function(String current) change,
) async {
  await container.read(settingsProvider.future);
  final failures = container.read(settingsSaveFailuresProvider);
  await container
      .read(settingsProvider.notifier)
      .updateSettings(
        (s) => s.copyWith(customVocabulary: change(s.stt.customVocabulary)),
      );
  if (container.read(settingsSaveFailuresProvider) != failures) {
    throw StateError('Vocabulary could not be saved');
  }
}
