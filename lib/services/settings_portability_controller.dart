/// Orchestrates the user-facing export/import flow for the settings-
/// portability feature (PRD `settings-portability-vollumfang`, Tickets 03
/// + 04; predecessor: PRD `experience-perf-polish` Cluster 5).
///
/// Mirrors the [HistoryExporter] pattern in
/// `services/history/history_exporter.dart`: a plain class with injectable
/// seams for the collaborators (gather/apply the bundle, resolve the target
/// directory, show a toast) so tests can substitute fakes without touching
/// real platform channels or Riverpod.
///
/// A native save/open file dialog (`package:file_selector` —
/// `NSSavePanel`/`IFileDialog`/GTK `FileChooser`) picks the export/import
/// target. The confirmed path is remembered (via the injected
/// [getExportPath]/[setExportPath]/[getImportPath]/[setImportPath] seams,
/// backed by `AppSettings.portabilityPaths` in production) so later
/// export/import calls reuse it without asking again — until the
/// remembered path turns out to be unusable (file/folder gone, access
/// denied), at which point it is forgotten and the dialog opens again
/// automatically. Cancelling the dialog is not an error: no write, no
/// toast, no state change.
///
/// Under the Mac App Store sandbox, a remembered path alone does not
/// survive an app restart — the `NSOpenPanel`/`NSSavePanel` grant that made
/// it accessible is process-bound. [SecureBookmarkService] (Ticket 04)
/// persists an app-scoped security-scoped bookmark alongside the path so
/// the same location keeps working after relaunch. Every bookmark failure
/// (creation, resolution, access) falls back to the same dialog-based flow
/// Ticket 03 established — never a new error toast.
library;

import 'dart:io' show Directory, FileSystemException;

import 'package:file_selector/file_selector.dart'
    show XTypeGroup, getSaveLocation, openFile;
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../widgets/toast.dart';
import 'secure_bookmark_service.dart';
import 'settings_portability_service.dart';

// ---------------------------------------------------------------------------
// Injectable seams (top-level typedefs)
// ---------------------------------------------------------------------------

/// Gathers the current [SettingsExportBundle] from live app state.
typedef GatherBundleFn = Future<SettingsExportBundle> Function();

/// Applies an imported [SettingsExportBundle] to live app state.
typedef ApplyBundleFn = Future<void> Function(SettingsExportBundle bundle);

/// Directory resolver seam — mirrors `PathResolverFn` in `HistoryExporter`.
/// Used only to seed the dialog's `initialDirectory` before any path has
/// ever been remembered.
typedef PathResolverFn = Future<Directory?> Function();

/// Reads a remembered export/import path or bookmark (`''` when none is
/// remembered yet).
typedef PathGetterFn = Future<String> Function();

/// Persists (or, given `''`, forgets) a remembered export/import path or
/// bookmark in a single call.
typedef PathSetterFn = Future<void> Function(String path);

/// Opens the native save (export) or open (import) file dialog. Returns the
/// chosen path, or `null` if the user cancels.
typedef PickPathFn =
    Future<String?> Function({
      required bool forExport,
      required String suggestedName,
      String? initialDirectory,
    });

/// Toaster seam — shows a [WpToast] of the given [WpToastType].
typedef ToasterFn =
    void Function(BuildContext context, WpToastType type, String message);

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------

/// The suggested export filename pre-filled into the native save dialog.
const String settingsExportFileName = 'whispaste-settings-export.json';

/// File type filter for the export/import dialogs — both `extensions`
/// (Windows/Linux, which filter by extension) and `uniformTypeIdentifiers`
/// (macOS, which filters by UTI) must be set; a group carrying only one of
/// the two silently fails to filter correctly on the platform that reads
/// the other.
const _jsonTypeGroup = XTypeGroup(
  label: 'JSON',
  extensions: ['json'],
  uniformTypeIdentifiers: ['public.json'],
);

/// A resolved export/import target, ready for the file operation.
class _Target {
  const _Target({
    required this.path,
    required this.bookmark,
    required this.freshlyPicked,
  });

  final String path;

  /// The bookmark whose [SecureBookmarkService.startAccess] session is
  /// currently open for this target — `''` when no access session was
  /// started (unsupported platform, no bookmark stored, or a freshly
  /// picked path, which already has implicit dialog-granted access).
  /// Whoever finishes using [path] must call [SecureBookmarkService.stopAccess]
  /// with this exact value if it is non-empty.
  final String bookmark;

