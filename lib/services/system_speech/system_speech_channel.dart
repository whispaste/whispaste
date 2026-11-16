/// Dart side of the system speech engine (macOS 26+, SpeechAnalyzer). The
/// native host is `macos/Runner/SystemSpeechHost.swift`, channel
/// `whispaste/system_speech`. Native failures arrive as codes only; every
/// user-facing text is an ARB string chosen here.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Whether this Mac runs macOS 26 or later, the first release with
/// SpeechAnalyzer. [osVersion] defaults to `Platform.operatingSystemVersion`
/// (for example `Version 27.2 (Build ...)`); tests pass their own string.
bool systemSpeechOsSupported({String? osVersion}) {
  if (!Platform.isMacOS && osVersion == null) return false;
  final text = osVersion ?? Platform.operatingSystemVersion;
  final major = RegExp(r'(\d+)\.\d+').firstMatch(text);
  if (major == null) return false;
  return int.parse(major.group(1)!) >= 26;
}

/// The language the native side gets for a configured [languageCode], or
/// `null` for an automatic language (`auto`, empty). The system engine needs a
/// fixed language and must never fall back to the system language, so an
/// automatic language goes to the local engine instead.
String? systemSpeechLocaleFor(String? languageCode) {
  final code = languageCode?.trim() ?? '';
  return code.isEmpty || code == 'auto' ? null : code;
}

/// The time the native call may take for a WAV recording of [wavBytes]:
/// at least 20 s, otherwise four times the audio length plus 10 s. The host
/// uses the same rule, so both sides give up at about the same point. Past it
/// the recording goes to Whisper, so no text is lost.
Duration systemSpeechTimeLimit(List<int> wavBytes) {
  var seconds = 0.0;
  if (wavBytes.length > 44) {
    final header = ByteData.sublistView(
      Uint8List.fromList(wavBytes.sublist(0, 44)),
    );
    final rate = header.getUint32(24, Endian.little);
    final channels = header.getUint16(22, Endian.little);
    final bits = header.getUint16(34, Endian.little);
    if (rate > 0 && channels > 0 && bits > 0) {
      seconds = (wavBytes.length - 44) / (rate * channels * bits / 8);
    }
  }
  final limit = math.max(20.0, seconds * 4 + 10);
  return Duration(milliseconds: (limit * 1000).round());
}

/// Margin of the Dart-side limit over [systemSpeechTimeLimit]. The host gives
/// up first and stops its own work; the Dart limit only guards against a host
/// that never answers.
const kSystemSpeechDartTimeMargin = Duration(seconds: 5);

/// The time the Dart side waits for the native call before it cancels it and
/// hands the audio to the local engine.
Duration systemSpeechDartTimeLimit(List<int> wavBytes) =>
    systemSpeechTimeLimit(wavBytes) + kSystemSpeechDartTimeMargin;

/// Why the system engine handed a recording to the local engine.
enum SystemSpeechFallback {
  /// The system cannot transcribe the language (for example Russian), or the
  /// language is set to automatic.
  languageUnsupported,

  /// Any other technical failure, timeout or missing asset.
  failure,
}

/// The fallback cause for a native or Dart-side [code].
SystemSpeechFallback systemSpeechFallbackFor(String code) => switch (code) {
  'LOCALE_UNSUPPORTED' ||
  'LOCALE_AUTO' => SystemSpeechFallback.languageUnsupported,
  _ => SystemSpeechFallback.failure,
};

/// What the system reports for one locale.
class SystemSpeechCapability {
  const SystemSpeechCapability({
    required this.osSupported,
    this.localeSupported,
    this.installed = false,
  });

  /// Used when the channel is missing or the OS is too old.
  static const unavailable = SystemSpeechCapability(osSupported: false);

  final bool osSupported;

  /// The system's own identifier for the locale (for example `de_DE`), or
  /// `null` when the system cannot transcribe it.
  final String? localeSupported;

