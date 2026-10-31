/// Finished upload slices of a long recording, kept beside its audio so that a
/// crash or quit mid-transcription loses only the slice in progress.
///
/// The manifest `<audio>.slices` holds the slice texts in order and the audio
/// length they belong to. It is written once per finished slice (never per
/// request, never a copy of the audio), atomically, and it is removed together
/// with its audio. A manifest whose length does not match the audio is ignored,
/// so a changed WAV never reuses another recording's text.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/logging/app_logger.dart';
import '../../core/platform/posix_native.dart';
import 'transcriber_interface.dart';

final _log = AppLogger('SliceManifest');

/// Extension of a slice manifest: `<audio>.slices` sits beside `<audio>.wav`.
const kSliceManifestExtension = '.slices';

/// The finished-slice file of one audio file.
class SliceManifest {
  const SliceManifest(this.path);

  /// The manifest of the audio at [wavPath].
  factory SliceManifest.beside(String wavPath) =>
      SliceManifest(p.setExtension(wavPath, kSliceManifestExtension));

  final String path;

  /// The finished slice texts for audio of [wavLength] bytes, in slice order.
  /// Empty when there is no manifest, it cannot be read, or it was written for
  /// audio of another length.
  Future<List<String>> read(int wavLength) async {
    final file = File(path);
    if (!await file.exists()) return const [];
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (json['wavBytes'] != wavLength) return const [];
      return [
        for (final part in json['parts'] as List<dynamic>) part as String,
      ];
    } on Object catch (e) {
      _log.warning('Ignoring unreadable slice manifest (${e.runtimeType})');
      return const [];
    }
  }

  /// Writes [parts] for audio of [wavLength] bytes: a temporary file, then a
  /// rename, so a crash leaves either the old or the new manifest. Best
  /// effort: a failure only costs the saved progress and is logged.
  Future<void> write(int wavLength, List<String> parts) async {
    final tmp = File('$path.tmp');
    try {
      await tmp.writeAsString(
        jsonEncode({'wavBytes': wavLength, 'parts': parts}),
        flush: true,
      );
      await restrictPrivateFile(tmp.path);
      await tmp.rename(path);
    } on Object catch (e) {
      await _deleteFile(tmp.path);
      _log.warning('Could not keep finished slices (${e.runtimeType})');
    }
  }

  /// Removes the manifest if it exists. Best effort.
  Future<void> delete() async {
    await _deleteFile(path);
  }

  /// Moves the manifest to [dest], replacing any file there. Does nothing when
  /// there is no manifest. If the move fails the source is removed instead:
  /// the text must never stay behind in a folder it does not belong to.
  Future<void> moveTo(String dest) async {
    final file = File(path);
    if (!await file.exists()) return;
    try {
      await file.rename(dest);
    } on Object catch (e) {
      _log.warning('Could not move slice manifest (${e.runtimeType})');
      await _deleteFile(path);
    }
  }

  static Future<void> _deleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on Object catch (e) {
      _log.warning('Could not remove slice manifest (${e.runtimeType})');
    }
  }
}

/// Keeps the manifest of one recording in step with its finished slices.
///
/// Each call receives all finished slice texts so far. The manifest is written
/// only when a new slice has finished since the last write, so a call without
/// progress (the first call of a run, or a resumed run) writes nothing.
class SliceCheckpointWriter {
  SliceCheckpointWriter({
    required this.manifest,
    required this.wavLength,
    required this.persisted,
  });

  final SliceManifest manifest;

  /// Length of the audio the slices belong to.
  final int wavLength;

  /// How many slices the manifest on disk already holds.
  int persisted;

  /// Records the finished slices [parts] of a split upload of [total] slices.
  Future<void> call(List<String> parts, int total) async {
    if (parts.length <= persisted) return;
    await manifest.write(wavLength, parts);
    persisted = parts.length;
  }
}

/// Transcribes [wavBytes] with a resumable [transcriber], picking up the
/// finished slices of [manifestPath] and saving each new one there.
Future<String> transcribeWithSliceManifest(
  ResumableTranscriber transcriber,
  List<int> wavBytes, {
  required String manifestPath,
  String? language,
}) async {
  final manifest = SliceManifest(manifestPath);
  final completed = await manifest.read(wavBytes.length);
  final writer = SliceCheckpointWriter(
    manifest: manifest,
    wavLength: wavBytes.length,
    persisted: completed.length,
  );
  return transcriber.transcribeResumable(
    wavBytes,
    language: language,
    completedParts: completed,
    onSliceDone: writer.call,
  );
}

/// Makes [path] readable by the owner only (0600) on macOS and Linux. Windows
/// has no POSIX modes and is skipped. Best effort: a failure is logged at
/// debug level and the file stays as it is.
Future<void> restrictPrivateFile(String path) async {
  if (Platform.isWindows) return;
  if (!nativeChmod(path, 0x180)) {
    _log.debug('chmod 600 failed');
  }
}
