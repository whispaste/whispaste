// loam-ignore: circular-dependencies – the library, the Smart Mode section and ModelChoiceRow share activateLibraryModel and startSmartModeDownloadWithRamCheck; moving them into a shared file is left until after the release
/// Settings area "Modelle" (Modellbibliothek, #1514): every speech and Smart
/// Mode model with size, languages, speed, accuracy, local or cloud and its
/// status; install with progress and cancel, remove with confirmation and
/// the space it frees, switch the model in use. The user's own models
/// (#1789) share the list and remain marked "not checked".
///
/// The entries come from `model_library.dart`, which builds the speech
/// section from `selectableSpeechModelsProvider` (the dock's and tray's
/// source too) and the catalog (#1513). The actions call the existing
/// download services; nothing here keeps a model list of its own.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../widgets/wp_search_field.dart';
import '../../../widgets/wp_dropdown.dart';
import '../../../widgets/wp_icon_button.dart';
import '../../../widgets/searchable_list_page.dart'
    show showWpListMenu, WpListMenuAction;

import '../../../core/accessibility/announce.dart';
import '../../../core/config/model_library.dart';
import '../../../core/config/model_sampling.dart'
    show kCatalogTextModelSamplingId;
import '../../../core/config/selectable_speech_models.dart';
import '../../../core/config/settings_enums.dart'
    show OnDeviceEngine, SmartModeProviderType;
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/models/model_catalog.dart' show ModelLevel;
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/model_download_service.dart';
import '../../../services/smart_mode/smart_mode_ffi_engine.dart'
    show smartModeModelPath;
import '../../../services/smart_mode/smart_mode_model_download_service.dart';
import '../../../services/stt/stt_bundle.dart';
import '../../../services/stt_parakeet/parakeet_download_service.dart';
import '../../../services/user_models/user_model.dart';
import '../../../services/user_models/user_model_use.dart'
    show ownSmartModelPathFor, userModelUseProvider;
import '../../../services/user_models/user_models_provider.dart';
import '../../../widgets/dialog.dart';
import '../../../widgets/model_ram_precheck_dialog.dart';
import '../../../widgets/parakeet_language_notice.dart'
    show languageDisplayName;
import '../../../widgets/wp_accent_badge.dart';
import '../../../widgets/wp_banner.dart';
import '../../../widgets/wp_button.dart';
import '../../../widgets/wp_progress_bar.dart';
import '../../../widgets/wp_model_download_error_notice.dart';
import '../../../services/path_service.dart' show sttDir;
import '../../../services/stt_parakeet/parakeet_model_registry.dart'
    show parakeetModelDir;
import '../widgets/add_user_model_dialog.dart';
import '../widgets/model_sampling_dialog.dart';
import '../widgets/model_choice_row.dart' show kModelLibraryRowId;
import '../widgets/wp_settings_group.dart';
import 'smart_mode_section.dart' show startSmartModeDownloadWithRamCheck;

/// A single catalog; filters never create a second source of model state.
class ModelLibrarySection extends ConsumerStatefulWidget {
  const ModelLibrarySection({super.key});

  @override
  ConsumerState<ModelLibrarySection> createState() =>
      _ModelLibrarySectionState();
}

