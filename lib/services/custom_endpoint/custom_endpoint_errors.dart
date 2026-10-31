/// One message per error class of the user's own endpoint (W-M3), shared by
/// transcription and Smart Mode. Each message names its next step, so both
/// paths show the same text for the same class.
library;

import '../../core/l10n/generated/app_localizations.dart';

/// The message for an error [code] of the own endpoint, or null when the code
/// belongs to another engine. Transcription uses `custom_*` codes, Smart Mode
/// uses the `smart_mode_custom_*` codes of its engine.
String? customEndpointErrorText(L10n l10n, String code) => switch (code) {
  'custom_endpoint_unreachable' ||
  'smart_mode_custom_unreachable' ||
  'smart_mode_custom_timeout' => l10n.errorCustomEndpointUnreachable,
  'custom_endpoint_not_configured' ||
  'smart_mode_custom_not_configured' => l10n.errorCustomEndpointNotConfigured,
  'custom_model_missing' ||
  'smart_mode_custom_model_missing' => l10n.errorCustomModelMissing,
  'custom_bad_response' ||
  'smart_mode_custom_bad_format' => l10n.errorCustomBadResponse,
  'smart_mode_custom_unauthorized' => l10n.errorCustomEndpointUnauthorized,
  'smart_mode_custom_server_error' => l10n.errorCustomEndpointServerError,
  _ => null,
};
