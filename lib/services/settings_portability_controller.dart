/// Orchestrates the user-facing export/import flow for the settings-
/// portability feature (PRD `experience-perf-polish`, Cluster 5).
///
/// Mirrors the [HistoryExporter] pattern in
/// `services/history/history_exporter.dart`: a plain class with injectable
/// seams for the collaborators (gather/apply the bundle, resolve the target
/// directory, show a toast) so tests can substitute fakes without touching
/// real platform channels or Riverpod. The always-fixed filename
/// (`whispaste-settings-export.json`) is a deliberate minimal choice — no
/// native save/open file dialog is introduced by this feature; the same
/// well-known filename in the user's Downloads (falling back to Documents)
/// folder is used for both directions, matching how `HistoryExporter`
/// already resolves its output directory. Moving the file between devices
/// (cloud sync, USB, etc.) is left to the user.
library;

import 'dart:io' show Directory;

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
typedef PathResolverFn = Future<Directory?> Function();

/// Toaster seam — shows a [WpToast] of the given [WpToastType].
typedef ToasterFn =
    void Function(BuildContext context, WpToastType type, String message);

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------

/// The fixed export/import filename — both directions read/write the same
/// well-known name so no file dialog is required (see library doc above).
const String settingsExportFileName = 'whispaste-settings-export.json';

class SettingsPortabilityController {
  const SettingsPortabilityController({
    required this.gather,
    required this.apply,
    this.service = const SettingsPortabilityService(),
    this.downloadsDirFn = getDownloadsDirectory,
    this.documentsDirFn = getApplicationDocumentsDirectory,
    this.toaster = _defaultToaster,
  });

  final GatherBundleFn gather;
  final ApplyBundleFn apply;
  final SettingsPortabilityService service;
  final PathResolverFn downloadsDirFn;
  final PathResolverFn documentsDirFn;
  final ToasterFn toaster;

  /// Resolves the full path both [export] and [import] operate on.
  Future<String> resolvePath() async {
    final dir = await downloadsDirFn() ?? await documentsDirFn();
    final dirPath = dir?.path ?? '.';
    return p.join(dirPath, settingsExportFileName);
  }

  /// Gathers the current bundle and writes it to [resolvePath]. Shows a
  /// success or error toast.
  Future<void> export(BuildContext context) async {
    final path = await resolvePath();
    try {
      final bundle = await gather();
      await service.exportToFile(path, bundle);
      if (!context.mounted) return;
      toaster(
        context,
        WpToastType.success,
        L10n.of(context).settingsPortabilityExportSuccess(path),
      );
    } catch (e) {
      if (!context.mounted) return;
      toaster(
        context,
        WpToastType.error,
        L10n.of(context).settingsPortabilityExportError(_message(e)),
      );
    }
  }

  /// Reads the bundle from [resolvePath] and applies it via [apply]. Shows a
  /// success or error toast — a missing export file gets a dedicated,
  /// friendlier message.
  Future<void> import(BuildContext context) async {
    final path = await resolvePath();
    try {
      final bundle = await service.importFromFile(path);
      await apply(bundle);
      if (!context.mounted) return;
      toaster(
        context,
        WpToastType.success,
        L10n.of(context).settingsPortabilityImportSuccess(path),
      );
    } catch (e) {
      if (!context.mounted) return;
      final l10n = L10n.of(context);
      final message = e is SettingsImportFileNotFoundException
          ? l10n.settingsPortabilityImportNotFound(path)
          : l10n.settingsPortabilityImportError(_message(e));
      toaster(context, WpToastType.error, message);
    }
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

void _defaultToaster(BuildContext context, WpToastType type, String message) {
  WpToast.show(context, message: message, type: type);
}
