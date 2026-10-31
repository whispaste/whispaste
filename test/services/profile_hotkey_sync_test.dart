import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/services/app_profiles/app_profile.dart';
import 'package:whispaste/services/hotkey_key_resolver.dart';
import 'package:whispaste/services/hotkey_service.dart';
import 'package:whispaste/services/keyboard_up_monitor.dart';
import 'package:whispaste/services/profile_hotkey_plan.dart';

import 'hotkey_service_test.dart' show FakeHotKeyRegistrar;

class _Settings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async =>
      AppSettings.defaults.copyWith(hotkeyEnabled: false);
}

AppProfile _profile(String id, {String? key, String? mods}) =>
    AppProfile(id: id, name: id, hotkeyKey: key, hotkeyModifiers: mods);

ProfileHotkeyEntry _entry(String id, String key, String mods) =>
    ProfileHotkeyEntry(profileId: id, key: key, modifiers: mods);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('planProfileHotkeys', () {
    test('keeps a free combination', () {
      final plan = planProfileHotkeys(
        profiles: [_profile('a', key: 'F5', mods: 'ctrl+shift')],
        reserved: const [],
      );
      expect(plan.entries.map((e) => e.profileId), ['a']);
      expect(plan.refusedIds, isEmpty);
    });

    test('refuses a combination an app hotkey already holds', () {
      final plan = planProfileHotkeys(
        profiles: [_profile('a', key: 'L', mods: 'ctrl+shift')],
        reserved: const [(key: 'L', modifiers: 'ctrl+shift')],
      );
      expect(plan.entries, isEmpty);
      expect(plan.refusedIds, {'a'});
    });

    test('compares modifiers regardless of their order and case', () {
      final plan = planProfileHotkeys(
        profiles: [_profile('a', key: 'l', mods: 'Shift+Ctrl')],
        reserved: const [(key: 'L', modifiers: 'ctrl+shift')],
      );
      expect(plan.refusedIds, {'a'});
    });

    test('the first profile wins a duplicate, the later one is refused', () {
      final plan = planProfileHotkeys(
        profiles: [
          _profile('first', key: 'F5', mods: 'ctrl+alt'),
          _profile('second', key: 'F5', mods: 'alt+ctrl'),
        ],
        reserved: const [],
      );
      expect(plan.entries.map((e) => e.profileId), ['first']);
      expect(plan.refusedIds, {'second'});
    });

    test('a hotkey without a modifier is refused', () {
      final plan = planProfileHotkeys(
        profiles: [_profile('a', key: 'F5', mods: '')],
        reserved: const [],
      );
      expect(plan.entries, isEmpty);
      expect(plan.refusedIds, {'a'});
    });

    test('a profile without a hotkey is neither registered nor refused', () {
      final plan = planProfileHotkeys(
        profiles: [_profile('a')],
        reserved: const [],
      );
      expect(plan.entries, isEmpty);
      expect(plan.refusedIds, isEmpty);
    });
  });

  group('HotkeyService profile hotkeys', () {
    late FakeHotKeyRegistrar registrar;
    late ProviderContainer container;
    late HotkeyService service;

    setUp(() async {
      registrar = FakeHotKeyRegistrar();
      container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(_Settings.new),
          hotkeyServiceProvider.overrideWith(() {
            final s = HotkeyService()..injectRegistrar(registrar);
            return s..injectMonitor(NoopKeyboardUpMonitor());
          }),
        ],
      );
      addTearDown(container.dispose);
      container.read(hotkeyServiceProvider);
      await container.read(settingsProvider.future);
      service = container.read(hotkeyServiceProvider.notifier);
    });

    test(
      'registers each entry once and a repeated sync adds nothing',
      () async {
        await service.syncProfileHotkeys([
          _entry('a', 'F5', 'ctrl+alt'),
          _entry('b', 'F6', 'ctrl+alt'),
        ]);
        final afterFirst = registrar.registered.length;
        await service.syncProfileHotkeys([
          _entry('a', 'F5', 'ctrl+alt'),
          _entry('b', 'F6', 'ctrl+alt'),
        ]);
        expect(registrar.registered.length, afterFirst);
        expect(registrar.unregistered, isEmpty);
      },
    );

    test('a changed combination is unregistered and registered anew', () async {
      await service.syncProfileHotkeys([_entry('a', 'F5', 'ctrl+alt')]);
      await service.syncProfileHotkeys([_entry('a', 'F7', 'ctrl+alt')]);
      expect(
        registrar.unregistered.single.logicalKey.keyId,
        resolveKey('F5').keyId,
      );
      expect(registrar.registered.map((h) => h.logicalKey.keyId), [
        resolveKey('F7').keyId,
      ]);
    });

    test(
      'a removed profile is unregistered and leaves no state behind',
      () async {
        await service.syncProfileHotkeys([_entry('a', 'F5', 'ctrl+alt')]);
        await service.syncProfileHotkeys(const []);
        expect(registrar.registered, isEmpty);
        expect(registrar.unregistered, hasLength(1));
        // A later sync registers it again as a fresh entry, not as a duplicate.
        await service.syncProfileHotkeys([_entry('a', 'F5', 'ctrl+alt')]);
        expect(registrar.registered, hasLength(1));
      },
    );

    test(
      'a refused registration is reported and nothing is left registered',
      () async {
        registrar.throwOnFirstRegister = StateError('taken by another app');
        final refused = await service.syncProfileHotkeys([
          _entry('a', 'F5', 'ctrl+alt'),
        ]);
        expect(refused, {'a'});
        expect(registrar.registered, isEmpty);
      },
    );

    test('pressing a profile hotkey reports its profile id', () async {
      final pressed = <String>[];
      service.onProfileHotkeyPressed = pressed.add;
      await service.syncProfileHotkeys([_entry('schnell', 'F5', 'ctrl+alt')]);

      registrar.capturedKeyDownHandler!(
        HotKey(key: resolveKey('F5'), modifiers: resolveModifiers('ctrl+alt')),
      );
      expect(pressed, ['schnell']);
    });
  });
}
