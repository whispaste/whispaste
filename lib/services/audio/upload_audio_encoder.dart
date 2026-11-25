/// Compressed upload copy for cloud transcription (#177, LONG-AUDIO T1).
///
/// A slice of 16 kHz mono 16-bit PCM goes up as Opus in WebM at 32 kbit/s
/// instead of WAV (512 kbit/s): a 10-minute slice shrinks from about 19.2 MB
/// to about 2.4 MB. The encoder is libopus inside the bundled, audio-only
/// FFmpeg helper (ADR 0037, ADR 0040), the same program on all three systems.
///
/// The recording itself is never changed; only the request body differs.
/// Whenever the helper is missing (development builds) or the encoding fails,
/// the caller sends the WAV as before, so compression can only save bytes and
/// never cost a transcript.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import 'import/pcm_decoder.dart';
import 'import/video_audio_decoder.dart' show bundledVideoDecoderPath;

final _log = AppLogger('UploadAudioEncoder');

/// Bit rate of the Opus upload copy. 32 kbit/s keeps speech of a 16 kHz
/// recording transparent for recognition; below 24 kbit/s Opus narrows the
/// band audibly.
const int kUploadOpusBitrate = 32000;

/// libopus complexity (0-10). 5 halves the encoder's CPU time against the
/// default 10 at about the same size (measured: 5.6 s instead of 10.2 s CPU
/// for a 10-minute speech slice on an M-series Mac under load).
const int kUploadOpusComplexity = 5;

/// Shortest audio that is compressed: 30 s (960 kB of samples). Below it the
/// WAV upload takes well under a second on a normal line, while starting the
/// helper would add its own delay to the dictation's hotkey-to-text path.
const int kUploadCompressMinPcmBytes = 30 * kSttSampleRate * 2;

/// One request body in a compressed format.
class EncodedUpload {
  const EncodedUpload(this.bytes, {required this.filename, required this.mime});

  final Uint8List bytes;

  /// File name of the multipart field; its extension names the format.
  final String filename;

  /// MIME type of a raw request body (Deepgram).
  final String mime;
}

/// Turns PCM samples into a smaller upload. Returns null when the audio has
/// to go up as WAV (no encoder, failure, or no gain).
abstract class UploadAudioEncoder {
  Future<EncodedUpload?> encode(List<Uint8List> pcmParts, int pcmLength);
}

/// The encoder the cloud transcribers use. Tests override it.
final uploadAudioEncoderProvider = Provider<UploadAudioEncoder>(
  (ref) => OpusUploadEncoder(),
);

/// The sample bytes of [wav] when it is the canonical WhisPaste layout
/// (44-byte header, PCM, mono, 16 kHz, 16 bit), otherwise null. Any other
/// layout stays WAV: the encoder reads raw samples and would take a foreign
/// header for audio.
Uint8List? canonicalPcm16MonoSamples(Uint8List wav) {
  if (wav.length <= 44) return null;
  final header = ByteData.sublistView(wav, 0, 44);
  final canonical =
      header.getUint32(0, Endian.little) == 0x46464952 && // RIFF
      header.getUint32(8, Endian.little) == 0x45564157 && // WAVE
      header.getUint32(12, Endian.little) == 0x20746D66 && // 'fmt '
      header.getUint32(16, Endian.little) == 16 &&
      header.getUint16(20, Endian.little) == 1 && // PCM
      header.getUint16(22, Endian.little) == 1 && // mono
      header.getUint32(24, Endian.little) == kSttSampleRate &&
      header.getUint16(34, Endian.little) == 16 &&
      header.getUint32(36, Endian.little) == 0x61746164; // 'data'
  return canonical ? Uint8List.sublistView(wav, 44) : null;
}

typedef UploadEncoderStarter =
    Future<Process> Function(String executable, List<String> arguments);

Future<Process> _start(String executable, List<String> arguments) =>
    Process.start(executable, arguments, runInShell: false);

