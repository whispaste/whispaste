/// The safety net around an own model in use (#1789): a failure hands the
/// same audio or text to a checked model, a cancel is no failure, and without
/// a checked model the recording stays retryable.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/smart_mode/smart_mode_engine.dart';
import 'package:whispaste/services/transcription/transcriber_interface.dart';
import 'package:whispaste/services/user_models/user_model_guards.dart';

const _id = 'user-aaaaaaaaaaaa';

class _Host implements UserModelGuardHost {
  _Host({this.ready = true, this.replaced = true});

  bool ready;
  final bool replaced;
  final events = <String>[];

  @override
  bool isReady(String id) => ready;

  @override
  void markInFlight(String id) => events.add('mark $id');

  @override
  void clearInFlight() => events.add('clear');

  @override
  Future<bool> fallBackFromSpeech(String id) async {
    events.add('fallback speech $id');
    return replaced;
  }

  @override
  Future<bool> fallBackFromSmartMode(String id) async {
    events.add('fallback smart $id');
    return replaced;
  }
}

class _Transcriber implements Transcriber {
  _Transcriber({this.text = 'ok', this.error});

  final String text;
  final Object? error;
  var prepared = 0;
  var calls = 0;

  @override
  Future<void> prepare() async => prepared++;

  @override
  Future<String> transcribe(List<int> wavBytes, {String? language}) async {
    calls++;
    if (error != null) throw error!;
    return text;
  }

  @override
  void release() {}
}

class _Engine implements SmartModeEngine {
  _Engine({this.text = 'ok', this.error});

  final String text;
  final Object? error;

  @override
  Future<String> run({
    required String systemPrompt,
    required String userText,
  }) async {
    if (error != null) throw error!;
    return text;
  }

  @override
  Future<void> cancel() async {}
}

void main() {
  UserModelGuardedTranscriber guard(
    _Transcriber inner,
    _Host host,
    _Transcriber replacement,
  ) => UserModelGuardedTranscriber(
    modelId: _id,
    inner: inner,
    host: host,
    fallback: () => replacement,
    fallbackModelId: () => 'whisper-small',
  );

  group('speech', () {
    test('a working own model writes and is named in history', () async {
      final host = _Host();
      final g = guard(_Transcriber(text: 'own'), host, _Transcriber());
      expect(await g.transcribe([1, 2]), 'own');
      expect(g.lastUsedModelId, _id);
      // The crash marker brackets the native call.
      expect(host.events, ['mark $_id', 'clear']);
    });

    test('a failure hands the same audio to the checked model', () async {
      final host = _Host();
      final replacement = _Transcriber(text: 'checked');
      final g = guard(
        _Transcriber(error: StateError('decode')),
        host,
        replacement,
      );
      expect(await g.transcribe([1, 2]), 'checked');
      expect(g.lastUsedModelId, 'whisper-small');
      expect(host.events, contains('fallback speech $_id'));
      expect(replacement.prepared, 1);

      // The next recording goes straight to the replacement.
      expect(await g.transcribe([3]), 'checked');
      expect(replacement.calls, 2);
    });

    test('a cancel is passed on, the model stays in use', () async {
      final host = _Host();
      final g = guard(
        _Transcriber(
          error: const TranscriberException(
            'cancelled',
            reason: TranscriberFailureReason.cancelled,
          ),
        ),
        host,
        _Transcriber(),
      );
      await expectLater(
        g.transcribe([1]),
        throwsA(isA<TranscriberException>()),
      );
      expect(host.events.where((e) => e.startsWith('fallback')), isEmpty);
    });

    test('without a checked model the recording stays retryable', () async {
      final host = _Host(replaced: false);
      final g = guard(
        _Transcriber(error: StateError('decode')),
        host,
        _Transcriber(),
      );
      await expectLater(
        g.transcribe([1]),
        throwsA(
          isA<TranscriberException>().having(
            (e) => e.message,
            'message',
            'stt_server_failed',
          ),
        ),
      );
    });

    test('a model no longer ready is never loaded', () async {
      final inner = _Transcriber();
      final replacement = _Transcriber();
      final g = guard(inner, _Host(ready: false), replacement);
      await g.prepare();
      expect(inner.prepared, 0);
      expect(replacement.prepared, 1);
    });
  });

  group('Smart Mode', () {
    test('a failure runs the instruction on the bundled model', () async {
      final host = _Host();
      final g = UserModelGuardedSmartModeEngine(
        modelId: _id,
        inner: _Engine(error: StateError('load')),
        host: host,
        fallback: () => _Engine(text: 'gemma'),
      );
      expect(await g.run(systemPrompt: 's', userText: 'u'), 'gemma');
      expect(g.fellBack, isTrue);
      expect(host.events.last, 'clear');
    });

    test('without the bundled model the error goes on', () async {
      final g = UserModelGuardedSmartModeEngine(
        modelId: _id,
        inner: _Engine(error: StateError('load')),
        host: _Host(replaced: false),
        fallback: _Engine.new,
      );
      await expectLater(
        g.run(systemPrompt: 's', userText: 'u'),
        throwsStateError,
      );
    });
  });
}