  /// The language asset is on disk, so transcription can start.
  final bool installed;
}

/// Progress of the system asset download.
class SystemSpeechProgress {
  const SystemSpeechProgress({
    required this.state,
    required this.fraction,
    this.code = '',
  });

  /// `idle`, `installing`, `done` or `error`.
  final String state;

  /// Fraction of the download in `0..1`.
  final double fraction;

  /// The cause when [state] is `error` (for example `DOWNLOAD_FAILED`).
  final String code;
}

/// A native failure, identified by the host's code only (for example
/// `LOCALE_UNSUPPORTED`, `ASSET_MISSING`, `TIMEOUT`). It carries no text.
class SystemSpeechException implements Exception {
  const SystemSpeechException(this.code);

  final String code;

  @override
  String toString() => 'SystemSpeechException($code)';
}

class SystemSpeechChannel {
  SystemSpeechChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('whispaste/system_speech');

  final MethodChannel _channel;

  /// Opens the streaming analyzer for the live preview. Answers `false` when
  /// the host cannot start it; never throws, because the preview is optional
  /// and must not disturb the recording.
  Future<bool> liveStart(String locale, {List<String> terms = const []}) async {
    try {
      return await _channel.invokeMethod<bool>('liveStart', {
            'locale': locale,
            'terms': terms,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Sends 16 kHz mono 16-bit little-endian samples to the live analyzer.
  Future<void> liveFeed(Uint8List pcm) async {
    try {
      await _channel.invokeMethod<void>('liveFeed', {'pcm': pcm});
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  Future<void> liveStop() async {
    try {
      await _channel.invokeMethod<void>('liveStop');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  /// Registers the receiver of the host's interim texts (`livePartial`).
  void onLivePartial(void Function(String text) handler) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'livePartial' && call.arguments is String) {
        handler(call.arguments as String);
      }
      return null;
    });
  }

  Future<SystemSpeechCapability> capability(String locale) async {
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>(
        'capability',
        {'locale': locale},
      );
      if (map == null) return SystemSpeechCapability.unavailable;
      return SystemSpeechCapability(
        osSupported: map['osSupported'] == true,
        localeSupported: map['localeSupported'] as String?,
        installed: map['installed'] == true,
      );
    } on MissingPluginException {
      return SystemSpeechCapability.unavailable;
    } on PlatformException {
      return SystemSpeechCapability.unavailable;
    }
  }

  Future<void> installAsset(String locale) => _run(
    () => _channel.invokeMethod<void>('installAsset', {'locale': locale}),
  );

  Future<SystemSpeechProgress> installProgress() async {
    final map = await _run(
      () => _channel.invokeMapMethod<String, dynamic>('installProgress'),
    );
    return SystemSpeechProgress(
      state: map?['state'] as String? ?? 'idle',
      fraction: (map?['fraction'] as num?)?.toDouble() ?? 0,
      code: map?['code'] as String? ?? '',
    );
  }

  /// Loads the model for [locale] ahead of a dictation.
  Future<void> prewarm(String locale) =>
      _run(() => _channel.invokeMethod<void>('prewarm', {'locale': locale}));

  /// Stops a running [transcribe] on the native side. Never throws: after a
  /// timeout the local engine takes over regardless.
  Future<void> cancel() async {
    try {
      await _channel.invokeMethod<void>('cancel');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  /// Transcribes the WAV file at [path] in [locale], the language chosen in
  /// Settings; [terms] are vocabulary hints for the recognizer.
  Future<String> transcribe({
    required String path,
    required String locale,
    List<String> terms = const [],
  }) async {
    final text = await _run(
      () => _channel.invokeMethod<String>('transcribe', {
        'path': path,
        'locale': locale,
        'terms': terms,
      }),
    );
    return text ?? '';
  }

  Future<T?> _run<T>(Future<T?> Function() call) async {
    try {
      return await call();
    } on PlatformException catch (e) {
      throw SystemSpeechException(e.code);
    }
  }
}