  /// `true` when [path] came from a dialog shown during this call, not
  /// from a remembered location — see [SettingsPortabilityController]'s
  /// docstring on the export-bookmark timing trap.
  final bool freshlyPicked;
}

class SettingsPortabilityController {
  const SettingsPortabilityController({
    required this.gather,
    required this.apply,
    required this.getExportPath,
    required this.setExportPath,
    required this.getImportPath,
    required this.setImportPath,
    required this.getExportBookmark,
    required this.setExportBookmark,
    required this.getImportBookmark,
    required this.setImportBookmark,
    this.service = const SettingsPortabilityService(),
    this.bookmarks = const SecureBookmarkService(),
    this.downloadsDirFn = getDownloadsDirectory,
    this.documentsDirFn = getApplicationDocumentsDirectory,
    this.pickPath = _defaultPickPath,
    this.toaster = _defaultToaster,
  });

  final GatherBundleFn gather;
  final ApplyBundleFn apply;

  /// Reads/writes `AppSettings.portabilityPaths.exportPath`.
  final PathGetterFn getExportPath;
  final PathSetterFn setExportPath;

  /// Reads/writes `AppSettings.portabilityPaths.importPath` — deliberately
  /// separate from the export pair, so an export after an import does not
  /// overwrite the file the import just read from.
  final PathGetterFn getImportPath;
  final PathSetterFn setImportPath;

  /// Reads/writes `AppSettings.portabilityPaths.exportBookmark` /
  /// `.importBookmark` — the base64 security-scoped bookmark paired with
  /// the export/import path above. Always empty on non-macOS.
  final PathGetterFn getExportBookmark;
  final PathSetterFn setExportBookmark;
  final PathGetterFn getImportBookmark;
  final PathSetterFn setImportBookmark;

  final SettingsPortabilityService service;
  final SecureBookmarkService bookmarks;
  final PathResolverFn downloadsDirFn;
  final PathResolverFn documentsDirFn;
  final PickPathFn pickPath;
  final ToasterFn toaster;

  /// Resolves the export or import target path: the remembered location if
  /// still usable, otherwise the native dialog. Returns `null` if the user
  /// cancels the dialog — not an error, callers must not show a toast for
  /// it.
  ///
  /// Used directly by the UI to preview the import path in the
  /// destructive-confirm dialog before [import] runs; [export] and [import]
  /// also use it internally as the first step of their own flow. Any
  /// bookmark access session opened while resolving is closed again before
  /// this returns — the actual export/import call re-opens its own.
  Future<String?> resolvePath({required bool forExport}) async {
    final target = await _resolveTarget(forExport: forExport);
    if (target == null) return null;
    if (target.bookmark.isNotEmpty) {
      await bookmarks.stopAccess(target.bookmark);
    }
    return target.path;
  }

  /// Gathers the current bundle and writes it to the resolved export path.
  /// Shows a success or error toast; a cancelled dialog shows neither.
  Future<void> export(BuildContext context) async {
    final SettingsExportBundle bundle;
    try {
      bundle = await gather();
    } catch (e) {
      if (!context.mounted) return;
      toaster(
        context,
        WpToastType.error,
        L10n.of(context).settingsPortabilityExportError(_message(e)),
      );
      return;
    }
    if (!context.mounted) return;

    await _runFileOp(
      context: context,
      forExport: true,
      attempt: (path) => service.exportToFile(path, bundle),
      onSuccess: (path) =>
          L10n.of(context).settingsPortabilityExportSuccess(path),
      onError: (e) =>
          L10n.of(context).settingsPortabilityExportError(_message(e)),
    );
  }

  /// Reads the bundle from the resolved import path and applies it via
  /// [apply]. Shows a success or error toast; a cancelled dialog shows
  /// neither.
  Future<void> import(BuildContext context) async {
    await _runFileOp(
      context: context,
      forExport: false,
      attempt: (path) async {
        final bundle = await service.importFromFile(path);
        await apply(bundle);
      },
      onSuccess: (path) =>
          L10n.of(context).settingsPortabilityImportSuccess(path),
      // A missing file at the *freshly re-prompted* path (i.e. the file
      // vanished again in the instant between picking it and reading it) is
      // the one case this dedicated, friendlier message still exists for —
      // any ordinary "the remembered path is stale" case is already caught
      // and silently retried by `_runFileOp` below, never reaching a toast.
      onError: (e) => e is SettingsImportFileNotFoundException
          ? L10n.of(context).settingsPortabilityImportNotFound(e.path)
          : L10n.of(context).settingsPortabilityImportError(_message(e)),
    );
  }

