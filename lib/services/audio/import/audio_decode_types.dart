/// Shared decoder contract, independent of platform channels and processes.
library;

/// Container/codec families the import queue recognises by their magic bytes.
enum AudioSourceFormat {
  wav,
  flac,
  mp3,
  m4a,
  mp4,
  matroska,
  mpeg,
  mpegts,
  ogg,
  unknown;

  String get label => switch (this) {
    AudioSourceFormat.wav => 'WAV',
    AudioSourceFormat.flac => 'FLAC',
    AudioSourceFormat.mp3 => 'MP3',
    AudioSourceFormat.m4a => 'M4A/AAC',
    AudioSourceFormat.mp4 => 'MP4/MOV',
    AudioSourceFormat.matroska => 'MKV/WebM',
    AudioSourceFormat.mpeg => 'MPEG',
    AudioSourceFormat.mpegts => 'MPEG-TS',
    AudioSourceFormat.ogg => 'Ogg/Opus',
    AudioSourceFormat.unknown => 'unknown',
  };

  bool get isVideo =>
      this == AudioSourceFormat.mp4 ||
      this == AudioSourceFormat.matroska ||
      this == AudioSourceFormat.mpeg ||
      this == AudioSourceFormat.mpegts;

  /// Formats that need the platform decoder.
  bool get isCompressed =>
      this == AudioSourceFormat.flac ||
      this == AudioSourceFormat.mp3 ||
      this == AudioSourceFormat.m4a ||
      this == AudioSourceFormat.ogg;
}

/// Thrown when a file cannot be imported on this platform, or its content is
/// not an audio format the decoders know. The message is user-facing.
class AudioFormatUnsupportedException implements Exception {
  const AudioFormatUnsupportedException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thrown when a supported format fails to decode (corrupt file, truncated
/// stream). Distinct from "unsupported" so the queue can offer a retry.
/// The format is known, but no platform decoder for it is installed (for
/// example M4A/AAC on Linux without GStreamer and an AAC decoder).
class AudioDecoderUnavailableException implements Exception {
  const AudioDecoderUnavailableException(this.message);

  final String message;

  @override
  String toString() => 'AudioDecoderUnavailableException: $message';
}

/// The platform decoder could not write its output (disk full, not writable,
/// or an unreadable scratch file). The message is developer-facing.
class AudioDecoderIoException implements Exception {
  const AudioDecoderIoException(this.message);

  final String message;

  @override
  String toString() => 'AudioDecoderIoException: $message';
}

class AudioDecodeFailedException implements Exception {
  const AudioDecodeFailedException(this.message);

  final String message;

  @override
  String toString() => message;
}
