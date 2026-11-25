/// Smart Mode's text model: whether the chosen provider can run right now, and
/// what the user is told when it cannot (UIA-XP-7-05). The dock, the Settings
/// page and the after-dictation notice read these rules, so they agree.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/custom_endpoint_rules.dart';
import '../../core/config/settings_enums.dart';
import '../../core/config/settings_provider.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../custom_endpoint/custom_endpoint_errors.dart';
import '../paste/paster.dart';
import 'smart_mode_ffi_engine.dart' show smartModeLocalEngineAvailableProvider;
import 'smart_mode_model_download_service.dart' show smartModeDownloadProvider;
import 'smart_mode_openai_engine.dart' show SmartModeOpenAiEngine;
import '../user_models/user_model_use.dart'
    show smartModeLocalModelReadyProvider;

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
    // An own GGUF model in use counts like the bundled one (#1789).
    modelDownloaded:
        ref.watch(smartModeLocalModelReadyProvider) ||
        !ref.watch(smartModeDownloadProvider.select((s) => s.scanned)),
    openAiApiKey: settings.cloudProvider.openAiApiKey,
    customEndpointConfigured: customEndpointReady(
      url: settings.cloudProvider.customEndpointUrl,
      model: settings.cloudProvider.customEndpointSmartModel,
    ),
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

  /// Own endpoint without a usable address or model name (W-M3).
  customEndpointMissing,
}

/// Only the chosen provider counts (ADR 0010, strict either-or): a model on
/// disk does not make the cloud provider ready, and a key does not make the
/// local one ready.
SmartModeTextModelStatus smartModeTextModelStatus({
  required SmartModeProviderType provider,
  required bool localEngineAvailable,
  required bool modelDownloaded,
  required String openAiApiKey,
  bool customEndpointConfigured = false,
}) {
  if (provider.isLocal) {
    if (!localEngineAvailable) {
      return SmartModeTextModelStatus.localEngineUnavailable;
    }
    if (!modelDownloaded) return SmartModeTextModelStatus.localModelMissing;
    return SmartModeTextModelStatus.ready;
  }
  if (provider == SmartModeProviderType.custom) {
    return customEndpointConfigured
        ? SmartModeTextModelStatus.ready
        : SmartModeTextModelStatus.customEndpointMissing;
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
  SmartModeTextModelStatus.cloudKeyMissing ||
  SmartModeTextModelStatus.customEndpointMissing =>
    l10n.smartModeNoTextModelHint,
};

/// The Settings row that fixes [status] (`text-smart-mode-model` for the
/// download, `api-keys-openai` for the API key, #208), or null when no row
/// does.
String? smartModeFixRowId(SmartModeTextModelStatus status) => switch (status) {
  SmartModeTextModelStatus.localModelMissing => 'text-smart-mode-model',
  SmartModeTextModelStatus.cloudKeyMissing => 'api-keys-openai',
  SmartModeTextModelStatus.customEndpointMissing =>
    'text-smart-mode-endpoint-url',
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
      SmartModeTextModelStatus.customEndpointMissing =>
        l10n.smartModeConfigureEndpointAction,
      SmartModeTextModelStatus.ready ||
      SmartModeTextModelStatus.localEngineUnavailable => null,
    };

/// Why Smart Mode left a dictation's text unedited.
///
/// [openAi] is a failed OpenAI request: its error code says why (key, model
/// access, quota, network), so the notice can name the cause and the next
/// step instead of the generic sentence (#2116).
enum SmartModeFallbackReason {
  noTextModel,
  timedOut,
  failed,
  customEndpoint,
  openAi,
}

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
  PasteOutcome.unconfirmedRestored ||
  PasteOutcome.unconfirmedNoBridge ||
  PasteOutcome.unconfirmedReceiptRefused ||
  PasteOutcome.secureInput => SmartModeDelivery.unconfirmed,
  _ => clipboardHeld ? SmartModeDelivery.clipboard : SmartModeDelivery.none,
};

/// The reason sentence for an error code of the OpenAI Smart Mode engine
/// (`smart_mode_openai_*`, see `SmartModeOpenAiEngine.run`), or null for a
/// code without its own sentence. Each names what went wrong and the next
/// step; a cloud failure on every dictation is otherwise undiagnosable (#2116).
String? smartModeOpenAiErrorText(L10n l10n, String code) {
  if (code.startsWith('smart_mode_openai_network_error')) {
    return l10n.notificationSmartModeSkippedOpenAiNetwork;
  }
  return switch (code) {
    'smart_mode_openai_invalid_api_key' || 'smart_mode_openai_error_401' =>
      l10n.notificationSmartModeSkippedOpenAiInvalidKey(
        l10n.settingsAreaApiKeys,
      ),
    // 403: the key lacks the permission for chat requests (a restricted key)
    // or the country is not served; 404: the project may not use the model.
    'smart_mode_openai_error_403' || 'smart_mode_openai_error_404' =>
      l10n.notificationSmartModeSkippedOpenAiNoModelAccess(
        SmartModeOpenAiEngine.openAiModel,
      ),
    'smart_mode_openai_rate_limited' =>
      l10n.notificationSmartModeSkippedOpenAiRateLimited,
    'smart_mode_openai_timeout' => l10n.notificationSmartModeSkippedTimedOut,
    _ => null,
  };
}

/// Body of the OS notice for a Smart Mode fallback: the reason, then what
/// happened to the text. Only [SmartModeDelivery.pasted] may say the text was
/// inserted.
String smartModeFallbackNoticeBody(
  L10n l10n, {
  required SmartModeFallbackReason reason,
  required SmartModeDelivery delivery,
  String? errorCode,
}) {
  final reasonText = switch (reason) {
    SmartModeFallbackReason.noTextModel =>
      l10n.notificationSmartModeSkippedNoTextModel,
    SmartModeFallbackReason.timedOut =>
      l10n.notificationSmartModeSkippedTimedOut,
    SmartModeFallbackReason.failed => l10n.notificationSmartModeSkippedBody,
    // One message per error class of the own endpoint (W-M3), the same text
    // as for transcription; the generic body only if the code is unknown.
    SmartModeFallbackReason.customEndpoint =>
      customEndpointErrorText(l10n, errorCode ?? '') ??
          l10n.notificationSmartModeSkippedBody,
    SmartModeFallbackReason.openAi =>
      smartModeOpenAiErrorText(l10n, errorCode ?? '') ??
          l10n.notificationSmartModeSkippedBody,
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