/// The arguments for one encoding: raw PCM on stdin, WebM on stdout. Only the
/// pipe protocol is allowed, so no file or address is ever opened.
List<String> opusUploadArguments() => [
  '-nostdin', '-hide_banner', '-nostats', '-loglevel', 'error',
  '-protocol_whitelist', 'pipe',
  // Input: the raw samples of the slice.
  '-f', 's16le', '-ar', '$kSttSampleRate', '-ch_layout', 'mono',
  '-i', 'pipe:0',
  '-map', '0:a:0', '-map_metadata', '-1', '-threads', '1',
  // Output: Opus for speech, variable bit rate around the target.
  '-c:a', 'libopus', '-b:a', '$kUploadOpusBitrate', '-vbr', 'on',
  '-application', 'voip', '-compression_level', '$kUploadOpusComplexity',
  '-f', 'webm', 'pipe:1',
];

/// Opus/WebM through the bundled FFmpeg helper. The helper runs only while a
/// slice is encoded (about a second for 10 minutes) and is reaped afterwards.
class OpusUploadEncoder implements UploadAudioEncoder {
  OpusUploadEncoder({
    String? executable,
    UploadEncoderStarter? start,
    this.stallTimeout = const Duration(seconds: 30),
  }) : _executable = executable ?? bundledVideoDecoderPath(),
       _startProcess = start ?? _start;

  final String _executable;
  final UploadEncoderStarter _startProcess;

  /// The helper is killed when it neither reads nor writes for this long.
  final Duration stallTimeout;

  @override
  Future<EncodedUpload?> encode(List<Uint8List> pcmParts, int pcmLength) async {
    if (pcmLength < kUploadCompressMinPcmBytes) return null;
    // A development build has no helper; that is no failure worth a warning.
    if (!File(_executable).existsSync()) return null;
    final Process process;
    try {
      process = await _startProcess(_executable, opusUploadArguments());
    } on ProcessException catch (e) {
      _log.warning(
        'Upload encoder did not start (${e.errorCode}); sending WAV',
      );
      return null;
    }

    var lastActivity = DateTime.now();
    var killed = false;
    var tooLarge = false;
    void stop() {
      if (killed) return;
      killed = true;
      process.kill(ProcessSignal.sigkill);
    }

    final stallTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (DateTime.now().difference(lastActivity) > stallTimeout) stop();
    });
    // Diagnostics are not kept: they are not needed to fall back to WAV.
    final stderrDone = process.stderr.drain<void>().catchError((_) {});
    // Feeding stdin while stdout is read; a helper that dies early closes the
    // pipe, and that write error only means "send WAV".
    final feed = () async {
      try {
        for (final part in pcmParts) {
          if (killed) break;
          process.stdin.add(part);
          await process.stdin.flush();
          lastActivity = DateTime.now();
        }
        await process.stdin.close();
      } on Object {
        stop();
      }
    }();

    final output = BytesBuilder(copy: false);
    try {
      await for (final chunk in process.stdout) {
        lastActivity = DateTime.now();
        output.add(chunk);
        // Larger than the WAV would be no gain; stop at once.
        if (output.length >= pcmLength) {
          tooLarge = true;
          stop();
          break;
        }
      }
      final exit = await process.exitCode;
      await feed;
      await stderrDone;
      final bytes = output.takeBytes();
      if (killed || exit != 0 || !_isWebm(bytes)) {
        _log.warning(
          'Upload encoding failed (exit $exit, '
          '${tooLarge ? 'no gain' : (killed ? 'stalled' : '${bytes.length} bytes')}'
          '); sending WAV',
        );
        return null;
      }
      _log.info(
        'Upload copy compressed: ${pcmLength + 44} -> ${bytes.length} bytes',
      );
      return EncodedUpload(bytes, filename: 'audio.webm', mime: 'audio/webm');
    } on Object catch (e) {
      _log.warning('Upload encoding failed (${e.runtimeType}); sending WAV');
      return null;
    } finally {
      stallTimer.cancel();
      stop();
      await process.exitCode;
    }
  }
}

/// A WebM file starts with the EBML magic number.
bool _isWebm(Uint8List bytes) =>
    bytes.length > 4 &&
    bytes[0] == 0x1A &&
    bytes[1] == 0x45 &&
    bytes[2] == 0xDF &&
    bytes[3] == 0xA3;
