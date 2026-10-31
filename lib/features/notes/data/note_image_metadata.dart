/// Removes embedded metadata from note images (WP-31a) — GPS positions and
/// camera or author data, which a photo carries in its header.
///
/// This is a structural walk over the file's segments, chunks or blocks. The
/// compressed pixel data is copied byte for byte and never decoded, so the
/// image looks the same and the cost stays linear in the file size.
///
/// Kept per format:
/// - JPEG: everything except APP1 (Exif, XMP), APP13 (IPTC) and COM.
/// - PNG: everything except eXIf, tEXt, zTXt, iTXt and tIME. Kept chunks keep
///   their CRCs, since their bytes do not change.
/// - WebP: everything except EXIF and XMP chunks; the RIFF size and the VP8X
///   EXIF/XMP flags are fixed up to match.
/// - GIF: everything except comment and application extensions, but the
///   NETSCAPE2.0 loop count stays, since animation depends on it.
library;

import 'dart:typed_data';

import 'note_image_inspector.dart';

/// A file whose structure cannot be walked. It is refused, never stored
/// unstripped.
class NoteImageMetadataException implements Exception {
  const NoteImageMetadataException(this.message);

  final String message;

  @override
  String toString() => 'NoteImageMetadataException: $message';
}

/// Returns [bytes] with embedded metadata removed. Throws
/// [NoteImageMetadataException] when the structure is broken.
Uint8List stripImageMetadata(Uint8List bytes, NoteImageType type) {
  return switch (type) {
    NoteImageType.jpeg => _stripJpeg(bytes),
    NoteImageType.png => _stripPng(bytes),
    NoteImageType.webp => _stripWebp(bytes),
    NoteImageType.gif => _stripGif(bytes),
  };
}

Never _broken(String what) => throw NoteImageMetadataException(what);

// ── JPEG ──────────────────────────────────────────────────────────────────

/// Only the segments decoding needs are kept, by whitelist: quantisation,
/// frame, Huffman, restart and scan headers, and the end marker. Everything
/// else is dropped, including the APPn segments that carry GPS, camera data,
/// embedded thumbnails and secondary images (MPF). Two exceptions: the ICC
/// colour profile (APP2) and the Exif orientation, which is kept on its own.
bool _jpegKeptMarker(int marker) =>
    marker == 0xDB || // DQT
    marker == 0xC4 || // DHT
    marker == 0xDD || // DRI
    (marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 && // DHT
        marker != 0xC8 && // JPG (reserved)
        marker != 0xCC); // DAC

Uint8List _stripJpeg(Uint8List b) {
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) {
    _broken('JPEG does not start with SOI');
  }
  final out = BytesBuilder(copy: false)..add([0xFF, 0xD8]);
  var i = 2;
  while (i < b.length) {
    if (b[i] != 0xFF) _broken('expected a marker at $i');
    var m = i + 1;
    while (m < b.length && b[m] == 0xFF) {
      m++; // fill bytes may precede a marker
    }
    if (m >= b.length) _broken('marker cut off');
    final marker = b[m];

    if (marker == 0xD9) {
      out.add([0xFF, 0xD9]);
      return out.toBytes();
    }
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      out.add(b.sublist(i, m + 1)); // standalone marker, no length
      i = m + 1;
      continue;
    }

    final end = m + 1 + _u16be(b, m + 1);
    if (end > b.length) _broken('segment runs past the end');
    if (marker == 0xDA) {
      // Start of scan: the entropy-coded data after the header runs to the
      // end of the file, so it is copied as it is.
      out
        ..add(b.sublist(i, end))
        ..add(b.sublist(end));
      return out.toBytes();
    }
    _addKeptSegment(out, marker, b.sublist(i, end));
    i = end;
  }
  _broken('JPEG has no end of image');
}

/// Writes one header segment to [out] when the privacy whitelist keeps it:
/// the Exif orientation as a minimal APP1, ICC profiles, and decode tables.
void _addKeptSegment(BytesBuilder out, int marker, Uint8List segment) {
  if (marker == 0xE1) {
    final orientation = _exifOrientation(segment);
    if (orientation != null && orientation >= 2 && orientation <= 8) {
      out.add(_orientationApp1(orientation));
    }
    return;
  }
  if (marker == 0xE2) {
    if (_isIccSegment(segment)) out.add(segment);
    return;
  }
  if (_jpegKeptMarker(marker)) out.add(segment);
}

