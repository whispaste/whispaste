/// The choices of the dock's speech-recognition dropdown. They read and write
/// the same settings the Settings page uses (`sttProvider`, `sttEngine`,
/// `sttModel`), so the dock and Settings are two views of one value.
library;

import '../../services/model_download_service.dart' show SttModelInfo;
import '../l10n/generated/app_localizations.dart';
import 'selectable_speech_models.dart';
import 'settings_enums.dart';
import 'settings_provider.dart';

/// One speech-recognition choice in the dock dropdown.
class SttChoice {
  const SttChoice({
    required this.value,
    required this.label,
    required this.onDevice,
  });

  /// The choice key: `whisper:<model>`, an on-device engine value
  /// (`parakeet`), or a cloud provider's enum name.
  final String value;
  final String label;
  final bool onDevice;

  /// Picking this entry starts a download instead of changing the setting.
  bool get needsDownload => value.startsWith(kSttDownloadChoicePrefix);
}

/// The choice in effect, in the key format of [SttChoice.value].
String sttChoiceValue(AppSettings settings) {
  if (!settings.sttProviderType.isLocal) return settings.sttProviderType.name;
  if (settings.onDeviceEngine == OnDeviceEngine.parakeet) {
    return OnDeviceEngine.parakeet.value;
  }
  return '$kSttModelChoicePrefix${settings.effectiveModelId}';
}

/// The dock's choices: only the entries of [models] that can be used right
/// now (see [selectableSpeechModelsProvider]), so local models that are on
/// disk and cloud providers with a key (UIA-DOCK-02). Other downloads happen
/// in Settings, reached through the dock's "manage speech models" footer;
/// only the [missing] selected model is offered for download right here
/// (UIA-MDL-GATE b). A
/// model being loaded is marked as loading, and the cloud providers are
/// labelled by their name.
List<SttChoice> sttChoicesFrom(
  List<SelectableSpeechModel> models,
  L10n l10n, {
  SelectableSpeechModel? missing,
}) => [
  // The selected model is not there: its download comes first, so the
  // selector never stays empty or silent about it (UIA-MDL-GATE b).
  if (missing != null)
    SttChoice(
      value: missing.downloadChoiceValue,
      label: l10n.dockMenuDownloadMissing(
        missing.displayName(l10n),
        missing.sizeLabel,
      ),
      onDevice: true,
    ),
  for (final model in models)
    if (model.isInstalled)
      SttChoice(
        value: model.choiceValue,
        label: _dockLabel(model, l10n),
        onDevice: model.group == SpeechModelGroup.local,
      ),
];

String _dockLabel(SelectableSpeechModel model, L10n l10n) {
  final state = model.state;
  if (state is SpeechModelLoading) {
    return '${model.displayName(l10n)} · ${l10n.dockMenuModelLoading}';
  }
  return model.displayName(l10n);
}

/// Returns [settings] with the choice [value] applied. A download choice, an
/// unknown value, or the on-device provider name leaves the settings unchanged.
AppSettings applySttChoice(AppSettings settings, String value) {
  if (value.startsWith(kSttModelChoicePrefix)) {
    return settings.copyWith(
      sttProvider: SttProviderType.onDevice.value,
      sttEngine: OnDeviceEngine.whisper.value,
      sttModel: value.substring(kSttModelChoicePrefix.length),
    );
  }
  if (OnDeviceEngine.values.any((e) => e.value == value)) {
    return settings.copyWith(
      sttProvider: SttProviderType.onDevice.value,
      sttEngine: value,
    );
  }
  final provider = SttProviderType.values
      .where((p) => p.name == value && p != SttProviderType.onDevice)
      .firstOrNull;
  if (provider == null) return settings;
  return settings.copyWith(sttProvider: provider.value);
}

/// Settings' engine dropdown: switches the on-device engine to [engine]. On
/// the way to Whisper, a selected Whisper model that is not on disk gives
/// way to the first one in [models] that is, so the switch lands on a
/// usable model instead of a missing one (UIA-XP-7-04). With none on disk
/// the selection stays, and the missing-model state offers its download.
AppSettings applyEngineChoice(
  AppSettings settings,
  String engine, {
  required Set<String> downloaded,
  required List<SttModelInfo> models,
}) {
  final next = settings.copyWith(sttEngine: engine);
  if (engine != OnDeviceEngine.whisper.value ||
      downloaded.contains(next.effectiveModelId)) {
    return next;
  }
  final installed = models.where((m) => downloaded.contains(m.id)).firstOrNull;
  return installed == null ? next : next.copyWith(sttModel: installed.id);
}
