import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localized_locales/flutter_localized_locales.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/config/selectable_speech_models.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../services/app_profiles/app_profile.dart';
import '../../../services/app_profiles/app_profile_context_edits.dart';
import '../../../services/app_profiles/app_profile_choice.dart';
import '../../../services/app_profiles/app_profile_editing.dart';
import '../../../services/app_profiles/app_profile_repository.dart';
import '../../../services/app_profiles/app_profile_resolver.dart';
import '../../../services/app_profiles/app_target_capture.dart';
import '../../../services/audio_service.dart' show audioInputDevicesProvider;
import '../../../widgets/dialog.dart';
import '../../../widgets/hotkey_recorder.dart';
import '../../../widgets/wp_button.dart';
import '../hotkey_flow.dart' show activeHotkeyBindings;
import '../settings_widgets.dart';
import '../widgets/wp_settings_group.dart';
import 'profile_options.dart';

/// The editable fields of one profile. Every change is saved at once; a field
/// on "Unverändert lassen" is stored as `null`, so activating the profile does
/// not touch that setting.
class ProfileDetailGroup extends ConsumerStatefulWidget {
  const ProfileDetailGroup({
    super.key,
    required this.profile,
    required this.profiles,
    required this.onDeleted,
  });

  final AppProfile profile;

  /// All profiles, in order: the hotkey and app checks need them.
  final List<AppProfile> profiles;

  /// Called after the profile was deleted, so the list drops its selection.
  final VoidCallback onDeleted;

  @override
  ConsumerState<ProfileDetailGroup> createState() => _ProfileDetailGroupState();
}

