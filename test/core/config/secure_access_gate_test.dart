import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:whispaste/core/config/secure_access_gate.dart';
import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/services/feedback_consent_store.dart';

// Hand-over "start → no key-store read that could prompt before the
// explanation" (#1161): while the gate is closed only the quiet reader is
// asked; the plugin (which may prompt) is called only after allowPrompts.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pluginChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  final pluginReads = <String>[];
  final quietReads = <String>[];
  late Map<String, QuietReadResult> quietAnswers;
  late SecureAccessGate gate;

  SecureKeyStore newStore() => SecureKeyStore(
    null,
    () async => KeyringAvailability.usable,
    null,
    (key) async {
      quietReads.add(key);
      return quietAnswers[key] ??
          const QuietReadResult(QuietReadStatus.missing);
    },
    gate,
  );

  setUp(() {
    pluginReads.clear();
    quietReads.clear();
    quietAnswers = {};
    gate = SecureAccessGate();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pluginChannel, (call) async {
          if (call.method == 'read') {
            pluginReads.add((call.arguments as Map)['key'] as String);
            return 'from-plugin';
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pluginChannel, null);
  });

  group('closed gate', () {
    test('reads quietly and never calls the prompting plugin', () async {
      quietAnswers['wp_data_key'] = const QuietReadResult(
        QuietReadStatus.ok,
        value: 'v',
      );
      final store = newStore();

      expect(await store.readKey('wp_data_key'), 'v');
      expect(await store.readKey('wp_automation_api_token'), isNull);
      expect(quietReads, ['wp_data_key', 'wp_automation_api_token']);
      expect(pluginReads, isEmpty);
    });

    test('holds an item back with SecretNeedsConsent naming it', () async {
      quietAnswers['wp_feedback_consent_state'] = const QuietReadResult(
        QuietReadStatus.needsConsent,
        code: -25293,
      );
      final store = newStore();

      await expectLater(
        withSecureTrigger(
          'test start',
          () => store.readKey('wp_feedback_consent_state'),
        ),
        throwsA(
          predicate<Object>(
            (e) =>
                isSecretNeedsConsent(e) &&
                (e as PlatformException).details == 'wp_feedback_consent_state',
          ),
        ),
      );
      expect(pluginReads, isEmpty);
    });

    test('readAllApiKeys skips held-back keys instead of failing', () async {
      final mapping = apiKeyMapping.values.toList();
      quietAnswers[mapping.first] = const QuietReadResult(
        QuietReadStatus.needsConsent,
      );
      quietAnswers[mapping.last] = const QuietReadResult(
        QuietReadStatus.ok,
        value: 'k',
      );
      final store = newStore();

      expect(await store.readAllApiKeys(), {mapping.last: 'k'});
      expect(pluginReads, isEmpty);
    });
  });

  group('open gate', () {
    test('reads through the plugin after allowPrompts', () async {
      final store = newStore();
      gate.allowPrompts('test');

      expect(await store.readKey('wp_data_key'), 'from-plugin');
      expect(quietReads, isEmpty);
      expect(pluginReads, ['wp_data_key']);
    });

    test('tells every listener once, removed ones never', () {
      var first = 0;
      var removed = 0;
      gate.addOpenListener(() => first++);
      final remove = gate.addOpenListener(() => removed++);
      remove();

      gate.allowPrompts('a');
      gate.allowPrompts('b');

      expect(gate.promptsAllowed, isTrue);
      expect(first, 1);
      expect(removed, 0);
    });
  });

  test('retryHeldBack re-tells listeners only after the gate opened', () {
    var calls = 0;
    gate.addOpenListener(() => calls++);

    gate.retryHeldBack('closed');
    expect(calls, 0);

    gate.allowPrompts('first');
    gate.retryHeldBack('after unlock');
    expect(calls, 2);
  });

  test('withSecureTrigger names the caller inside its zone only', () async {
    expect(currentSecureTrigger(), 'unspecified');
    expect(
      await withSecureTrigger('x', () async => currentSecureTrigger()),
      'x',
    );
  });

  group('mayHavePendingWithdrawal', () {
    Future<SharedPreferences> prefs(Map<String, Object> values) async {
      SharedPreferences.setMockInitialValues(values);
      return SharedPreferences.getInstance();
    }

    test('false without any feedback state, so start reads nothing', () async {
      expect(mayHavePendingWithdrawal(await prefs({})), isFalse);
    });

    test('false for a mirror without an open withdrawal', () async {
      final mirror = jsonEncode([
        const ConsentReference(hash: 'h').toJson(),
        const ConsentReference(
          hash: 'f',
          withdrawn: true,
          failed: true,
        ).toJson(),
      ]);
      expect(
        mayHavePendingWithdrawal(await prefs({kConsentMirrorKey: mirror})),
        isFalse,
      );
    });

    test('true for an open withdrawal or unreadable mirror', () async {
      final mirror = jsonEncode([
        const ConsentReference(hash: 'h', withdrawn: true).toJson(),
      ]);
      expect(
        mayHavePendingWithdrawal(await prefs({kConsentMirrorKey: mirror})),
        isTrue,
      );
      expect(
        mayHavePendingWithdrawal(await prefs({kConsentMirrorKey: '{'})),
        isTrue,
      );
      expect(
        mayHavePendingWithdrawal(await prefs({kConsentStateKey: '{}'})),
        isTrue,
      );
    });
  });
}
