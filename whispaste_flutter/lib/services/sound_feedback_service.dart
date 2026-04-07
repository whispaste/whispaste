/// Sound feedback service — plays audio cues for recording events.
///
/// On Windows, uses the Win32 `PlaySound` API via `dart:ffi` — this avoids
/// the native threading crash in `audioplayers_windows_plugin.dll` (see
/// Windows Event Viewer: 0xc0000005 in audioplayers).
///
/// Failures are logged and retried — sound feedback is non-critical but
/// important for user experience.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/config/settings_provider.dart';
import '../core/logging/app_logger.dart';

// ---------------------------------------------------------------------------
// Win32 PlaySound FFI bindings
// ---------------------------------------------------------------------------

// PlaySoundW flags
const int _sndAsync = 0x0001;
const int _sndFilename = 0x00020000;
const int _sndNoDefault = 0x0002;

typedef _PlaySoundNative = Int32 Function(
    Pointer<Utf16> pszSound, IntPtr hmod, Uint32 fdwSound);
typedef _PlaySoundDart = int Function(
    Pointer<Utf16> pszSound, int hmod, int fdwSound);

/// Lazy-loaded Win32 PlaySound function.
_PlaySoundDart? _playSound;

bool _initWin32() {
  if (_playSound != null) return true;
  if (!Platform.isWindows) return false;
  try {
    final winmm = DynamicLibrary.open('winmm.dll');
    _playSound =
        winmm.lookupFunction<_PlaySoundNative, _PlaySoundDart>('PlaySoundW');
    return true;
  } catch (e) {
    _log.warning('Failed to load winmm.dll: $e');
    return false;
  }
}

/// Plays a WAV file asynchronously via Win32 PlaySound.
/// Returns true if the API call succeeded.
bool _playSoundWin32(String filePath) {
  if (_playSound == null) return false;
  final ptr = filePath.toNativeUtf16();
  try {
    final result =
        _playSound!(ptr, 0, _sndAsync | _sndFilename | _sndNoDefault);
    return result != 0;
  } finally {
    calloc.free(ptr);
  }
}

final _log = AppLogger('SoundFeedback');

const _soundAssets = ['start.wav', 'stop.wav', 'success.wav', 'error.wav'];

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

class SoundFeedbackService extends Notifier<void> {
  /// Resolved absolute paths for each sound asset.
  final Map<String, String> _resolvedPaths = {};
  bool _win32Available = false;
  bool _extracted = false;

  @override
  void build() {
    _win32Available = _initWin32();
    if (_win32Available) {
      _extractAssets();
    } else {
      _log.warning('Win32 PlaySound not available — sound disabled');
    }
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<void> playRecordStart() =>
      _play('start.wav', _settings.recordStartSound);

  Future<void> playRecordStop() =>
      _play('stop.wav', _settings.recordStopSound);

  Future<void> playTranscriptionComplete() =>
      _play('success.wav', _settings.transcriptionCompleteSound);

  Future<void> playError() => _play('error.wav', true);

  // ── Private ────────────────────────────────────────────────────────────────

  AppSettings get _settings =>
      ref.read(settingsProvider).value ?? AppSettings.defaults;

  Future<void> _extractAssets() async {
    try {
      final dir = await getTemporaryDirectory();
      final soundDir = Directory(p.join(dir.path, 'whispaste_sounds'));
      if (!soundDir.existsSync()) soundDir.createSync(recursive: true);

      for (final name in _soundAssets) {
        final target = File(p.join(soundDir.path, name));
        if (!target.existsSync() || target.lengthSync() == 0) {
          final data = await rootBundle.load('assets/sounds/$name');
          await target.writeAsBytes(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            flush: true,
          );
          _log.info('Extracted $name (${data.lengthInBytes} bytes)');
        }
        _resolvedPaths[name] = target.path;
      }
      _extracted = true;
      _log.info(
          'Sound assets ready at ${soundDir.path} (${_resolvedPaths.length} files)');
    } catch (e) {
      _log.warning('Failed to extract sound assets: $e');
      _extracted = false;
    }
  }

  Future<void> _play(String assetName, bool enabled) async {
    if (!enabled || !_win32Available) return;

    // If extraction hasn't completed yet, wait for it.
    if (!_extracted) {
      _log.info('Sound assets not yet extracted, re-extracting...');
      await _extractAssets();
    }

    final filePath = _resolvedPaths[assetName];
    if (filePath == null) {
      _log.warning('No resolved path for $assetName');
      return;
    }

    // Verify file still exists (temp cleanup protection).
    if (!File(filePath).existsSync()) {
      _log.info('Sound file missing, re-extracting: $assetName');
      _extracted = false;
      await _extractAssets();
      final retryPath = _resolvedPaths[assetName];
      if (retryPath == null || !File(retryPath).existsSync()) {
        _log.warning('Re-extraction failed for $assetName');
        return;
      }
      _playSoundAndLog(retryPath, assetName);
      return;
    }

    _playSoundAndLog(filePath, assetName);
  }

  void _playSoundAndLog(String filePath, String assetName) {
    try {
      final ok = _playSoundWin32(filePath);
      if (ok) {
        _log.debug('Playing $assetName');
      } else {
        _log.warning('PlaySound returned FALSE for $assetName ($filePath)');
      }
    } catch (e) {
      _log.warning('Sound playback exception ($assetName): $e');
    }
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final soundFeedbackProvider =
    NotifierProvider<SoundFeedbackService, void>(SoundFeedbackService.new);
