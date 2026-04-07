/// Sound feedback service — plays audio cues for recording events.
///
/// On Windows, uses the Win32 `PlaySound` API via `dart:ffi` — this avoids
/// the native threading crash in `audioplayers_windows_plugin.dll` (see
/// Windows Event Viewer: 0xc0000005 in audioplayers).
///
/// Failures are silently logged — sound feedback is non-critical and must
/// never block the recording pipeline.
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
  } catch (_) {
    return false;
  }
}

/// Plays a WAV file asynchronously via Win32 PlaySound.
void _playSoundWin32(String filePath) {
  if (_playSound == null) return;
  final ptr = filePath.toNativeUtf16();
  try {
    _playSound!(ptr, 0, _sndAsync | _sndFilename | _sndNoDefault);
  } finally {
    calloc.free(ptr);
  }
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

class SoundFeedbackService extends Notifier<void> {
  static final _log = AppLogger('SoundFeedback');

  /// Resolved absolute paths for each sound asset.
  final Map<String, String> _resolvedPaths = {};
  bool _available = false;

  @override
  void build() {
    _available = _initWin32();
    if (_available) {
      // Pre-extract assets to temp so PlaySound can read them.
      _extractAssets();
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

      for (final name in ['start.wav', 'stop.wav', 'success.wav', 'error.wav']) {
        final target = File(p.join(soundDir.path, name));
        if (!target.existsSync()) {
          final data = await rootBundle.load('assets/sounds/$name');
          await target.writeAsBytes(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            flush: true,
          );
        }
        _resolvedPaths[name] = target.path;
      }
      _log.info('Sound assets extracted to ${soundDir.path}');
    } catch (e) {
      _log.warning('Failed to extract sound assets: $e');
      _available = false;
    }
  }

  Future<void> _play(String assetName, bool enabled) async {
    if (!enabled || !_available) return;

    final filePath = _resolvedPaths[assetName];
    if (filePath == null) return;

    try {
      _playSoundWin32(filePath);
      _log.debug('Playing $assetName');
    } catch (e) {
      _log.debug('Sound playback failed ($assetName): $e');
    }
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final soundFeedbackProvider =
    NotifierProvider<SoundFeedbackService, void>(SoundFeedbackService.new);
