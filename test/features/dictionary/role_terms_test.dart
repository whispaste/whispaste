/// The dictionary's one-time term suggestion for the onboarding roles: which
/// terms are offered, how they join the terms list, and that taking them
/// over or hiding them ends it (maintainer 2026-10-31, ticket 2a, part B).
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/dictionary/widgets/role_terms_card.dart';
import 'package:whispaste/features/dictionary/role_terms.dart';
import 'package:whispaste/widgets/wp_filter_chip.dart';

import '../../fixtures/test_helpers.dart';

class _RecordingSettingsNotifier extends SettingsNotifier {
  _RecordingSettingsNotifier(this._settings);

  AppSettings _settings;
  final List<AppSettings> updates = <AppSettings>[];

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    updates.add(_settings);
    state = AsyncData(_settings);
  }
}

OnboardingSettings _roles(String roles, {bool done = false}) =>
    OnboardingSettings(
      onboardingCompleted: true,
      userRoles: roles,
      roleTermsDone: done,
    );

List<String> _terms(List<RoleTermGroup> groups) => [
  for (final g in groups) ...g.terms,
];

void main() {
  group('roleTermSuggestion', () {
    test('offers the pack of each chosen role, in chip order', () {
      final groups = roleTermSuggestion(
        onboarding: _roles('dev,legal'),
        vocabulary: '',
        languageCode: 'de',
      );
      expect(groups.map((g) => g.role), ['dev', 'legal']);
      expect(groups.first.terms, kRoleTermPacks['dev']!['*']);
      expect(groups.last.terms, kRoleTermPacks['legal']!['de']);
    });

    test('national packs follow the app language, others fall back', () {
      List<String> legal(String lang) => _terms(
        roleTermSuggestion(
          onboarding: _roles('legal'),
          vocabulary: '',
          languageCode: lang,
        ),
      );
      expect(legal('ru'), kRoleTermPacks['legal']!['ru']);
      expect(legal('fr'), kRoleTermPacks['legal']!['en']);
    });

    test('nothing for roles without a pack, "Keine Angabe" or no answer', () {
      for (final roles in ['writing,other', 'declined', '']) {
        expect(
          roleTermSuggestion(
            onboarding: _roles(roles),
            vocabulary: '',
            languageCode: 'en',
          ),
          isEmpty,
          reason: roles,
        );
      }
    });

    test('terms already in the list are left out, case ignored', () {
      final groups = roleTermSuggestion(
        onboarding: _roles('business'),
        vocabulary: 'kpi,\nCRM, OKR, B2B',
        languageCode: 'en',
      );
      expect(_terms(groups), ['SaaS']);
    });

    test('a pack fully in the list leaves no suggestion', () {
      expect(
        roleTermSuggestion(
          onboarding: _roles('business'),
          vocabulary: 'KPI, CRM, OKR, B2B, SaaS',
          languageCode: 'en',
        ),
        isEmpty,
      );
    });

    test('a finished suggestion never comes back', () {
      expect(
        roleTermSuggestion(
          onboarding: _roles('dev', done: true),
          vocabulary: '',
          languageCode: 'en',
        ),
        isEmpty,
      );
    });

    test('the finished mark survives a restart and defaults to open', () {
      final stored = _roles('dev', done: true).toMap();
      expect(OnboardingSettings.fromMap(stored).roleTermsDone, isTrue);
      expect(OnboardingSettings.fromMap(const {}).roleTermsDone, isFalse);
    });
  });

  group('mergeVocabulary', () {
    test('appends with ", " and keeps the existing text', () {
      expect(mergeVocabulary('Alice Meyer', ['GitHub']), 'Alice Meyer, GitHub');
      expect(mergeVocabulary('', ['GitHub', 'npm']), 'GitHub, npm');
      expect(mergeVocabulary('Alice,', ['npm']), 'Alice, npm');
    });

    test('a list with one term per line goes on that way', () {
      expect(mergeVocabulary('Alice\nBob\n', ['npm']), 'Alice\nBob\nnpm');
    });

    test('never adds a term twice, case ignored', () {
      expect(
        mergeVocabulary('github', ['GitHub', 'npm', 'NPM']),
        'github, npm',
      );
      expect(mergeVocabulary('npm', ['npm']), 'npm');
    });
  });

  group('RoleTermsCard', () {
    Finder chip(String testId) =>
        find.byWidgetPredicate((w) => w is WpFilterChip && w.testId == testId);

    late HistoryDatabase db;

    Future<_RecordingSettingsNotifier> pump(
      WidgetTester tester, {
      String roles = 'dev',
      String vocabulary = '',
    }) async {
      final settings = _RecordingSettingsNotifier(
        AppSettings.defaults
            .copyWith(customVocabulary: vocabulary)
            .copyWithSections(onboarding: _roles(roles)),
      );
      await tester.pumpWidget(
        makeTestable(
          const Scaffold(body: RoleTermsCard()),
          db: db = HistoryDatabase.forTesting(NativeDatabase.memory()),
          overrides: [settingsProvider.overrideWith(() => settings)],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      return settings;
    }

    testWidgets('"Add" takes over the selected terms and ends the card', (
      tester,
    ) async {
      final settings = await pump(tester);
      final dev = kRoleTermPacks['dev']!['*']!;

      await tester.tap(chip('dictionary-role-terms-dev-1'));
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('dictionary-role-terms-accept')),
      );
      await tester.pumpAndSettle();

      // Terms are term entries "term → term" now (#1969).
      final rows = await tester.runAsync(db.readAllReplacements);
      final taken = {
        for (final r in rows!)
          if (r.triggers.single == r.row.replacement) r.row.replacement,
      };
      expect(taken, containsAll([...dev]..removeAt(1)));
      expect(taken, isNot(contains(dev[1])));
      expect(settings.updates.last.onboarding.roleTermsDone, isTrue);
      expect(chip('dictionary-role-terms-dev-0'), findsNothing);
    });

    testWidgets('"Hide" adds nothing and ends the card', (tester) async {
      final settings = await pump(tester);

      await tester.tap(
        find.byKey(const ValueKey('dictionary-role-terms-dismiss')),
      );
      await tester.pumpAndSettle();

      final saved = settings.updates.single;
      expect(saved.onboarding.roleTermsDone, isTrue);
      expect(chip('dictionary-role-terms-dev-0'), findsNothing);
    });

    testWidgets('terms the recogniser already gets are not suggested', (
      tester,
    ) async {
      await pump(tester, vocabulary: kRoleTermPacks['dev']!['*']!.join(', '));

      expect(chip('dictionary-role-terms-dev-0'), findsNothing);
    });

    testWidgets('with every term deselected "Add" does nothing', (
      tester,
    ) async {
      final settings = await pump(tester, roles: 'business', vocabulary: '');
      for (var i = 0; i < kRoleTermPacks['business']!['*']!.length; i++) {
        await tester.tap(chip('dictionary-role-terms-business-$i'));
        await tester.pump();
      }

      await tester.tap(
        find.byKey(const ValueKey('dictionary-role-terms-accept')),
      );
      await tester.pumpAndSettle();

      expect(settings.updates, isEmpty);
    });
  });
}
