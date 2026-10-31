import 'dart:async';

import 'package:flutter/foundation.dart'
    show ValueListenable, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart' show InputDevice;

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/audio_service.dart' show audioInputDevicesProvider;
import '../../../services/microphone_selection_service.dart';
import '../../../services/permissions/mic_permission_notifier.dart';
import '../../../widgets/wp_button.dart';
import '../../../widgets/wp_dropdown.dart';
import '../../../widgets/wp_hero_button.dart';
import '../mic_probe.dart';
import '../onboarding_download_provider.dart';
import '../onboarding_download_status.dart';
import '../onboarding_scene.dart';
import '../onboarding_split_page.dart';
import 'onboarding_headings.dart';
import '../onboarding_mic_gate.dart';

/// Microphone page body (Onboarding v6, ticket V04, S3).
///
/// One level card with the device picker at its top left, a single status
/// line, and the secondary way "Überspringen". The page's one statement is the
/// page heading in the shell. The shell holds "Weiter" until speech has been
/// heard ([onboardingMicSpeechHeardProvider]).
///
/// The microphone permission belongs to the Access page. This page only asks
/// for it again when it is still missing, in one line with a single action
/// (no second permission card). The level probe starts only once the
/// permission is granted, because the probe's own permission check may raise
/// the operating-system dialog.
class AccessMicStep extends ConsumerStatefulWidget {
  const AccessMicStep({
    super.key,
    required this.onSkip,
    required this.onNext,
    this.onBack,
    this.primaryKey,
  });

  /// Moves on without speech ("Überspringen").
  final VoidCallback onSkip;

  /// The primary "Weiter"; `null` holds it until speech is heard (S3).
  final VoidCallback? onNext;

  /// "Zurück" above the heading; `null` hides it.
  final VoidCallback? onBack;

  /// Key of the primary button, for the flow's keyboard handling.
  final Key? primaryKey;

  @override
  ConsumerState<AccessMicStep> createState() => _AccessMicStepState();
}

