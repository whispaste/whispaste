/// Smart Mode's text model: whether the chosen provider can run right now, and
/// what the user is told when it cannot (UIA-XP-7-05). The dock, the Settings
/// page and the after-dictation notice read these rules, so they agree.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_enums.dart';
import '../../core/config/settings_provider.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../paste/paster.dart';
import 'smart_mode_ffi_engine.dart' show smartModeLocalEngineAvailableProvider;
import 'smart_mode_model_download_service.dart' show smartModeDownloadProvider;

/// The text-model status of the running app, read by the dock and the Settings
/// page so they cannot disagree.
final smartModeTextModelStatusProvider = Provider<SmartModeTextModelStatus>((
  ref,
) {
  final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
  return smartModeTextModelStatus(
    provider: SmartModeProviderType.fromValue(settings.smartMode.provider),
    localEngineAvailable: ref.watch(smartModeLocalEngineAvailableProvider),
    // Unknown until the initial disk scan: not reported as missing.
    modelDownloaded: ref.watch(
      smartModeDownloadProvider.select((s) => s.modelDownloaded || !s.scanned),
    ),
    openAiApiKey: settings.cloudProvider.openAiApiKey,
  );
});

/// Whether Smart Mode can run its text model with the chosen provider.
enum SmartModeTextModelStatus {
  ready,

  /// Local provider, but the model file is not on disk yet: a download fixes it.
  localModelMissing,

  /// Local provider in a build without the bundled engine: no download helps.
  localEngineUnavailable,

  /// Cloud provider without an OpenAI API key.
  cloudKeyMissing,
}

/// Only the chosen provider counts (ADR 0010, strict either-or): a model on
/// disk does not make the cloud provider ready, and a key does not make the
/// local one ready.
SmartModeTextModelStatus smartModeTextModelStatus({
  required SmartModeProviderType provider,
  required bool localEngineAvailable,
  required bool modelDownloaded,
  required String openAiApiKey,
}) {
  if (provider.isLocal) {
    if (!localEngineAvailable) {
      return SmartModeTextModelStatus.localEngineUnavailable;
    }
    if (!modelDownloaded) return SmartModeTextModelStatus.localModelMissing;
    return SmartModeTextModelStatus.ready;
  }
  return openAiApiKey.trim().isEmpty
      ? SmartModeTextModelStatus.cloudKeyMissing
      : SmartModeTextModelStatus.ready;
}

/// The reason shown for every Smart Mode preset that cannot be picked, or null
/// when the text model is ready.
String? smartModeUnavailableReason(
  SmartModeTextModelStatus status,
  L10n l10n,
) => switch (status) {
  SmartModeTextModelStatus.ready => null,
  SmartModeTextModelStatus.localEngineUnavailable =>
    l10n.smartModeLocalUnavailable,
  SmartModeTextModelStatus.localModelMissing ||
  SmartModeTextModelStatus.cloudKeyMissing => l10n.smartModeNoTextModelHint,
};

/// The Settings row that fixes [status] (`text-smart-mode-model` for the
/// download, `text-smart-mode-key` for the API key), or null when no row does.
String? smartModeFixRowId(SmartModeTextModelStatus status) => switch (status) {
  SmartModeTextModelStatus.localModelMissing => 'text-smart-mode-model',
  SmartModeTextModelStatus.cloudKeyMissing => 'text-smart-mode-key',
  SmartModeTextModelStatus.ready ||
  SmartModeTextModelStatus.localEngineUnavailable => null,
};

/// The footer label that opens [smartModeFixRowId], or null when there is none.
String? smartModeFixLabel(SmartModeTextModelStatus status, L10n l10n) =>
    switch (status) {
      SmartModeTextModelStatus.localModelMissing =>
        l10n.smartModeLoadTextModelAction,
      SmartModeTextModelStatus.cloudKeyMissing =>
        l10n.smartModeAddOpenAiKeyAction,
      SmartModeTextModelStatus.ready ||
      SmartModeTextModelStatus.localEngineUnavailable => null,
    };

/// Why Smart Mode left a dictation's text unedited.
enum SmartModeFallbackReason { noTextModel, timedOut, failed }

/// Where the unedited text ended up once the paste step was over.
enum SmartModeDelivery {
  /// The paste was confirmed: the text is in the field.
  pasted,

  /// The paste was sent but nothing proves the text arrived.
  unconfirmed,

  /// The text is on the clipboard, but no paste landed.
  clipboard,

  /// Neither a paste nor a clipboard copy happened.
  none,
}

/// Maps the paste result and the clipboard state to a [SmartModeDelivery].
/// [paste] is null when no paste was attempted (copy only, quick note, ...).
SmartModeDelivery smartModeDeliveryOf({
  required PasteOutcome? paste,
  required bool clipboardHeld,
}) => switch (paste) {
  PasteOutcome.success => SmartModeDelivery.pasted,
  PasteOutcome.unconfirmed ||
  PasteOutcome.unconfirmedNoBridge => SmartModeDelivery.unconfirmed,
  _ => clipboardHeld ? SmartModeDelivery.clipboard : SmartModeDelivery.none,
};

/// Body of the OS notice for a Smart Mode fallback: the reason, then what
/// happened to the text. Only [SmartModeDelivery.pasted] may say the text was
/// inserted.
String smartModeFallbackNoticeBody(
  L10n l10n, {
  required SmartModeFallbackReason reason,
  required SmartModeDelivery delivery,
}) {
  final reasonText = switch (reason) {
    SmartModeFallbackReason.noTextModel =>
      l10n.notificationSmartModeSkippedNoTextModel,
    SmartModeFallbackReason.timedOut =>
      l10n.notificationSmartModeSkippedTimedOut,
    SmartModeFallbackReason.failed => l10n.notificationSmartModeSkippedBody,
  };
  final outcome = switch (delivery) {
    SmartModeDelivery.pasted => l10n.notificationSmartModeOutcomePasted,
    SmartModeDelivery.unconfirmed =>
      l10n.notificationSmartModeOutcomeUnconfirmed,
    SmartModeDelivery.clipboard => l10n.notificationSmartModeOutcomeClipboard,
    SmartModeDelivery.none => l10n.notificationSmartModeOutcomeNone,
  };
  return '$reasonText $outcome';
}