class _ProfileDetailGroupState extends ConsumerState<ProfileDetailGroup> {
  late final TextEditingController _name = TextEditingController(
    text: widget.profile.name,
  );
  final TextEditingController _app = TextEditingController();
  String? _nameError;
  String? _appError;
  Timer? _countdownTimer;
  int? _countdown;
  AppCaptureOutcome? _captureResult;
  String? _capturedName;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _name.dispose();
    _app.dispose();
    super.dispose();
  }

  Future<void> _save(AppProfile next) =>
      ref.read(appProfilesProvider.notifier).save(next);

  void _saveName(String raw) {
    final name = cleanAppProfileName(raw);
    setState(
      () =>
          _nameError = name == null ? L10n.of(context).profilesNameEmpty : null,
    );
    if (name == null) return;
    unawaited(_save(widget.profile.copyWith(name: name)));
  }

  void _addApp(String raw) {
    final identifier = raw.trim();
    if (identifier.isEmpty) return;
    _addIdentifier(identifier);
    _app.clear();
  }

  /// Adds one app rule unless another profile already claims it. Returns
  /// whether the rule was added.
  bool _addIdentifier(String identifier) {
    final clash = appRuleClashName(
      identifier: identifier,
      profile: widget.profile,
      profiles: widget.profiles,
    );
    if (clash != null) {
      setState(() => _appError = L10n.of(context).profileAppClash(clash));
      return false;
    }
    setState(() => _appError = null);
    unawaited(
      _save(
        widget.profile.copyWith(
          rules: [
            ...widget.profile.rules,
            AppMatchRule(identifier: identifier),
          ],
        ),
      ),
    );
    return true;
  }

  /// "App erfassen": a three-second countdown, then the app in front is read.
  /// The countdown runs inline, not in a dialog: a dialog would make WhisPaste
  /// the app in front and the capture would find nothing.
  void _startCapture() {
    if (_countdown != null) return;
    setState(() {
      _countdown = 3;
      _captureResult = null;
      _capturedName = null;
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final left = (_countdown ?? 1) - 1;
      if (left > 0) {
        setState(() => _countdown = left);
        return;
      }
      timer.cancel();
      unawaited(_finishCapture());
    });
  }

  Future<void> _finishCapture() async {
    final outcome = await ref.read(appCaptureProvider)();
    if (!mounted) return;
    setState(() {
      _countdown = null;
      _captureResult = outcome;
    });
    if (outcome case AppCaptured(:final identifier)) {
      final added = _addIdentifier(identifier);
      setState(() => _capturedName = added ? identifier : null);
    }
  }

  void _removeApp(AppMatchRule rule) {
    unawaited(
      _save(
        widget.profile.copyWith(
          rules: [
            for (final other in widget.profile.rules)
              if (other != rule) other,
          ],
        ),
      ),
    );
  }

  Future<void> _recordHotkey() async {
    final profile = widget.profile;
    final result = await WpHotkeyRecorderDialog.show(
      context,
      initialKey: profile.hotkeyKey,
      initialDisplayKey: profile.hotkeyKey,
      initialModifiers: profile.hotkeyModifiers,
    );
    if (result == null || !mounted) return;
    unawaited(
      _save(
        profile.copyWith(
          hotkeyKey: result.key,
          hotkeyModifiers: result.modifiers,
        ),
      ),
    );
  }

  Future<void> _setContext(AppProfileContextSource source) async {
    final profile = widget.profile;
    final providerId =
        ref.read(settingsProvider).value?.smartMode.provider ??
        AppSettings.defaults.smartMode.provider;
    final l10n = L10n.of(context);
    var consent = profile.consentAfterContextEdit(source, providerId);
    if (profile.contextEditNeedsGrant(source, providerId)) {
      final agreed = await showWpConfirmDialog(
        context: context,
        title: l10n.profileConsentTitle,
        message: l10n.profileConsentBody,
        confirmLabel: l10n.profileConsentAccept,
      );
      if (!agreed || !mounted) return;
      consent = profile.grantContextConsent(source, providerId);
    }
    unawaited(_save(profile.copyWith(contextSource: source, consent: consent)));
  }

  void _withdrawConsent() {
    unawaited(_save(widget.profile.copyWith(consent: null)));
  }

  Future<void> _delete() async {
    final l10n = L10n.of(context);
    final profile = widget.profile;
    final confirmed = await showWpConfirmDialog(
      context: context,
      title: l10n.profileDeleteTitle(profile.name),
      message: l10n.profileDeleteMessage,
      confirmLabel: l10n.profileDeleteAction,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final choice = ref.read(profileChoiceProvider);
    if (choice is ProfileChoiceProfile && choice.profileId == profile.id) {
      ref
          .read(profileChoiceProvider.notifier)
          .select(const ProfileChoiceAutomatic());
    }
    await ref.read(appProfilesProvider.notifier).delete(profile.id);
    if (mounted) widget.onDeleted();
  }

  /// The line under the app input: the result of the last capture, or nothing.
  String? _captureStatus(L10n l10n) {
    if (_captureResult == null) return null;
    return switch (_captureResult!) {
      AppCaptured() when _capturedName != null => l10n.profileAppCaptured(
        _capturedName!,
      ),
      AppCaptured() => null,
      AppCaptureNoForeignApp() => l10n.profileAppCaptureNone,
      AppCaptureUnavailable() => l10n.profileAppCaptureUnavailable,
    };
  }

  ProfileHotkeyConflict? _hotkeyConflict(AppSettings settings, L10n l10n) {
    final profile = widget.profile;
    if (!profile.hasHotkey) return null;
    return profileHotkeyConflict(
      key: profile.hotkeyKey!,
      modifiers: profile.hotkeyModifiers ?? '',
      profileId: profile.id,
      profiles: widget.profiles,
      appBindings: activeHotkeyBindings(settings, l10n),
      onlyEarlier: true,
    );
  }

  bool _consentGiven(String providerId) =>
      widget.profile.consentCoversContext(providerId);

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final profile = widget.profile;
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final providerId = settings.smartMode.provider;
    final keep = l10n.profileKeepUnchanged;
    String unavailable(String value) => l10n.profileValueUnavailable(value);

    final modelOptions = withKeepEntry(
      keep,
      withStoredEntry(
        profileSpeechModelOptions(
          models: ref.watch(selectableSpeechModelsProvider),
          l10n: l10n,
        ),
        profile.modelId,
        unavailable,
      ),
    );
    final languageOptions = withKeepEntry(
      keep,
      withStoredEntry(
        profileLanguageOptions(
          l10n: l10n,
          localeNames: LocaleNames.of(context),
        ),
        profile.asrLanguage,
        unavailable,
      ),
    );
    final micOptions = withKeepEntry(
      keep,
      withStoredEntry(
        profileMicrophoneOptions(
          l10n: l10n,
          devices: ref.watch(audioInputDevicesProvider).value ?? const [],
        ),
        profile.microphone,
        unavailable,
      ),
    );
    final smartOptions = withKeepEntry(keep, profileSmartModeOptions(l10n));
    final afterOptions = withKeepEntry(
      keep,
      profileAfterTranscriptionOptions(l10n),
    );
    final contextOptions = [
      (value: 'none', label: l10n.profileContextNone),
      (value: 'selection', label: l10n.profileContextSelection),
      (value: 'clipboard', label: l10n.profileContextClipboard),
    ];

    final conflict = _hotkeyConflict(settings, l10n);
    final consentGiven = _consentGiven(providerId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WpSettingsGroup(
          heading: l10n.profileDetailHeading,
          children: [
            WpSettingsRow(
              rowId: 'profiles-detail-name',
              title: l10n.profilesNameLabel,
              trailing: KeyedSubtree(
                key: const ValueKey('profile-detail-name'),
                child: settingsTextField(
                  context: context,
                  controller: _name,
                  semanticLabel: l10n.profilesNameLabel,
                  onChanged: _saveName,
                ),
              ),
              subtitle: _nameError,
            ),
            _ChoiceRow(
              rowId: 'profiles-detail-model',
              testId: 'profile-detail-model',
              title: l10n.profileDetailModel,
              value: profile.modelId ?? kProfileKeepValue,
              options: modelOptions,
              onChanged: (v) => _save(
                profile.copyWith(modelId: v == kProfileKeepValue ? null : v),
              ),
            ),
            _ChoiceRow(
              rowId: 'profiles-detail-language',
              testId: 'profile-detail-language',
              title: l10n.profileDetailLanguage,
              subtitle: l10n.profileDetailLanguageSubtitle,
              value: profile.asrLanguage ?? kProfileKeepValue,
              options: languageOptions,
              onChanged: (v) => _save(
                profile.copyWith(
                  asrLanguage: v == kProfileKeepValue ? null : v,
                ),
              ),
            ),
            _ChoiceRow(
              rowId: 'profiles-detail-smart-mode',
              testId: 'profile-detail-smart-mode',
              title: l10n.profileDetailSmartMode,
              value: profile.smartMode == AppProfileSmartMode.standard
                  ? kProfileKeepValue
                  : profile.smartMode.storageValue,
              options: smartOptions,
              onChanged: (v) => _save(
                profile.copyWith(
                  smartMode: v == kProfileKeepValue
                      ? AppProfileSmartMode.standard
                      : AppProfileSmartMode.values.firstWhere(
                          (m) => m.storageValue == v,
                        ),
                ),
              ),
            ),
            _ChoiceRow(
              rowId: 'profiles-detail-after',
              testId: 'profile-detail-after',
              title: l10n.profileDetailAfter,
              value: profile.afterTranscription ?? kProfileKeepValue,
              options: afterOptions,
              onChanged: (v) => _save(
                profile.copyWith(
                  afterTranscription: v == kProfileKeepValue ? null : v,
                ),
              ),
            ),
            _ChoiceRow(
              rowId: 'profiles-detail-microphone',
              testId: 'profile-detail-microphone',
              title: l10n.profileDetailMicrophone,
              value: profile.microphone ?? kProfileKeepValue,
              options: micOptions,
              onChanged: (v) => _save(
                profile.copyWith(microphone: v == kProfileKeepValue ? null : v),
              ),
            ),
            WpSettingsRow(
              rowId: 'profiles-detail-hotkey',
              title: l10n.profileDetailHotkey,
              subtitle: l10n.profileDetailHotkeySubtitle,
              trailing: KeyedSubtree(
                key: const ValueKey('profile-detail-hotkey'),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    if (profile.hasHotkey)
                      HotkeyDisplay(
                        hotkeyKey: profile.hotkeyKey!,
                        hotkeyModifiers: profile.hotkeyModifiers ?? '',
                        hotkeyKeyDisplay: profile.hotkeyKey!,
                      )
                    else
                      Text(l10n.profileHotkeyNone),
                    WpButton(
                      label: l10n.profileHotkeyChange,
                      variant: WpButtonVariant.secondary,
                      testId: 'profile-detail-hotkey-change',
                      onPressed: _recordHotkey,
                    ),
                    if (profile.hasHotkey)
                      WpButton(
                        label: l10n.profileHotkeyRemove,
                        variant: WpButtonVariant.ghost,
                        testId: 'profile-detail-hotkey-remove',
                        onPressed: () => unawaited(
                          _save(
                            profile.copyWith(
                              hotkeyKey: null,
                              hotkeyModifiers: null,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (conflict != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: HotkeyNotice(
              noticeKey: const Key('profile-detail-hotkey-notice'),
              icon: LucideIcons.info,
              color: WpColors.warning,
              text: switch (conflict) {
                ProfileHotkeyNeedsModifier() => l10n.profileHotkeyNeedsModifier,
                ProfileHotkeyTakenByApp(:final actionLabel) =>
                  l10n.profileHotkeyTakenByApp(actionLabel),
                ProfileHotkeyTakenByProfile(:final profileName) =>
                  l10n.profileHotkeyTakenByProfile(profileName),
              },
            ),
          ),
        const SizedBox(height: 16),
        WpSettingsGroup(
          heading: l10n.profileDetailApps,
          children: [
            WpSettingsRow(
              rowId: 'profiles-detail-apps',
              title: l10n.profileDetailApps,
              subtitle:
                  '${l10n.profileDetailAppsSubtitle}\n'
                  '${l10n.profileAppHintMac}\n'
                  '${l10n.profileAppHintWindows}\n'
                  '${l10n.profileAppHintLinux}',
              trailing: KeyedSubtree(
                key: const ValueKey('profile-detail-apps-input'),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    settingsTextField(
                      context: context,
                      controller: _app,
                      hintText: l10n.profileAppIdentifierLabel,
                      semanticLabel: l10n.profileAppIdentifierLabel,
                    ),
                    WpButton(
                      label: l10n.profileAppAdd,
                      variant: WpButtonVariant.secondary,
                      testId: 'profile-detail-app-add',
                      onPressed: () => _addApp(_app.text),
                    ),
                    WpButton(
                      label: _countdown == null
                          ? l10n.profileAppCapture
                          : l10n.profileAppCaptureCountdown(_countdown!),
                      variant: WpButtonVariant.secondary,
                      testId: 'profile-detail-app-capture',
                      onPressed: _countdown == null ? _startCapture : null,
                    ),
                  ],
                ),
              ),
            ),
            if (_captureStatus(l10n) case final status?)
              Padding(
                key: const ValueKey('profile-detail-app-capture-status'),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  status,
                  style: TextStyle(color: WpColors.textMuted),
                ),
              ),
            if (_appError != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  _appError!,
                  style: TextStyle(color: WpColors.error),
                ),
              ),
            for (final rule in profile.rules)
              WpSettingsRow(
                rowId: 'profiles-detail-apps-rule-${rule.identifier}',
                title: rule.identifier,
                indent: true,
                trailing: WpButton(
                  label: l10n.profileAppRemove,
                  variant: WpButtonVariant.ghost,
                  testId: 'profile-detail-app-remove-${rule.identifier}',
                  onPressed: () => _removeApp(rule),
                ),
              ),
            if (profile.rules.isEmpty)
              WpSettingsRow(
                rowId: 'profiles-detail-apps-empty',
                title: l10n.profileAppEmpty,
                trailing: const SizedBox.shrink(),
              ),
          ],
        ),
        const SizedBox(height: 16),
        WpSettingsGroup(
          heading: l10n.profileDetailContext,
          children: [
            _ChoiceRow(
              rowId: 'profiles-detail-context',
              testId: 'profile-detail-context',
              title: l10n.profileDetailContext,
              subtitle: l10n.profileDetailContextSubtitle,
              value: profile.contextSourceName,
              options: contextOptions,
              onChanged: (v) => unawaited(
                _setContext(
                  AppProfileContextSource.values.firstWhere((s) => s.name == v),
                ),
              ),
            ),
            if (profile.hasContextSource)
              WpSettingsRow(
                rowId: 'profiles-detail-context-consent',
                title: consentGiven
                    ? l10n.profileConsentGiven
                    : l10n.profileConsentMissing,
                trailing: consentGiven
                    ? WpButton(
                        label: l10n.profileConsentWithdraw,
                        variant: WpButtonVariant.ghost,
                        testId: 'profile-detail-consent-withdraw',
                        onPressed: _withdrawConsent,
                      )
                    : const SizedBox.shrink(),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: WpButton(
            label: l10n.profileDeleteAction,
            variant: WpButtonVariant.secondary,
            tone: WpButtonTone.danger,
            testId: 'profile-detail-delete',
            onPressed: _delete,
          ),
        ),
      ],
    );
  }
}

/// One dropdown row of the detail group. [value] must be one of [options].
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.rowId,
    required this.testId,
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
    this.subtitle,
  });

  final String rowId;
  final String testId;
  final String title;
  final String? subtitle;
  final String value;
  final List<ProfileOption> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return WpSettingsRow(
      rowId: rowId,
      title: title,
      subtitle: subtitle,
      trailing: KeyedSubtree(
        key: ValueKey(testId),
        child: settingsDropdown(
          context: context,
          value: value,
          items: [for (final option in options) option.value],
          labels: [for (final option in options) option.label],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}
