/// Selection and fallback rules of the system speech transcriber: the chosen
/// language is checked before the run, an automatic language, a missing
/// language or asset, any failure or a timeout hands the same audio to the
/// local engine, each cause is reported, vocabulary goes along, and the
/// temporary WAV file lives in a private folder and is removed.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/system_speech/system_speech_channel.dart';
import 'package:whispaste/core/config/settings_enums.dart'
    show systemSpeechModelId;
import 'package:whispaste/services/system_speech/system_speech_transcriber.dart';
import 'package:whispaste/services/transcription/transcriber_interface.dart';

const _channelName = 'whispaste/system_speech';

class _FakeLocal implements Transcriber {
  int transcribed = 0;
  String? language;

  @override
  Future<void> prepare() async {}

  @override
  Future<String> transcribe(List<int> wavBytes, {String? language}) async {
    transcribed++;
    this.language = language;
    return 'local text';
  }

  @override
  void release() {}
}

/// A WAV header for [seconds] of 16 kHz mono 16-bit audio, so the time limit
/// reads a real length.
List<int> _wav({double seconds = 0}) {
  final data = ByteData(44 + (seconds * 32000).round());
  data.setUint32(24, 16000, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint16(34, 16, Endian.little);
  return data.buffer.asUint8List();
}

/// The native answer for a supported, installed language.
const _ready = {
  'osSupported': true,
  'localeSupported': 'de_DE',
  'installed': true,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory tempDir;
  late _FakeLocal local;
  late int localBuilt;
  late List<SystemSpeechFallback> causes;
  late List<MethodCall> calls;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('system-speech-test');
    local = _FakeLocal();
    localBuilt = 0;
    causes = [];
    calls = [];
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(const MethodChannel(_channelName), null);
    tempDir.deleteSync(recursive: true);
  });

  SystemSpeechTranscriber build({
    String Function()? fallbackModelId,
    List<String> Function()? vocabulary,
    Duration limit = const Duration(seconds: 30),
  }) => SystemSpeechTranscriber(
    channel: SystemSpeechChannel(),
    fallback: () {
      localBuilt++;
      return local;
    },
    tempDirectory: () => tempDir,
    onFallback: causes.add,
    fallbackModelId: fallbackModelId ?? () => 'whisper-small',
    vocabulary: vocabulary ?? () => const [],
    osSupported: () => true,
    timeLimit: (_) => limit,
  );

  /// Answers `capability` with [capability] and `transcribe` with
  /// [transcribe]; every call is recorded.
  void native({
    Map<String, Object?> capability = _ready,
    Future<Object?> Function(MethodCall call)? transcribe,
  }) {
    messenger.setMockMethodCallHandler(const MethodChannel(_channelName), (
      call,
    ) async {
      calls.add(call);
      return switch (call.method) {
        'capability' => capability,
        'transcribe' => transcribe == null ? 'system text' : transcribe(call),
        _ => null,
      };
    });
  }

  List<String> methods() => calls.map((c) => c.method).toList();

  test(
    'the system text is returned and the local engine is never built',
    () async {
      native();

      final text = await build().transcribe(_wav(), language: 'de');

      expect(text, 'system text');
      expect(localBuilt, 0);
      expect(causes, isEmpty);
    },
  );

  test('the stored model is the system engine, or the local one on a '
      'fallback (#1080)', () async {
    native();
    final t = build(fallbackModelId: () => 'whisper-small');
    await t.transcribe(_wav(), language: 'de');
    expect(t.lastUsedModelId, systemSpeechModelId);

    // A language the system cannot take goes to the local engine.
    await t.transcribe(_wav(), language: 'auto');
    expect(t.lastUsedModelId, 'whisper-small');

    // A technical failure of the system run goes to the local engine too.
    native(transcribe: (_) async => throw StateError('boom'));
    await t.transcribe(_wav(), language: 'de');
    expect(t.lastUsedModelId, 'whisper-small');
  });

  test(
    'the chosen language is checked and used, never the system one',
    () async {
      native();

      await build().transcribe(_wav(), language: 'de');

      expect(methods(), ['capability', 'transcribe']);
      expect((calls[0].arguments as Map)['locale'], 'de');
      expect((calls[1].arguments as Map)['locale'], 'de');
    },
  );

  test(
    'an automatic language goes to the local engine without a native run',
    () async {
      native();

      final text = await build().transcribe(_wav(), language: 'auto');

      expect(text, 'local text');
      expect(calls, isEmpty);
      expect(local.language, 'auto');
      expect(causes, [SystemSpeechFallback.languageUnsupported]);
    },
  );

  test('an unsupported language is caught before the run, calmly', () async {
    native(capability: {'osSupported': true, 'installed': false});

    final text = await build().transcribe(_wav(), language: 'ru');

    expect(text, 'local text');
    expect(methods(), ['capability']);
    expect(causes, [SystemSpeechFallback.languageUnsupported]);
  });

  test('a missing asset falls back before the run', () async {
    native(
      capability: {
        'osSupported': true,
        'localeSupported': 'de_DE',
        'installed': false,
      },
    );

    final text = await build().transcribe(_wav(), language: 'de');

    expect(text, 'local text');
    expect(methods(), ['capability']);
    expect(causes, [SystemSpeechFallback.failure]);
  });

  test('a technical failure falls back with the same audio', () async {
    native(
      transcribe: (_) async {
        throw PlatformException(code: 'TRANSCRIBE_FAILED');
      },
    );
    final wav = _wav(seconds: 0.5);

    final text = await build().transcribe(wav, language: 'de');

    expect(text, 'local text');
    expect(local.transcribed, 1);
    expect(causes, [SystemSpeechFallback.failure]);
  });

  test('a host that never answers is cancelled and falls back', () async {
    final never = Completer<Object?>();
    native(transcribe: (_) => never.future);

    final text = await build(
      limit: const Duration(milliseconds: 50),
    ).transcribe(_wav(), language: 'de');

    expect(text, 'local text');
    expect(methods(), ['capability', 'transcribe', 'cancel']);
    expect(causes, [SystemSpeechFallback.failure]);
  });

  test('a native timeout code falls back', () async {
    native(
      transcribe: (_) async {
        throw PlatformException(code: 'TIMEOUT');
      },
    );

    final text = await build().transcribe(_wav(), language: 'de');

    expect(text, 'local text');
    expect(causes, [SystemSpeechFallback.failure]);
  });

  test('vocabulary goes along with the native call', () async {
    List<Object?>? seenTerms;
    native(
      transcribe: (call) async {
        seenTerms = (call.arguments as Map)['terms'] as List<Object?>;
        return 'ok';
      },
    );

    await build(
      vocabulary: () => ['Kubernetes'],
    ).transcribe(_wav(), language: 'de');

    expect(seenTerms, ['Kubernetes']);
  });

  test('the WAV file lies in the private folder and is removed', () async {
    String? seenPath;
    native(
      transcribe: (call) async {
        seenPath = (call.arguments as Map)['path'] as String;
        expect(File(seenPath!).existsSync(), isTrue);
        return 'ok';
      },
    );

    await build().transcribe(_wav(), language: 'de');

    expect(seenPath, isNotNull);
    expect(File(seenPath!).parent.path, endsWith(kSystemSpeechTempFolder));
    expect(File(seenPath!).existsSync(), isFalse);
  });

  test('app start clears audio an earlier run left behind', () async {
    final dir = Directory('${tempDir.path}/$kSystemSpeechTempFolder')
      ..createSync();
    File('${dir.path}/audio-1.wav').writeAsBytesSync([1, 2, 3]);

    await clearSystemSpeechTemp(tempDir);

    expect(dir.listSync(), isEmpty);
  });

  test('the time limit is at least 20 s and grows with the audio', () {
    expect(systemSpeechTimeLimit(_wav()), const Duration(seconds: 20));
    expect(
      systemSpeechTimeLimit(_wav(seconds: 60)),
      const Duration(seconds: 250),
    );
  });
}
