/// Keeps the folders that hold user audio private (POSIX mode 0700).
///
/// Retained recordings, audio waiting for a history save and import copies
/// live under the app-data folder. Without 0700 another local user could read
/// the WAVs wherever that folder is traversable. The check is the same as for
/// the capture folder ([ensurePrivateDir]): a real directory, owned by the
/// current user, set to 0700. Windows relies on the per-user ACL of the
/// app-data folder.
///
/// Unlike the capture folder, a failure never stops anything: these folders
/// hold audio the user chose to keep or a dictation not yet saved. Refusing
/// to write would lose that audio, so the folder is used as it is and a
/// warning names it. A symlink the user set up (for example to move
/// recordings to another disk) keeps working the same way.
library;

import 'dart:io';

import '../../core/logging/app_logger.dart';
import '../path_service.dart';
import 'capture/capture_dir.dart';

final _log = AppLogger('UserAudioDirs');

class UserAudioDirs {
  UserAudioDirs({
    CaptureSystem Function()? system,
    List<String> Function()? directories,
  }) : _system = system ?? CaptureSystem.current,
       _directories = directories ?? userAudioDirectories;

  final CaptureSystem Function() _system;
  final List<String> Function() _directories;

  // Result per folder already checked in this process. A save path calls
  // [ensure] for every recording, and the check spawns `id`, `stat` and
  // `chmod`. A failure is cached too, so its warning appears once.
  final _checked = <String, bool>{};

  /// Creates [path] if needed and makes it private. Returns `false` when it
  /// could not be made private; the folder is then used as it is.
  Future<bool> ensure(String path) async {
    final cached = _checked[path];
    if (cached != null && (_isDirectory(path) || _isLink(path))) {
      return cached;
    }
    try {
      await Directory(path).create(recursive: true);
    } on FileSystemException catch (e) {
      // The caller's own write reports the real error.
      _log.warning('Audio folder could not be created: $path: $e');
      return false;
    }
    return _harden(path);
  }

  /// Tightens every existing user audio folder at startup. Creates none and
  /// never throws.
  Future<void> hardenExisting() async {
    for (final path in _directories()) {
      if (!_isDirectory(path) && !_isLink(path)) continue;
      try {
        await _harden(path);
      } on Exception catch (e) {
        _log.warning('Audio folder check failed: $path: $e');
      }
    }
  }

  Future<bool> _harden(String path) async {
    final private = await ensurePrivateDir(path, _system());
    final firstTime = !_checked.containsKey(path);
    _checked[path] = private;
    if (!private && firstTime) {
      _log.warning(
        'Audio folder is not private (symlink, other owner or chmod failed), '
        'using it as it is: $path',
      );
    }
    return private;
  }

  static bool _isDirectory(String path) =>
      FileSystemEntity.typeSync(path, followLinks: false) ==
      FileSystemEntityType.directory;

  static bool _isLink(String path) =>
      FileSystemEntity.typeSync(path, followLinks: false) ==
      FileSystemEntityType.link;
}

/// The app-wide instance.
final userAudioDirs = UserAudioDirs();
