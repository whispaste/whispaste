/// Local video extraction in a short-lived, audio-only FFmpeg process.
/// No PATH lookup, shell, network protocol, video decoder or startup work.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'audio_decode_types.dart';
import 'pcm_decoder.dart';

const videoImportExtensions = [
  'mp4',
  'mov',
  'mkv',
  'webm',
  'mpeg',
  'mpg',
  'mpe',
  'vob',
  'ts',
  'mts',
  'm2ts',
];

class AudioImportCancelled implements Exception {
  const AudioImportCancelled();
}

class VideoDecoderUnavailable implements Exception {
  const VideoDecoderUnavailable();
}

class VideoHasNoAudio implements Exception {
  const VideoHasNoAudio();
}

/// The queue owns cancellation; only the active job receives this control.
class ImportDecodeControl {
  ImportDecodeControl({required this.isCancelled, this.onProgress});

  final bool Function() isCancelled;
  final void Function(double fraction)? onProgress;

  void checkCancelled() {
    if (isCancelled()) throw const AudioImportCancelled();
  }
}

/// Resolves only the helper shipped with this app. System FFmpeg versions
/// differ in codecs/licences and are deliberately never used as a fallback.
String bundledVideoDecoderPath() {
  final executableDir = p.dirname(Platform.resolvedExecutable);
  return Platform.isMacOS
      ? p.join(executableDir, '..', 'Helpers', 'ffmpeg')
      : p.join(
          executableDir,
          'video-decoder',
          Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg',
        );
}

typedef VideoProcessStarter =
    Future<Process> Function(String executable, List<String> arguments);

Future<Process> _start(String executable, List<String> arguments) =>
    Process.start(executable, arguments, runInShell: false);

class VideoAudioDecoder {
  VideoAudioDecoder({String? executable, VideoProcessStarter? start})
    : _executable = executable ?? bundledVideoDecoderPath(),
      _startProcess = start ?? _start;

  final String _executable;
  final VideoProcessStarter _startProcess;

