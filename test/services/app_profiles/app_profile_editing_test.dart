import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/services/app_profiles/app_profile.dart';
import 'package:whispaste/services/app_profiles/app_profile_editing.dart';
import 'package:whispaste/services/app_profiles/profile_activation.dart';
import 'package:whispaste/services/hotkey_conflicts.dart';

const _mail = AppProfile(
  id: 'mail',
  name: 'Mail',
  rules: [AppMatchRule(identifier: 'com.apple.mail')],
  hotkeyKey: 'F5',
  hotkeyModifiers: 'ctrl+shift',
);
const _notes = AppProfile(
  id: 'notes',
  name: 'Notizen',
  rules: [AppMatchRule(identifier: 'notes.exe')],
);

void main() {
  group('limit and order', () {
    test('nine profiles are the most', () {
      final eight = [
        for (var i = 0; i < 8; i++) AppProfile(id: 'p$i', name: 'P$i'),
      ];
      expect(canAddAppProfile(eight), isTrue);
      final nine = [...eight, const AppProfile(id: 'p8', name: 'P8')];
      expect(canAddAppProfile(nine), isFalse);
      expect(kMaxAppProfiles, 9);
    });

    test('a new id is unique per instant and non-empty', () {
      final a = newAppProfileId(DateTime(2026, 10, 19, 12));
      final b = newAppProfileId(DateTime(2026, 10, 19, 12, 0, 0, 1));
      expect(a, isNotEmpty);
      expect(a, isNot(b));
    });

    test('moving up and down swaps neighbours', () {
      const list = [_mail, _notes];
      expect(movedAppProfileIds(list, 'notes', -1), ['notes', 'mail']);
      expect(movedAppProfileIds(list, 'mail', 1), ['notes', 'mail']);
    });

    test('moving past an end or an unknown id keeps the order', () {
      const list = [_mail, _notes];
      expect(movedAppProfileIds(list, 'mail', -1), ['mail', 'notes']);
      expect(movedAppProfileIds(list, 'notes', 1), ['mail', 'notes']);
      expect(movedAppProfileIds(list, 'gone', 1), ['mail', 'notes']);
    });
  });

  test('a blank name is refused, a name is trimmed', () {
    expect(cleanAppProfileName('   '), isNull);
    expect(cleanAppProfileName('  Mail  '), 'Mail');
  });

  group('app rules', () {
    test('a free identifier is accepted', () {
      expect(
        appRuleClashName(
          identifier: 'org.example.app',
          profile: _notes,
          profiles: const [_mail, _notes],
        ),
        isNull,
      );
    });

    test('an identifier another profile claims names that profile', () {
      expect(
        appRuleClashName(
          identifier: 'COM.APPLE.MAIL',
          profile: _notes,
          profiles: const [_mail, _notes],
        ),
        'Mail',
      );
    });

    test('a ".exe" suffix counts as the same app', () {
      expect(
        appRuleClashName(
          identifier: 'Notes',
          profile: _mail,
          profiles: const [_mail, _notes],
        ),
        'Notizen',
      );
    });
  });

  group('hotkey conflicts', () {
    const appBindings = [
      HotkeyBinding(
        actionId: 'global',
        actionLabel: 'Diktat',
        key: 'D',
        modifiers: 'ctrl+alt',
      ),
    ];

    test('a free combination has no conflict', () {
      expect(
        profileHotkeyConflict(
          key: 'F6',
          modifiers: 'ctrl+shift',
          profileId: 'notes',
          profiles: const [_mail, _notes],
          appBindings: appBindings,
        ),
        isNull,
      );
    });

    test('an app hotkey is named as the conflict', () {
      final hit = profileHotkeyConflict(
        key: 'D',
        modifiers: 'ctrl+alt',
        profileId: 'notes',
        profiles: const [_mail, _notes],
        appBindings: appBindings,
      );
      expect(hit, isA<ProfileHotkeyTakenByApp>());
      expect((hit! as ProfileHotkeyTakenByApp).actionLabel, 'Diktat');
    });

    test('another profile holds it in either direction', () {
      final fromNotes = profileHotkeyConflict(
        key: 'F5',
        modifiers: 'shift+ctrl',
        profileId: 'notes',
        profiles: const [_mail, _notes],
        appBindings: appBindings,
      );
      expect((fromNotes! as ProfileHotkeyTakenByProfile).profileName, 'Mail');
      // Mail comes first in the list, yet the check also covers later ones.
      final fromMail = profileHotkeyConflict(
        key: 'F5',
        modifiers: 'ctrl+shift',
        profileId: 'mail',
        profiles: const [
          _mail,
          AppProfile(
            id: 'x',
            name: 'X',
            hotkeyKey: 'F5',
            hotkeyModifiers: 'ctrl+shift',
          ),
        ],
        appBindings: const [],
      );
      expect((fromMail! as ProfileHotkeyTakenByProfile).profileName, 'X');
    });

    test('onlyEarlier explains a stored refusal like the planner', () {
      const later = AppProfile(
        id: 'later',
        name: 'Später',
        hotkeyKey: 'F5',
        hotkeyModifiers: 'ctrl+shift',
      );
      // The first profile keeps the combination: no conflict for it.
      expect(
        profileHotkeyConflict(
          key: 'F5',
          modifiers: 'ctrl+shift',
          profileId: 'mail',
          profiles: const [_mail, later],
          appBindings: const [],
          onlyEarlier: true,
        ),
        isNull,
      );
      // The later one is the one refused.
      expect(
        (profileHotkeyConflict(
                  key: 'F5',
                  modifiers: 'ctrl+shift',
                  profileId: 'later',
                  profiles: const [_mail, later],
                  appBindings: const [],
                  onlyEarlier: true,
                )!
                as ProfileHotkeyTakenByProfile)
            .profileName,
        'Mail',
      );
    });

    test('a combination without a modifier is refused', () {
      expect(
        profileHotkeyConflict(
          key: 'F6',
          modifiers: '',
          profileId: 'notes',
          profiles: const [_mail, _notes],
          appBindings: const [],
        ),
        isA<ProfileHotkeyNeedsModifier>(),
      );
    });
  });

  group('copyWith', () {
    test('null clears a nullable field, leaving it out keeps it', () {
      final cleared = _mail.copyWith(hotkeyKey: null, hotkeyModifiers: null);
      expect(cleared.hasHotkey, isFalse);
      expect(cleared.hotkeyModifiers, isNull);
      final kept = _mail.copyWith(name: 'Post');
      expect(kept.name, 'Post');
      expect(kept.hotkeyKey, 'F5');
      expect(kept.id, 'mail');
    });
  });

  group('speech model choice', () {
    final base = AppSettings.defaults;

    test('a whisper choice sets the model of the dock format', () {
      final out = settingsWithProfile(
        base,
        const AppProfile(id: 'm', name: 'M', modelId: 'whisper:whisper-small'),
      );
      expect(out.stt.model, 'whisper-small');
      expect(
        profileStillApplies(
          const AppProfile(
            id: 'm',
            name: 'M',
            modelId: 'whisper:whisper-small',
          ),
          out,
        ),
        isTrue,
      );
    });

    test('a changed model ends the profile marker', () {
      const profile = AppProfile(
        id: 'm',
        name: 'M',
        modelId: 'whisper:whisper-small',
      );
      final applied = settingsWithProfile(base, profile);
      final changed = settingsWithProfile(
        applied,
        const AppProfile(
          id: 'other',
          name: 'O',
          modelId: 'whisper:whisper-tiny',
        ),
      );
      expect(profileStillApplies(profile, changed), isFalse);
    });
  });
}
