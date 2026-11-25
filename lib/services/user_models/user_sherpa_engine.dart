/// sherpa-onnx offline recognizer for a user's own model (#1789), one of the
/// families in [SherpaFamily].
///
/// Deliberately separate from the Parakeet engine: that one carries the GPU
/// path, the GGUF variant and the catalog files. This one only builds the
/// family's config, runs on CPU in a worker isolate and decodes in the same
/// ≤ 25 s chunks as Parakeet ([transcribePcmInParakeetChunks]).
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import '../../core/logging/app_logger.dart';
import '../audio/pcm_wav_codec.dart';
import '../stt_parakeet/parakeet_audio_chunker.dart'
    show transcribePcmInParakeetChunks;
import 'user_model.dart';

final _log = AppLogger('UserSherpaEngine');

/// The sherpa-onnx model config for [model] in [dir]. Pure, for tests.
sherpa_onnx.OfflineModelConfig userSherpaModelConfig(
  UserModel model,
  String dir, {
  required int numThreads,
}) {
  String path(UserModelFileRole role) {
    final file = model.fileFor(role);
    return file == null ? '' : p.join(dir, file.name);
  }

  final family = model.family!;
  const none = sherpa_onnx.OfflineModelConfig(tokens: '');
  return sherpa_onnx.OfflineModelConfig(
    transducer:
        family == SherpaFamily.transducer ||
            family == SherpaFamily.nemoTransducer
        ? sherpa_onnx.OfflineTransducerModelConfig(
            encoder: path(UserModelFileRole.encoder),
            decoder: path(UserModelFileRole.decoder),
            joiner: path(UserModelFileRole.joiner),
          )
        : none.transducer,
    whisper: family == SherpaFamily.whisper
        ? sherpa_onnx.OfflineWhisperModelConfig(
            encoder: path(UserModelFileRole.encoder),
            decoder: path(UserModelFileRole.decoder),
          )
        : none.whisper,
    paraformer: family == SherpaFamily.paraformer
        ? sherpa_onnx.OfflineParaformerModelConfig(
            model: path(UserModelFileRole.model),
          )
        : none.paraformer,
    senseVoice: family == SherpaFamily.senseVoice
        ? sherpa_onnx.OfflineSenseVoiceModelConfig(
            model: path(UserModelFileRole.model),
            useInverseTextNormalization: true,
          )
        : none.senseVoice,
    nemoCtc: family == SherpaFamily.nemoCtc
        ? sherpa_onnx.OfflineNemoEncDecCtcModelConfig(
            model: path(UserModelFileRole.model),
          )
        : none.nemoCtc,
    zipformerCtc: family == SherpaFamily.zipformerCtc
        ? sherpa_onnx.OfflineZipformerCtcModelConfig(
            model: path(UserModelFileRole.model),
          )
        : none.zipformerCtc,
    moonshine: family == SherpaFamily.moonshine
        ? sherpa_onnx.OfflineMoonshineModelConfig(
            preprocessor: path(UserModelFileRole.preprocessor),
            encoder: path(UserModelFileRole.encoder),
            uncachedDecoder: path(UserModelFileRole.uncachedDecoder),
            cachedDecoder: path(UserModelFileRole.cachedDecoder),
          )
        : none.moonshine,
    fireRedAsr: family == SherpaFamily.fireRedAsr
        ? sherpa_onnx.OfflineFireRedAsrModelConfig(
            encoder: path(UserModelFileRole.encoder),
            decoder: path(UserModelFileRole.decoder),
          )
        : none.fireRedAsr,
    dolphin: family == SherpaFamily.dolphin
        ? sherpa_onnx.OfflineDolphinModelConfig(
            model: path(UserModelFileRole.model),
          )
        : none.dolphin,
    // sherpa-onnx reads `vocab.json`, `merges.txt` and
    // `tokenizer_config.json` from this folder; they keep those names
    // ([UserModelFileRole.fixedFileName]).
    qwen3Asr: family == SherpaFamily.qwen3Asr
        ? sherpa_onnx.OfflineQwen3AsrModelConfig(
            convFrontend: path(UserModelFileRole.convFrontend),
            encoder: path(UserModelFileRole.encoder),
            decoder: path(UserModelFileRole.decoder),
            tokenizer: dir,
            // A 25 s chunk of fast speech runs past the default of 128.
            maxNewTokens: kQwen3AsrMaxNewTokens,
          )
        : none.qwen3Asr,
    tokens: path(UserModelFileRole.tokens),
    numThreads: numThreads,
    provider: 'cpu',
    modelType: family == SherpaFamily.nemoTransducer ? 'nemo_transducer' : '',
    debug: false,
  );
}

/// Tokens Qwen3-ASR may write per chunk. 25 s of fast German speech are
/// about 80 words, well over sherpa-onnx's default of 128 tokens.
const kQwen3AsrMaxNewTokens = 256;

