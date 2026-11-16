/// Name and icon of the app a recording was pasted into, for the recording
/// rows (overview, recordings list, detail).
///
/// The database stores only the raw identifier (`dev.warp.Warp-Stable`,
/// `notepad`, `org.gnome.Terminal`). The system knows the readable name and
/// the icon; the native host `com.whispaste.app_identity` asks it. Answers are
/// cached in the app data folder (`app_icons/`: one PNG per app plus
/// `index.json`), never per entry in the database.
///
/// Lookups happen only when a row is shown, never in the hotkey → text path:
/// asking the system for an app bundle or icon theme can take a while.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/logging/app_logger.dart';
import '../path_service.dart';
import 'app_category.dart';

/// Folder below the app data directory that holds the cache.
const String appIconFolderName = 'app_icons';

/// Icon edge requested from the system, in pixels: 2× the largest tile.
const int appIconPixelSize = 64;

/// How long "the system answered and has no icon" is believed before asking
/// again, so an app installed or updated later still gets its icon. Short on
/// purpose: a lookup is cheap, a wrongly remembered miss is a missing icon.
const Duration appIdentityMissRetry = Duration(hours: 6);

/// How long one system lookup may take before the row keeps its fallback.
const Duration appIdentityLookupTimeout = Duration(seconds: 5);

/// What the rows show for one target app.
class AppIdentity {
  const AppIdentity({
    required this.name,
    required this.category,
    this.iconPath,
    this.nameFromSystem = false,
  });

  /// Readable name: the system's display name, else [cleanAppName].
  final String name;

  /// Whether [name] is the system's own display name. A cleaned identifier
  /// can be wrong (Firefox reports `Navigator` on X11), so statements like
  /// "Pasted into …" only use a system name.
  final bool nameFromSystem;

  /// Tile shown when [iconPath] is null.
  final AppCategory category;

  /// The cached system icon (PNG), null when the system has none.
  final String? iconPath;
}

/// The system's answer for one app; every part is optional.
class NativeAppInfo {
  const NativeAppInfo({this.name, this.iconPng, this.path});

  /// Parses the channel reply `{name: String?, icon: Uint8List?, path:
  /// String?}`. Empty values count as missing; a reply with no part is null.
  static NativeAppInfo? fromMap(Map<Object?, Object?>? map) {
    if (map == null) return null;
    final rawName = map['name'];
    final rawIcon = map['icon'];
    final name = rawName is String && rawName.trim().isNotEmpty
        ? rawName.trim()
        : null;
    final icon = rawIcon is Uint8List && rawIcon.isNotEmpty ? rawIcon : null;
    final rawPath = map['path'];
    final path = rawPath is String && rawPath.trim().isNotEmpty
        ? rawPath.trim()
        : null;
    if (name == null && icon == null && path == null) return null;
    return NativeAppInfo(name: name, iconPng: icon, path: path);
  }

  final String? name;
  final Uint8List? iconPng;

  /// Where the system found the app (Windows: the exe), so a later session
  /// can still resolve it after the app is closed. Null on other systems.
  final String? path;
}

/// Asks the system for name and icon of [identifier] at [size] pixels.
/// [knownPath] is the location persisted by an earlier answer. Null means the
/// system answered and knows no such app; a throw means there was no answer
/// (host missing, app not locatable, failed or too slow).
typedef NativeAppLookup =
    Future<NativeAppInfo?> Function(
      String identifier,
      int size,
      String? knownPath,
    );

const _suffixes = [
  '-stable',
  '-beta',
  '-nightly',
  '-insiders',
  '-preview',
  '-server',
  '-desktop',
];

/// A readable name from the raw identifier, for apps the system cannot name:
/// the last segment of a bundle id or app_id, without `.exe`, channel
/// suffixes (`-Stable`) and dashes. `dev.warp.Warp-Stable` → `Warp`,
/// `gnome-terminal-server` → `Gnome terminal`.
String cleanAppName(String identifier) {
  var name = identifier.trim();
  if (name.toLowerCase().endsWith('.exe')) {
    name = name.substring(0, name.length - 4);
  }
  if (name.contains('.') && !name.contains(' ')) {
    final last = name.split('.').last;
    if (last.isNotEmpty) name = last;
  }
  for (var stripped = true; stripped;) {
    stripped = false;
    for (final suffix in _suffixes) {
      final lower = name.toLowerCase();
      if (lower.length > suffix.length && lower.endsWith(suffix)) {
        name = name.substring(0, name.length - suffix.length);
        stripped = true;
      }
    }
  }
  name = name.replaceAll(RegExp(r'[-_]+'), ' ').trim();
  if (name.isEmpty) return identifier.trim();
  if (name == name.toLowerCase()) {
    name = name[0].toUpperCase() + name.substring(1);
  }
  return name;
}

