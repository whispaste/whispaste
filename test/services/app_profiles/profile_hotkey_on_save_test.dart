import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/services/app_profiles/app_profile.dart';
import 'package:whispaste/services/app_profiles/app_profile_repository.dart';
import 'package:whispaste/services/app_profiles/profile_hotkey_sync.dart';
import 'package:whispaste/services/hotkey_key_resolver.dart';
import 'package:whispaste/services/hotkey_service.dart';
import 'package:whispaste/services/keyboard_up_monitor.dart';

import '../../fixtures/fake_app_profiles.dart';
import '../hotkey_service_test.dart' show FakeHotKeyRegistrar;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'saving a profile hotkey registers it, removing it unregisters it',
    () async {
      final registrar = FakeHotKeyRegistrar();
      final fake = FakeAppProfiles(const []);
      final container = ProviderContainer(
        overrides: [
          appProfilesProvider.overrideWith(() => fake),
          settingsProvider.overrideWith(FakeSettings.new),
          hotkeyServiceProvider.overrideWith(() {
            final s = HotkeyService()..injectRegistrar(registrar);
            return s..injectMonitor(NoopKeyboardUpMonitor());
          }),
        ],
      );
      addTearDown(container.dispose);
      container.read(profileHotkeySyncProvider);
      await container.read(settingsProvider.future);
      await container.read(appProfilesProvider.future);
      final notifier = container.read(appProfilesProvider.notifier);

      await notifier.save(
        const AppProfile(
          id: 'a',
          name: 'Mail',
          hotkeyKey: 'F5',
          hotkeyModifiers: 'ctrl+shift',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        registrar.registered.map((h) => h.logicalKey.keyId),
        contains(resolveKey('F5').keyId),
      );

      await notifier.save(const AppProfile(id: 'a', name: 'Mail'));
      await Future<void>.delayed(Duration.zero);

      expect(
        registrar.unregistered.map((h) => h.logicalKey.keyId),
        contains(resolveKey('F5').keyId),
      );
    },
  );
}
