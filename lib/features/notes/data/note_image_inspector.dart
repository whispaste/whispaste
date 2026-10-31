/// Validation of an image before it is stored as a note attachment (WP-31a).
///
/// Works on the file header only: no image codec runs during import, so a
/// hostile file cannot make the app decode a huge bitmap. Accepted formats are
/// PNG, JPEG, GIF and WebP. SVG is refused outright (it can carry script), as
/// is anything whose type cannot be recognised from its first bytes.
library;

import 'dart:typed_data';

enum NoteImageType {
  png('image/png', 'png'),
  jpeg('image/jpeg', 'jpg'),
  gif('image/gif', 'gif'),
  webp('image/webp', 'webp');

  const NoteImageType(this.mimeType, this.extension);

  final String mimeType;
  final String extension;
}

enum NoteImageRejection {
  empty,
  tooLarge,
  svgNotAllowed,
  unsupportedType,
  unreadableHeader,
  dimensionsTooLarge,
  unreadableStructure,
}

class NoteImageInfo {
  const NoteImageInfo({
    required this.type,
    required this.width,
    required this.height,
  });

  final NoteImageType type;
  final int width;
  final int height;
}

class NoteImageCheck {
  const NoteImageCheck.accepted(NoteImageInfo this.info) : rejection = null;
  const NoteImageCheck.rejected(NoteImageRejection this.rejection)
    : info = null;

  final NoteImageInfo? info;
  final NoteImageRejection? rejection;

  bool get isAccepted => info != null;
}

/// Upper limits for one attachment. A 10 MiB file of 8192 px per side is far
/// above what a note needs and still well inside what the image widget decodes.
class NoteImageLimits {
  const NoteImageLimits({
    this.maxBytes = 10 * 1024 * 1024,
    this.maxSide = 8192,
    this.maxPixels = 40 * 1000 * 1000,
  });

  final int maxBytes;
  final int maxSide;
  final int maxPixels;

  static const NoteImageLimits standard = NoteImageLimits();
}

NoteImageCheck inspectNoteImage(
  Uint8List bytes, {
  NoteImageLimits limits = NoteImageLimits.standard,
}) {
  if (bytes.isEmpty) {
    return const NoteImageCheck.rejected(NoteImageRejection.empty);
  }
  if (bytes.length > limits.maxBytes) {
    return const NoteImageCheck.rejected(NoteImageRejection.tooLarge);
  }
  if (_looksLikeSvg(bytes)) {
    return const NoteImageCheck.rejected(NoteImageRejection.svgNotAllowed);
  }

  final NoteImageType? type = _sniffType(bytes);
  if (type == null) {
    return const NoteImageCheck.rejected(NoteImageRejection.unsupportedType);
  }

  final size = switch (type) {
    NoteImageType.png => _pngSize(bytes),
    NoteImageType.gif => _gifSize(bytes),
    NoteImageType.webp => _webpSize(bytes),
    NoteImageType.jpeg => _jpegSize(bytes),
  };
  if (size == null) {
    return const NoteImageCheck.rejected(NoteImageRejection.unreadableHeader);
  }
  final (width, height) = size;
  if (width <= 0 || height <= 0) {
    return const NoteImageCheck.rejected(NoteImageRejection.unreadableHeader);
  }
  if (width > limits.maxSide ||
      height > limits.maxSide ||
      width * height > limits.maxPixels) {
    return const NoteImageCheck.rejected(NoteImageRejection.dimensionsTooLarge);
  }
  return NoteImageCheck.accepted(
    NoteImageInfo(type: type, width: width, height: height),
  );
}

bool _looksLikeSvg(Uint8List bytes) {
  final head = String.fromCharCodes(
    bytes.sublist(0, bytes.length.clamp(0, 512)),
  );
  final trimmed = head.trimLeft().toLowerCase();
  return trimmed.startsWith('<svg') ||
      trimmed.startsWith('<?xml') ||
      trimmed.startsWith('<!doctype svg') ||
      (trimmed.startsWith('<') && trimmed.contains('<svg'));
}

NoteImageType? _sniffType(Uint8List b) {
  for (final type in NoteImageType.values) {
    if (_hasSignature(b, type)) return type;
  }
  return null;
}

bool _hasSignature(Uint8List b, NoteImageType type) => switch (type) {
  NoteImageType.png =>
    b.length >= 8 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47,
  NoteImageType.jpeg =>
    b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF,
  NoteImageType.gif =>
    b.length >= 6 &&
        b[0] == 0x47 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x38,
  NoteImageType.webp =>
    b.length >= 12 && _ascii(b, 0, 'RIFF') && _ascii(b, 8, 'WEBP'),
};

bool _ascii(Uint8List b, int offset, String text) {
  for (var i = 0; i < text.length; i++) {
    if (b[offset + i] != text.codeUnitAt(i)) return false;
  }
  return true;
}

int _u32be(Uint8List b, int o) =>
    (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

int _u16be(Uint8List b, int o) => (b[o] << 8) | b[o + 1];

int _u16le(Uint8List b, int o) => b[o] | (b[o + 1] << 8);

int _u24le(Uint8List b, int o) => b[o] | (b[o + 1] << 8) | (b[o + 2] << 16);

(int, int)? _pngSize(Uint8List b) {
  // IHDR must follow the 8-byte signature: length(4) "IHDR"(4) width height.
  if (b.length < 24 || !_ascii(b, 12, 'IHDR')) return null;
  return (_u32be(b, 16), _u32be(b, 20));
}

(int, int)? _gifSize(Uint8List b) {
  if (b.length < 10) return null;
  return (_u16le(b, 6), _u16le(b, 8));
}

(int, int)? _webpSize(Uint8List b) {
  if (b.length < 30) return null;
  final chunk = String.fromCharCodes(b.sublist(12, 16));
  switch (chunk) {
    case 'VP8 ':
      // Keyframe: 3-byte frame tag, 3-byte start code, then 14-bit sizes.
      return (_u16le(b, 26) & 0x3FFF, _u16le(b, 28) & 0x3FFF);
    case 'VP8L':
      if (b[20] != 0x2F) return null;
      final bits = b[21] | (b[22] << 8) | (b[23] << 16) | (b[24] << 24);
      return ((bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1);
    case 'VP8X':
      return (_u24le(b, 24) + 1, _u24le(b, 27) + 1);
    default:
      return null;
  }
}

(int, int)? _jpegSize(Uint8List b) {
  var i = 2;
  while (i + 4 <= b.length) {
    if (b[i] != 0xFF) return null;
    final marker = b[i + 1];
    if (marker == 0xFF) {
      i++; // fill byte
      continue;
    }
    // Standalone markers without a length field.
    if (marker == 0xD8 ||
        marker == 0x01 ||
        (marker >= 0xD0 && marker <= 0xD7)) {
      i += 2;
      continue;
    }
    if (marker == 0xD9) {
      return null;
    }
    final length = _u16be(b, i + 2);
    final isStartOfFrame =
        marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC;
    if (isStartOfFrame) {
      if (i + 9 > b.length) return null;
      return (_u16be(b, i + 7), _u16be(b, i + 5));
    }
    if (length < 2) {
      return null;
    }
    i += 2 + length;
  }
  return null;
}
