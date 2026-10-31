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

/// How long "the system knows no such app" is believed before asking again,
/// so an app installed later still gets its icon.
const Duration appIdentityMissRetry = Duration(days: 7);

/// How long one system lookup may take before the row keeps its fallback.
const Duration appIdentityLookupTimeout = Duration(seconds: 5);

/// What the rows show for one target app.
class AppIdentity {
  const AppIdentity({
    required this.name,
    required this.category,
    this.iconPath,
  });

  /// Readable name: the system's display name, else [cleanAppName].
  final String name;

  /// Tile shown when [iconPath] is null.
  final AppCategory category;

  /// The cached system icon (PNG), null when the system has none.
  final String? iconPath;
}

/// The system's answer for one app; both parts are optional.
class NativeAppInfo {
  const NativeAppInfo({this.name, this.iconPng});

  /// Parses the channel reply `{name: String?, icon: Uint8List?}`. Empty
  /// values count as missing; a reply with neither part is null.
  static NativeAppInfo? fromMap(Map<Object?, Object?>? map) {
    if (map == null) return null;
    final rawName = map['name'];
    final rawIcon = map['icon'];
    final name = rawName is String && rawName.trim().isNotEmpty
        ? rawName.trim()
        : null;
    final icon = rawIcon is Uint8List && rawIcon.isNotEmpty ? rawIcon : null;
    if (name == null && icon == null) return null;
    return NativeAppInfo(name: name, iconPng: icon);
  }

  final String? name;
  final Uint8List? iconPng;
}

/// Asks the system for name and icon of [identifier] at [size] pixels. Null
/// means the system answered and knows no such app; a throw means there was
/// no answer (host missing, failed or too slow).
typedef NativeAppLookup =
    Future<NativeAppInfo?> Function(String identifier, int size);

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
  const _CacheEntry({this.name, this.icon, required this.checkedAt});

  factory _CacheEntry.fromJson(Map<String, Object?> json) => _CacheEntry(
    name: json['name'] as String?,
    icon: json['icon'] as String?,
    checkedAt: DateTime.fromMillisecondsSinceEpoch(
      (json['at'] as num?)?.toInt() ?? 0,
    ),
  );

  final String? name;

  /// File name inside the cache folder.
  final String? icon;
  final DateTime checkedAt;

  bool get found => name != null || icon != null;

  Map<String, Object?> toJson() => {
    if (name != null) 'name': name,
    if (icon != null) 'icon': icon,
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
    final index = await _loadIndex();
    final cached = index[id];
    if (cached != null &&
        (cached.found ||
            _now().difference(cached.checkedAt) < appIdentityMissRetry)) {
      return _identityFrom(id, cached);
    }
    if (_unanswered.contains(id)) return fallbackAppIdentity(id);

    final NativeAppInfo? info;
    try {
      info = await _lookup(
        id,
        appIconPixelSize,
      ).timeout(appIdentityLookupTimeout);
    } catch (e) {
      // No answer is not "no such app": caching it would hide the icon for
      // a week once the host works. Ask again in the next session.
      _log.info('App lookup got no answer for one target', e);
      _unanswered.add(id);
      return fallbackAppIdentity(id);
    }

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

    final entry = _CacheEntry(
      name: info?.name,
      icon: iconFile,
      checkedAt: _now(),
    );
    index[id] = entry;
    await _saveIndex(index);
    return _identityFrom(id, entry);
  }

  AppIdentity _identityFrom(String id, _CacheEntry entry) {
    final icon = entry.icon == null ? null : p.join(directory, entry.icon);
    return AppIdentity(
      name: entry.name ?? cleanAppName(id),
      category: appCategoryFor(id),
      iconPath: icon != null && File(icon).existsSync() ? icon : null,
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

  Future<void> _saveIndex(Map<String, _CacheEntry> index) async {
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
    _index = {};
    _indexLoad = null;
    _unanswered.clear();
    final root = Directory(directory);
    if (await root.exists()) await root.delete(recursive: true);
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

  static Future<NativeAppInfo?> lookup(String identifier, int size) async {
    final reply = await _channel.invokeMapMethod<Object?, Object?>(
      'resolveApp',
      {'id': identifier, 'size': size},
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
