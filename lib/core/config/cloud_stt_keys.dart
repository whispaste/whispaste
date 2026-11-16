/// Whether a cloud speech provider is set up: its API key is saved.
///
/// Pure functions over the settings snapshot, so the recording preflight and
/// the onboarding model gate (UIA-MDL-GATE) answer from one rule.
library;

import 'custom_endpoint_rules.dart';
import 'settings_enums.dart';
import 'settings_sections.dart';

/// Whether [provider] has a non-blank API key saved. Always false for the
/// on-device engine, which has no key.
bool hasSttApiKey(CloudProviderSettings cloud, SttProviderType provider) =>
    switch (provider) {
      SttProviderType.openAI => cloud.openAiApiKey.trim().isNotEmpty,
      SttProviderType.deepgram => cloud.deepgramApiKey.trim().isNotEmpty,
      // The own endpoint is set up by address and model, not by a key (W-M3).
      SttProviderType.customEndpoint => customEndpointReady(
        url: cloud.customEndpointUrl,
        model: cloud.customEndpointSttModel,
      ),
      SttProviderType.onDevice => false,
    };

/// The first cloud speech provider with a saved key, or `null` when none
/// has one. The onboarding model step offers it as an explicit choice.
SttProviderType? firstCloudSttProviderWithKey(CloudProviderSettings cloud) {
  for (final provider in [SttProviderType.openAI, SttProviderType.deepgram]) {
    if (hasSttApiKey(cloud, provider)) return provider;
  }
  return null;
}