/// The fallback shown before (or instead of) the system's answer.
AppIdentity fallbackAppIdentity(String identifier) => AppIdentity(
  name: cleanAppName(identifier),
  category: appCategoryFor(identifier),
);

/// One cached answer, as stored in `index.json`.
class _CacheEntry {
  const _CacheEntry({this.name, this.icon, this.path, required this.checkedAt});

  factory _CacheEntry.fromJson(Map<String, Object?> json) => _CacheEntry(
    name: json['name'] as String?,
    icon: json['icon'] as String?,
    path: json['path'] as String?,
    checkedAt: DateTime.fromMillisecondsSinceEpoch(
      (json['at'] as num?)?.toInt() ?? 0,
    ),
  );

  final String? name;

  /// File name inside the cache folder.
  final String? icon;

  /// Persisted location of the app (see [NativeAppInfo.path]).
  final String? path;
  final DateTime checkedAt;

  bool get found => name != null || icon != null;

  /// A located app whose answer had no icon (packaged Windows apps before the
  /// shell fallback existed, or an icon that could not be read). Asked again
  /// after [appIdentityMissRetry] so old entries heal; until then the cached
  /// name is shown.
  bool get missingIcon => icon == null && path != null;

  /// Whether the cached answer is believed at [now].
  bool isFresh(DateTime now) =>
      (found && !missingIcon) ||
      now.difference(checkedAt) < appIdentityMissRetry;

  Map<String, Object?> toJson() => {
    if (name != null) 'name': name,
    if (icon != null) 'icon': icon,
    if (path != null) 'path': path,
    'at': checkedAt.millisecondsSinceEpoch,
  };
}

