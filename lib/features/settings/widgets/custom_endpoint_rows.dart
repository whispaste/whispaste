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
import '../../../services/custom_endpoint/custom_endpoint_models.dart';
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

/// Loads the model list ("Modelle laden"). Injected so widget tests never
/// reach a network.
typedef CustomEndpointModelsFn =
    Future<CustomEndpointModelList> Function({
      required Uri base,
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

/// The line under "Modelle laden" after a request: how many models were found,
/// or why there is no list. Every failure keeps free typing open (#1790).
String customEndpointModelsText(L10n l10n, CustomEndpointModelList list) =>
    switch (list.result) {
      CustomEndpointModelListResult.loaded =>
        list.needsV1
            ? l10n.customEndpointModelsLoadedNeedsV1
            : l10n.customEndpointModelsLoaded(list.models.length),
      CustomEndpointModelListResult.empty => l10n.customEndpointModelsEmpty,
      CustomEndpointModelListResult.unreachable =>
        l10n.customEndpointModelsUnreachable,
      CustomEndpointModelListResult.unauthorized =>
        l10n.customEndpointModelsUnauthorized,
      CustomEndpointModelListResult.noList => l10n.customEndpointModelsNoList,
      CustomEndpointModelListResult.serverError =>
        l10n.customEndpointModelsServerError,
    };

/// Whether the outcome line reads as a problem (error colour): no answer, no
/// list, a refused key, a server error, or names that need the `/v1` address.
bool customEndpointModelsIsProblem(CustomEndpointModelList list) =>
    list.needsV1 ||
    (list.result != CustomEndpointModelListResult.loaded &&
        list.result != CustomEndpointModelListResult.empty);

class CustomEndpointRows extends ConsumerStatefulWidget {
  const CustomEndpointRows({
    super.key,
    required this.scope,
    this.probe,
    this.loadModels,
  });

  final CustomEndpointScope scope;

  /// Connection test. Null in the app (the real probe runs); tests inject one.
  final CustomEndpointProbeFn? probe;

  /// Model list request. Null in the app (the real request runs); tests
  /// inject one.
  final CustomEndpointModelsFn? loadModels;

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
  bool _loadingModels = false;
  CustomEndpointModelList? _models;
  int _modelsRequest = 0;

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
    // A changed address or model makes the last test result stale; a changed
    // address or key makes the model list stale.
    final listStale = (url != null || key != null) && _models != null;
    if (_probe != null || listStale) {
      setState(() {
        _probe = null;
        if (listStale) _models = null;
      });
    }
  }

  Future<void> _loadModels(CloudProviderSettings cloud) async {
    final uri = checkCustomEndpointUrl(cloud.customEndpointUrl).uri;
    if (uri == null) return;
    final key = cloud.customEndpointApiKey.trim();
    final request = ++_modelsRequest;
    setState(() {
      _loadingModels = true;
      _models = null;
    });
    final run = widget.loadModels ?? _defaultLoadModels;
    final result = await run(base: uri, apiKey: key.isEmpty ? null : key);
    if (!mounted || request != _modelsRequest) return;
    setState(() {
      _loadingModels = false;
      _models = result;
    });
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

  /// A choice of well-known local servers under the address field (#1957).
  /// Picking one only fills in its usual address on this device; the field
  /// stays free for any other address. The choice shows the server whose
  /// address is entered, so it needs no setting of its own.
  Widget _serverPresetBlock(
    BuildContext context,
    L10n l10n,
    CloudProviderSettings cloud,
    String prefix,
  ) {
    final selected = customEndpointServerPresetFor(cloud.customEndpointUrl);
    final hint = l10n.customEndpointServerPick;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.sm,
        vertical: WpSpacing.xs,
      ),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Semantics(
          label: hint,
          child: settingsDropdown(
            context: context,
            value: selected?.name,
            items: [for (final p in kCustomEndpointServerPresets) p.name],
            hint: hint,
            keyPrefix: '$prefix-server-picker',
            testId: '$prefix-server-picker',
            onChanged: (name) {
              for (final p in kCustomEndpointServerPresets) {
                if (p.name == name) _setField(url: p.url);
              }
            },
          ),
        ),
      ),
    );
  }

  /// "Modelle laden" under the model field, the picker once names arrived,
  /// and one line with the outcome. The text field above stays the source of
  /// the model name: picking only fills it in.
  Widget _modelsBlock(
    BuildContext context,
    L10n l10n,
    CloudProviderSettings cloud,
    String model,
    String prefix,
    bool urlValid,
  ) {
    final list = _models;
    final names = list?.models ?? const <String>[];
    final pickLabel = l10n.customEndpointModelsPickLabel;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.sm,
        vertical: WpSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: WpSpacing.sm,
            runSpacing: WpSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              WpButton(
                testId: '$prefix-models-load-button',
                label: l10n.customEndpointModelsLoadAction,
                variant: WpButtonVariant.secondary,
                isLoading: _loadingModels,
                onPressed: urlValid && !_loadingModels
                    ? () => _loadModels(cloud)
                    : null,
                disabledTooltip: l10n.customEndpointModelsLoadDisabledHint,
              ),
              if (names.isNotEmpty)
                Semantics(
                  label: pickLabel,
                  child: settingsDropdown(
                    context: context,
                    value: names.contains(model.trim()) ? model.trim() : null,
                    items: names,
                    hint: l10n.customEndpointModelsPickHint,
                    keyPrefix: '$prefix-models-picker',
                    testId: '$prefix-models-picker',
                    onChanged: (v) {
                      if (v != null) _setField(model: v);
                    },
                  ),
                ),
            ],
          ),
          if (list != null)
            Padding(
              padding: const EdgeInsets.only(top: WpSpacing.xs),
              child: Semantics(
                identifier: '$prefix-models-result',
                liveRegion: true,
                child: Text(
                  key: ValueKey('$prefix-models-result'),
                  customEndpointModelsText(l10n, list),
                  style: TextStyle(
                    fontSize: WpTypography.caption,
                    color: customEndpointModelsIsProblem(list)
                        ? WpColors.error
                        : WpColors.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(settingsProvider, (previous, next) {
      final before = previous?.value?.cloudProvider;
      final after = next.value?.cloudProvider;
      if (before?.customEndpointUrl != after?.customEndpointUrl ||
          before?.customEndpointApiKey != after?.customEndpointApiKey) {
        setState(() {
          _modelsRequest++;
          _models = null;
          _loadingModels = false;
        });
      }
    });
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
              hintText: 'http://127.0.0.1:11434/v1',
              semanticLabel: l10n.customEndpointUrlTitle,
              onChanged: (v) => _setField(url: v),
            ),
          ),
        ),
        _serverPresetBlock(context, l10n, cloud, prefix),
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
        _modelsBlock(context, l10n, cloud, model, prefix, check.isValid),
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

/// The real model list request with the app's own short timeout.
Future<CustomEndpointModelList> _defaultLoadModels({
  required Uri base,
  String? apiKey,
}) => loadCustomEndpointModels(base: base, apiKey: apiKey);

/// The real probe: `GET /models` with the app's own short timeout.
Future<CustomEndpointProbe> _defaultProbe({
  required Uri base,
  required String model,
  String? apiKey,
}) => probeCustomEndpoint(base: base, model: model, apiKey: apiKey);
