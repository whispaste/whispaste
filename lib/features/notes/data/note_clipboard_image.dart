/// Image paste into the notes editor (Cmd/Ctrl+V). The system clipboard is
/// read through this seam, so tests can replace it.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_clipboard/super_clipboard.dart';

/// Returns the clipboard's image bytes, or null when the clipboard holds text
/// (the ordinary text paste applies), no supported image, or no clipboard.
typedef NoteClipboardImageReader = Future<Uint8List?> Function();

final noteClipboardImageReaderProvider = Provider<NoteClipboardImageReader>(
  (ref) => readImageFromClipboardIfNoText,
);

Future<Uint8List?> readImageFromClipboardIfNoText() async {
  final clipboard = SystemClipboard.instance;
  if (clipboard == null) return null;
  final reader = await clipboard.read();
  if (reader.canProvide(Formats.plainText)) return null;
  for (final format in <FileFormat>[
    Formats.png,
    Formats.jpeg,
    Formats.gif,
    Formats.webp,
  ]) {
    if (!reader.canProvide(format)) continue;
    final bytes = Completer<Uint8List?>();
    final progress = reader.getFile(
      format,
      (file) async {
        try {
          bytes.complete(await file.readAll());
        } catch (_) {
          bytes.complete(null);
        }
      },
      onError: (_) {
        if (!bytes.isCompleted) bytes.complete(null);
      },
    );
    if (progress == null) continue;
    final data = await bytes.future;
    if (data != null) return data;
  }
  return null;
}
