/// Header-level image validation for note attachments (WP-31a): type
/// sniffing, dimension parsing, SVG refusal and size caps. Nothing here
/// decodes pixels.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/notes/data/note_image_inspector.dart';

Uint8List _png(int w, int h) {
  final b = Uint8List(64);
  b.setAll(0, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  b.setAll(8, [0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52]);
  final d = ByteData.sublistView(b);
  d.setUint32(16, w);
  d.setUint32(20, h);
  return b;
}

Uint8List _gif(int w, int h) {
  final b = Uint8List(32)..setAll(0, 'GIF89a'.codeUnits);
  final d = ByteData.sublistView(b);
  d.setUint16(6, w, Endian.little);
  d.setUint16(8, h, Endian.little);
  return b;
}

Uint8List _webpVp8x(int w, int h) {
  final b = Uint8List(40)
    ..setAll(0, 'RIFF'.codeUnits)
    ..setAll(8, 'WEBP'.codeUnits)
    ..setAll(12, 'VP8X'.codeUnits);
  b[24] = (w - 1) & 0xFF;
  b[25] = ((w - 1) >> 8) & 0xFF;
  b[26] = ((w - 1) >> 16) & 0xFF;
  b[27] = (h - 1) & 0xFF;
  b[28] = ((h - 1) >> 8) & 0xFF;
  b[29] = ((h - 1) >> 16) & 0xFF;
  return b;
}

Uint8List _jpeg(int w, int h) => Uint8List.fromList([
  0xFF, 0xD8, // SOI
  0xFF, 0xC0, 0x00, 0x11, 0x08, // SOF0, length 17, precision 8
  (h >> 8) & 0xFF, h & 0xFF, // height
  (w >> 8) & 0xFF, w & 0xFF, // width
  ...List.filled(20, 0),
]);

void main() {
  test('accepts a PNG and reads its size from IHDR', () {
    final check = inspectNoteImage(_png(640, 480));
    expect(check.isAccepted, isTrue);
    expect(check.info!.type, NoteImageType.png);
    expect(check.info!.width, 640);
    expect(check.info!.height, 480);
    expect(check.info!.type.extension, 'png');
    expect(check.info!.type.mimeType, 'image/png');
  });

  test('accepts a GIF and reads little-endian dimensions', () {
    final check = inspectNoteImage(_gif(300, 200));
    expect(check.info!.type, NoteImageType.gif);
    expect(check.info!.width, 300);
    expect(check.info!.height, 200);
  });

  test('accepts an extended WebP and reads its canvas size', () {
    final check = inspectNoteImage(_webpVp8x(1024, 768));
    expect(check.info!.type, NoteImageType.webp);
    expect(check.info!.width, 1024);
    expect(check.info!.height, 768);
  });

  test('accepts a JPEG and reads the SOF0 dimensions', () {
    final check = inspectNoteImage(_jpeg(800, 600));
    expect(check.info!.type, NoteImageType.jpeg);
    expect(check.info!.width, 800);
    expect(check.info!.height, 600);
    expect(check.info!.type.extension, 'jpg');
  });

  test('refuses SVG, even when it is disguised as a PNG name', () {
    final svg = Uint8List.fromList(
      '<?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg"></svg>'
          .codeUnits,
    );
    expect(inspectNoteImage(svg).rejection, NoteImageRejection.svgNotAllowed);
  });

  test('refuses an empty file and an oversized file', () {
    expect(inspectNoteImage(Uint8List(0)).rejection, NoteImageRejection.empty);
    final big = _png(10, 10);
    expect(
      inspectNoteImage(
        big,
        limits: const NoteImageLimits(maxBytes: 16),
      ).rejection,
      NoteImageRejection.tooLarge,
    );
  });

  test('refuses dimensions above the side and pixel caps', () {
    expect(
      inspectNoteImage(_png(9000, 10)).rejection,
      NoteImageRejection.dimensionsTooLarge,
    );
    expect(
      inspectNoteImage(_png(8000, 8000)).rejection,
      NoteImageRejection.dimensionsTooLarge,
    );
  });

  test('refuses unknown formats and truncated headers', () {
    expect(
      inspectNoteImage(
        Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9]),
      ).rejection,
      NoteImageRejection.unsupportedType,
    );
    final truncated = Uint8List.fromList([
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
    ]);
    expect(
      inspectNoteImage(truncated).rejection,
      NoteImageRejection.unreadableHeader,
    );
  });
}
