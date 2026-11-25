/// Extra dictation keys (#2055): the resolution key → language/Smart Mode,
/// the registration plan, the stored form, and the hand-over in the hotkey
/// service (press, release, and an untouched main path without extra keys).
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/extra_dictation_keys.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/services/dictation_key_plan.dart';
import 'package:whispaste/services/hotkey_key_resolver.dart';
import 'package:whispaste/services/hotkey_service.dart';
import 'package:whispaste/services/profile_hotkey_plan.dart';
import 'package:whispaste/services/smart_mode/smart_mode_presets.dart';

import 'hotkey_service_test.dart'
    show FakeHotKeyRegistrar, FakeKeyboardUpMonitor;

ExtraDictationKey _key(
  String id, {
  String key = 'E',
  String modifiers = 'ctrl+alt',
  String language = 'en',
  ExtraDictationKeySmartMode smartMode = ExtraDictationKeySmartMode.standard,
}) => ExtraDictationKey(
  id: id,
  key: key,
  modifiers: modifiers,
  language: language,
  smartMode: smartMode,
);

AppSettings _withKeys(List<ExtraDictationKey> keys) =>
    AppSettings.defaults.copyWithSections(
      hotkey: AppSettings.defaults.hotkey.copyWith(extraDictationKeys: keys),
    );