bool _isIccSegment(Uint8List seg) =>
    seg.length >= 18 && _ascii(seg, 4, 12) == 'ICC_PROFILE\u0000';

/// The Exif orientation (tag 0x0112) of an APP1 [seg], or null when the
/// segment is not Exif, has no such tag, or is malformed.
int? _exifOrientation(Uint8List seg) {
  if (seg.length < 20 || _ascii(seg, 4, 6) != 'Exif\u0000\u0000') return null;
  const tiff = 10;
  final order = _ascii(seg, tiff, 2);
  if (order != 'II' && order != 'MM') return null;
  final le = order == 'II';
  final ifdOffset = _uintAt(seg, tiff + 4, 4, le);
  if (ifdOffset < 0) return null;
  final ifd = tiff + ifdOffset;
  final count = _uintAt(seg, ifd, 2, le);
  if (count < 0) return null;
  for (var k = 0; k < count; k++) {
    final entry = ifd + 2 + 12 * k;
    if (_uintAt(seg, entry, 2, le) != 0x0112) continue;
    if (_uintAt(seg, entry + 2, 2, le) != 3) return null; // SHORT
    final value = _uintAt(seg, entry + 8, 2, le);
    return value < 0 ? null : value;
  }
  return null;
}

/// A minimal Exif APP1 that carries only the orientation, so a portrait photo
/// still displays upright. Its TIFF part is a single IFD0 entry.
Uint8List _orientationApp1(int orientation) {
  final payload = <int>[
    0x45, 0x78, 0x69, 0x66, 0x00, 0x00, // "Exif\0\0"
    0x49,
    0x49,
    0x2A,
    0x00,
    0x08,
    0x00,
    0x00,
    0x00, // little-endian TIFF, IFD0 at 8
    0x01, 0x00, // one entry
    0x12,
    0x01,
    0x03,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00, // tag 0x0112, SHORT, count 1
    orientation & 0xFF, orientation >> 8, 0x00, 0x00, // value
    0x00, 0x00, 0x00, 0x00, // no next IFD
  ];
  final length = payload.length + 2;
  return Uint8List.fromList([
    0xFF,
    0xE1,
    length >> 8,
    length & 0xFF,
    ...payload,
  ]);
}

/// Reads an unsigned integer of [n] bytes at [o], or -1 when it lies outside
/// [b].
int _uintAt(Uint8List b, int o, int n, bool le) {
  if (o < 0 || o + n > b.length) return -1;
  var v = 0;
  for (var k = 0; k < n; k++) {
    v = (v << 8) | b[le ? o + n - 1 - k : o + k];
  }
  return v;
}

// ── PNG ───────────────────────────────────────────────────────────────────

const _pngDroppedChunks = {'eXIf', 'tEXt', 'zTXt', 'iTXt', 'tIME'};

Uint8List _stripPng(Uint8List b) {
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (b.length < 8 || !_startsWith(b, signature)) {
    _broken('PNG signature missing');
  }
  final out = BytesBuilder(copy: false)..add(signature);
  var i = 8;
  while (i + 12 <= b.length) {
    final length = _u32be(b, i);
    final end = i + 12 + length;
    if (end > b.length) _broken('PNG chunk runs past the end');
    final type = String.fromCharCodes(b.sublist(i + 4, i + 8));
    if (!_pngDroppedChunks.contains(type)) {
      out.add(b.sublist(i, end));
    }
    i = end;
    if (type == 'IEND') return out.toBytes();
  }
  _broken('PNG has no IEND chunk');
}

// ── WebP ──────────────────────────────────────────────────────────────────

const _vp8xExifFlag = 0x08;
const _vp8xXmpFlag = 0x04;

