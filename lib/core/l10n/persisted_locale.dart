import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../services/path_service.dart' as paths;
import '../logging/app_logger.dart';

final _log = AppLogger('PersistedLocale');

/// Overrides [localeMirrorPath] in tests, so a test never touches the real
/// `~/Library/Application Support/WhisPaste` directory.
@visibleForTesting
String? localeMirrorPathOverride;

/// Path of the sidecar file mirroring the persisted `locale` setting.
String localeMirrorPath() =>
    localeMirrorPathOverride ?? p.join(paths.appDataDir(), 'locale');

/// Reads the mirrored locale code, or `null` when there is none.
///
/// Deliberately synchronous and free of any dependency other than `dart:io`:
/// the callers are secondary Flutter engines during `initState`, where a
/// plugin-backed store (`SharedPreferences`) is not available because those
/// engines register no plugins, and where SQLite must not be touched at all
/// (see [writeLocaleMirror]).
String? readLocaleMirror() {
  try {
    final file = File(localeMirrorPath());
    if (!file.existsSync()) return null;
    final code = file.readAsStringSync().trim();
    return code.isEmpty ? null : code;
  } catch (e) {
    // Unreadable mirror is not an error worth surfacing — the caller falls
    // back to its default locale.
    _log.debug('Failed to read locale mirror: $e');
    return null;
  }
}

/// Mirrors [code] next to the database, so secondary engines can resolve the
/// UI language without opening SQLite.
///
/// WHY THIS FILE EXISTS — the alternative crashed the app (2026-09-01,
/// `EXC_BAD_ACCESS` at `0x0` from inside `sqlite3Close`):
///
/// The floating button/overlay, snippet picker and side panel each run in
/// their own Flutter engine, and therefore in their own Dart *isolate group*
/// (ADR 0002). An isolate group resolves its FFI native assets lazily, the
/// first time it calls into one — so a lazily booted engine `dlopen`s
/// `sqlite3.framework/sqlite3` minutes or hours after launch. That path is a
/// symlink (`sqlite3.framework/sqlite3` → `Versions/A/sqlite3`), so dyld
/// cannot match it against the already-loaded image by path string and falls
/// back to comparing the file's identity. If the bundle's binary was replaced
/// in the meantime — a rebuild while the app is still running, or an in-place
/// app update — the identity no longer matches and dyld maps a **second,
/// independent copy of SQLite**, with its own, still zeroed,
/// `sqlite3GlobalConfig`. A `sqlite3*` that then crosses copies dies in
/// `sqlite3Close`, which calls `sqlite3GlobalConfig.mutex.xMutexEnter`
/// through a NULL function pointer.
///
/// Reading one string out of `app_settings` was the only thing that made a
/// secondary engine open — and close — a SQLite connection at all, so mirroring
/// the value into a plain file takes those engines out of that failure mode
/// entirely. It also removes a full drift database construction plus a
/// background-isolate spawn from the hotkey→overlay path.
///
/// Best-effort and idempotent: a write failure leaves the previous mirror in
/// place, and an unchanged value is not rewritten.
void writeLocaleMirror(String? code) {
  // Without an explicit override this resolves to the real
  // `~/Library/Application Support/WhisPaste` — a unit test exercising
  // `writeAppSettings` must not scribble a fixture locale into the user's
  // install. Reads stay unguarded; they are harmless and return null there.
  if (localeMirrorPathOverride == null && _isTestEnvironment) return;
  try {
    final file = File(localeMirrorPath());
    final value = (code ?? '').trim();
    if (value.isEmpty) return;
    if (file.existsSync() && file.readAsStringSync().trim() == value) return;
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(value, flush: true);
  } catch (e) {
    _log.debug('Failed to write locale mirror: $e');
  }
}

/// Same detection [UiThreadWatchdog] uses: `flutter_test` installs this zone
/// value for every test it runs.
bool get _isTestEnvironment => kIsWeb || Zone.current[#test.declarer] != null;