  /// Shared export/import lifecycle: resolve a target (remembered or via
  /// dialog), attempt the file operation, and on a path-availability
  /// failure — the remembered path's file/folder disappeared, permissions
  /// changed, a volume was unmounted — forget it and retry exactly once
  /// against a freshly picked target. A dialog cancellation at any point
  /// ends the operation silently (no write, no toast).
  Future<void> _runFileOp({
    required BuildContext context,
    required bool forExport,
    required Future<void> Function(String path) attempt,
    required String Function(String path) onSuccess,
    required String Function(Object error) onError,
  }) async {
    final target = await _resolveTarget(forExport: forExport);
    if (target == null) return;

    final error = await _attemptWithTarget(target, attempt);
    if (error == null) {
      await _afterSuccessfulWrite(forExport: forExport, target: target);
      if (!context.mounted) return;
      toaster(context, WpToastType.success, onSuccess(target.path));
      return;
    }

    final isPathUnusable =
        error is FileSystemException ||
        error is SettingsImportFileNotFoundException;
    if (!isPathUnusable) {
      if (!context.mounted) return;
      toaster(context, WpToastType.error, onError(error));
      return;
    }

    await _forgetLocation(forExport: forExport);
    final retryTarget = await _promptFreshTarget(
      forExport: forExport,
      previousPath: target.path,
    );
    if (retryTarget == null) return;

    final retryError = await _attemptWithTarget(retryTarget, attempt);
    if (retryError != null) {
      if (!context.mounted) return;
      toaster(context, WpToastType.error, onError(retryError));
      return;
    }
    await _afterSuccessfulWrite(forExport: forExport, target: retryTarget);
    if (!context.mounted) return;
    toaster(context, WpToastType.success, onSuccess(retryTarget.path));
  }

  /// Resolves the export or import target: the remembered location if
  /// still usable (bookmark resolved and access granted, or — pre-Ticket-04
  /// / non-macOS — simply a remembered path with no bookmark to check),
  /// otherwise a freshly picked one via the dialog. Returns `null` only if
  /// the user cancels the dialog.
  Future<_Target?> _resolveTarget({required bool forExport}) async {
    final rememberedPath = await (forExport ? getExportPath : getImportPath)();
    if (rememberedPath.isEmpty) {
      return _promptFreshTarget(forExport: forExport, previousPath: null);
    }

    final rememberedBookmark = await (forExport
        ? getExportBookmark
        : getImportBookmark)();
    final target = await _resolveRememberedTarget(
      forExport: forExport,
      rememberedPath: rememberedPath,
      rememberedBookmark: rememberedBookmark,
    );
    if (target != null) return target;

    // Unusable — forget the stale location, prompt fresh (mirrors Ticket
    // 03's stale-path retry, extended to also drop a stale bookmark).
    await _forgetLocation(forExport: forExport);
    return _promptFreshTarget(
      forExport: forExport,
      previousPath: rememberedPath,
    );
  }

  /// Resolves a remembered [rememberedPath]/[rememberedBookmark] pair to a
  /// usable [_Target]. Returns `null` if the location turns out unusable —
  /// bookmark resolution failed, access could not be started, or a stale
  /// bookmark could not be recreated. On `null`, any access session opened
  /// along the way has already been balanced with a matching `stopAccess`.
  Future<_Target?> _resolveRememberedTarget({
    required bool forExport,
    required String rememberedPath,
    required String rememberedBookmark,
  }) async {
    if (rememberedBookmark.isEmpty || !bookmarks.isSupported) {
      // Pre-Ticket-04 remembered path, prior bookmark failure, or a
      // platform without the sandbox/bookmark concept — Ticket 03 behaviour.
      return _Target(path: rememberedPath, bookmark: '', freshlyPicked: false);
    }

    final resolution = await bookmarks.resolve(rememberedBookmark);
    if (resolution == null) return null;

    final started = await bookmarks.startAccess(rememberedBookmark);
    if (!started) return null;

    if (resolution.isStale) {
      final fresh = await bookmarks.create(resolution.path);
      if (fresh == null) {
        await bookmarks.stopAccess(rememberedBookmark);
        return null;
      }
      await (forExport ? setExportBookmark : setImportBookmark)(fresh);
    }

    if (resolution.path != rememberedPath) {
      await (forExport ? setExportPath : setImportPath)(resolution.path);
    }

    return _Target(
      path: resolution.path,
      bookmark: rememberedBookmark,
      freshlyPicked: false,
    );
  }

