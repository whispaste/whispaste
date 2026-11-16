/// [Transcriber] for the system speech engine. The audio goes to the system
/// (SpeechAnalyzer) first. Before that, the language chosen in Settings (never
/// the system language) is checked: a language the system cannot transcribe,
/// an automatic language, a missing asset, any failure or a timeout hands the
/// same audio to the local engine, so no recording is lost. Each such fallback
/// is reported once per cause, calmly, through [onFallback]; the log names only
/// the code, never the content.
library;

import 'dart:async';
import 'dart:io';

import '../../core/config/settings_enums.dart' show systemSpeechModelId;
import '../../core/logging/app_logger.dart';
import '../transcription/transcriber_interface.dart';
import 'system_speech_channel.dart';

final _log = AppLogger('SystemSpeech');

/// Name of the private folder below the temp directory that holds the audio
/// handed to the system engine.
const kSystemSpeechTempFolder = 'whispaste-system-speech';

/// Removes audio an earlier run left in the private folder below [base]. Runs
/// at app start, before any recording; a folder that is missing is fine.
Future<void> clearSystemSpeechTemp(Directory base) async {
  final dir = Directory('${base.path}/$kSystemSpeechTempFolder');
  try {
    if (!await dir.exists()) return;
    await for (final entry in dir.list()) {
      try {
        await entry.delete(recursive: true);
      } on FileSystemException catch (e) {
        _log.debug('stale audio cleanup failed: ${e.osError}');
      }
    }
  } on FileSystemException catch (e) {
    _log.debug('stale audio folder unreadable: ${e.osError}');
  }
}

class SystemSpeechTranscriber
    implements Transcriber, ModelReportingTranscriber {
  SystemSpeechTranscriber({
    required this.channel,
    required this.fallback,
    required this.tempDirectory,
    required this.onFallback,
    this.fallbackModelId = _systemModelId,
    this.vocabulary = _noTerms,
    this.osSupported = systemSpeechOsSupported,
    this.timeLimit = systemSpeechDartTimeLimit,
  });

  final SystemSpeechChannel channel;

  /// The local engine, used when the system engine cannot take the audio.
  /// Built on first use, so a recording the system handles never loads it.
  final Transcriber Function() fallback;

  /// The base directory; the audio goes into a private subfolder of it.
  final Directory Function() tempDirectory;

  /// Reports why a recording went to the local engine.
  final void Function(SystemSpeechFallback cause) onFallback;

  /// Model identity of the local engine [fallback] builds, read when a
  /// recording falls back, so history names the engine that did the work.
  final String Function() fallbackModelId;

  static String _systemModelId() => systemSpeechModelId;

  @override
  String? lastUsedModelId;

  /// Vocabulary hints for the recognizer, read per recording.
  final List<String> Function() vocabulary;

  static List<String> _noTerms() => const [];

  /// Whether the OS can run the engine; tests on other platforms pass `true`.
  final bool Function() osSupported;

  /// How long the native call may take for a recording; tests shorten it.
  final Duration Function(List<int> wavBytes) timeLimit;

  Transcriber? _fallback;
  Transcriber get _local => _fallback ??= fallback();

  bool _folderReady = false;

  @override
  Future<void> prepare() async {
    if (!osSupported()) {
      throw const TranscriberException(
        'system-speech-os-unsupported',
        reason: TranscriberFailureReason.notReady,
      );
    }
  }

  @override
  Future<String> transcribe(List<int> wavBytes, {String? language}) async {
    lastUsedModelId = null;
    final locale = systemSpeechLocaleFor(language);
    // An automatic language is never resolved to the system language: the
    // local engine detects the language itself.
    if (locale == null) {
      return _fallbackFor(wavBytes, language, 'LOCALE_AUTO');
    }
    final cap = await channel.capability(locale);
    if (!cap.osSupported) {
      return _fallbackFor(wavBytes, language, 'OS_UNSUPPORTED');
    }
    if (cap.localeSupported == null) {
      return _fallbackFor(wavBytes, language, 'LOCALE_UNSUPPORTED');
    }
    if (!cap.installed) {
      return _fallbackFor(wavBytes, language, 'ASSET_MISSING');
    }

    final dir = await _privateDirectory();
    final file = File(
      '${dir.path}/audio-${DateTime.now().microsecondsSinceEpoch}.wav',
    );
    try {
      await file.writeAsBytes(wavBytes, flush: true);
      await _restrict(file.path, '600');
      final text = await channel
          .transcribe(path: file.path, locale: locale, terms: vocabulary())
          .timeout(timeLimit(wavBytes));
      lastUsedModelId = systemSpeechModelId;
      return text;
    } on SystemSpeechException catch (e) {
      return _fallbackFor(wavBytes, language, e.code);
    } on TimeoutException {
      // The host should have given up first; stop its work before the local
      // engine takes the same audio.
      await channel.cancel();
      return _fallbackFor(wavBytes, language, 'TIMEOUT');
    } finally {
      try {
        if (await file.exists()) await file.delete();
      } on FileSystemException catch (e) {
        _log.debug('temp audio cleanup failed: ${e.osError}');
      }
    }
  }

  Future<String> _fallbackFor(
    List<int> wavBytes,
    String? language,
    String code,
  ) async {
    _log.warning(
      'System speech handed the recording to the local engine '
      '($code)',
    );
    onFallback(systemSpeechFallbackFor(code));
    final local = _local;
    await local.prepare();
    final text = await local.transcribe(wavBytes, language: language);
    lastUsedModelId = fallbackModelId();
    return text;
  }

  /// The private folder for the audio, made owner-only once per process.
  Future<Directory> _privateDirectory() async {
    final dir = Directory('${tempDirectory().path}/$kSystemSpeechTempFolder');
    if (!_folderReady || !await dir.exists()) {
      await dir.create(recursive: true);
      await _restrict(dir.path, '700');
      _folderReady = true;
    }
    return dir;
  }

  /// Owner-only permissions on macOS and Linux. Other platforms never run this
  /// engine, so there the call is skipped.
  Future<void> _restrict(String path, String mode) async {
    if (!Platform.isMacOS && !Platform.isLinux) return;
    final result = await Process.run('chmod', [mode, path]);
    if (result.exitCode != 0) {
      _log.debug('chmod $mode failed for temp audio');
    }
  }

  @override
  void release() => _fallback?.release();
}