/// Resolves and caches [AppIdentity]s. Memory first, then `index.json`, the
/// system only on a miss; one lookup per app at a time.
class AppIdentityService {
  AppIdentityService({
    required this.directory,
    required this._lookup,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static final _log = AppLogger('AppIdentity');

  /// The cache folder (`<app data>/app_icons`).
  final String directory;
  final NativeAppLookup _lookup;
  final DateTime Function() _now;

  Map<String, _CacheEntry>? _index;
  Future<Map<String, _CacheEntry>>? _indexLoad;

  /// Index writes run one after the other: two writers sharing the temp file
  /// would rename it away from each other and drop an update.
  Future<void> _saves = Future.value();

  /// Counts [clear] calls. A lookup that started before a clear must not
  /// write its app back into the deleted cache.
  var _generation = 0;
  final _inflight = <String, Future<AppIdentity>>{};

  /// Identifiers whose lookup got no answer this session. Kept in memory
  /// only: an app update that brings the host must not inherit them.
  final _unanswered = <String>{};

  /// Name and icon of [identifier]; never throws, falls back to
  /// [fallbackAppIdentity].
  Future<AppIdentity> resolve(String identifier) {
    final id = identifier.trim();
    if (id.isEmpty) return Future.value(fallbackAppIdentity(id));
    // The block body matters: `=> _inflight.remove(id)` would hand
    // whenComplete this very future to wait for, and it never completes.
    return _inflight[id] ??= _resolve(id).whenComplete(() {
      _inflight.remove(id);
    });
  }

  Future<AppIdentity> _resolve(String id) async {
    final generation = _generation;
    final index = await _loadIndex();
    final cached = index[id];
    if (cached != null && cached.isFresh(_now())) {
      return _identityFrom(id, cached);
    }
    if (_unanswered.contains(id)) {
      return cached == null
          ? fallbackAppIdentity(id)
          : _identityFrom(id, cached);
    }

    final NativeAppInfo? info;
    try {
      info = await _lookup(
        id,
        appIconPixelSize,
        cached?.path,
      ).timeout(appIdentityLookupTimeout);
    } catch (e) {
      // No answer is not "no such app": caching it would hide the icon for
      // a week once the host works. Ask again in the next session.
      _log.info('App lookup got no answer for one target', e);
      _unanswered.add(id);
      return cached == null
          ? fallbackAppIdentity(id)
          : _identityFrom(id, cached);
    }

    if (generation != _generation) return fallbackAppIdentity(id);
    String? iconFile;
    final png = info?.iconPng;
    if (png != null) {
      iconFile = '${_fileStem(id)}.png';
      try {
        await Directory(directory).create(recursive: true);
        await File(p.join(directory, iconFile)).writeAsBytes(png, flush: true);
      } catch (e) {
        _log.warning('App icon not cached', e);
        iconFile = null;
      }
    }

    if (generation != _generation) {
      if (iconFile != null) await _deleteIcon(iconFile);
      return fallbackAppIdentity(id);
    }
    final entry = _CacheEntry(
      name: info?.name ?? cached?.name,
      icon: iconFile,
      path: info?.path ?? cached?.path,
      checkedAt: _now(),
    );
    index[id] = entry;
    await _saveIndex();
    return _identityFrom(id, entry);
  }

  AppIdentity _identityFrom(String id, _CacheEntry entry) {
    final icon = entry.icon == null ? null : p.join(directory, entry.icon);
    return AppIdentity(
      name: entry.name ?? cleanAppName(id),
      category: appCategoryFor(id),
      iconPath: icon != null && File(icon).existsSync() ? icon : null,
      nameFromSystem: entry.name != null,
    );
  }

  Future<Map<String, _CacheEntry>> _loadIndex() {
    final loaded = _index;
    if (loaded != null) return Future.value(loaded);
    return _indexLoad ??= _readIndex().then((index) => _index = index);
  }

  Future<Map<String, _CacheEntry>> _readIndex() async {
    final file = File(p.join(directory, 'index.json'));
    try {
      if (!await file.exists()) return {};
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, Object?>) return {};
      return {
        for (final e in json.entries)
          if (e.value is Map<String, Object?>)
            e.key: _CacheEntry.fromJson(e.value! as Map<String, Object?>),
      };
    } catch (e) {
      // A damaged index only costs a fresh lookup per app.
      _log.warning('App icon index unreadable, starting over', e);
      return {};
    }
  }

  /// Queues a write of the index as it stands when the write runs.
  Future<void> _saveIndex() => _saves = _saves.then((_) => _writeIndex());

  Future<void> _writeIndex() async {
    final index = _index;
    if (index == null) return;
    try {
      await Directory(directory).create(recursive: true);
      final tmp = File(p.join(directory, 'index.json.tmp'));
      await tmp.writeAsString(
        jsonEncode({for (final e in index.entries) e.key: e.value.toJson()}),
        flush: true,
      );
      await tmp.rename(p.join(directory, 'index.json'));
    } catch (e) {
      _log.warning('App icon index not saved', e);
    }
  }

  /// Deletes the cache folder and forgets everything in memory. Part of
  /// deleting the recordings: the cache tells which apps were dictated into.
  Future<void> clear() async {
    _generation++;
    _index = {};
    _indexLoad = null;
    _unanswered.clear();
    // A write still queued would recreate the folder after the delete.
    await _saves;
    final root = Directory(directory);
    if (await root.exists()) await root.delete(recursive: true);
  }

  /// Forgets every app not in [identifiers] and deletes its icon. Runs after
  /// entries are deleted for good: the cache must not keep telling which apps
  /// were dictated into once no recording names them.
  Future<void> retainOnly(Set<String> identifiers) async {
    final index = await _loadIndex();
    final gone = [
      for (final id in index.keys)
        if (!identifiers.contains(id)) id,
    ];
    if (gone.isEmpty) return;
    for (final id in gone) {
      final icon = index.remove(id)?.icon;
      if (icon != null) await _deleteIcon(icon);
    }
    await _saveIndex();
  }

  Future<void> _deleteIcon(String icon) async {
    try {
      final file = File(p.join(directory, icon));
      if (await file.exists()) await file.delete();
    } catch (e) {
      _log.warning('App icon not deleted', e);
    }
  }

  /// A file name that is safe on every platform and unique per identifier.
  static String _fileStem(String id) {
    final safe = id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final short = safe.length > 80 ? safe.substring(0, 80) : safe;
    return '${short}_${id.hashCode.toUnsigned(32).toRadixString(16)}';
  }
}

/// Removes the icon cache below [appDataDir]; a missing folder is fine.
Future<void> eraseAppIdentityCache(String appDataDir) async {
  final root = Directory(p.join(appDataDir, appIconFolderName));
  if (await root.exists()) await root.delete(recursive: true);
}

/// The native host. A missing host (an older native build) throws
/// [MissingPluginException], so the service does not cache it as an answer.
class AppIdentityChannel {
  static const _channel = MethodChannel('com.whispaste.app_identity');

  static Future<NativeAppInfo?> lookup(
    String identifier,
    int size,
    String? knownPath,
  ) async {
    final reply = await _channel.invokeMapMethod<Object?, Object?>(
      'resolveApp',
      {'id': identifier, 'size': size, 'path': ?knownPath},
    );
    return NativeAppInfo.fromMap(reply);
  }
}

final appIdentityServiceProvider = Provider<AppIdentityService>(
  (ref) => AppIdentityService(
    directory: p.join(appDataDir(), appIconFolderName),
    lookup: AppIdentityChannel.lookup,
  ),
);

/// Name and icon for one target identifier, resolved when a row asks.
final appIdentityProvider = FutureProvider.family<AppIdentity, String>(
  (ref, identifier) =>
      ref.watch(appIdentityServiceProvider).resolve(identifier),
);
