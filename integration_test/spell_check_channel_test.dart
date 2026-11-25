/// Runs the real `whispaste/spell_check` host (#670): NSSpellChecker on
/// macOS, the Spell Checking API on Windows, Enchant 2 on Linux. Each lab
/// machine has an English dictionary (Ubuntu: `libenchant-2-2` and
/// `hunspell-en-us`), so the channel must list it, flag a misspelled word,
/// pass a correct one and suggest the fix.
/// Run with `flutter test integration_test/spell_check_channel_test.dart -d`
/// and the target macos, linux or windows.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:whispaste/core/spell/spell_check.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const backend = ChannelSpellCheckBackend();

  testWidgets('lists, checks and suggests with the system dictionary', (
    tester,
  ) async {
    final languages = await backend.languages();
    // ignore: avoid_print
    print('SPELL-LANGUAGES ${languages.length}: ${languages.take(20)}');
    final en = resolveSpellLanguage(
      setting: spellCheckLanguageAuto,
      dictationLanguage: 'en',
      appLanguage: 'en',
      available: languages,
    );
    expect(en, isNotNull, reason: 'no English dictionary in $languages');

    final answers = await backend.checkWords(en!, ['house', 'hosue', '']);
    expect(answers, [true, false, true]);

    final suggestions = await backend.suggest(en, 'hosue');
    // ignore: avoid_print
    print('SPELL-SUGGEST $en hosue -> $suggestions');
    expect(suggestions, contains('house'));
    expect(suggestions.length, lessThanOrEqualTo(10));
  });

  testWidgets('an unknown language answers every word as correct', (
    tester,
  ) async {
    final answers = await backend.checkWords('xx-XX', ['hosue']);
    expect(answers, [true]);
  });
}
