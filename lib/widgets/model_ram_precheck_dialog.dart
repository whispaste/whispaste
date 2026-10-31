/// The RAM precheck before a local speech model is loaded (decision 9a,
/// 2026-10-25). One shared gate serves every path that chooses a model or an
/// engine: it asks only when the OS reports clearly too little free RAM, and
/// never blocks. "Abbrechen" keeps the current model; "Trotzdem laden" loads.
library;

import 'package:flutter/material.dart';

import '../core/app_navigator.dart' show appNavigatorKey;
import '../core/config/settings_enums.dart' show OnDeviceEngine;
import '../core/config/settings_provider.dart' show AppSettings;
import '../core/l10n/generated/app_localizations.dart';
import '../services/stt/memory_pressure.dart';
import '../services/stt/model_ram_precheck.dart';
import 'dialog.dart';
import 'toast.dart';

/// Returns true when the model may be loaded: the RAM is fine, unknown, or the
/// user chose "Trotzdem laden". Returns false only when the user cancelled a
/// clearly short load.
///
/// [readSnapshot] defaults to [defaultMemorySnapshotReader]; tests inject it.
Future<bool> confirmModelLoadRam({
  required BuildContext context,
  required OnDeviceEngine engine,
  required String modelId,
  Future<MemorySnapshot?> Function()? readSnapshot,
}) async {
  final estimateMB = onDeviceRamEstimateMB(engine: engine, modelId: modelId);
  if (estimateMB == null) return true;
  final snapshot = await (readSnapshot ?? defaultMemorySnapshotReader)();
  if (!ramClearlyShort(estimateMB: estimateMB, snapshot: snapshot)) {
    return true;
  }
  if (!context.mounted) return false;
  final l10n = L10n.of(context);
  return showWpConfirmDialog(
    context: context,
    title: l10n.modelRamPrecheckTitle,
    message: l10n.modelRamPrecheckBody(
      estimateMB.toString(),
      snapshot!.availableMB.toString(),
    ),
    confirmLabel: l10n.modelRamPrecheckContinue,
    cancelLabel: l10n.actionCancel,
  );
}

/// The gate for a settings change that leads to a model load. [settings] is
/// the state after the change. Cloud providers never load a local model, and
/// [loads] is false when the target model is not on disk yet (nothing loads).
/// Shared by the settings, dock, tray, onboarding and benchmark paths.
Future<bool> confirmSttSettingsRam({
  required BuildContext context,
  required AppSettings settings,
  bool loads = true,
  Future<MemorySnapshot?> Function()? readSnapshot,
}) {
  if (!loads || !settings.sttProviderType.isLocal) return Future.value(true);
  return confirmModelLoadRam(
    context: context,
    engine: settings.onDeviceEngine,
    modelId: settings.effectiveModelId,
    readSnapshot: readSnapshot,
  );
}

/// The same gate for callers without a widget context (dock and tray menus).
/// Uses the app's root navigator. Without a mounted root context the question
/// cannot be shown, so the load proceeds as it did before this check.
Future<bool> confirmSttSettingsRamFromApp({
  required AppSettings settings,
  bool loads = true,
  Future<MemorySnapshot?> Function()? readSnapshot,
}) {
  final context = appNavigatorKey.currentContext;
  if (context == null) return Future.value(true);
  return confirmSttSettingsRam(
    context: context,
    settings: settings,
    loads: loads,
    readSnapshot: readSnapshot,
  );
}

/// One-time start notice when the chosen local model clearly needs more RAM
/// than is free. It only informs: the model still loads, and no question is
/// asked. Returns true when the notice was shown.
Future<bool> showWpModelRamStartupNotice({
  required BuildContext context,
  required OnDeviceEngine engine,
  required String modelId,
  Future<MemorySnapshot?> Function()? readSnapshot,
}) async {
  final estimateMB = onDeviceRamEstimateMB(engine: engine, modelId: modelId);
  final snapshot = await (readSnapshot ?? defaultMemorySnapshotReader)();
  if (!context.mounted ||
      !ramClearlyShort(estimateMB: estimateMB, snapshot: snapshot)) {
    return false;
  }
  final l10n = L10n.of(context);
  WpToast.show(
    context,
    message: l10n.modelRamStartupHint(
      estimateMB.toString(),
      snapshot!.availableMB.toString(),
    ),
    type: WpToastType.info,
    duration: const Duration(seconds: 8),
  );
  return true;
}