class _AccessMicStepState extends ConsumerState<AccessMicStep>
    with WidgetsBindingObserver {
  late final OnboardingMicProbe _probe = ref.read(onboardingMicProbeProvider);
  final FocusNode _deviceFocus = FocusNode(debugLabel: 'onboardingMicDevice');

  /// Bumped on every start. Outcomes of a superseded run are ignored.
  int _run = 0;

  /// Result of the current probe run, or `null` while it listens. The probe
  /// only resolves on speech, a denied permission or an error.
  MicProbeOutcome? _outcome;

  /// Set once the current run has heard nothing for
  /// [kOnboardingMicSilenceTimeout]. Speech still clears it.
  bool _silent = false;

  Timer? _silenceTimer;

  /// Set once the current run has heard nothing for [_kQuietAfter]: the
  /// first, gentle stage before [_silent].
  bool _quiet = false;
  Timer? _quietTimer;

  /// Retries a failed device on its own every [_kRetryEvery], so plugging
  /// the microphone back in or closing the app that held it is enough.
  Timer? _retryTimer;

  bool get _linux => defaultTargetPlatform == TargetPlatform.linux;

  bool get _permissionOk =>
      _linux ||
      ref.read(micPermissionNotifierProvider).status ==
          MicPermissionStatus.granted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _probe.capturing.addListener(_onCapturing);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_permissionOk) {
        unawaited(_start());
      } else {
        // Side-effect-free status read. A grant found here flips the state,
        // and the listener in build() starts the probe.
        unawaited(ref.read(micPermissionNotifierProvider.notifier).check());
      }
    });
  }

  /// Back from System Settings: read the permission again, so a grant
  /// given there starts the test without another click.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_permissionOk) {
      unawaited(ref.read(micPermissionNotifierProvider.notifier).check());
    }
  }

  /// A retry got the device back: the error goes at once, not only on speech.
  void _onCapturing() {
    if (!mounted || !_probe.capturing.value) return;
    if (_deviceFailed(_outcome)) setState(() => _outcome = null);
  }

  static bool _deviceFailed(MicProbeOutcome? outcome) =>
      outcome == MicProbeOutcome.error ||
      outcome == MicProbeOutcome.noDevice ||
      outcome == MicProbeOutcome.disconnected;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _probe.capturing.removeListener(_onCapturing);
    _quietTimer?.cancel();
    _retryTimer?.cancel();
    _silenceTimer?.cancel();
    unawaited(_probe.stop());
    _deviceFocus.dispose();
    super.dispose();
  }

  /// Starts (or restarts) one probe run on the device chosen in Settings.
  ///
  /// A [retry] keeps the shown device error until the device is back, so the
  /// status does not flicker every [_kRetryEvery].
  Future<void> _start({bool retry = false}) async {
    if (!mounted) return;
    final run = ++_run;
    _silenceTimer?.cancel();
    _quietTimer?.cancel();
    _retryTimer?.cancel();
    await _probe.stop();
    if (!mounted || run != _run) return;
    setState(() {
      if (!retry) _outcome = null;
      _silent = false;
      _quiet = false;
    });
    _quietTimer = Timer(_kQuietAfter, () {
      if (!mounted || run != _run) return;
      if (ref.read(onboardingMicSpeechHeardProvider)) return;
      setState(() => _quiet = true);
    });
    _silenceTimer = Timer(kOnboardingMicSilenceTimeout, () {
      if (!mounted || run != _run) return;
      if (ref.read(onboardingMicSpeechHeardProvider)) return;
      setState(() => _silent = true);
    });

    final device = await _deviceFor(_selectedLabel());
    if (!mounted || run != _run) return;
    final outcome = await _probe.start(device: device);
    if (!mounted || run != _run) return;
    _silenceTimer?.cancel();
    _quietTimer?.cancel();
    if (_deviceFailed(outcome)) {
      _retryTimer = Timer(_kRetryEvery, () {
        if (mounted && run == _run) unawaited(_start(retry: true));
      });
    }
    if (outcome == MicProbeOutcome.speechDetected) {
      ref.read(onboardingMicSpeechHeardProvider.notifier).markHeard();
    }
    setState(() {
      _outcome = outcome;
      if (outcome == MicProbeOutcome.speechDetected) _silent = false;
    });
  }

  String _selectedLabel() =>
      ref.read(settingsProvider).value?.audioInput.microphone ??
      micDefaultLabel;

  /// The probe takes a device object, not a label. The system default needs
  /// none.
  Future<InputDevice?> _deviceFor(String label) async {
    if (label == micDefaultLabel) return null;
    final devices = await _probe.listInputDevices();
    for (final device in devices) {
      if (device.label == label) return device;
    }
    return null;
  }

  /// Persists the choice through the shared selection path (the same one the
  /// tray and the status-bar chip use) and listens again on the new device.
  Future<void> _selectDevice(String label) async {
    await ref.read(microphoneSelectionServiceProvider).select(label);
    if (!mounted) return;
    await _start();
  }

  void _requestPermission() {
    unawaited(ref.read(micPermissionNotifierProvider.notifier).request());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<MicPermissionState>(micPermissionNotifierProvider, (
      previous,
      next,
    ) {
      if (next.status == MicPermissionStatus.granted &&
          previous?.status != MicPermissionStatus.granted) {
        unawaited(_start());
      }
    });

    final l10n = L10n.of(context);
    final permission = ref.watch(micPermissionNotifierProvider).status;
    final heard = ref.watch(onboardingMicSpeechHeardProvider);

    final permissionMissing =
        !_linux &&
        (_outcome == MicProbeOutcome.permissionDenied ||
            (permission != MicPermissionStatus.granted &&
                permission != MicPermissionStatus.requesting));

    final devices =
        ref.watch(audioInputDevicesProvider).value ?? const [micDefaultLabel];
    final selected =
        ref.watch(settingsProvider).value?.audioInput.microphone ??
        micDefaultLabel;
    final options = buildMicrophoneOptions(
      deviceLabels: devices,
      selectedLabel: selected,
    );

    final compact = onboardingCompactText(context);
    final gap = compact ? WpSpacing.lg : WpSpacing.xl;
    return OnboardingSplitPage(
      panelAsset: 'assets/onboarding/welcome-klangbaender.webp',
      panel: _MicScene(level: _probe.level, heard: heard),
      copy: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.onBack != null)
            OnboardingBackLink(
              testId: 'onboarding-mic-back',
              label: l10n.onboardingBack,
              onPressed: widget.onBack!,
            ),
          OnboardingSplitHeading(
            l10n.onboardingMicTitle,
            testId: 'onboarding-mic-heading',
          ),
          const SizedBox(height: WpSpacing.sm),
          Text(
            l10n.onboardingMicStatement,
            style: TextStyle(
              fontSize: WpTypography.body,
              height: 1.45,
              color: WpColors.textSecondary,
            ),
          ),
          SizedBox(height: gap),
          SizedBox(
            width: kOnboardingCopyWidth,
            child: WpDropdown<String>(
              expanded: true,
              testId: 'onboarding-mic-device',
              focusNode: _deviceFocus,
              value: selected,
              items: [
                for (final option in options)
                  WpDropdownItem<String>(
                    value: option,
                    label: option == micDefaultLabel
                        ? l10n.settingsMicSystemDefault
                        : option,
                  ),
              ],
              onChanged: (label) {
                if (label != null) unawaited(_selectDevice(label));
              },
            ),
          ),
          if (_looksBluetooth(selected)) ...[
            const SizedBox(height: WpSpacing.xs),
            SizedBox(
              width: kOnboardingCopyWidth,
              child: Text(
                l10n.onboardingMicBluetoothHint,
                style: TextStyle(
                  fontSize: WpTypography.small,
                  height: 1.4,
                  color: WpColors.textMuted,
                ),
              ),
            ),
          ],
          const SizedBox(height: WpSpacing.md),
          // A minimum height for the status, so the button below does not
          // jump when a one-line status appears or goes.
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Semantics(
                liveRegion: true,
                identifier: 'onboarding-mic-status',
                child: _statusLine(
                  l10n: l10n,
                  permissionMissing: permissionMissing,
                  heard: heard,
                  silent: _silent,
                  quiet: _quiet,
                  outcome: _outcome,
                ),
              ),
            ),
          ),
          SizedBox(height: gap),
          SizedBox(
            width: kOnboardingCopyWidth,
            child: WpHeroButton(
              testId: 'onboarding-mic-next',
              key: widget.primaryKey,
              label: l10n.onboardingNext,
              onPressed: widget.onNext,
            ),
          ),
          if (!heard) ...[
            const SizedBox(height: WpSpacing.sm),
            WpButton(
              testId: 'onboarding-mic-skip',
              label: l10n.onboardingMicSkip,
              variant: WpButtonVariant.ghost,
              tone: WpButtonTone.neutral,
              onPressed: widget.onSkip,
            ),
          ],
          if (_modelLikelyLate(ref.watch(onboardingDownloadStatusProvider)))
            Padding(
              padding: const EdgeInsets.only(top: WpSpacing.md),
              child: SizedBox(
                width: kOnboardingCopyWidth,
                child: Text(
                  l10n.onboardingMicModelStillLoading,
                  style: TextStyle(
                    fontSize: WpTypography.small,
                    height: 1.4,
                    color: WpColors.textMuted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Whether the speech model will probably still be loading when the
  /// try-out page needs it: the download runs and is not about to finish
  /// (or its remaining time is not measured yet). Said here, two pages
  /// ahead, so the wait there is no surprise.
  bool _modelLikelyLate(OnboardingDownloadStatus status) {
    final running =
        status.phase == OnboardingDownloadPhase.running ||
        status.phase == OnboardingDownloadPhase.verifying;
    final remaining = status.remaining;
    return running && (remaining == null || remaining > _kModelLateThreshold);
  }

  /// Bluetooth headsets switch to a narrow call codec while their microphone
  /// is open, which costs recognition quality. Known only from the name.
  static bool _looksBluetooth(String label) => RegExp(
    r'airpods|bluetooth|headset|buds|\bbt\b|hands-free|freisprech',
    caseSensitive: false,
  ).hasMatch(label);

  Widget _statusLine({
    required L10n l10n,
    required bool permissionMissing,
    required bool heard,
    required bool silent,
    required bool quiet,
    required MicProbeOutcome? outcome,
  }) {
    if (permissionMissing) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              l10n.onboardingMicPermissionLine,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: WpSpacing.md),
          WpButton(
            testId: 'onboarding-mic-allow',
            label: l10n.permissionRowAllow,
            variant: WpButtonVariant.ghost,
            tone: WpButtonTone.accent,
            onPressed: _requestPermission,
          ),
        ],
      );
    }
    if (heard) {
      // A live region: the confirmation is announced as soon as speech lands.
      return Semantics(
        liveRegion: true,
        child: Text(
          l10n.onboardingMicHeard,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    // Device trouble first: it explains a silence too. Each names the
    // cause; the ones the user can fix offer the picker, and all of them
    // retry on their own.
    final (String? line, bool offerPicker) = switch (outcome) {
      MicProbeOutcome.noDevice => (l10n.onboardingMicNoDevice, false),
      MicProbeOutcome.disconnected => (l10n.onboardingMicDisconnected, true),
      MicProbeOutcome.error => (l10n.onboardingMicOpenError, true),
      _ when silent => (l10n.onboardingMicSilence, true),
      _ when quiet => (l10n.onboardingMicQuiet, false),
      _ => (null, false),
    };
    if (line == null) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(line, style: Theme.of(context).textTheme.bodyMedium),
        ),
        if (offerPicker) ...[
          const SizedBox(width: WpSpacing.md),
          WpButton(
            testId: 'onboarding-mic-silence-prompt',
            label: l10n.onboardingMicChooseOther,
            variant: WpButtonVariant.ghost,
            tone: WpButtonTone.accent,
            // Moves focus to the picker, so the keyboard can choose at once.
            onPressed: _deviceFocus.requestFocus,
          ),
        ],
      ],
    );
  }
}

