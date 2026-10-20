/// Metadata stripping of note images (WP-31a): GPS and other embedded metadata
/// is removed without decoding the pixels, and the result still decodes.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/notes/data/note_image_inspector.dart';
import 'package:whispaste/features/notes/data/note_image_metadata.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/notes/$name').readAsBytesSync();

Uint8List _ascii(String s) => Uint8List.fromList(s.codeUnits);

Uint8List _concat(List<Uint8List> parts) {
  final b = BytesBuilder(copy: false);
  for (final p in parts) {
    b.add(p);
  }
  return b.toBytes();
}

int _indexOf(Uint8List haystack, String needle) {
  final n = needle.codeUnits;
  outer:
  for (var i = 0; i + n.length <= haystack.length; i++) {
    for (var j = 0; j < n.length; j++) {
      if (haystack[i + j] != n[j]) continue outer;
    }
    return i;
  }
  return -1;
}

bool _contains(Uint8List haystack, String needle) =>
    _indexOf(haystack, needle) >= 0;

final Uint8List _gpsPayload = _ascii('Exif\x00\x00GPS 52.5200N 13.4050E');

/// Decodes [bytes] with Flutter's own codec. A structural break that the
/// header check would miss still shows up here.
Future<void> _expectDecodes(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  expect(frame.image.width, greaterThan(0));
  frame.image.dispose();
  codec.dispose();
}

void _expectNoMetadata(Uint8List out) {
  for (final forbidden in ['Exif', 'EXIF', 'GPS', 'XMP', 'secret']) {
    expect(
      _contains(out, forbidden),
      isFalse,
      reason: '"$forbidden" must not survive stripping',
    );
  }
}

// ── JPEG ──────────────────────────────────────────────────────────────────

Uint8List _jpegWithGps(Uint8List base) {
  // Insert APP1 (Exif) and COM right after SOI.
  final app1Length = 2 + _gpsPayload.length;
  final app1 = _concat([
    Uint8List.fromList([0xFF, 0xE1, app1Length >> 8, app1Length & 0xFF]),
    _gpsPayload,
  ]);
  final comment = _ascii('secret note');
  final comLength = 2 + comment.length;
  final com = _concat([
    Uint8List.fromList([0xFF, 0xFE, comLength >> 8, comLength & 0xFF]),
    comment,
  ]);
  return _concat([base.sublist(0, 2), app1, com, base.sublist(2)]);
}

// ── PNG ───────────────────────────────────────────────────────────────────

