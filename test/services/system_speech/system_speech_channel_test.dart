/// Channel contract of the system speech engine: the arguments sent to the
/// native host and the mapping of its answers. The host itself runs only on
/// macOS, so the tests answer its calls with a fake handler.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/system_speech/system_speech_channel.dart';

const _channelName = 'whispaste/system_speech';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late SystemSpeechChannel channel;
  final calls = <MethodCall>[];

  void answer(Future<Object?> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(const MethodChannel(_channelName), (
      call,
    ) async {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(() {
    calls.clear();
    channel = SystemSpeechChannel();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(const MethodChannel(_channelName), null);
  });

  group('systemSpeechOsSupported', () {
    test('needs macOS 26 or later', () {
      expect(
        systemSpeechOsSupported(osVersion: 'Version 27.2 (Build x)'),
        isTrue,
      );
      expect(systemSpeechOsSupported(osVersion: 'Version 26.0'), isTrue);
      expect(systemSpeechOsSupported(osVersion: 'Version 15.7.1'), isFalse);
      expect(systemSpeechOsSupported(osVersion: 'unknown'), isFalse);
    });
  });

  group('systemSpeechLocaleFor', () {
    test('an automatic language has no locale, never the system one', () {
      expect(systemSpeechLocaleFor('auto'), isNull);
      expect(systemSpeechLocaleFor(null), isNull);
      expect(systemSpeechLocaleFor(' '), isNull);
      expect(systemSpeechLocaleFor('de'), 'de');
    });
  });

  test('fallback causes: language codes are calm, the rest is a failure', () {
    expect(
      systemSpeechFallbackFor('LOCALE_UNSUPPORTED'),
      SystemSpeechFallback.languageUnsupported,
    );
    expect(
      systemSpeechFallbackFor('LOCALE_AUTO'),
      SystemSpeechFallback.languageUnsupported,
    );
    expect(systemSpeechFallbackFor('TIMEOUT'), SystemSpeechFallback.failure);
    expect(
      systemSpeechFallbackFor('ASSET_MISSING'),
      SystemSpeechFallback.failure,
    );
  });

  test('the Dart time limit lies past the native one', () {
    final wav = List<int>.filled(44, 0);
    expect(
      systemSpeechDartTimeLimit(wav),
      systemSpeechTimeLimit(wav) + kSystemSpeechDartTimeMargin,
    );
  });

  test('capability maps the native answer', () async {
    answer(
      (_) async => {
        'osSupported': true,
        'localeSupported': 'de_DE',
        'installed': false,
      },
    );

    final cap = await channel.capability('de');

    expect(calls.single.method, 'capability');
    expect(calls.single.arguments, {'locale': 'de'});
    expect(cap.osSupported, isTrue);
    expect(cap.localeSupported, 'de_DE');
    expect(cap.installed, isFalse);
  });

  test('a missing native host reads as unavailable', () async {
    // No handler registered: the channel reports the engine as unavailable.
    final cap = await channel.capability('de');

    expect(cap.osSupported, isFalse);
    expect(cap.installed, isFalse);
  });

  test('transcribe sends the path and locale and returns the text', () async {
    answer((_) async => 'Hallo Welt');

    final text = await channel.transcribe(path: '/tmp/a.wav', locale: 'de');

    expect(text, 'Hallo Welt');
    expect(calls.single.method, 'transcribe');
    expect(calls.single.arguments, {
      'path': '/tmp/a.wav',
      'locale': 'de',
      'terms': <String>[],
    });
  });

  test('a native error keeps its code', () async {
    answer((_) async {
      throw PlatformException(code: 'ASSET_MISSING', message: 'not installed');
    });

    expect(
      () => channel.transcribe(path: '/tmp/a.wav', locale: 'de'),
      throwsA(
        isA<SystemSpeechException>().having(
          (e) => e.code,
          'code',
          'ASSET_MISSING',
        ),
      ),
    );
  });

  test('installProgress maps state and fraction', () async {
    answer((_) async => {'state': 'installing', 'fraction': 0.25});

    final progress = await channel.installProgress();

    expect(progress.state, 'installing');
    expect(progress.fraction, 0.25);
  });
}