class _ModelLibrarySectionState extends ConsumerState<ModelLibrarySection> {
  final _search = TextEditingController();
  ModelLibraryKind? _kind;
  bool _installed = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final entries = [
      ...ref.watch(speechLibraryEntriesProvider),
      ...ref.watch(smartModeLibraryEntriesProvider),
    ];
    final query = _search.text.trim().toLowerCase();
    final visible = entries
        .where(
          (entry) =>
              (_kind == null || entry.kind == _kind) &&
              (!_installed ||
                  (entry.location == ModelLocation.local &&
                      {
                        ModelLibraryStatus.installed,
                        ModelLibraryStatus.active,
                        ModelLibraryStatus.loading,
                      }.contains(entry.status))) &&
              (query.isEmpty || entry.name(l10n).toLowerCase().contains(query)),
        )
        .toList();
    final busy = ref.watch(userModelsProvider.select((state) => state.busy));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsRowFrame(
          rowId: kModelLibraryRowId,
          child: Padding(
            padding: const EdgeInsets.only(bottom: WpSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: WpSearchField(
                    testId: 'model-library-search',
                    controller: _search,
                    hintText: l10n.modelLibrarySearch,
                    variant: WpSearchFieldVariant.outlined,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: WpSpacing.sm),
                Builder(
                  builder: (buttonContext) => WpIconButton(
                    key: const ValueKey('model-library-add-menu'),
                    testId: 'model-library-add-menu',
                    icon: LucideIcons.plus,
                    tooltip: l10n.modelLibraryAdd,
                    onPressed: () => showWpListMenu(buttonContext, [
                      for (final kind in ModelLibraryKind.values)
                        WpListMenuAction(
                          itemKey: ValueKey(
                            'model-library-own-${kind.name}-add',
                          ),
                          label: kind == ModelLibraryKind.speech
                              ? l10n.modelLibraryAddTitleSpeech
                              : l10n.modelLibraryAddTitleSmartMode,
                          icon: modelLibraryKindIcon(kind),
                          enabled: !busy,
                          hint: busy ? l10n.modelLibraryAddBusy : null,
                          onSelected: () =>
                              unawaited(addOwnLibraryModel(context, ref, kind)),
                        ),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ),
        Wrap(
          spacing: WpSpacing.sm,
          runSpacing: WpSpacing.xs,
          children: [
            WpDropdown<ModelLibraryKind?>(
              testId: 'model-library-kind',
              hint: l10n.modelLibraryAllTypes,
              value: _kind,
              items: [
                WpDropdownItem(value: null, label: l10n.modelLibraryAllTypes),
                WpDropdownItem(
                  value: ModelLibraryKind.speech,
                  label: l10n.modelLibrarySpeechType,
                ),
                WpDropdownItem(
                  value: ModelLibraryKind.smartMode,
                  label: l10n.modelLibraryTextType,
                ),
              ],
              onChanged: (value) => setState(() => _kind = value),
            ),
            WpDropdown<bool>(
              testId: 'model-library-availability',
              value: _installed,
              items: [
                WpDropdownItem(value: false, label: l10n.modelLibraryAllModels),
                WpDropdownItem(
                  value: true,
                  label: l10n.modelLibraryInstalledFilter,
                ),
              ],
              onChanged: (value) => setState(() => _installed = value ?? false),
            ),
          ],
        ),
        const SizedBox(height: WpSpacing.md),
        if (ref.watch(modelLibraryOfflineProvider))
          Padding(
            padding: const EdgeInsets.only(bottom: WpSpacing.md),
            child: Semantics(
              liveRegion: true,
              child: WpBanner(
                key: const ValueKey('model-library-offline'),
                tone: WpBannerTone.info,
                message: l10n.modelLibraryOffline,
              ),
            ),
          ),
        const _LibraryDownloadErrors(),
        WpSettingsGroup(
          children: [
            if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: WpSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      liveRegion: true,
                      child: Text(l10n.searchNoMatches),
                    ),
                    WpButton(
                      testId: 'model-library-reset',
                      label: l10n.modelLibraryReset,
                      variant: WpButtonVariant.ghost,
                      onPressed: () => setState(() {
                        _search.clear();
                        _kind = null;
                        _installed = false;
                      }),
                    ),
                  ],
                ),
              ),
            for (final entry in visible) _ModelEntryRow(entry: entry),
          ],
        ),
      ],
    );
  }
}

/// One glyph per model kind, the same in the list rows and the "+" menu:
/// the sound wave of the "Spracherkennung" settings area for speech models,
/// letters with lines for text models. It lets a scanning eye tell the two
/// kinds apart before reading the caption.
IconData modelLibraryKindIcon(ModelLibraryKind kind) => switch (kind) {
  ModelLibraryKind.speech => LucideIcons.audioLines,
  ModelLibraryKind.smartMode => LucideIcons.letterText,
};

