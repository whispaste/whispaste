/// Measuring and emptying the three storage areas of the overview. Measuring
/// walks the folders only while the overview is on screen and keeps the
/// result for a while, so leaving and returning does not walk them again.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/overview/storage_usage.dart';
import 'path_service.dart';

/// Bytes of all regular files below [path]. `0` when the folder does not
/// exist; `null` when anything below it cannot be read, because the sum would
/// then be a guess. Symbolic links are not followed.
Future<int?> directoryBytes(String path) async {
  final dir = Directory(path);
  try {
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) total += (await entity.stat()).size;
    }
    return total;
  } on FileSystemException {
    return null;
  }
}

/// Sum of [directoryBytes] over several folders; `null` if any is unreadable.
Future<int?> _sumBytes(List<String> paths) async {
  var total = 0;
  for (final path in paths) {
    final bytes = await directoryBytes(path);
    if (bytes == null) return null;
    total += bytes;
  }
  return total;
}

/// Measures the three areas. Models are the speech folder, recordings are the
/// user audio folders, the cache is [storageCacheDirs].
Future<StorageSizes> measureStorage() async {
  final cache = storageCacheDirs(appDataDir());
  return StorageSizes(
    models: await _sumBytes([sttDir()]),
    recordings: await _sumBytes(userAudioDirectories()),
    cache: await _sumBytes(cache),
  );
}

/// Empties the cache folders. Missing folders are fine; any other failure is
/// thrown, so the caller can show it.
Future<void> clearStorageCache() async {
  for (final path in storageCacheDirs(appDataDir())) {
    final dir = Directory(path);
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

/// Keeps one measurement for [ttl]. Concurrent reads share one walk.
class StorageUsageCache {
  StorageUsageCache({
    required this.measure,
    DateTime Function()? now,
    this.ttl = const Duration(minutes: 10),
  }) : _now = now ?? DateTime.now;

  final Future<StorageSizes> Function() measure;
  final DateTime Function() _now;
  final Duration ttl;

  StorageSizes? _value;
  DateTime? _at;
  Future<StorageSizes>? _pending;

  /// The sizes: from memory while fresh, otherwise measured again.
  Future<StorageSizes> read({bool force = false}) {
    final value = _value;
    final at = _at;
    if (!force && value != null && at != null && _now().difference(at) < ttl) {
      return Future.value(value);
    }
    return _pending ??= _remeasure();
  }

  /// Forgets the stored sizes, e.g. after the cache was emptied.
  void invalidate() {
    _value = null;
    _at = null;
  }

  Future<StorageSizes> _remeasure() async {
    try {
      final sizes = await measure();
      _value = sizes;
      _at = _now();
      return sizes;
    } finally {
      _pending = null;
    }
  }
}

final storageUsageCacheProvider = Provider<StorageUsageCache>(
  (ref) => StorageUsageCache(measure: measureStorage),
);