  /// Writes bounded, streamed PCM; the caller wraps it in a canonical WAV.
  /// A cancellation kills and reaps the child before any scratch cleanup.
  Future<int> decodeToRawPcm16({
    required String inputPath,
    required String rawOutputPath,
    required AudioSourceFormat format,
    ImportDecodeControl? control,
    Duration maxDuration = kMaxImportDuration,
  }) async {
    control?.checkCancelled();
    final Process process;
    try {
      process = await _startProcess(_executable, [
        '-nostdin', '-hide_banner', '-nostats', '-xerror',
        '-protocol_whitelist', 'file,pipe',
        // Force the sniffed container. A renamed playlist must
        // never get to a different demuxer or open another file/URL.
        '-f',
        switch (format) {
          AudioSourceFormat.mp4 => 'mov',
          AudioSourceFormat.matroska => 'matroska',
          AudioSourceFormat.mpeg => 'mpeg',
          AudioSourceFormat.mpegts => 'mpegts',
          _ => throw const AudioFormatUnsupportedException(
            'not a video container',
          ),
        },
        '-err_detect', 'explode', '-threads', '1',
        '-i', File(inputPath).absolute.path,
        '-map', '0:a:0', '-vn', '-sn', '-dn',
        '-threads', '1', '-ac', '1', '-ar', '$kSttSampleRate',
        '-c:a', 'pcm_s16le', '-f', 's16le',
        '-progress', 'pipe:2', 'pipe:1',
      ]);
    } on ProcessException {
      throw const VideoDecoderUnavailable();
    }

    var cancelled = false;
    var killed = false;
    var stalled = false;
    var durationExceeded = false;
    var lastActivity = DateTime.now();
    double? durationSeconds;
    var noAudio = false;
    var lastProgress = -1.0;
    void stop() {
      if (killed) return;
      killed = true;
      process.kill(ProcessSignal.sigkill);
    }

    final timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (control?.isCancelled() ?? false) {
        cancelled = true;
        stop();
      } else if (DateTime.now().difference(lastActivity) >
          const Duration(seconds: 60)) {
        stalled = true;
        stop();
      }
    });
    // Diagnostics can contain filenames/metadata: inspect bounded lines in
    // memory only, never return them to logs or crash reporting.
    final diagnosticsDone = Completer<void>();
    final diagnostics = _boundedLines(process.stderr).listen(
      (line) {
        if (line.contains('matches no streams')) noAudio = true;
        final duration = RegExp(
          r'^  Duration: (\d+):(\d+):(\d+(?:\.\d+)?),',
        ).firstMatch(line);
        if (duration != null) {
          durationSeconds =
              int.parse(duration[1]!) * 3600 +
              int.parse(duration[2]!) * 60 +
              double.parse(duration[3]!);
          if (durationSeconds! > maxDuration.inMilliseconds / 1000) {
            durationExceeded = true;
            stop();
          }
        }
        if (line.startsWith('out_time_us=')) {
          final micros = int.tryParse(line.substring('out_time_us='.length));
          if (micros != null &&
              durationSeconds != null &&
              durationSeconds! > 0) {
            final progress = (micros / 1000000 / durationSeconds!).clamp(
              0.0,
              1.0,
            );
            if (progress > lastProgress) {
              lastProgress = progress;
              control?.onProgress?.call(progress);
            }
          }
        }
      },
      onDone: () {
        if (!diagnosticsDone.isCompleted) diagnosticsDone.complete();
      },
      onError: (Object error) {
        if (!diagnosticsDone.isCompleted) diagnosticsDone.complete();
        stalled = true;
        stop();
      },
    );
    RandomAccessFile? output;
    var bytes = 0;
    final maxBytes = maxDuration.inMilliseconds * kSttSampleRate ~/ 1000 * 2;
    try {
      output = await File(rawOutputPath).open(mode: FileMode.write);
      await for (final chunk in process.stdout) {
        lastActivity = DateTime.now();
        control?.checkCancelled();
        bytes += chunk.length;
        if (bytes > maxBytes) {
          throw const AudioInputLimitException(
            'video audio exceeds duration limit',
          );
        }
        await output.writeFrom(chunk);
      }
      final exit = await process.exitCode;
      // stderr completion must precede the classification (no-audio can be
      // the last diagnostic, delivered after the stdout pipe closes).
      await diagnosticsDone.future;
      control?.checkCancelled();
      if (cancelled) throw const AudioImportCancelled();
      if (durationExceeded) {
        throw const AudioInputLimitException('video exceeds duration limit');
      }
      if (exit != 0 && noAudio) throw const VideoHasNoAudio();
      if (stalled || exit != 0 || bytes == 0 || bytes.isOdd) {
        throw const AudioDecodeFailedException('video audio extraction failed');
      }
      control?.onProgress?.call(1);
      return bytes ~/ 2;
    } on FileSystemException {
      throw const AudioDecoderIoException('cannot write extracted audio');
    } finally {
      timer.cancel();
      stop();
      await process.exitCode;
      await diagnostics.cancel();
      try {
        await output?.close();
      } on FileSystemException {
        throw const AudioDecoderIoException('cannot close extracted audio');
      }
    }
  }
}

/// A malformed metadata line must not grow a LineSplitter buffer without a
/// bound. Only short ASCII FFmpeg status lines are relevant here.
Stream<String> _boundedLines(Stream<List<int>> input) async* {
  final line = BytesBuilder(copy: false);
  var dropping = false;
  await for (final chunk in input) {
    for (final byte in chunk) {
      if (byte == 10 || byte == 13) {
        if (!dropping) {
          yield utf8.decode(line.takeBytes(), allowMalformed: true);
        }
        line.clear();
        dropping = false;
      } else if (!dropping) {
        if (line.length >= 4096) {
          line.clear();
          dropping = true;
        } else {
          line.addByte(byte);
        }
      }
    }
  }
  if (!dropping && line.length > 0) {
    yield utf8.decode(line.takeBytes(), allowMalformed: true);
  }
}
