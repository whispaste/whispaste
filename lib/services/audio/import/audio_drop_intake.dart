import 'dart:io';

import 'package:path/path.dart' as p;

import 'pcm_decoder.dart';

/// Why a dropped path is not queued.
enum AudioDropRejection {
  folder,
  notFound,
  notRegularFile,
  reservedName,
  tooLarge,
  unsupportedFormat,
}

class AudioDropRejected {
  const AudioDropRejected(this.path, this.reason);

  final String path;
  final AudioDropRejection reason;
}

/// The dropped paths sorted into files for the import queue and refusals.
class AudioDropSplit {
  const AudioDropSplit({required this.accepted, required this.rejected});

  final List<String> accepted;
  final List<AudioDropRejected> rejected;
}

/// What a path points to, judged without opening it.
enum ImportSourceKind {
  regularFile,
  directory,
  notFound,
  notRegularFile,
  reservedName,
}

const _reservedDeviceNames = {
  'CON', 'PRN', 'AUX', 'NUL', 'CONIN\$', 'CONOUT\$', //
  'COM0',
  'COM1',
  'COM2',
  'COM3',
  'COM4',
  'COM5',
  'COM6',
  'COM7',
  'COM8',
  'COM9',
  'COM\u00b9', 'COM\u00b2', 'COM\u00b3', // superscript digits 1-3
  'LPT0',
  'LPT1',
  'LPT2',
  'LPT3',
  'LPT4',
  'LPT5',
  'LPT6',
  'LPT7',
  'LPT8',
  'LPT9',
  'LPT\u00b9', 'LPT\u00b2', 'LPT\u00b3',
};

/// Device namespaces: `\\.\`, `\\?\` and the NT form `\??\`, also with
/// forward slashes. A path under them addresses a device whatever its last
/// component looks like.
bool _isDeviceNamespace(String path) {
  return path.startsWith(r'\\.\') ||
      path.startsWith(r'\\?\') ||
      path.startsWith(r'\??\') ||
      path.startsWith('//./') ||
      path.startsWith('//?/') ||
      path.startsWith('//??/');
}

/// True for names Windows maps to devices (CON, NUL, COM1, lpt9.mp3 ...),
/// whatever the extension and letter case, and for paths in the Windows device
/// namespaces. Such a name must never be opened: on Windows it refers to a
/// device, not to a file. Checked on every platform so that a file copied from
/// Windows is refused the same way.
bool isReservedDeviceName(String path) {
  if (_isDeviceNamespace(path)) return true;
  final base = p.basename(path);
  // The name ends at the first '.' (extension) or ':' (NTFS stream or device
  // suffix): "NUL:", "CON:" and "NUL:stream" all address the device.
  final stem = base.split(RegExp(r'[.:]')).first.trimRight().toUpperCase();
  return _reservedDeviceNames.contains(stem);
}

/// The result of [inspectImportSource].
class ImportSource {
  const ImportSource(this.kind, {this.resolvedPath = '', this.size = 0});

  final ImportSourceKind kind;

  /// The path with symbolic links resolved. Only set for [regularFile].
  final String resolvedPath;

  /// Size in bytes as reported by stat. Only set for [regularFile].
  final int size;
}

/// Classifies [path] without reading it. Runs asynchronously so that the UI
/// isolate never waits on the file system. Symbolic links and aliases are
/// followed once; the target must be a regular file, so a link to a FIFO, a
/// device or a socket is refused, and nothing is opened, so a FIFO cannot
/// block the check.
Future<ImportSource> inspectImportSource(String path) async {
  // Refused by name before any file-system call: a reserved name is a device
  // on Windows, and opening it could block.
  if (isReservedDeviceName(path)) {
    return const ImportSource(ImportSourceKind.reservedName);
  }
  var resolved = path;
  if (await FileSystemEntity.isLink(path)) {
    try {
      resolved = await File(path).resolveSymbolicLinks();
    } on FileSystemException {
      // A dangling link has no target to import.
      return const ImportSource(ImportSourceKind.notFound);
    }
  }
  final stat = await FileStat.stat(resolved);
  switch (stat.type) {
    case FileSystemEntityType.notFound:
      // Dart's stat gives no type for device nodes and sockets; they report
      // notFound, while File.exists is true for them. A missing path is
      // false for both.
      return ImportSource(
        await File(resolved).exists()
            ? ImportSourceKind.notRegularFile
            : ImportSourceKind.notFound,
      );
    case FileSystemEntityType.directory:
      return const ImportSource(ImportSourceKind.directory);
    case FileSystemEntityType.file when _isRegularMode(stat.mode):
      return ImportSource(
        ImportSourceKind.regularFile,
        resolvedPath: resolved,
        size: stat.size,
      );
    default:
      return const ImportSource(ImportSourceKind.notRegularFile);
  }
}

/// POSIX `S_IFREG` check. Windows reports no file-type bits in its mode, so
/// there the type check alone decides.
bool _isRegularMode(int mode) {
  if (Platform.isWindows) return true;
  return (mode & 0xF000) == 0x8000;
}

/// Sorts dropped paths the same way the file picker's type filter does, so a
/// drop and "Transcribe file…" accept exactly the same files. Folders and
/// missing paths are checked first, so a folder named like an audio file is
/// reported as a folder, not as a format error. [extensions] are lower-case
/// and without the dot. Files larger than [maxBytes] are refused here, before
/// anything is copied. Accepted entries keep the path as dropped; the queue
/// resolves it again when the job is created.
Future<AudioDropSplit> splitAudioDrop(
  Iterable<String> paths, {
  required Set<String> extensions,
  int maxBytes = kMaxImportFileBytes,
}) async {
  final accepted = <String>[];
  final rejected = <AudioDropRejected>[];
  for (final path in paths) {
    final source = await inspectImportSource(path);
    switch (source.kind) {
      case ImportSourceKind.directory:
        rejected.add(AudioDropRejected(path, AudioDropRejection.folder));
        continue;
      case ImportSourceKind.notFound:
        rejected.add(AudioDropRejected(path, AudioDropRejection.notFound));
        continue;
      case ImportSourceKind.notRegularFile:
        rejected.add(
          AudioDropRejected(path, AudioDropRejection.notRegularFile),
        );
        continue;
      case ImportSourceKind.reservedName:
        rejected.add(AudioDropRejected(path, AudioDropRejection.reservedName));
        continue;
      case ImportSourceKind.regularFile:
        break;
    }
    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    if (!extensions.contains(ext)) {
      rejected.add(
        AudioDropRejected(path, AudioDropRejection.unsupportedFormat),
      );
      continue;
    }
    if (source.size > maxBytes) {
      rejected.add(AudioDropRejected(path, AudioDropRejection.tooLarge));
      continue;
    }
    accepted.add(path);
  }
  return AudioDropSplit(accepted: accepted, rejected: rejected);
}
