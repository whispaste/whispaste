/// 9.10: the hand-off notifier that carries the wrong-language hint to the
/// recording widget. A new instance per event lets repeats fire again.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/transcription/language_mismatch_hint.dart';

void main() {
  test('starts empty, publishes a hint, and clears it', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(languageMismatchHintProvider.notifier);

    expect(container.read(languageMismatchHintProvider), isNull);

    notifier.show(const LanguageMismatchHint(detected: 'en', configured: 'de'));
    final hint = container.read(languageMismatchHintProvider);
    expect(hint?.detected, 'en');
    expect(hint?.configured, 'de');

    notifier.clear();
    expect(container.read(languageMismatchHintProvider), isNull);
  });

  test('a repeated mismatch fires again after the clear', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(languageMismatchHintProvider.notifier);

    notifier.show(const LanguageMismatchHint(detected: 'en', configured: 'de'));
    notifier.clear();
    expect(container.read(languageMismatchHintProvider), isNull);
    notifier.show(const LanguageMismatchHint(detected: 'en', configured: 'de'));
    expect(container.read(languageMismatchHintProvider)?.detected, 'en');
  });
}
