import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/app_profiles/app_profile.dart';
import 'package:whispaste/services/app_profiles/app_profile_consent.dart';
import 'package:whispaste/services/app_profiles/app_profile_resolver.dart';

const _mail = AppProfile(
  id: 'mail',
  name: 'Mail',
  rules: [AppMatchRule(identifier: 'com.apple.mail')],
  smartMode: AppProfileSmartMode.cleanup,
);
const _code = AppProfile(
  id: 'code',
  name: 'Code',
  rules: [AppMatchRule(identifier: 'Code.exe')],
  asrLanguage: 'en',
);
const _manualOnly = AppProfile(id: 'notes', name: 'Notizen');
const _profiles = [_mail, _code, _manualOnly];

AppTargetEvidence _app(String identifier, {String? teamId}) =>
    AppTargetEvidence(identifiers: [identifier], teamId: teamId);

ResolvedAppProfile _auto(
  List<AppProfile> profiles,
  AppTargetEvidence? target,
) => resolveAppProfile(
  choice: const ProfileChoiceAutomatic(),
  profiles: profiles,
  target: target,
);

void main() {
  group('name matching (DEV-237)', () {
    test('matches a bundle id of the frontmost app', () {
      final result = _auto(_profiles, _app('com.apple.mail'));
      expect(result.profile, _mail);
      expect(result.selection, AppProfileSelection.rule);
    });

    test('"chrome" matches "Chrome.EXE" on both sides', () {
      const chrome = AppProfile(
        id: 'chrome',
        name: 'Chrome',
        rules: [AppMatchRule(identifier: 'chrome')],
      );
      expect(_auto([chrome], _app('Chrome.EXE')).profile, chrome);
      const chromeExe = AppProfile(
        id: 'chrome-exe',
        name: 'Chrome',
        rules: [AppMatchRule(identifier: 'Chrome.EXE')],
      );
      expect(_auto([chromeExe], _app('chrome')).profile, chromeExe);
    });

    test('ignores case and surrounding whitespace', () {
      expect(_auto(_profiles, _app('  code.EXE ')).profile, _code);
    });

    test(
      'an unknown app, a blank name or no target resolves to no profile',
      () {
        expect(_auto(_profiles, _app('org.example.other')).profile, isNull);
        expect(_auto(_profiles, _app('  ')).profile, isNull);
        expect(_auto(_profiles, null).profile, isNull);
        expect(_auto(_profiles, const AppTargetEvidence()).profile, isNull);
      },
    );

    test('a profile without rules never matches automatically', () {
      expect(_auto([_manualOnly], _app('Notizen')).profile, isNull);
    });
  });

  group('Linux WM_CLASS parts (DEV-238)', () {
    const rule = AppProfile(
      id: 'chrome',
      name: 'Chrome',
      rules: [AppMatchRule(identifier: 'Google-chrome')],
    );
    const target = AppTargetEvidence(
      identifiers: ['google-chrome', 'Google-chrome'],
    );

    test('a rule matches the class part', () {
      expect(_auto([rule], target).profile, rule);
    });

    test('a rule matches the instance part', () {
      const instanceRule = AppProfile(
        id: 'chrome-instance',
        name: 'Chrome',
        rules: [AppMatchRule(identifier: 'google-chrome')],
      );
      expect(_auto([instanceRule], target).profile, instanceRule);
    });

    test('neither part matching resolves to no profile', () {
      const other = AppProfile(
        id: 'other',
        name: 'Anderes',
        rules: [AppMatchRule(identifier: 'firefox')],
      );
      expect(_auto([other], target).profile, isNull);
    });
  });

  group('deterministic order (DEV-239)', () {
    test('two profiles claiming the same key: the earlier one wins', () {
      const first = AppProfile(
        id: 'first',
        name: 'Erstes',
        rules: [AppMatchRule(identifier: 'com.apple.mail')],
      );
      const second = AppProfile(
        id: 'second',
        name: 'Zweites',
        rules: [AppMatchRule(identifier: 'com.apple.mail')],
      );
      expect(_auto([first, second], _app('com.apple.mail')).profile, first);
      expect(_auto([second, first], _app('com.apple.mail')).profile, second);
    });

    test(
      'duplicate keys are reported within a profile and across profiles',
      () {
        const repeated = AppProfile(
          id: 'a',
          name: 'A',
          rules: [
            AppMatchRule(identifier: 'mail'),
            AppMatchRule(identifier: 'MAIL.exe'),
          ],
        );
        expect(duplicateMatchKeys(repeated, const [repeated]), {'mail'});

        const clash = AppProfile(
          id: 'b',
          name: 'B',
          rules: [AppMatchRule(identifier: 'mail')],
        );
        expect(duplicateMatchKeys(clash, const [repeated, clash]), {'mail'});
        expect(duplicateMatchKeys(_mail, const [_mail, _code]), isEmpty);
      },
    );
  });

  group('precedence', () {
    test('a manual profile beats a matching rule', () {
      final result = resolveAppProfile(
        choice: const ProfileChoiceProfile('code'),
        profiles: _profiles,
        target: _app('com.apple.mail'),
      );
      expect(result.profile, _code);
      expect(result.selection, AppProfileSelection.manual);
    });

    test('a manual profile applies with no detected app', () {
      final result = resolveAppProfile(
        choice: const ProfileChoiceProfile('notes'),
        profiles: _profiles,
        target: null,
      );
      expect(result.profile, _manualOnly);
    });

    test('"no profile" beats a matching rule', () {
      final result = resolveAppProfile(
        choice: const ProfileChoiceNone(),
        profiles: _profiles,
        target: _app('com.apple.mail'),
      );
      expect(result.profile, isNull);
      expect(result.selection, AppProfileSelection.none);
    });

    test('a stale manual id falls back to the automatic rules', () {
      final result = resolveAppProfile(
        choice: const ProfileChoiceProfile('deleted-profile'),
        profiles: _profiles,
        target: _app('com.apple.mail'),
      );
      expect(result.profile, _mail);
      expect(result.selection, AppProfileSelection.rule);
    });
  });

  group('stored values (DEV-240)', () {
    test('every smart mode value round-trips through its storage value', () {
      for (final mode in AppProfileSmartMode.values) {
        expect(AppProfileSmartMode.fromStorage(mode.storageValue), mode);
      }
    });

    test(
      'every context source value round-trips through its storage value',
      () {
        for (final source in AppProfileContextSource.values) {
          expect(
            AppProfileContextSource.fromStorage(source.storageValue),
            source,
          );
        }
      },
    );

    test('unknown or missing smart mode becomes standard, never off', () {
      expect(
        AppProfileSmartMode.fromStorage(null),
        AppProfileSmartMode.standard,
      );
      expect(AppProfileSmartMode.fromStorage(''), AppProfileSmartMode.standard);
      expect(
        AppProfileSmartMode.fromStorage('bogus'),
        AppProfileSmartMode.standard,
      );
    });

    test('unknown or missing context source becomes none', () {
      expect(
        AppProfileContextSource.fromStorage(null),
        AppProfileContextSource.none,
      );
      expect(
        AppProfileContextSource.fromStorage('everything'),
        AppProfileContextSource.none,
      );
    });

    test('the smart mode choices map onto their presets', () {
      expect(AppProfileSmartMode.standard.preset, isNull);
      expect(AppProfileSmartMode.off.preset?.name, 'off');
      expect(AppProfileSmartMode.translate.preset?.name, 'translate');
    });
  });

  group('context plan (GS-067, GS-072, BIZ consent)', () {
    final given = DateTime.utc(2026, 10, 18, 9);

    AppProfileConsent consentFor({
      String provider = 'openai',
      bool selection = true,
      bool clipboard = true,
      String version = kAppProfileConsentTextVersion,
    }) => AppProfileConsent(
      providerId: provider,
      selectionCovered: selection,
      clipboardCovered: clipboard,
      textVersion: version,
      givenAtUtc: given,
    );

    /// Profile with one rule per [rules] entry (identifier, teamId).
    AppProfile profileWith(
      AppProfileContextSource source, {
      AppProfileConsent? consent,
      List<AppMatchRule> rules = const [AppMatchRule(identifier: 'app')],
    }) => AppProfile(
      id: 'p',
      name: 'P',
      rules: rules,
      contextSource: source,
      consent: consent,
    );

    ResolvedAppProfile resolvedFor(String identifier, AppProfile profile) =>
        resolveAppProfile(
          choice: const ProfileChoiceAutomatic(),
          profiles: [profile],
          target: AppTargetEvidence(identifiers: [identifier]),
        );

    ContextPlan plan(
      AppProfile profile, {
      bool local = false,
      String provider = 'openai',
      AppTargetEvidence? target,
      bool isMacOS = false,
      String? identifier,
    }) => planContext(
      resolved: identifier == null
          ? ResolvedAppProfile(profile, AppProfileSelection.manual)
          : resolvedFor(identifier, profile),
      providerIsLocal: local,
      providerId: provider,
      target: target,
      isMacOS: isMacOS,
    );

    test('no profile or source none reads nothing', () {
      final none = planContext(
        resolved: const ResolvedAppProfile.none(),
        providerIsLocal: true,
        providerId: 'local',
        target: null,
        isMacOS: false,
      );
      expect(none.readsContext, isFalse);
      expect(
        plan(
          profileWith(AppProfileContextSource.none),
          local: true,
        ).readsContext,
        isFalse,
      );
    });

    test('a cloud provider without consent sends no context', () {
      for (final source in [
        AppProfileContextSource.selection,
        AppProfileContextSource.clipboard,
      ]) {
        final result = plan(
          profileWith(source),
          target: const AppTargetEvidence(identifiers: ['app'], teamId: 'T'),
          isMacOS: true,
        );
        expect(result.readsContext, isFalse, reason: source.name);
        expect(result.blockedBy, ContextBlockReason.consentMissing);
      }
    });

    test('cloud with a matching consent may use the source', () {
      final result = plan(
        profileWith(AppProfileContextSource.selection, consent: consentFor()),
      );
      expect(result.source, AppProfileContextSource.selection);
    });

    test('a local provider uses context without any consent', () {
      final result = plan(
        profileWith(AppProfileContextSource.selection),
        local: true,
      );
      expect(result.source, AppProfileContextSource.selection);
    });

    test('consent lapses when the provider changes', () {
      final result = plan(
        profileWith(
          AppProfileContextSource.selection,
          consent: consentFor(provider: 'openai'),
        ),
        provider: 'other-cloud',
      );
      expect(result.blockedBy, ContextBlockReason.consentMissing);
    });

    test('consent lapses when the text version changes', () {
      final result = plan(
        profileWith(
          AppProfileContextSource.selection,
          consent: consentFor(version: 'v0-old'),
        ),
      );
      expect(result.blockedBy, ContextBlockReason.consentMissing);
    });

    test(
      'consent is per source: selection consent does not cover clipboard',
      () {
        final result = plan(
          profileWith(
            AppProfileContextSource.clipboard,
            consent: consentFor(selection: true, clipboard: false),
          ),
          target: const AppTargetEvidence(identifiers: ['app']),
        );
        expect(result.readsContext, isFalse);
        expect(result.blockedBy, ContextBlockReason.consentMissing);
      },
    );

    test('macOS clipboard uses the matched rule only (GS-072)', () {
      // Rule A: bundle a, team X. Rule B: bundle b, team Y.
      const profile = AppProfile(
        id: 'p',
        name: 'P',
        rules: [
          AppMatchRule(identifier: 'com.example.a', teamId: 'X'),
          AppMatchRule(identifier: 'com.example.b', teamId: 'Y'),
        ],
        contextSource: AppProfileContextSource.clipboard,
      );
      // Bundle b comes from rule B (team Y); the target claims team X.
      // Team X belongs to rule A, so this must fail.
      final spoofed = plan(
        profile,
        local: true,
        identifier: 'com.example.b',
        target: const AppTargetEvidence(
          identifiers: ['com.example.b'],
          teamId: 'X',
        ),
        isMacOS: true,
      );
      expect(spoofed.readsContext, isFalse);
      expect(spoofed.blockedBy, ContextBlockReason.bindingMismatch);

      final genuine = plan(
        profile,
        local: true,
        identifier: 'com.example.b',
        target: const AppTargetEvidence(
          identifiers: ['com.example.b'],
          teamId: 'Y',
        ),
        isMacOS: true,
      );
      expect(genuine.source, AppProfileContextSource.clipboard);
    });

    test(
      'macOS clipboard: a matched rule without team id blocks clipboard',
      () {
        final result = plan(
          profileWith(AppProfileContextSource.clipboard),
          local: true,
          identifier: 'app',
          target: const AppTargetEvidence(identifiers: ['app'], teamId: 'T'),
          isMacOS: true,
        );
        expect(result.blockedBy, ContextBlockReason.bindingUnavailable);
      },
    );

    test('macOS clipboard: the target reports no team id, no context', () {
      final result = plan(
        profileWith(
          AppProfileContextSource.clipboard,
          rules: const [AppMatchRule(identifier: 'app', teamId: 'T')],
        ),
        local: true,
        identifier: 'app',
        target: const AppTargetEvidence(identifiers: ['app']),
        isMacOS: true,
      );
      expect(result.blockedBy, ContextBlockReason.bindingUnavailable);
    });

    test('Windows and Linux clipboard: the name match is enough', () {
      final result = plan(
        profileWith(AppProfileContextSource.clipboard),
        local: true,
        identifier: 'app',
        target: const AppTargetEvidence(identifiers: ['app']),
        isMacOS: false,
      );
      expect(result.source, AppProfileContextSource.clipboard);
    });
  });

  group('consent text', () {
    test('the canonical v1 text is pinned (change = bump the version)', () {
      expect(kAppProfileConsentTextVersion, 'v1');
      expect(
        appProfileConsentTextHash(kAppProfileConsentCanonicalText),
        kAppProfileConsentTextV1Hash,
      );
    });
  });

  group('per-profile dictation language (SW-07)', () {
    test('a matched profile hands its asrLanguage through unchanged', () {
      final resolved = _auto(_profiles, _app('Code.exe'));
      expect(resolved.profile?.id, 'code');
      expect(resolved.profile?.asrLanguage, 'en');
    });

    test('a profile without asrLanguage keeps the configured language', () {
      final resolved = _auto(_profiles, _app('com.apple.mail'));
      expect(resolved.profile?.id, 'mail');
      expect(resolved.profile?.asrLanguage, isNull);
    });
  });
}
