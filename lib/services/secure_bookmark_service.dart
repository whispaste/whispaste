/// Bridge to native macOS security-scoped bookmarks (PRD
/// `settings-portability-vollumfang`, Ticket 04).
///
/// An `NSOpenPanel`/`NSSavePanel` selection (via `package:file_selector`,
/// see `SettingsPortabilityController`) only grants sandbox access to the
/// chosen file for the lifetime of the current process. Without a
/// persisted, app-scoped security-scoped bookmark
/// (`URL.bookmarkData(options: .withSecurityScope)`), the remembered
/// export/import path from Ticket 03 fails with "Operation not permitted"
/// after the app restarts under the Mac App Store sandbox.
///
/// No pub package used deliberately — `macos_secure_bookmarks` is ~3 years
/// unpublished, has low pub points, and pulls in `logging_appenders`. See
/// `AutostartHost.swift`'s docstring for the established precedent of
/// calling Apple's own framework directly instead of vendoring a
/// third-party dependency for a narrow, well-documented API.
///
/// Windows/Linux (and the macOS direct-download build, which runs with
/// `app-sandbox=false`): [isSupported] is `false`, every method is a no-op
/// returning a "no bookmark available" result — never an error. Callers
/// must treat that identically to any other bookmark failure: fall back to
/// the Ticket 03 dialog-based flow, never surface a toast for it.
library;

import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../core/logging/app_logger.dart';

final _log = AppLogger('SecureBookmark');

/// Result of resolving a stored bookmark back to a filesystem path.
class BookmarkResolution {
  const BookmarkResolution({required this.path, required this.isStale});

  /// The resolved absolute path. May differ from the path that was stored
  /// alongside the bookmark if the file was moved or renamed since.
  final String path;

  /// `true` when the bookmark data is stale and should be recreated from
  /// [path] — the resolution still succeeded, this is not a failure.
  final bool isStale;
}

class SecureBookmarkService {
  const SecureBookmarkService();

  static const _channel = MethodChannel('com.whispaste.secure_bookmark');

  bool get isSupported => Platform.isMacOS;

  /// Creates a security-scoped bookmark for [path]. The caller must
  /// currently have sandbox access to [path] (e.g. immediately after an
  /// `NSOpenPanel`/`NSSavePanel` selection, or while an access session
  /// started via [startAccess] is still open) — otherwise bookmark creation
  /// itself fails and this returns `null`.
  Future<String?> create(String path) async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<String>('create', {'path': path});
    } on PlatformException catch (e) {
      _log.warning('create($path) failed: $e');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Resolves [bookmark] back to a path without starting an access session.
  /// Returns `null` if the bookmark data is invalid or can no longer be
  /// resolved at all (not the same as [BookmarkResolution.isStale], which
  /// is a successful-but-outdated resolution).
  Future<BookmarkResolution?> resolve(String bookmark) async {
    if (!isSupported || bookmark.isEmpty) return null;
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'resolve',
        {'bookmark': bookmark},
      );
      final path = raw?['path'];
      final isStale = raw?['isStale'];
      if (path is! String || isStale is! bool) return null;
      return BookmarkResolution(path: path, isStale: isStale);
    } on PlatformException catch (e) {
      _log.warning('resolve failed: $e');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Starts a `startAccessingSecurityScopedResource()` session for
  /// [bookmark]. Returns `true` on success — every successful call must be
  /// balanced by exactly one [stopAccess] call for the same [bookmark],
  /// even if the subsequent file operation fails.
  Future<bool> startAccess(String bookmark) async {
    if (!isSupported || bookmark.isEmpty) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('startAccess', {
        'bookmark': bookmark,
      });
      return ok ?? false;
    } on PlatformException catch (e) {
      _log.warning('startAccess failed: $e');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Ends the access session started by a preceding successful
  /// [startAccess] call for the same [bookmark]. A call without a matching
  /// active session is a safe no-op.
  Future<void> stopAccess(String bookmark) async {
    if (!isSupported || bookmark.isEmpty) return;
    try {
      await _channel.invokeMethod<void>('stopAccess', {'bookmark': bookmark});
    } on PlatformException catch (e) {
      _log.warning('stopAccess failed: $e');
    } on MissingPluginException catch (e) {
      _log.debug('stopAccess: no host to balance ($e)');
    }
  }
}