/// The panel: the waveform pill large on the painting, following the
/// microphone live, the one thing to look at while you speak. Grey while
/// nothing usable has arrived, amber once speech was heard, so the answer to
/// "does it work?" sits right where the eye already is. It follows the
/// signal under reduced motion too (bar heights, no own animation).
class _MicScene extends StatelessWidget {
  const _MicScene({required this.level, required this.heard});

  final ValueListenable<double> level;
  final bool heard;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Center(
      child: Semantics(
        label: l10n.onboardingMicLevelLabel,
        identifier: 'onboarding-mic-level',
        child: ExcludeSemantics(
          child: RepaintBoundary(
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: heard ? 1 : 0),
              duration: WpMotion.durationFor(context, WpMotion.dramatic),
              curve: WpMotion.defaultCurve,
              builder: (context, lit, _) => ValueListenableBuilder<double>(
                valueListenable: level,
                builder: (context, value, _) =>
                    OnboardingWavePill(level: value, lit: lit, scale: 2.6),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Remaining download time above which the microphone test mentions it:
/// about what the hotkey page takes.
const Duration _kModelLateThreshold = Duration(minutes: 2);

/// First, gentle silence stage: "speak up" before "choose another device".
const Duration _kQuietAfter = Duration(seconds: 5);

/// Interval of the automatic retry after a device error.
const Duration _kRetryEvery = Duration(seconds: 2);
