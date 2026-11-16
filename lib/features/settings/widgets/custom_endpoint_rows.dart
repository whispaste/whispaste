/// Settings rows for the user's own OpenAI-compatible endpoint (W-M3). They
/// appear inline under the provider choice of the speech and the Smart Mode
/// sections, only while the own endpoint is chosen there. Both sections edit
/// the same address and key and differ only in their model name.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/custom_endpoint_rules.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/config/settings_sections.dart' show CloudProviderSettings;
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/custom_endpoint/custom_endpoint_probe.dart';
import '../../../widgets/wp_button.dart';
import '../settings_widgets.dart';
import 'wp_settings_group.dart';

/// Which function the rows configure: the transcription model or the Smart
/// Mode model. The address and key are shared.
enum CustomEndpointScope { speech, smartMode }

/// Runs the connection test. Injected so widget tests never reach a network.
typedef CustomEndpointProbeFn =
    Future<CustomEndpointProbe> Function({
      required Uri base,
      required String model,
      String? apiKey,
    });

/// Row-id prefix of a scope: `speech-custom-endpoint` or
/// `text-smart-mode-endpoint`. The Smart Mode rows keep the prefix the Smart
/// Mode section already uses for its fix link.
String customEndpointRowPrefix(CustomEndpointScope scope) => switch (scope) {
  CustomEndpointScope.speech => 'speech-custom-endpoint',
  CustomEndpointScope.smartMode => 'text-smart-mode-endpoint',
};

/// Text under the address field for a refused address, or null when the
/// address is fine or still empty (an empty field needs no message yet).
String? customEndpointUrlProblemText(L10n l10n, String raw) {
  final check = checkCustomEndpointUrl(raw);
  return switch (check.problem) {
    null || CustomEndpointUrlProblem.empty => null,
    CustomEndpointUrlProblem.invalid => l10n.customEndpointUrlInvalid,
    CustomEndpointUrlProblem.credentialsOrQuery =>
      l10n.customEndpointUrlCredentials,
    CustomEndpointUrlProblem.httpToRemoteHost =>
      l10n.customEndpointUrlHttpRemote,
  };
}

/// Network notice for a valid address: local stays on the device or in the
/// local network, anything else names the host that receives the data.
String customEndpointNoticeText(
  L10n l10n,
  Uri uri, {
  required CustomEndpointScope scope,
}) {
  final notice = customEndpointNetworkNotice(uri);
  return switch (notice.network) {
    CustomEndpointNetwork.device => l10n.customEndpointNoticeLocal,
    CustomEndpointNetwork.lan => l10n.customEndpointNoticeLan,
    CustomEndpointNetwork.remote =>
      scope == CustomEndpointScope.speech
          ? l10n.customEndpointNoticeRemoteAudio(notice.host!)
          : l10n.customEndpointNoticeRemoteText(notice.host!),
  };
}

/// The result line of the connection test, one message per result.
String customEndpointProbeText(
  L10n l10n,
  CustomEndpointProbe probe,
) => switch (probe.result) {
  CustomEndpointProbeResult.connected =>
    probe.modelVerified
        ? l10n.customEndpointProbeConnected
        : l10n.customEndpointProbeConnectedUnverified,
  CustomEndpointProbeResult.modelMissing =>
    l10n.customEndpointProbeModelMissing(
      probe.availableModels.isEmpty ? '—' : probe.availableModels.join(', '),
    ),
  CustomEndpointProbeResult.unreachable => l10n.customEndpointProbeUnreachable,
  CustomEndpointProbeResult.unauthorized =>
    l10n.customEndpointProbeUnauthorized,
  CustomEndpointProbeResult.badFormat => l10n.customEndpointProbeBadFormat,
  CustomEndpointProbeResult.serverError => l10n.customEndpointProbeServerError,
};

class CustomEndpointRows extends ConsumerStatefulWidget {
  const CustomEndpointRows({super.key, required this.scope, this.probe});

  final CustomEndpointScope scope;

  /// Connection test. Null in the app (the real probe runs); tests inject one.
  final CustomEndpointProbeFn? probe;

  @override
  ConsumerState<CustomEndpointRows> createState() => _CustomEndpointRowsState();
}

class _CustomEndpointRowsState extends ConsumerState<CustomEndpointRows> {
  final _urlCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  bool _showKey = false;
  bool _testing = false;
  CustomEndpointProbe? _probe;

  @override
  void dispose() {
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  void _setField({String? url, String? key, String? model}) {
    ref
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWithSections(
            cloudProvider: s.cloudProvider.copyWith(
              customEndpointUrl: url,
              customEndpointApiKey: key,
              customEndpointSttModel: widget.scope == CustomEndpointScope.speech
                  ? model
                  : null,
              customEndpointSmartModel:
                  widget.scope == CustomEndpointScope.smartMode ? model : null,
            ),
          ),
        );
    // A changed address or model makes the last test result stale.
    if (_probe != null) setState(() => _probe = null);
  }