String modelLibraryStatusLabel(L10n l10n, ModelLibraryEntry entry) =>
    switch (entry.status) {
      ModelLibraryStatus.notInstalled => l10n.modelLibraryStatusNotInstalled,
      ModelLibraryStatus.downloading => l10n.modelLibraryStatusDownloading(
        entry.percent,
      ),
      ModelLibraryStatus.checking => l10n.modelLibraryStatusChecking,
      ModelLibraryStatus.installed =>
        entry.location == ModelLocation.cloud
            ? l10n.modelLibraryStatusReady
            : l10n.modelLibraryStatusInstalled,
      ModelLibraryStatus.loading => l10n.modelLibraryStatusLoading,
      ModelLibraryStatus.active => l10n.modelLibraryStatusActive,
      ModelLibraryStatus.unavailable => l10n.modelLibraryStatusUnavailable,
      ModelLibraryStatus.failed => l10n.modelLibraryStatusFailed,
    };

/// Why an own model failed, in one sentence.
String userModelFailureText(L10n l10n, UserModelFailure failure) =>
    switch (failure) {
      UserModelFailure.download => l10n.modelLibraryFailureDownload,
      UserModelFailure.diskSpace => l10n.modelLibraryFailureDiskSpace,
      UserModelFailure.fileChanged => l10n.modelLibraryFailureFileChanged,
      UserModelFailure.missingFiles => l10n.modelLibraryFailureMissingFiles,
      UserModelFailure.badFormat ||
      UserModelFailure.unsupportedArchitecture ||
      UserModelFailure.noChatTemplate => l10n.modelLibraryFailureFormat,
      UserModelFailure.shortTestFailed ||
      UserModelFailure.shortTestEmpty ||
      UserModelFailure.crashed ||
      UserModelFailure.failedInUse => l10n.modelLibraryFailureTest,
      UserModelFailure.checkUnavailable => l10n.modelLibraryFailureCheck,
    };

String _speedText(L10n l10n, ModelLevel? level) => switch (level) {
  ModelLevel.high => l10n.modelLibrarySpeedHigh,
  ModelLevel.medium => l10n.modelLibrarySpeedMedium,
  ModelLevel.low => l10n.modelLibrarySpeedLow,
  null => l10n.modelLibrarySpeedUnknown,
};

String _accuracyText(L10n l10n, ModelLevel? level) => switch (level) {
  ModelLevel.high => l10n.modelLibraryAccuracyHigh,
  ModelLevel.medium => l10n.modelLibraryAccuracyMedium,
  ModelLevel.low => l10n.modelLibraryAccuracyLow,
  null => l10n.modelLibraryAccuracyUnknown,
};

/// [codes] as language names in the app language, comma-separated.
String languageNames(BuildContext context, Iterable<String> codes) =>
    [for (final code in codes) languageDisplayName(context, code)].join(', ');

/// The facts line: where it runs, size, languages, speed, accuracy. A model
/// the catalog says writes all of the user's languages says so with its
/// language count (#1953).
String modelLibraryFacts(L10n l10n, ModelLibraryEntry entry) => [
  entry.location == ModelLocation.local
      ? l10n.modelLibraryLocal
      : l10n.modelLibraryCloud,
  if (entry.sizeLabel.isNotEmpty) entry.sizeLabel,
  switch (entry.languages) {
    ModelLanguages.counted when entry.fitsLanguages =>
      l10n.modelLibraryLanguagesCountFits(entry.languageCount),
    ModelLanguages.counted => l10n.modelLibraryLanguagesCount(
      entry.languageCount,
    ),
    ModelLanguages.many => l10n.modelLibraryLanguagesMany,
    ModelLanguages.system => l10n.modelLibraryLanguagesSystem,
    ModelLanguages.provider => l10n.modelLibraryLanguagesProvider,
    ModelLanguages.unknown => l10n.modelLibraryLanguagesUnknown,
  },
  _speedText(l10n, entry.speed),
  _accuracyText(l10n, entry.accuracy),
  if (entry.smartProvider == SmartModeProviderType.local) ...[
    l10n.smartModeMemoryFootprintInfo,
    l10n.smartModeFactGuardHint,
  ],
].join(' · ');

