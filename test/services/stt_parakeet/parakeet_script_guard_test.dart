/// Parakeet keeps to the user's languages by their script (#2168): a Polish
/// dictation that Parakeet writes in Cyrillic goes to Whisper when its model
/// is installed, otherwise the text stays and the switch is offered.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_script_guard.dart';
import 'package:whispaste/services/transcription/transcriber_interface.dart';

class _Fake implements Transcriber, WavFileTranscriber {
  _Fake(this.text, {this.error});

  final String text;
  final TranscriberException? error;
  int calls = 0;
  int fileCalls = 0;
  String? language;

  @override
  Future<void> prepare() async {}

  @override
  Future<String> transcribe(List<int> wavBytes, {String? language}) async {
    calls++;
    this.language = language;
    if (error case final e?) throw e;
    return text;
  }

  @override
  Future<String> transcribeWavFile(
    String wavPath,
    List<int> wavBytes, {
    String? language,
  }) {
    fileCalls++;
    return transcribe(wavBytes, language: language);
  }

  @override
  void release() {}
}

const _cyrillic = 'Привет, как у тебя дела сегодня?';
const _polish = 'Cześć, jak się dzisiaj masz?';

void main() {
  group('script detection', () {
    test('names the dominant script', () {
      expect(dominantScript(_polish), WritingScript.latin);
      expect(dominantScript(_cyrillic), WritingScript.cyrillic);
      expect(dominantScript('Καλημέρα'), WritingScript.greek);
      expect(dominantScript('12, 3.'), isNull);
    });

    test('Cyrillic is foreign to Polish, Latin is not', () {
      expect(isForeignScript(_cyrillic, ['pl']), isTrue);
      expect(isForeignScript(_polish, ['pl']), isFalse);
      // A Russian name inside Polish text keeps the Latin majority.
      expect(isForeignScript('Rozmawiałem z Иван wczoraj', ['pl']), isFalse);
    });

    test('nothing to compare against switches the check off', () {
      expect(isForeignScript(_cyrillic, const []), isFalse);
      expect(isForeignScript(_cyrillic, ['pl', 'uk']), isFalse);
      // Serbian is written in both scripts.
      expect(isForeignScript(_cyrillic, ['pl', 'sr']), isFalse);
    });

    test('the request language wins, automatic uses the allowed set', () {
      expect(languagesForRequest('pl', ['de', 'en']), ['pl']);
      expect(languagesForRequest('auto', ['pl', 'en']), ['pl', 'en']);
      expect(languagesForRequest(null, const []), isEmpty);
    });
  });

  group('guarded Parakeet', () {
    late _Fake parakeet;
    late _Fake whisper;
    late List<ParakeetScriptNotice> notices;
    late bool whisperInstalled;

    ParakeetScriptGuardedTranscriber guard() =>
        ParakeetScriptGuardedTranscriber(
          inner: parakeet,
          languagesFor: (language) => languagesForRequest(language, ['pl']),
          whisperInstalled: () => whisperInstalled,
          whisper: () => whisper,
          whisperModelId: () => 'whisper-large-v3-turbo',
          onNotice: notices.add,
        );

    setUp(() {
      parakeet = _Fake(_cyrillic);
      whisper = _Fake(_polish);
      notices = [];
      whisperInstalled = true;
    });

    test('a Polish dictation in Cyrillic goes to Whisper in Polish', () async {
      final t = guard();
      final text = await t.transcribe(const [1, 2], language: 'pl');

      expect(text, _polish);
      expect(whisper.language, 'pl');
      expect(t.lastUsedModelId, 'whisper-large-v3-turbo');
      expect(notices.single.handledByWhisper, isTrue);
      expect(notices.single.languages, ['pl']);
    });

    test('the WAV file path reaches Whisper too', () async {
      final t = guard();
      await t.transcribeWavFile('/tmp/a.wav', const [1], language: 'auto');

      expect(parakeet.fileCalls, 1);
      expect(whisper.fileCalls, 1);
      expect(whisper.language, 'auto');
    });

    test('a matching script stays with Parakeet', () async {
      parakeet = _Fake(_polish);
      final t = guard();

      expect(await t.transcribe(const [1], language: 'pl'), _polish);
      expect(whisper.calls, 0);
      expect(t.lastUsedModelId, isNull);
      expect(notices, isEmpty);
    });

    test('without Whisper the text stays and the switch is offered', () async {
      whisperInstalled = false;
      final t = guard();

      expect(await t.transcribe(const [1], language: 'pl'), _cyrillic);
      expect(whisper.calls, 0);
      expect(notices.single.handledByWhisper, isFalse);
    });

    test('a failed Whisper run keeps the Parakeet text', () async {
      whisper = _Fake(
        '',
        error: const TranscriberException(
          'stt_server_failed',
          reason: TranscriberFailureReason.notReady,
        ),
      );
      final t = guard();

      expect(await t.transcribe(const [1], language: 'pl'), _cyrillic);
      expect(t.lastUsedModelId, isNull);
      expect(notices.single.handledByWhisper, isFalse);
    });

    test('cancelling during the Whisper run stays a cancel', () async {
      whisper = _Fake(
        '',
        error: const TranscriberException(
          'cancelled',
          reason: TranscriberFailureReason.cancelled,
        ),
      );

      await expectLater(
        guard().transcribe(const [1], language: 'pl'),
        throwsA(isA<TranscriberException>()),
      );
    });
  });

  test('Whisper taking over is said once, the offer every time', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final shown = <ParakeetScriptNotice>[];
    container.listen(parakeetScriptNoticeProvider, (_, next) {
      if (next != null) shown.add(next);
    });
    final notifier = container.read(parakeetScriptNoticeProvider.notifier);
    const took = ParakeetScriptNotice(
      languages: ['pl'],
      handledByWhisper: true,
    );
    const offer = ParakeetScriptNotice(
      languages: ['pl'],
      handledByWhisper: false,
    );

    for (final notice in [took, took, offer, offer]) {
      notifier.show(notice);
      notifier.clear();
    }

    expect(shown, [took, offer, offer]);
  });
}