  Future<void> _runTest(CloudProviderSettings cloud, String model) async {
    final check = checkCustomEndpointUrl(cloud.customEndpointUrl);
    final uri = check.uri;
    if (uri == null) return;
    final key = cloud.customEndpointApiKey.trim();
    setState(() {
      _testing = true;
      _probe = null;
    });
    final run = widget.probe ?? _defaultProbe;
    final result = await run(
      base: uri,
      model: model,
      apiKey: key.isEmpty ? null : key,
    );
    if (!mounted) return;
    setState(() {
      _testing = false;
      _probe = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final cloud = settings.cloudProvider;
    final isSpeech = widget.scope == CustomEndpointScope.speech;
    final model = isSpeech
        ? cloud.customEndpointSttModel
        : cloud.customEndpointSmartModel;
    final prefix = customEndpointRowPrefix(widget.scope);

    syncController(_urlCtrl, cloud.customEndpointUrl);
    syncController(_keyCtrl, cloud.customEndpointApiKey);
    syncController(_modelCtrl, model);

    final check = checkCustomEndpointUrl(cloud.customEndpointUrl);
    final problem = customEndpointUrlProblemText(l10n, cloud.customEndpointUrl);
    final canTest = check.isValid && model.trim().isNotEmpty && !_testing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WpSettingsRow(
          rowId: '$prefix-url',
          title: l10n.customEndpointUrlTitle,
          subtitle: l10n.customEndpointUrlSubtitle,
          trailing: KeyedSubtree(
            key: ValueKey('$prefix-url-field'),
            child: settingsTextField(
              context: context,
              controller: _urlCtrl,
              hintText: 'http://localhost:1234/v1',
              semanticLabel: l10n.customEndpointUrlTitle,
              onChanged: (v) => _setField(url: v),
            ),
          ),
        ),
        if (problem != null)
          settingsInlineNotice(context: context, message: problem)
        else if (check.isValid && customEndpointPlainHttpOnLan(check.uri!))
          settingsInlineNotice(
            context: context,
            message: l10n.customEndpointHttpLanWarning,
          ),
        if (problem == null && check.isValid)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.sm,
              vertical: WpSpacing.xs,
            ),
            child: Semantics(
              liveRegion: true,
              child: Text(
                key: ValueKey('$prefix-network-notice'),
                customEndpointNoticeText(l10n, check.uri!, scope: widget.scope),
                style: TextStyle(
                  fontSize: WpTypography.caption,
                  color: WpColors.textSecondary,
                ),
              ),
            ),
          ),
        WpSettingsRow(
          rowId: '$prefix-key',
          title: l10n.customEndpointKeyTitle,
          subtitle: l10n.customEndpointKeySubtitle,
          trailing: KeyedSubtree(
            key: ValueKey('$prefix-key-field'),
            child: settingsApiKeyField(
              context: context,
              controller: _keyCtrl,
              obscure: !_showKey,
              onToggle: () => setState(() => _showKey = !_showKey),
              onChanged: (v) => _setField(key: v),
              semanticLabel: l10n.customEndpointKeyTitle,
            ),
          ),
        ),
        WpSettingsRow(
          rowId: '$prefix-model',
          title: isSpeech
              ? l10n.customEndpointSttModelTitle
              : l10n.customEndpointSmartModelTitle,
          subtitle: l10n.customEndpointModelSubtitle,
          trailing: KeyedSubtree(
            key: ValueKey('$prefix-model-field'),
            child: settingsTextField(
              context: context,
              controller: _modelCtrl,
              hintText: isSpeech ? 'whisper-1' : 'llama-3.1-8b',
              semanticLabel: isSpeech
                  ? l10n.customEndpointSttModelTitle
                  : l10n.customEndpointSmartModelTitle,
              onChanged: (v) => _setField(model: v),
            ),
          ),
        ),
        WpSettingsRow(
          rowId: '$prefix-test',
          title: l10n.customEndpointTestTitle,
          subtitle: l10n.customEndpointTestSubtitle,
          trailing: WpButton(
            testId: '$prefix-test-button',
            label: l10n.customEndpointTestAction,
            variant: WpButtonVariant.secondary,
            isLoading: _testing,
            onPressed: canTest ? () => _runTest(cloud, model) : null,
            disabledTooltip: l10n.customEndpointTestDisabledHint,
          ),
        ),
        if (_probe != null)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.sm,
              vertical: WpSpacing.xs,
            ),
            child: Semantics(
              liveRegion: true,
              child: Text(
                key: ValueKey('$prefix-test-result'),
                customEndpointProbeText(l10n, _probe!),
                style: TextStyle(
                  fontSize: WpTypography.caption,
                  color: _probe!.result == CustomEndpointProbeResult.connected
                      ? WpColors.textSecondary
                      : WpColors.error,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The real probe: `GET /models` with the app's own short timeout.
Future<CustomEndpointProbe> _defaultProbe({
  required Uri base,
  required String model,
  String? apiKey,
}) => probeCustomEndpoint(base: base, model: model, apiKey: apiKey);
