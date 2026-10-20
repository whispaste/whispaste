import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/services/app_commands/app_command.dart';
import 'package:whispaste/services/app_commands/tray_choice_commands.dart';
import 'package:whispaste/services/app_profiles/app_profile.dart';
import 'package:whispaste/services/app_profiles/app_profile_choice.dart';
import 'package:whispaste/services/app_profiles/app_profile_resolver.dart';

const _mail = AppProfile(id: 'mail', name: 'Mail');
const _chat = AppProfile(id: 'chat', name: 'Chat');

void main() {
  group('encoding', () {
    test('every choice survives a stored round trip', () {
      for (final choice in <ProfileChoice>[
        const ProfileChoiceAutomatic(),
        const ProfileChoiceNone(),
        const ProfileChoiceProfile('mail'),
      ]) {
        final decoded = decodeProfileChoice(encodeProfileChoice(choice));
        expect(encodeProfileChoice(decoded), encodeProfileChoice(choice));
      }
    });

    test('an unknown or empty stored value means automatic', () {
      expect(decodeProfileChoice(null), isA<ProfileChoiceAutomatic>());
      expect(decodeProfileChoice('garbage'), isA<ProfileChoiceAutomatic>());
      expect(decodeProfileChoice('profile:'), isA<ProfileChoiceAutomatic>());
    });
  });

  group('ProfileChoiceController', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('a repeated pick changes nothing and reports false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(profileChoiceProvider.notifier);

      expect(controller.select(const ProfileChoiceProfile('mail')), isTrue);
      expect(controller.select(const ProfileChoiceProfile('mail')), isFalse);
      expect(
        container.read(profileChoiceProvider),
        isA<ProfileChoiceProfile>(),
      );
    });

    test('the choice is written to the preferences', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(profileChoiceProvider.notifier)
          .select(const ProfileChoiceNone());
      await Future<void>.delayed(Duration.zero);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_profile_choice'), 'none');
    });

    test('the stored choice is restored on the next start', () async {
      SharedPreferences.setMockInitialValues({
        'app_profile_choice': 'profile:chat',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(profileChoiceProvider);
      await Future<void>.delayed(Duration.zero);
      final restored = container.read(profileChoiceProvider);
      expect(restored, isA<ProfileChoiceProfile>());
      expect((restored as ProfileChoiceProfile).profileId, 'chat');
    });
  });

  group('buildProfileCommands', () {
    test('is empty when no profile exists, so the submenu is hidden', () {
      expect(
        buildProfileCommands(
          profiles: const [],
          current: const ProfileChoiceAutomatic(),
        ),
        isEmpty,
      );
    });

    test(
      'lists automatic, none, then the profiles, checking the active one',
      () {
        final commands = buildProfileCommands(
          profiles: const [_mail, _chat],
          current: const ProfileChoiceProfile('chat'),
        );
        expect(
          [for (final c in commands) c.id],
          [
            kTrayProfileAutomaticId,
            kTrayProfileNoneId,
            isA<String>(),
            'profile:mail',
            'profile:chat',
          ],
        );
        final checked = [
          for (final c in commands)
            if (c.checked ?? false) c.id,
        ];
        expect(checked, ['profile:chat']);
      },
    );

    test('a manual "no profile" choice checks the none entry only', () {
      final commands = buildProfileCommands(
        profiles: const [_mail],
        current: const ProfileChoiceNone(),
      );
      final checked = [
        for (final c in flattenAppCommands(commands))
          if (c.checked ?? false) c.id,
      ];
      expect(checked, [kTrayProfileNoneId]);
    });
  });
}