  /// Opens the native dialog and, on a successful pick, persists the
  /// result. For import, the picked file already exists, so its bookmark
  /// is created immediately — for export, the picked path in most cases
  /// does not exist yet, so its bookmark can only be created after the
  /// first successful write (see [_afterSuccessfulWrite]). Returns `null`
  /// if the user cancels — the caller must treat that as a silent no-op.
  Future<_Target?> _promptFreshTarget({
    required bool forExport,
    required String? previousPath,
  }) async {
    final initialDirectory = previousPath != null && previousPath.isNotEmpty
        ? p.dirname(previousPath)
        : await _defaultDirectory();
    final picked = await pickPath(
      forExport: forExport,
      suggestedName: settingsExportFileName,
      initialDirectory: initialDirectory,
    );
    if (picked == null) return null;
    await (forExport ? setExportPath : setImportPath)(picked);

    if (!forExport && bookmarks.isSupported) {
      final bookmark = await bookmarks.create(picked);
      if (bookmark != null) {
        await setImportBookmark(bookmark);
      }
    }

    return _Target(path: picked, bookmark: '', freshlyPicked: true);
  }

  /// Runs [attempt] against [target.path], guaranteeing a balanced
  /// [SecureBookmarkService.stopAccess] if [target] carries an open access
  /// session. Returns `null` on success, the caught error otherwise.
  Future<Object?> _attemptWithTarget(
    _Target target,
    Future<void> Function(String path) attempt,
  ) async {
    try {
      await attempt(target.path);
      return null;
    } catch (e) {
      return e;
    } finally {
      if (target.bookmark.isNotEmpty) {
        await bookmarks.stopAccess(target.bookmark);
      }
    }
  }

  /// The export-side half of the bookmark-creation trap this ticket is
  /// named after: a freshly picked *export* path usually does not exist
  /// yet when the dialog closes, so `bookmarkData` cannot be created then —
  /// only after this first write has confirmed the file exists, while the
  /// dialog's Powerbox-granted access is still active in this process. A
  /// freshly picked *import* path already got its bookmark at pick time
  /// (see [_promptFreshTarget]); a remembered target already has one.
  Future<void> _afterSuccessfulWrite({
    required bool forExport,
    required _Target target,
  }) async {
    if (!forExport || !target.freshlyPicked || !bookmarks.isSupported) return;
    final bookmark = await bookmarks.create(target.path);
    if (bookmark != null) {
      await setExportBookmark(bookmark);
    }
  }

  /// Forgets both the path and the bookmark for the given direction in one
  /// place, so the two never fall out of sync.
  Future<void> _forgetLocation({required bool forExport}) async {
    await (forExport ? setExportPath : setImportPath)('');
    await (forExport ? setExportBookmark : setImportBookmark)('');
  }

  /// Falls back to Downloads, then Documents — same fallback order
  /// `resolvePath()` used before the dialog existed.
  Future<String> _defaultDirectory() async {
    final dir = await downloadsDirFn() ?? await documentsDirFn();
    return dir?.path ?? '.';
  }

  /// Best-effort extraction of a human-readable message from [error].
  static String _message(Object error) {
    if (error is SettingsImportFormatException) return error.message;
    if (error is Exception) {
      final s = error.toString();
      const prefix = 'Exception: ';
      if (s.startsWith(prefix)) return s.substring(prefix.length);
      return s;
    }
    return error.toString();
  }
}

Future<String?> _defaultPickPath({
  required bool forExport,
  required String suggestedName,
  String? initialDirectory,
}) async {
  if (forExport) {
    final location = await getSaveLocation(
      acceptedTypeGroups: const [_jsonTypeGroup],
      initialDirectory: initialDirectory,
      suggestedName: suggestedName,
    );
    return location?.path;
  }
  final file = await openFile(
    acceptedTypeGroups: const [_jsonTypeGroup],
    initialDirectory: initialDirectory,
  );
  return file?.path;
}

void _defaultToaster(BuildContext context, WpToastType type, String message) {
  WpToast.show(context, message: message, type: type);
}
