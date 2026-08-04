/// Orchestrates the user-facing export/import flow for the settings-
/// portability feature (PRD `settings-portability-vollumfang`, Ticket 03;
/// predecessor: PRD `experience-perf-polish` Cluster 5).
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
library;

import 'dart:io' show Directory, FileSystemException;

import 'package:file_selector/file_selector.dart'
    show XTypeGroup, getSaveLocation, openFile;
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../widgets/toast.dart';
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

/// Reads the remembered export/import path (`''` when none is remembered
/// yet).
typedef PathGetterFn = Future<String> Function();

/// Persists (or, given `''`, forgets) the remembered export/import path in
/// a single call.
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

class SettingsPortabilityController {
  const SettingsPortabilityController({
    required this.gather,
    required this.apply,
    required this.getExportPath,
    required this.setExportPath,
    required this.getImportPath,
    required this.setImportPath,
    this.service = const SettingsPortabilityService(),
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

  final SettingsPortabilityService service;
  final PathResolverFn downloadsDirFn;
  final PathResolverFn documentsDirFn;
  final PickPathFn pickPath;
  final ToasterFn toaster;

  /// Resolves the export or import target: the remembered path if present,
  /// otherwise the native dialog (a freshly chosen path is persisted before
  /// this returns). Returns `null` if the user cancels the dialog — not an
  /// error, callers must not show a toast for it.
  ///
  /// Used directly by the UI to preview the import path in the
  /// destructive-confirm dialog before [import] runs; [export] and [import]
  /// also use it internally as the first step of their own flow.
  Future<String?> resolvePath({required bool forExport}) async {
    final remembered = await (forExport ? getExportPath : getImportPath)();
    if (remembered.isNotEmpty) return remembered;
    return _promptAndRemember(forExport: forExport, previousPath: null);
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

  /// Shared export/import lifecycle: resolve a path (remembered or via
  /// dialog), attempt the file operation, and on a path-availability
  /// failure — the remembered path's file/folder disappeared, permissions
  /// changed, a volume was unmounted — forget it and retry exactly once
  /// against a freshly picked path. A dialog cancellation at any point ends
  /// the operation silently (no write, no toast).
  Future<void> _runFileOp({
    required BuildContext context,
    required bool forExport,
    required Future<void> Function(String path) attempt,
    required String Function(String path) onSuccess,
    required String Function(Object error) onError,
  }) async {
    final path = await resolvePath(forExport: forExport);
    if (path == null) return;

    try {
      await attempt(path);
    } catch (e) {
      final isPathUnusable =
          e is FileSystemException || e is SettingsImportFileNotFoundException;
      if (!isPathUnusable) {
        if (!context.mounted) return;
        toaster(context, WpToastType.error, onError(e));
        return;
      }

      final stalePath = path;
      await (forExport ? setExportPath : setImportPath)('');
      final retryPath = await _promptAndRemember(
        forExport: forExport,
        previousPath: stalePath,
      );
      if (retryPath == null) return;
      try {
        await attempt(retryPath);
      } catch (e2) {
        if (!context.mounted) return;
        toaster(context, WpToastType.error, onError(e2));
        return;
      }
      if (!context.mounted) return;
      toaster(context, WpToastType.success, onSuccess(retryPath));
      return;
    }

    if (!context.mounted) return;
    toaster(context, WpToastType.success, onSuccess(path));
  }

  /// Opens the native dialog and, on a successful pick, persists the result
  /// via a single [setExportPath]/[setImportPath] call. Returns `null` if
  /// the user cancels — the caller must treat that as a silent no-op.
  Future<String?> _promptAndRemember({
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
    return picked;
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