/// Aligned columns at normal desktop sizes; stacked facts at narrow widths
/// and large text scales. Actions keep their labels through tooltips/semantics.
class _ModelEntryRow extends ConsumerWidget {
  const _ModelEntryRow({required this.entry});
  final ModelLibraryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final name = entry.name(l10n);
    final id = entry.id;
    final status = modelLibraryStatusLabel(l10n, entry);
    final kind = entry.kind == ModelLibraryKind.speech
        ? l10n.modelLibrarySpeechType
        : l10n.modelLibraryTextType;
    final failure = entry.failure == null
        ? null
        : userModelFailureText(l10n, entry.failure!);
    final details = [
      modelLibraryFacts(l10n, entry),
      if (!entry.verified) l10n.modelLibraryOwnModelsHint,
    ].join('\n');
    final missing = entry.missesLanguages
        ? l10n.modelLibraryNotForLanguages(
            languageNames(context, entry.missingLanguages!),
          )
        : null;
    final busy =
        entry.status == ModelLibraryStatus.downloading ||
        entry.status == ModelLibraryStatus.checking;
    final caption = TextStyle(
      fontSize: WpTypography.caption,
      color: WpColors.textMuted,
    );
    final statusBadge = WpAccentBadge(
      key: ValueKey('model-library-$id-status'),
      label: status,
      tone: entry.status == ModelLibraryStatus.active
          ? WpAccentBadgeTone.accent
          : WpAccentBadgeTone.muted,
    );
    final samplingTarget = localTextModelSamplingTarget(
      entry,
      ownPath: (id) =>
          ownSmartModelPathFor(id, ref.read(userModelStoreProvider)),
    );
    final actions = Wrap(
      spacing: WpSpacing.xxs,
      children: [
        if (entry.canInstall)
          WpIconButton.ghost(
            key: ValueKey('model-library-$id-install'),
            testId: 'model-library-$id-install',
            icon: LucideIcons.download,
            tooltip: '${l10n.modelLibraryInstall}: $name',
            onPressed: () =>
                unawaited(installLibraryEntry(context, ref, entry)),
          ),
        if (entry.canCancel)
          WpIconButton.ghost(
            key: ValueKey('model-library-$id-cancel'),
            testId: 'model-library-$id-cancel',
            icon: LucideIcons.x,
            tooltip: '${l10n.actionCancel}: $name',
            onPressed: () => cancelLibraryEntry(ref, entry),
          ),
        if (entry.canActivate)
          WpIconButton.ghost(
            key: ValueKey('model-library-$id-activate'),
            testId: 'model-library-$id-activate',
            icon: LucideIcons.check,
            tooltip: '${l10n.modelUse}: $name',
            onPressed: () =>
                unawaited(activateLibraryModel(context, ref, entry)),
          ),
        if (samplingTarget != null)
          WpIconButton.ghost(
            key: ValueKey('model-library-$id-sampling'),
            testId: 'model-library-$id-sampling',
            icon: LucideIcons.slidersHorizontal,
            tooltip: '${l10n.modelSamplingTitle}: $name',
            onPressed: () => unawaited(
              showModelSamplingDialog(
                context,
                modelId: samplingTarget.$1,
                modelName: name,
                modelPath: samplingTarget.$2,
              ),
            ),
          ),
        if (entry.canRetry)
          WpIconButton.ghost(
            key: ValueKey('model-library-$id-retry'),
            testId: 'model-library-$id-retry',
            icon: LucideIcons.refreshCw,
            tooltip: '${l10n.modelLibraryRetry}: $name',
            onPressed: () =>
                unawaited(ref.read(userModelsProvider.notifier).retry(id)),
          ),
        if (entry.canRemove)
          WpIconButton.ghost(
            key: ValueKey('model-library-$id-remove'),
            testId: 'model-library-$id-remove',
            icon: LucideIcons.trash2,
            tooltip: '${l10n.modelLibraryRemove}: $name',
            onPressed: () => unawaited(removeLibraryEntry(context, ref, entry)),
          ),
      ],
    );
    // Decorative for screen readers: the caption under the name already
    // says the kind, so the icon only adds the visual cue.
    final kindIcon = ExcludeSemantics(
      child: Tooltip(
        message: kind,
        child: Icon(
          modelLibraryKindIcon(entry.kind),
          key: ValueKey('model-library-$id-kind-icon'),
          size: WpIconSize.md,
          color: WpColors.textMuted,
        ),
      ),
    );
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: WpSpacing.xs,
          runSpacing: WpSpacing.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              name,
              style: TextStyle(
                fontSize: WpTypography.body,
                fontWeight: FontWeight.w600,
                color: WpColors.textPrimary,
              ),
            ),
            if (entry.recommended)
              Tooltip(
                message: entry.kind == ModelLibraryKind.speech
                    ? l10n.modelLibraryRecommendedDevice
                    : l10n.modelLibraryRecommended,
                child: Icon(
                  LucideIcons.star,
                  key: ValueKey('model-library-$id-recommended'),
                  size: WpIconSize.sm,
                  color: WpColors.accent,
                ),
              ),
            WpIconButton.ghost(
              key: ValueKey('model-library-$id-details'),
              icon: LucideIcons.info,
              compact: true,
              tooltip: details,
              onPressed: () => showWpDialog<void>(
                context: context,
                title: name,
                content: Text(details),
                actions: [
                  WpDialogAction<void>(
                    label: l10n.actionClose,
                    testId: 'model-library-details-close',
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: WpSpacing.xxs),
        Text(
          '$kind · ${entry.location == ModelLocation.local ? l10n.modelLibraryLocal : l10n.modelLibraryCloud}',
          style: caption,
        ),
        if (missing != null)
          Padding(
            padding: const EdgeInsets.only(top: WpSpacing.xxs),
            child: WpAccentBadge(
              key: ValueKey('model-library-$id-not-for'),
              label: missing,
              tone: WpAccentBadgeTone.muted,
            ),
          ),
        if (!entry.verified)
          Padding(
            padding: const EdgeInsets.only(top: WpSpacing.xxs),
            child: WpAccentBadge(
              key: ValueKey('model-library-$id-not-verified'),
              label: l10n.modelLibraryNotVerified,
              tone: WpAccentBadgeTone.muted,
            ),
          ),
      ],
    );
    return Semantics(
      key: ValueKey('model-library-$id'),
      identifier: 'model-library-$id',
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: WpSpacing.sm),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide =
                constraints.maxWidth >=
                460 * MediaQuery.textScalerOf(context).scale(1);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (wide)
                  Row(
                    children: [
                      kindIcon,
                      const SizedBox(width: WpSpacing.sm),
                      Expanded(child: title),
                      const SizedBox(width: WpSpacing.md),
                      SizedBox(
                        width: 60,
                        child: Text(entry.sizeLabel, style: caption),
                      ),
                      SizedBox(
                        width: 100,
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: statusBadge,
                        ),
                      ),
                      SizedBox(
                        width: 100,
                        child: Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: actions,
                        ),
                      ),
                    ],
                  )
                else ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      kindIcon,
                      const SizedBox(width: WpSpacing.sm),
                      Expanded(child: title),
                    ],
                  ),
                  const SizedBox(height: WpSpacing.xs),
                  Wrap(
                    spacing: WpSpacing.sm,
                    runSpacing: WpSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(entry.sizeLabel, style: caption),
                      statusBadge,
                      actions,
                    ],
                  ),
                ],
                if (failure != null)
                  Text(
                    failure,
                    key: ValueKey('model-library-$id-failure'),
                    style: caption.copyWith(color: WpColors.error),
                  ),
                if (busy)
                  Padding(
                    padding: const EdgeInsets.only(top: WpSpacing.xs),
                    child: WpProgressBar(
                      value: entry.status == ModelLibraryStatus.checking
                          ? null
                          : entry.percent / 100,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The sampling id and model file of [entry] when it is a local text model
/// on disk (the bundled Gemma once downloaded, or a ready own GGUF model),
/// else null: only those have "Einstellungen für dieses Modell" (#2204).
(String, String)? localTextModelSamplingTarget(
  ModelLibraryEntry entry, {
  required String? Function(String id) ownPath,
}) {
  if (entry.kind != ModelLibraryKind.smartMode) return null;
  final own = entry.userModel;
  if (own != null) {
    final path = own.isReady ? ownPath(own.id) : null;
    return path == null ? null : (own.id, path);
  }
  if (entry.smartProvider != SmartModeProviderType.local) return null;
  if (entry.status != ModelLibraryStatus.installed &&
      entry.status != ModelLibraryStatus.active) {
    return null;
  }
  return (kCatalogTextModelSamplingId, smartModeModelPath());
}

/// Opens "Add own model" for [kind] and starts the addition; its progress
/// shows in the list.
Future<void> addOwnLibraryModel(
  BuildContext context,
  WidgetRef ref,
  ModelLibraryKind kind,
) async {
  final draft = await showAddUserModelDialog(
    context,
    purpose: kind == ModelLibraryKind.speech
        ? UserModelPurpose.speech
        : UserModelPurpose.smartMode,
  );
  if (draft == null) return;
  final model = await ref.read(userModelsProvider.notifier).install(draft);
  if (model == null || !context.mounted) return;
  final l10n = L10n.of(context);
  announce(
    View.of(context),
    model.isReady
        ? l10n.modelLibraryAdded(model.name)
        : l10n.modelLibraryAddFailed(
            model.name,
            userModelFailureText(
              l10n,
              model.failure ?? UserModelFailure.checkUnavailable,
            ),
          ),
    Directionality.of(context),
  );
}

/// Installs [entry] through its download service. Whisper and the Smart
/// Mode model pass the RAM precheck first, as everywhere else.
Future<void> installLibraryEntry(
  BuildContext context,
  WidgetRef ref,
  ModelLibraryEntry entry,
) async {
  final speech = entry.speech;
  if (speech != null) {
    final base = ref.read(settingsProvider).value;
    if (speech.engine == SpeechModelEngine.whisper && base != null) {
      final target = base.copyWith(
        sttEngine: OnDeviceEngine.whisper.value,
        sttModel: speech.modelId,
      );
      if (!await confirmSttSettingsRam(context: context, settings: target)) {
        return;
      }
    }
    await downloadSpeechModel(
      model: speech,
      whisper: ref.read(modelDownloadProvider.notifier),
      parakeet: ref.read(parakeetDownloadProvider.notifier),
    );
    return;
  }
  if (entry.smartProvider == SmartModeProviderType.local && context.mounted) {
    await startSmartModeDownloadWithRamCheck(
      context: context,
      notifier: ref.read(smartModeDownloadProvider.notifier),
      l10n: L10n.of(context),
    );
  }
}

/// Stops the download of [entry].
void cancelLibraryEntry(WidgetRef ref, ModelLibraryEntry entry) {
  if (entry.userModel != null) {
    ref.read(userModelsProvider.notifier).cancel();
    return;
  }
  switch (entry.speech?.engine) {
    case SpeechModelEngine.whisper:
      ref.read(modelDownloadProvider.notifier).cancelDownload();
    case SpeechModelEngine.parakeet:
      ref.read(parakeetDownloadProvider.notifier).cancelDownload();
    case null when entry.smartProvider == SmartModeProviderType.local:
      ref.read(smartModeDownloadProvider.notifier).cancelDownload();
    default:
      break;
  }
}

/// Makes [entry] the model in use. A speech model passes the RAM precheck,
/// as the dock and the tray do.
Future<void> activateLibraryModel(
  BuildContext context,
  WidgetRef ref,
  ModelLibraryEntry entry,
) async {
  final own = entry.userModel;
  if (own != null) {
    // Remembers the checked model to return to, then puts the own one in use.
    await ref.read(userModelUseProvider).activate(own);
    if (!context.mounted) return;
    final l10n = L10n.of(context);
    announce(
      View.of(context),
      l10n.modelLibraryActivated(own.name),
      Directionality.of(context),
    );
    return;
  }
  final base = ref.read(settingsProvider).value;
  if (base == null) return;
  final next = activateLibraryEntry(base, entry);
  if (entry.speech != null &&
      !await confirmSttSettingsRam(context: context, settings: next)) {
    return;
  }
  await ref
      .read(settingsProvider.notifier)
      .updateSettings((s) => activateLibraryEntry(s, entry));
  if (!context.mounted) return;
  final l10n = L10n.of(context);
  announce(
    View.of(context),
    l10n.modelLibraryActivated(entry.name(l10n)),
    Directionality.of(context),
  );
}

/// Asks, then deletes the files of [entry]. The dialog names the space the
/// removal frees and, for the model in use, that it has to be replaced.
Future<void> removeLibraryEntry(
  BuildContext context,
  WidgetRef ref,
  ModelLibraryEntry entry,
) async {
  final l10n = L10n.of(context);
  final name = entry.name(l10n);
  final message = [
    if (entry.sizeLabel.isNotEmpty)
      l10n.modelLibraryRemoveMessage(entry.sizeLabel)
    else
      l10n.modelLibraryRemoveMessageNoSize,
    if (entry.status == ModelLibraryStatus.active)
      l10n.modelLibraryRemoveActiveNote,
  ].join(' ');
  final confirmed = await showWpConfirmDialog(
    context: context,
    title: l10n.modelLibraryRemoveTitle(name),
    message: message,
    confirmLabel: l10n.modelLibraryRemove,
    cancelLabel: l10n.actionCancel,
    destructive: true,
  );
  if (!confirmed) return;
  final speech = entry.speech;
  if (entry.userModel != null) {
    // A model in use gives way to a checked one before its files go.
    await ref.read(userModelUseProvider).beforeRemove(entry.id);
    ref.read(userModelsProvider.notifier).remove(entry.id);
  } else {
    switch (speech?.engine) {
      case SpeechModelEngine.whisper:
        await ref
            .read(modelDownloadProvider.notifier)
            .deleteModel(
              speech!.modelId,
              releaseEngine: ref
                  .read(localSttBundleProvider.notifier)
                  .releaseModel,
            );
      case SpeechModelEngine.parakeet:
        await ref.read(parakeetDownloadProvider.notifier).deleteBundle();
      case null when entry.smartProvider == SmartModeProviderType.local:
        await ref.read(smartModeDownloadProvider.notifier).deleteModel();
      default:
        return;
    }
  }
  if (!context.mounted) return;
  announce(
    View.of(context),
    entry.sizeLabel.isEmpty
        ? l10n.modelLibraryRemovedNoSize(name)
        : l10n.modelLibraryRemoved(name, entry.sizeLabel),
    Directionality.of(context),
  );
}

/// Keep recovery in the library, even when a filter hides the failed model.
class _LibraryDownloadErrors extends ConsumerWidget {
  const _LibraryDownloadErrors();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speech = ref.watch(modelDownloadProvider);
    final parakeet = ref.watch(parakeetDownloadProvider);
    final text = ref.watch(smartModeDownloadProvider);
    return Column(
      children: [
        if (speech.isError)
          WpModelDownloadErrorNotice(
            message: speech.errorMessage,
            kind: speech.errorKind,
            folder: sttDir,
            testIdPrefix: 'library-speech',
            onRetry: () =>
                unawaited(ref.read(modelDownloadProvider.notifier).retry()),
          ),
        if (parakeet.phase == ParakeetDownloadPhase.error)
          WpModelDownloadErrorNotice(
            message: parakeet.errorMessage,
            kind: parakeet.errorKind,
            folder: parakeetModelDir,
            testIdPrefix: 'library-parakeet',
            onRetry: () => unawaited(
              ref.read(parakeetDownloadProvider.notifier).downloadBundle(),
            ),
          ),
        if (text.isError)
          WpModelDownloadErrorNotice(
            message: text.errorMessage,
            kind: text.errorKind,
            folder: smartModeModelDir,
            testIdPrefix: 'library-text',
            onRetry: () => unawaited(
              startSmartModeDownloadWithRamCheck(
                context: context,
                notifier: ref.read(smartModeDownloadProvider.notifier),
                l10n: L10n.of(context),
              ),
            ),
          ),
      ],
    );
  }
}