HotkeyService _service(FakeHotKeyRegistrar registrar, {Object? monitor}) {
  final service = HotkeyService()..injectRegistrar(registrar);
  service.injectMonitor(
    monitor as FakeKeyboardUpMonitor? ??
        FakeKeyboardUpMonitor(supportsKeyUp: false),
  );
  service.injectEnvironment(const {});
  return service;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('resolveDictationKey', () {
    test('forces the key language and follows the standard preset', () {
      final run = resolveDictationKey(_withKeys([_key('k1')]), 'k1');
      expect(run?.language, 'en');
      expect(run?.preset, isNull);
    });

    test('maps each Smart Mode choice to the forced preset', () {
      const expected = {
        ExtraDictationKeySmartMode.standard: null,
        ExtraDictationKeySmartMode.off: SmartModePreset.off,
        ExtraDictationKeySmartMode.cleanup: SmartModePreset.cleanup,
        ExtraDictationKeySmartMode.concise: SmartModePreset.concise,
      };
      for (final entry in expected.entries) {
        final settings = _withKeys([
          _key('k1', language: 'de', smartMode: entry.key),
        ]);
        final run = resolveDictationKey(settings, 'k1');
        expect(run?.language, 'de');
        expect(run?.preset, entry.value, reason: '${entry.key}');
      }
    });

    test('picks the pressed key among several', () {
      final settings = _withKeys([
        _key('k1', key: 'E', language: 'en'),
        _key('k2', key: 'F', language: 'fr'),
      ]);
      expect(resolveDictationKey(settings, 'k2')?.language, 'fr');
    });

    test('a removed key or one without a valid language starts nothing', () {
      expect(resolveDictationKey(_withKeys([_key('k1')]), 'gone'), isNull);
      expect(
        resolveDictationKey(_withKeys([_key('k1', language: 'auto')]), 'k1'),
        isNull,
      );
      expect(
        resolveDictationKey(_withKeys([_key('k1', language: 'xx')]), 'k1'),
        isNull,
      );
    });
  });

  group('planDictationKeys', () {
    test('without extra keys nothing is planned', () {
      final plan = planDictationKeys(
        keys: AppSettings.defaults.hotkey.extraDictationKeys,
        reserved: fixedAppHotkeysOf(AppSettings.defaults),
      );
      expect(plan.entries, isEmpty);
      expect(plan.refusedIds, isEmpty);
    });

    test('keeps a free combination', () {
      final plan = planDictationKeys(keys: [_key('k1')], reserved: const []);
      expect(plan.entries.single.keyId, 'k1');
      expect(plan.entries.single.actionId, 'dictationKey:k1');
    });

    test('refuses the main hotkey combination, a bare key and an unknown '
        'language', () {
      final plan = planDictationKeys(
        keys: [
          _key('main', key: 'D', modifiers: 'shift+ctrl'),
          _key('bare', key: 'F5', modifiers: ''),
          _key('lang', key: 'G', language: 'auto'),
        ],
        reserved: const [(key: 'D', modifiers: 'ctrl+shift')],
      );
      expect(plan.entries, isEmpty);
      expect(plan.refusedIds, {'main', 'bare', 'lang'});
    });

    test('the first key wins a duplicate combination', () {
      final plan = planDictationKeys(
        keys: [
          _key('a', key: 'E', modifiers: 'ctrl+alt'),
          _key('b', key: 'e', modifiers: 'Alt+Ctrl'),
        ],
        reserved: const [],
      );
      expect(plan.entries.map((e) => e.keyId), ['a']);
      expect(plan.refusedIds, {'b'});
    });

    test('a profile cannot take an extra dictation key', () {
      final settings = _withKeys([_key('k1', key: 'E')]);
      expect(
        reservedHotkeysOf(
          settings,
        ).any((r) => r.key == 'E' && r.modifiers == 'ctrl+alt'),
        isTrue,
      );
    });
  });

  group('stored form', () {
    test('defaults to no extra key and stores an empty value', () {
      expect(AppSettings.defaults.hotkey.extraDictationKeys, isEmpty);
      expect(
        AppSettings.defaults.toStorageMap()['hotkey_extra_dictation_keys'],
        '',
      );
    });

    test('round-trips through the settings storage map', () {
      final settings = _withKeys([
        _key('k1', smartMode: ExtraDictationKeySmartMode.cleanup),
        _key('k2', key: 'G', language: 'de'),
      ]);
      final back = AppSettings.fromStorageMap(settings.toStorageMap());
      expect(
        back.hotkey.extraDictationKeys,
        settings.hotkey.extraDictationKeys,
      );
      expect(back.hotkey, settings.hotkey);
    });

    test('a damaged value reads as no extra key', () {
      expect(ExtraDictationKey.listFromJson('{not json'), isEmpty);
      expect(ExtraDictationKey.listFromJson('{"id":"k1"}'), isEmpty);
    });

    test('reads at most three keys, drops broken and duplicate entries', () {
      const raw =
          '[{"id":"a","key":"A","modifiers":"ctrl","language":"en"},'
          '{"id":"a","key":"B","modifiers":"ctrl","language":"de"},'
          '{"id":"x","key":"","language":"de"},'
          '{"id":"b","key":"B","modifiers":"ctrl","language":"de",'
          '"smartMode":"bogus"},'
          '{"id":"c","key":"C","modifiers":"ctrl","language":"fr"},'
          '{"id":"d","key":"D","modifiers":"ctrl","language":"it"}]';
      final keys = ExtraDictationKey.listFromJson(raw);
      expect(keys.map((k) => k.id), ['a', 'b', 'c']);
      expect(keys[1].smartMode, ExtraDictationKeySmartMode.standard);
    });

    test('copyWith keeps at most three keys', () {
      final hotkey = const HotkeySettings().copyWith(
        extraDictationKeys: [
          for (var i = 0; i < 5; i++) _key('k$i', key: 'F${i + 1}'),
        ],
      );
      expect(hotkey.extraDictationKeys, hasLength(kMaxExtraDictationKeys));
    });

    test('nextExtraDictationKeyId picks a free id', () {
      expect(nextExtraDictationKeyId(const []), 'k1');
      expect(nextExtraDictationKeyId([_key('k1'), _key('k3')]), 'k2');
    });
  });

  group('HotkeyService extra dictation keys', () {
    test('without extra keys nothing is registered', () async {
      final registrar = FakeHotKeyRegistrar();
      final service = _service(registrar);
      final refused = await service.syncDictationKeys(const []);
      expect(refused, isEmpty);
      expect(registrar.registered, isEmpty);
    });

    test('a press reaches the key callback with its id, never the main '
        'hotkey', () async {
      final registrar = FakeHotKeyRegistrar();
      final service = _service(registrar);
      final pressed = <String>[];
      var mainPressed = false;
      service.onDictationKeyPressed = pressed.add;
      service.onHotkeyPressed = () => mainPressed = true;
      await service.syncDictationKeys(const [
        DictationKeyEntry(keyId: 'k1', key: 'E', modifiers: 'ctrl+alt'),
      ]);
      registrar.keyDownHandlersByKeyId[resolveKey('E').keyId]!(
        registrar.registered.single,
      );
      expect(pressed, ['k1']);
      expect(mainPressed, isFalse);
    });

    test('macOS registrar: the release reaches the key callback', () async {
      final registrar = FakeHotKeyRegistrar(supportsKeyUp: true);
      final service = _service(registrar);
      final released = <String>[];
      service.onDictationKeyReleased = released.add;
      await service.syncDictationKeys(const [
        DictationKeyEntry(keyId: 'k1', key: 'E', modifiers: 'meta+alt'),
      ]);
      expect(service.dictationKeysSupportKeyUp, isTrue);
      final id = resolveKey('E').keyId;
      registrar.keyDownHandlersByKeyId[id]!(registrar.registered.single);
      registrar.keyUpHandlersByKeyId[id]!(registrar.registered.single);
      expect(released, ['k1']);
    });

    test(
      'Windows/Linux X11 monitor: the release after an extra key press '
      'goes to that key, a later main press takes the monitor back',
      () async {
        final registrar = FakeHotKeyRegistrar();
        final monitor = FakeKeyboardUpMonitor();
        final service = _service(registrar, monitor: monitor);
        await service.updateHotkey(key: LogicalKeyboardKey.keyD);
        final released = <String>[];
        var mainReleased = 0;
        service.onDictationKeyReleased = released.add;
        service.onHotkeyReleased = () => mainReleased++;
        await service.syncDictationKeys(const [
          DictationKeyEntry(keyId: 'k1', key: 'E', modifiers: 'ctrl+alt'),
        ]);
        expect(service.dictationKeysSupportKeyUp, isTrue);

        final extra = registrar.keyDownHandlersByKeyId[resolveKey('E').keyId]!;
        extra(registrar.registered.last);
        await Future<void>.delayed(Duration.zero);
        monitor.emitKeyUp();
        expect(released, ['k1']);
        expect(mainReleased, 0);

        final main =
            registrar.keyDownHandlersByKeyId[LogicalKeyboardKey.keyD.keyId]!;
        main(registrar.registered.first);
        monitor.emitKeyUp();
        expect(released, ['k1']);
        expect(mainReleased, 1);
      },
    );

    test('Wayland: extra keys toggle, the monitor stays with the main '
        'hotkey', () async {
      final registrar = FakeHotKeyRegistrar();
      final monitor = FakeKeyboardUpMonitor();
      final service = _service(registrar, monitor: monitor)
        ..injectEnvironment(const {'XDG_SESSION_TYPE': 'wayland'});
      expect(service.dictationKeysSupportKeyUp, isFalse);
      await service.syncDictationKeys(const [
        DictationKeyEntry(keyId: 'k1', key: 'E', modifiers: 'ctrl+alt'),
      ]);
      registrar.keyDownHandlersByKeyId[resolveKey('E').keyId]!(
        registrar.registered.single,
      );
      expect(monitor.armCount, 0);
    });

    test('an unchanged sync registers nothing again; a removed key is '
        'unregistered', () async {
      final registrar = FakeHotKeyRegistrar();
      final service = _service(registrar);
      const entry = DictationKeyEntry(
        keyId: 'k1',
        key: 'E',
        modifiers: 'ctrl+alt',
      );
      await service.syncDictationKeys(const [entry]);
      await service.syncDictationKeys(const [entry]);
      expect(registrar.registered, hasLength(1));
      expect(registrar.unregistered, isEmpty);
      await service.syncDictationKeys(const []);
      expect(registrar.registered, isEmpty);
      expect(registrar.unregistered, hasLength(1));
    });

    test('a combination the OS refuses is reported', () async {
      final registrar = FakeHotKeyRegistrar()
        ..refuseKey = LogicalKeyboardKey.keyE;
      final service = _service(registrar);
      final refused = await service.syncDictationKeys(const [
        DictationKeyEntry(keyId: 'k1', key: 'E', modifiers: 'ctrl+alt'),
      ]);
      expect(refused, {'k1'});
    });
  });
}
