// The "Über dich" rules: "Keine Angabe" counts as an answer and excludes
// the roles, Next waits for an answer, and the follow-up card asks only
// whoever declined, once, after enough dictations.

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/features/onboarding/about_answers.dart';

void main() {
  group('roles', () {
    test('"Keine Angabe" clears the roles, a role lifts it again', () {
      final declined = toggleAboutRole({'dev', 'legal'}, kAboutDeclined);
      expect(declined, {kAboutDeclined});
      expect(toggleAboutRole(declined, 'dev'), {'dev'});
    });

    test('a second tap takes the answer back', () {
      expect(toggleAboutRole({kAboutDeclined}, kAboutDeclined), isEmpty);
      expect(toggleAboutRole({'dev', 'legal'}, 'dev'), {'legal'});
    });

    test('stored in display order, "Keine Angabe" alone', () {
      expect(storeAboutRoles({'legal', 'writing'}), 'writing,legal');
      expect(storeAboutRoles({kAboutDeclined}), kAboutDeclined);
      expect(aboutRoles(storeAboutRoles({'legal', 'writing'})), {
        'writing',
        'legal',
      });
      expect(aboutRoles(''), isEmpty);
    });
  });

  test('a second tap on the chosen source clears it', () {
    expect(chooseAboutSource('', 'friend'), 'friend');
    expect(chooseAboutSource('friend', 'friend'), '');
    expect(chooseAboutSource('friend', kAboutDeclined), kAboutDeclined);
  });

  group('Next waits for an answer', () {
    test('nothing chosen holds both questions', () {
      const none = OnboardingSettings();
      expect(aboutAnswered(AboutQuestion.role, none), isFalse);
      expect(aboutAnswered(AboutQuestion.source, none), isFalse);
    });

    test('"Keine Angabe" and a real answer both free it', () {
      const declined = OnboardingSettings(
        userRoles: kAboutDeclined,
        userAttribution: kAboutDeclined,
      );
      const answered = OnboardingSettings(
        userRoles: 'dev',
        userAttribution: 'friend',
      );
      for (final q in AboutQuestion.values) {
        expect(aboutAnswered(q, declined), isTrue, reason: '$q declined');
        expect(aboutAnswered(q, answered), isTrue, reason: '$q answered');
      }
    });
  });

  group('follow-up card', () {
    const declinedBoth = OnboardingSettings(
      onboardingCompleted: true,
      userRoles: kAboutDeclined,
      userAttribution: kAboutDeclined,
    );

    test('asks the declined questions, role first, from the tenth '
        'dictation on', () {
      expect(
        aboutFollowUpQuestions(
          declinedBoth,
          dictations: kAboutFollowUpDictations - 1,
        ),
        isEmpty,
      );
      expect(
        aboutFollowUpQuestions(
          declinedBoth,
          dictations: kAboutFollowUpDictations,
        ),
        [AboutQuestion.role, AboutQuestion.source],
      );
    });

    test('only the declined question; answers and old empty states are '
        'never asked again', () {
      final roleOnly = declinedBoth.copyWith(userAttribution: 'friend');
      expect(aboutFollowUpQuestions(roleOnly, dictations: 50), [
        AboutQuestion.role,
      ]);
      const answered = OnboardingSettings(
        onboardingCompleted: true,
        userRoles: 'dev',
        userAttribution: 'friend',
      );
      expect(aboutFollowUpQuestions(answered, dictations: 50), isEmpty);
      const legacyEmpty = OnboardingSettings(onboardingCompleted: true);
      expect(aboutFollowUpQuestions(legacyEmpty, dictations: 50), isEmpty);
    });

    test('once: never after it was saved or dismissed, never before the '
        'onboarding is done', () {
      expect(
        aboutFollowUpQuestions(
          declinedBoth.copyWith(aboutFollowUpDone: true),
          dictations: 50,
        ),
        isEmpty,
      );
      expect(
        aboutFollowUpQuestions(
          declinedBoth.copyWith(onboardingCompleted: false),
          dictations: 50,
        ),
        isEmpty,
      );
    });

    test('the done mark survives a save and load', () {
      final stored = declinedBoth.copyWith(aboutFollowUpDone: true).toMap();
      expect(OnboardingSettings.fromMap(stored).aboutFollowUpDone, isTrue);
      expect(
        OnboardingSettings.fromMap(const {}).aboutFollowUpDone,
        isFalse,
        reason: 'an older settings store has no key: not done yet',
      );
    });
  });
}