Uint8List _stripWebp(Uint8List b) {
  if (b.length < 12 || _ascii(b, 0, 4) != 'RIFF' || _ascii(b, 8, 4) != 'WEBP') {
    _broken('WebP RIFF header missing');
  }
  final chunks = <Uint8List>[];
  var i = 12;
  while (i < b.length) {
    if (i + 8 > b.length) _broken('WebP chunk header cut off');
    final fourcc = _ascii(b, i, 4);
    final size = _u32le(b, i + 4);
    final start = i;
    final end = i + 8 + _paddedLength(size);
    if (end > b.length) _broken('WebP chunk runs past the end');
    i = end;
    if (fourcc == 'EXIF' || fourcc == 'XMP ') continue;

    final chunk = Uint8List.fromList(b.sublist(start, end));
    if (fourcc == 'VP8X' && size >= 1) {
      chunk[8] &= ~(_vp8xExifFlag | _vp8xXmpFlag) & 0xFF;
    }
    chunks.add(chunk);
  }

  var bodyLength = 4;
  for (final c in chunks) {
    bodyLength += c.length;
  }
  final out = Uint8List(8 + bodyLength);
  out.setAll(0, 'RIFF'.codeUnits);
  ByteData.sublistView(out).setUint32(4, bodyLength, Endian.little);
  out.setAll(8, 'WEBP'.codeUnits);
  var o = 12;
  for (final c in chunks) {
    out.setAll(o, c);
    o += c.length;
  }
  return out;
}

int _paddedLength(int size) => size + (size.isOdd ? 1 : 0);

// ── GIF ───────────────────────────────────────────────────────────────────

Uint8List _stripGif(Uint8List b) {
  if (b.length < 13 || (_ascii(b, 0, 3) != 'GIF')) {
    _broken('GIF header missing');
  }
  final out = BytesBuilder(copy: false)..add(b.sublist(0, 13));
  var i = 13;
  if (b[10] & 0x80 != 0) {
    i = _skipColorTable(b, i, b[10]);
    out.add(b.sublist(13, i));
  }
  while (i < b.length) {
    final introducer = b[i];
    if (introducer == 0x3B) {
      out.addByte(0x3B);
      return out.toBytes();
    }
    if (introducer == 0x21) {
      if (i + 2 > b.length) _broken('GIF extension cut off');
      final label = b[i + 1];
      final end = _subBlocksEnd(b, i + 2);
      if (_keepGifExtension(b, label, i)) {
        out.add(b.sublist(i, end));
      }
      i = end;
    } else if (introducer == 0x2C) {
      if (i + 10 > b.length) _broken('GIF image descriptor cut off');
      final packed = b[i + 9];
      var j = i + 10;
      if (packed & 0x80 != 0) {
        j = _skipColorTable(b, j, packed);
      }
      j += 1; // LZW minimum code size
      final end = _subBlocksEnd(b, j);
      out.add(b.sublist(i, end));
      i = end;
    } else {
      _broken('unknown GIF block 0x${introducer.toRadixString(16)}');
    }
  }
  _broken('GIF has no trailer');
}

bool _keepGifExtension(Uint8List b, int label, int at) {
  if (label == 0xFE) return false; // comment
  if (label == 0xFF) {
    // Application extension: the 11-byte identifier follows its size byte.
    if (at + 14 > b.length) _broken('GIF application block cut off');
    return _ascii(b, at + 3, 11) == 'NETSCAPE2.0';
  }
  return true;
}

int _skipColorTable(Uint8List b, int at, int packed) {
  final end = at + 3 * (1 << ((packed & 0x07) + 1));
  if (end > b.length) _broken('GIF color table cut off');
  return end;
}

/// Index after the terminating zero-length sub-block that starts at [start].
int _subBlocksEnd(Uint8List b, int start) {
  var j = start;
  while (true) {
    if (j >= b.length) _broken('GIF sub-blocks cut off');
    final size = b[j];
    if (size == 0) return j + 1;
    j += size + 1;
  }
}

// ── byte helpers ─────────────────────────────────────────────────────────

int _u16be(Uint8List b, int o) {
  if (o + 2 > b.length) _broken('length field cut off');
  return (b[o] << 8) | b[o + 1];
}

int _u32be(Uint8List b, int o) =>
    (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

int _u32le(Uint8List b, int o) =>
    b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

String _ascii(Uint8List b, int o, int n) {
  if (o + n > b.length) return '';
  return String.fromCharCodes(b.sublist(o, o + n));
}

bool _startsWith(Uint8List b, List<int> prefix) {
  for (var k = 0; k < prefix.length; k++) {
    if (b[k] != prefix[k]) return false;
  }
  return true;
}