final List<int> _crcTable = List.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final byte in data) {
    c = _crcTable[(c ^ byte) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}

Uint8List _pngChunk(String type, List<int> data) {
  final typeBytes = type.codeUnits;
  final crc = _crc32([...typeBytes, ...data]);
  final length = ByteData(4)..setUint32(0, data.length);
  final out = BytesBuilder(copy: false)
    ..add(length.buffer.asUint8List())
    ..add(typeBytes)
    ..add(data)
    ..add((ByteData(4)..setUint32(0, crc)).buffer.asUint8List());
  return out.toBytes();
}

Uint8List _pngWithMetadata(Uint8List base) {
  final iend = base.length - 12; // the IEND chunk is always 12 bytes
  return _concat([
    base.sublist(0, iend),
    _pngChunk('eXIf', [..._gpsPayload]),
    _pngChunk('tEXt', [...'GPS\x00secret'.codeUnits]),
    _pngChunk('iTXt', [
      ...'XML:com.adobe.xmp\x00\x00\x00\x00\x00XMP secret'.codeUnits,
    ]),
    _pngChunk('tIME', [0x07, 0xE6, 10, 18, 12, 0, 0]),
    base.sublist(iend),
  ]);
}

// ── WebP ──────────────────────────────────────────────────────────────────

Uint8List _riffChunk(String fourcc, Uint8List payload) {
  final size = payload.length;
  final header = ByteData(8)..setUint32(4, size, Endian.little);
  final head = header.buffer.asUint8List();
  head.setAll(0, fourcc.codeUnits);
  final padding = size.isOdd ? Uint8List(1) : Uint8List(0);
  return _concat([head, payload, padding]);
}

Uint8List _webpWithMetadata(Uint8List base) {
  // The base file is a simple-format WebP: one image chunk after the header.
  final image = base.sublist(12);
  final vp8x = Uint8List(10)
    ..[0] =
        0x08 |
        0x04 // EXIF and XMP flags
    // Canvas 16x16 (stored as size minus one), matching the base image.
    ..setAll(4, [15, 0, 0, 15, 0, 0]);
  final body = _concat([
    _riffChunk('VP8X', vp8x),
    _riffChunk('EXIF', _gpsPayload),
    _riffChunk('XMP ', _ascii('<x:xmpmeta>XMP secret</x:xmpmeta>')),
    image,
  ]);
  final riff = ByteData(8)..setUint32(4, body.length + 4, Endian.little);
  return _concat([
    _ascii('RIFF'),
    riff.buffer.asUint8List(4, 4),
    _ascii('WEBP'),
    body,
  ]);
}

// ── GIF ───────────────────────────────────────────────────────────────────

Uint8List _gifSubBlocks(List<int> data) {
  final out = BytesBuilder(copy: false);
  for (var i = 0; i < data.length; i += 255) {
    final end = (i + 255 < data.length) ? i + 255 : data.length;
    out.addByte(end - i);
    out.add(data.sublist(i, end));
  }
  out.addByte(0);
  return out.toBytes();
}

Uint8List _gifWithMetadata(Uint8List base) {
  final trailer = base.length - 1;
  final comment = _concat([
    Uint8List.fromList([0x21, 0xFE]),
    _gifSubBlocks('GPS secret'.codeUnits),
  ]);
  final xmp = _concat([
    Uint8List.fromList([0x21, 0xFF, 11]),
    _ascii('XMP DataXMP'),
    _gifSubBlocks('<x:xmpmeta>XMP secret</x:xmpmeta>'.codeUnits),
  ]);
  final netscape = _concat([
    Uint8List.fromList([0x21, 0xFF, 11]),
    _ascii('NETSCAPE2.0'),
    Uint8List.fromList([3, 1, 0, 0, 0]),
  ]);
  return _concat([
    base.sublist(0, trailer),
    comment,
    xmp,
    netscape,
    base.sublist(trailer),
  ]);
}

/// A JPEG segment: marker, length, payload.
Uint8List _jpegSegment(int marker, List<int> payload) {
  final length = payload.length + 2;
  return Uint8List.fromList([
    0xFF,
    marker,
    length >> 8,
    length & 0xFF,
    ...payload,
  ]);
}

List<int> _le(int value, int bytes) =>
    List.generate(bytes, (k) => (value >> (8 * k)) & 0xFF);

/// An Exif APP1 with a make ("Cam"), a GPS pointer and an orientation entry.
Uint8List _exifApp1({required int orientation}) {
  final entries = <int>[
    ..._le(0x010F, 2),
    ..._le(2, 2),
    ..._le(4, 4),
    0x43,
    0x61,
    0x6D,
    0x00,
    ..._le(0x0112, 2),
    ..._le(3, 2),
    ..._le(1, 4),
    ..._le(orientation, 2),
    0,
    0,
    ..._le(0x8825, 2),
    ..._le(4, 2),
    ..._le(1, 4),
    ..._le(0x20, 4),
  ];
  return _jpegSegment(0xE1, [
    0x45, 0x78, 0x69, 0x66, 0x00, 0x00, // "Exif\0\0"
    0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00, // little-endian TIFF
    ..._le(3, 2), // three entries
    ...entries,
    0x00, 0x00, 0x00, 0x00,
  ]);
}

void main() {
  group('JPEG', () {
    test('drops Exif, XMP-style APP1 and comment segments', () async {
      final input = _jpegWithGps(_fixture('base.jpg'));
      expect(_contains(input, 'GPS'), isTrue, reason: 'fixture carries GPS');

      final out = stripImageMetadata(input, NoteImageType.jpeg);

      _expectNoMetadata(out);
      expect(out.length, lessThan(input.length));
      expect(inspectNoteImage(out).info?.type, NoteImageType.jpeg);
      await _expectDecodes(out);
    });

    test(
      'keeps only the Exif orientation and drops make, GPS and MPF',
      () async {
        final base = _fixture('base.jpg');
        final icc = _ascii('ICC_PROFILE\x00\x01\x01icc-data');
        final input = _concat([
          base.sublist(0, 2), // SOI
          _exifApp1(orientation: 6),
          _jpegSegment(0xE2, _ascii('MPF\x00secondary-gps').toList()),
          _jpegSegment(0xE2, icc.toList()),
          base.sublist(2),
        ]);

        final out = stripImageMetadata(input, NoteImageType.jpeg);

        expect(_contains(out, 'Cam'), isFalse, reason: 'camera make dropped');
        expect(_contains(out, 'MPF'), isFalse, reason: 'MPF dropped');
        expect(_contains(out, 'secondary-gps'), isFalse);
        expect(_contains(out, 'ICC_PROFILE'), isTrue, reason: 'colour kept');
        // The orientation APP1 comes first: its TIFF IFD0 entry value (6) sits
        // at offset 30 of the file.
        expect(out[2], 0xFF);
        expect(out[3], 0xE1);
        expect(out[30], 6);
        expect(out[31], 0);
        expect(inspectNoteImage(out).info?.type, NoteImageType.jpeg);
        await _expectDecodes(out);
      },
    );

    test('an Exif orientation of 1 leaves no APP1 at all', () {
      final base = _fixture('base.jpg');
      final input = _concat([
        base.sublist(0, 2),
        _exifApp1(orientation: 1),
        base.sublist(2),
      ]);

      final out = stripImageMetadata(input, NoteImageType.jpeg);

      expect(_contains(out, 'Exif'), isFalse);
    });

    test('a truncated segment is refused, not written', () {
      final broken = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE1, 0x00, 0x40]);
      expect(
        () => stripImageMetadata(broken, NoteImageType.jpeg),
        throwsA(isA<NoteImageMetadataException>()),
      );
    });
  });

  group('PNG', () {
    test('drops eXIf, tEXt, iTXt and tIME chunks', () async {
      final input = _pngWithMetadata(_fixture('base.png'));
      expect(_contains(input, 'eXIf'), isTrue);

      final out = stripImageMetadata(input, NoteImageType.png);

      _expectNoMetadata(out);
      expect(_contains(out, 'tIME'), isFalse);
      expect(inspectNoteImage(out).info?.type, NoteImageType.png);
      await _expectDecodes(out);
    });
  });

  group('WebP', () {
    test('drops EXIF and XMP chunks and clears the VP8X flags', () async {
      final input = _webpWithMetadata(_fixture('base.webp'));
      expect(_contains(input, 'EXIF'), isTrue);

      final out = stripImageMetadata(input, NoteImageType.webp);

      _expectNoMetadata(out);
      final riffSize = ByteData.sublistView(out).getUint32(4, Endian.little);
      expect(riffSize, out.length - 8, reason: 'RIFF size matches the file');
      final vp8x = _indexOf(out, 'VP8X');
      expect(vp8x, greaterThan(0));
      expect(out[vp8x + 8] & (0x08 | 0x04), 0, reason: 'EXIF/XMP flags off');
      expect(inspectNoteImage(out).info?.type, NoteImageType.webp);
      await _expectDecodes(out);
    });
  });

  group('GIF', () {
    test('drops comment and XMP extensions, keeps NETSCAPE2.0', () async {
      final input = _gifWithMetadata(_fixture('base.gif'));
      expect(_contains(input, 'GPS secret'), isTrue);

      final out = stripImageMetadata(input, NoteImageType.gif);

      _expectNoMetadata(out);
      expect(
        _contains(out, 'NETSCAPE2.0'),
        isTrue,
        reason: 'animation loop count is kept',
      );
      expect(inspectNoteImage(out).info?.type, NoteImageType.gif);
      await _expectDecodes(out);
    });
  });
}