/// Threads for decoding: half the cores, at least 1, at most 4 (the same
/// budget the Parakeet CPU path uses).
int userSherpaThreads(int cores) => math.max(1, math.min(4, cores ~/ 2));

class _Init {
  const _Init(this.config);
  final sherpa_onnx.OfflineModelConfig config;
}

class _Decode {
  const _Decode(this.id, this.wav);
  final int id;
  final Uint8List wav;
}

class _Reply {
  const _Reply(this.id, {this.text, this.error});
  final int id;
  final String? text;
  final String? error;
}

class _Stop {
  const _Stop();
}

void _worker(SendPort main) {
  final port = ReceivePort();
  main.send(port.sendPort);
  sherpa_onnx.OfflineRecognizer? recognizer;
  port.listen((Object? message) {
    switch (message) {
      case final _Init init:
        try {
          sherpa_onnx.initBindings();
          recognizer = sherpa_onnx.OfflineRecognizer(
            sherpa_onnx.OfflineRecognizerConfig(model: init.config),
          );
          main.send(const _Reply(-1, text: ''));
        } catch (e) {
          main.send(_Reply(-1, error: '$e'));
        }
      case final _Decode req:
        final r = recognizer;
        if (r == null) {
          main.send(_Reply(req.id, error: 'not_initialized'));
          return;
        }
        try {
          final text = transcribePcmInParakeetChunks(
            Pcm16WavView(req.wav),
            sampleRate: 16000,
            decode: (chunk) {
              final stream = r.createStream();
              try {
                stream.acceptWaveform(samples: chunk, sampleRate: 16000);
                r.decode(stream);
                return r.getResult(stream).text;
              } finally {
                stream.free();
              }
            },
          );
          main.send(_Reply(req.id, text: text));
        } catch (e) {
          main.send(_Reply(req.id, error: '$e'));
        }
      case _Stop():
        recognizer?.free();
        port.close();
        Isolate.exit(main, const _Reply(-2));
    }
  });
}

/// One loaded user model. [start] loads it; [transcribe] takes WhisPaste's
/// canonical 16 kHz mono PCM16 WAV; [stop] frees it.
class UserSherpaEngine {
  UserSherpaEngine({required this.model, required this.dir});

  final UserModel model;
  final String dir;

  Isolate? _isolate;
  SendPort? _port;
  ReceivePort? _inbox;
  final Map<int, Completer<_Reply>> _pending = {};
  Completer<_Reply>? _initDone;
  Completer<void>? _stopped;
  int _next = 0;

  Future<void> start({required int cores}) async {
    if (_port != null) return;
    final inbox = ReceivePort();
    _inbox = inbox;
    final ready = Completer<SendPort>();
    inbox.listen((Object? message) {
      if (message is SendPort) {
        ready.complete(message);
      } else if (message is _Reply) {
        if (message.id == -1) {
          _initDone?.complete(message);
        } else if (message.id == -2) {
          _stopped?.complete();
        } else {
          _pending.remove(message.id)?.complete(message);
        }
      }
    });
    _isolate = await Isolate.spawn(_worker, inbox.sendPort);
    final port = await ready.future;
    _initDone = Completer<_Reply>();
    port.send(
      _Init(
        userSherpaModelConfig(model, dir, numThreads: userSherpaThreads(cores)),
      ),
    );
    final init = await _initDone!.future;
    if (init.error != null) {
      _log.warning('User model ${model.id} did not load: ${init.error}');
      await stop();
      throw StateError('user_model_load_failed');
    }
    _port = port;
  }

  Future<String> transcribe(List<int> wav, {Duration? timeout}) async {
    final port = _port;
    if (port == null) throw StateError('user_model_not_running');
    final id = _next++;
    final done = Completer<_Reply>();
    _pending[id] = done;
    port.send(_Decode(id, wav is Uint8List ? wav : Uint8List.fromList(wav)));
    final reply = timeout == null
        ? await done.future
        : await done.future.timeout(
            timeout,
            onTimeout: () {
              _pending.remove(id);
              return _Reply(id, error: 'transcription_timeout');
            },
          );
    if (reply.error != null) {
      _log.warning('User model ${model.id} decode failed: ${reply.error}');
      throw StateError(
        reply.error == 'transcription_timeout'
            ? 'transcription_timeout'
            : 'user_model_decode_failed',
      );
    }
    return reply.text ?? '';
  }

  Future<void> stop() async {
    final port = _port;
    final isolate = _isolate;
    _port = null;
    _isolate = null;
    if (port != null && isolate != null) {
      _stopped = Completer<void>();
      port.send(const _Stop());
      await _stopped!.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => isolate.kill(priority: Isolate.immediate),
      );
    } else {
      isolate?.kill(priority: Isolate.immediate);
    }
    for (final c in _pending.values) {
      c.complete(const _Reply(-3, error: 'stopped'));
    }
    _pending.clear();
    _inbox?.close();
    _inbox = null;
  }
}
