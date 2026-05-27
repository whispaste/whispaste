import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:record/record.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/audio_routing_service.dart';
import '../../../widgets/wp_accent_button.dart';
import '../mic_probe.dart';

// ---------------------------------------------------------------------------
// Mic step state machine
// ---------------------------------------------------------------------------

enum _MicPhase {
  /// Initial — show "Grant access" button.
  idle,

  /// OS permission dialog is in flight.
  requesting,

  /// Permission was denied — show TCC instructions.
  denied,

  /// Permission granted, live capture running, waveform reflects real audio.
  verifying,

  /// Capture completed but never crossed the speech threshold. Retry CTA +
  /// device picker get prominent treatment.
  silent,

  /// Mic confirmed working — Next button unlocks.
  ready,
}

/// Onboarding Step 2 — Microphone permission **and** an honest capture test.
///
/// Opens a real PCM stream, drives a live waveform off the measured amplitude,
/// and only advances once a sustained signal above the speech threshold is
/// actually detected. Lets the user pick a different input device on the spot
/// if the default mic is wrong (very common: a USB headset that's muted, a
/// virtual cable, or a webcam mic that isn't actually pointed at the user).
class MicrophoneStep extends StatefulWidget {
  const MicrophoneStep({
    super.key,
    required this.onNext,
    required this.onBack,
    this.probeFactory,
    AudioRoutingService? routing,
  }) : _injectedRouting = routing;

  final VoidCallback onNext;
  final VoidCallback onBack;

  /// Test seam: lets widget tests inject a fake probe without touching the
  /// real audio plugin. `null` in production → real probe.
  final OnboardingMicProbe Function()? probeFactory;

  /// Test seam for the macOS routing service. `null` in production → real
  /// implementation.
  final AudioRoutingService? _injectedRouting;

  @override
  State<MicrophoneStep> createState() => _MicrophoneStepState();
}

class _MicrophoneStepState extends State<MicrophoneStep> {
  _MicPhase _phase = _MicPhase.idle;
  OnboardingMicProbe? _probe;

  List<InputDevice> _devices = const <InputDevice>[];

  /// User's current pick. `null` means "use whatever the system default is" —
  /// it's the initial state and also what selecting the Default entry resets
  /// the picker to.
  InputDevice? _selectedDevice;

  late final AudioRoutingService _routing =
      widget._injectedRouting ?? AudioRoutingService();

  /// macOS-only: the system default input UID captured the very first time
  /// the user picked a non-default device. Restored on widget dispose so we
  /// never leave the user with their system mic permanently rerouted.
  String? _originalDefaultUid;

  @override
  void initState() {
    super.initState();
    unawaited(_loadDevices());
  }

  @override
  void dispose() {
    unawaited(_teardownAsync());
    super.dispose();
  }

  Future<void> _teardownAsync() async {
    await _probe?.dispose();
    await _restoreRouting();
  }

  Future<void> _restoreRouting() async {
    final original = _originalDefaultUid;
    if (original == null) return;
    _originalDefaultUid = null;
    await _routing.setDefaultInputDevice(original);
  }

  /// Loads the device list eagerly so the picker shows up the moment the
  /// step renders — without waiting for the user to grant TCC and run a
  /// failing probe first.
  ///
  /// On macOS we go through [AudioRoutingService] because it queries
  /// CoreAudio directly (no permission, UIDs consistent with the routing
  /// switch). On other hosts we fall back to the probe's `record`-package
  /// enumeration.
  Future<void> _loadDevices() async {
    List<InputDevice> devices = const <InputDevice>[];
    if (_routing.isSupported) {
      devices = await _routing.listInputDevices();
    }
    if (devices.isEmpty) {
      final probe = _probe ??=
          (widget.probeFactory?.call() ?? OnboardingMicProbe());
      devices = await probe.listInputDevices();
    }
    if (!mounted) return;
    setState(() => _devices = devices);
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _grantAndVerify() async {
    setState(() => _phase = _MicPhase.requesting);
    await _runProbe();
  }

  Future<void> _retry() async {
    await _probe?.stop();
    await _runProbe();
  }

  Future<void> _selectDevice(InputDevice? device) async {
    if (_devicesEqual(device, _selectedDevice)) return;
    if (!mounted) return;
    setState(() => _selectedDevice = device);

    // Only re-run capture automatically once we already have permission.
    // In idle / requesting / denied the selection is remembered and
    // applied on the next Grant-tap or Retry — restarting the probe early
    // would either no-op (no permission) or spam the TCC dialog.
    switch (_phase) {
      case _MicPhase.verifying:
      case _MicPhase.silent:
      case _MicPhase.ready:
        await _probe?.stop();
        await _runProbe();
      case _MicPhase.idle:
      case _MicPhase.requesting:
      case _MicPhase.denied:
        break;
    }
  }

  Future<void> _runProbe() async {
    final probe = _probe ??=
        (widget.probeFactory?.call() ?? OnboardingMicProbe());

    if (!mounted) return;
    setState(() => _phase = _MicPhase.verifying);

    // macOS: `record_macos` ignores RecordConfig.device, so we flip the
    // system default *and* wait for CoreAudio to confirm the switch before
    // opening the input stream. Without the wait, AVAudioEngine binds to
    // whatever device was default at start() time — i.e. the wrong one.
    if (_routing.isSupported) {
      await _applyRoutingForSelection();
    }

    // On macOS the routing switch handles the device. On other hosts we
    // pass the selection through RecordConfig.device.
    final probeDevice = _routing.isSupported ? null : _selectedDevice;
    final outcome = await probe.start(device: probeDevice);
    if (!mounted) return;

    if (outcome != MicProbeOutcome.permissionDenied && _devices.isEmpty) {
      // Permission unlocked a device list we couldn't see before — refresh.
      final devices = await probe.listInputDevices();
      if (!mounted) return;
      _devices = devices;
    }

    setState(() {
      switch (outcome) {
        case MicProbeOutcome.speechDetected:
          _phase = _MicPhase.ready;
        case MicProbeOutcome.permissionDenied:
          _phase = _MicPhase.denied;
        case MicProbeOutcome.silence:
        case MicProbeOutcome.error:
          _phase = _MicPhase.silent;
      }
    });
    // Release the active stream as soon as we have a verdict — recorder
    // stays alive so retry / device-switch can restart capture without
    // re-running TCC.
    await probe.stop();
  }

  Future<void> _applyRoutingForSelection() async {
    if (_selectedDevice != null) {
      _originalDefaultUid ??= await _routing.getDefaultInputDevice();
      final ok = await _routing.setDefaultInputDevice(_selectedDevice!.id);
      if (ok) {
        await _waitForDefaultInputSwitch(_selectedDevice!.id);
      }
      return;
    }
    // User picked the "System default" sentinel — restore the original if we
    // ever flipped it, then forget it so a later switch starts fresh.
    final original = _originalDefaultUid;
    if (original == null) return;
    _originalDefaultUid = null;
    final ok = await _routing.setDefaultInputDevice(original);
    if (ok) {
      await _waitForDefaultInputSwitch(original);
    }
  }

  /// Polls CoreAudio until the new default-input UID is visible, with a hard
  /// cap. Matches the pattern in [AudioServiceNotifier] — CoreAudio reports
  /// `set` success synchronously, but AVAudioEngine reads the default lazily
  /// at `start()` time, so without the wait the engine still latches the old
  /// device and the live probe captures from the wrong mic.
  Future<void> _waitForDefaultInputSwitch(
    String expectedUid, {
    Duration timeout = const Duration(milliseconds: 600),
    Duration poll = const Duration(milliseconds: 40),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final current = await _routing.getDefaultInputDevice();
      if (current == expectedUid) {
        // Extra HAL settle window — empirically the new device needs ~150 ms
        // to come out of power-save and produce frames.
        await Future<void>.delayed(const Duration(milliseconds: 150));
        return;
      }
      await Future<void>.delayed(poll);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);

    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final textSecondary = isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final accentGradient = isDark
        ? WpColorsDark.accentWarmGradient
        : WpColorsLight.accentWarmGradient;
    final surfaceVariant = isDark
        ? WpColorsDark.surfaceVariant
        : WpColorsLight.surfaceVariant;
    final successColor = isDark ? WpColorsDark.success : WpColorsLight.success;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.onboardingMicTitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: textPrimary,
          ),
        ),
        const SizedBox(height: WpSpacing.xs),

        Text(
          l10n.onboardingMicSubtitle,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: textSecondary),
        ),
        const SizedBox(height: WpSpacing.xxl),

        AnimatedSwitcher(
          duration: WpMotion.smooth,
          switchInCurve: WpMotion.smooth_,
          switchOutCurve: WpMotion.smooth_,
          child: _buildStatusArea(
            isDark: isDark,
            accent: accent,
            surfaceVariant: surfaceVariant,
            textSecondary: textSecondary,
            successColor: successColor,
            l10n: l10n,
          ),
        ),

        // Device picker — only meaningful once we know what's available.
        if (_shouldShowPicker) ...[
          const SizedBox(height: WpSpacing.md),
          _DevicePicker(
            devices: _devices,
            selected: _selectedDevice,
            onSelected: _selectDevice,
            isDark: isDark,
            highlight: _phase == _MicPhase.silent,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            surfaceVariant: surfaceVariant,
            accent: accent,
            l10n: l10n,
          ),
        ],

        const SizedBox(height: WpSpacing.lg),

        AnimatedSwitcher(
          duration: WpMotion.smooth,
          child: _buildAction(
            l10n: l10n,
            accentGradient: accentGradient,
            textSecondary: textSecondary,
          ),
        ),
        const SizedBox(height: WpSpacing.xxl),

        Row(
          children: [
            TextButton(
              onPressed: widget.onBack,
              child: Text(
                l10n.onboardingBack,
                style: TextStyle(color: textSecondary),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: 140,
              child: WpAccentButton(
                label: l10n.onboardingNext,
                gradient: accentGradient,
                onPressed: _phase == _MicPhase.ready ? widget.onNext : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Picker visibility — shown whenever we know about ≥ 2 devices and the
  /// user has something actionable to do with the selection. Includes the
  /// idle phase so users can pre-emptively pick the right mic before the
  /// first probe, instead of having to fail once and then fix it.
  bool get _shouldShowPicker {
    if (_devices.length < 2) return false;
    switch (_phase) {
      case _MicPhase.idle:
      case _MicPhase.verifying:
      case _MicPhase.silent:
      case _MicPhase.ready:
        return true;
      case _MicPhase.requesting:
      case _MicPhase.denied:
        return false;
    }
  }

  Widget _buildAction({
    required L10n l10n,
    required LinearGradient accentGradient,
    required Color textSecondary,
  }) {
    switch (_phase) {
      case _MicPhase.idle:
      case _MicPhase.denied:
        return Column(
          key: ValueKey('action-${_phase.name}'),
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_phase == _MicPhase.denied) ...[
              Text(
                l10n.onboardingMicDeniedInstructions,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: textSecondary),
              ),
              const SizedBox(height: WpSpacing.sm),
            ],
            SizedBox(
              width: 220,
              child: WpAccentButton(
                label: l10n.onboardingMicRequestAccess,
                gradient: accentGradient,
                onPressed: _grantAndVerify,
              ),
            ),
          ],
        );

      case _MicPhase.silent:
        return SizedBox(
          key: const ValueKey('action-silent'),
          width: 220,
          child: WpAccentButton(
            label: l10n.onboardingMicRetry,
            gradient: accentGradient,
            onPressed: _retry,
          ),
        );

      case _MicPhase.requesting:
      case _MicPhase.verifying:
      case _MicPhase.ready:
        return const SizedBox.shrink(key: ValueKey('action-none'));
    }
  }

  Widget _buildStatusArea({
    required bool isDark,
    required Color accent,
    required Color surfaceVariant,
    required Color textSecondary,
    required Color successColor,
    required L10n l10n,
  }) {
    final textMuted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final errorColor = isDark ? WpColorsDark.error : WpColorsLight.error;
    final warningColor = isDark ? WpColorsDark.warning : WpColorsLight.warning;

    switch (_phase) {
      case _MicPhase.idle:
        return Column(
          key: const ValueKey('idle'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.mic, size: WpIconSize.xxl, color: textMuted),
            const SizedBox(height: WpSpacing.sm),
            Text(
              l10n.onboardingMicPermissionPending,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textMuted,
              ),
            ),
          ],
        );

      case _MicPhase.requesting:
        return Column(
          key: const ValueKey('requesting'),
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: WpIconSize.xxl,
              height: WpIconSize.xxl,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: accent),
            ),
            const SizedBox(height: WpSpacing.sm),
            Text(
              l10n.onboardingMicPermissionPending,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
          ],
        );

      case _MicPhase.denied:
        return Column(
          key: const ValueKey('denied'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.circleX, size: WpIconSize.xxl, color: errorColor),
            const SizedBox(height: WpSpacing.sm),
            Text(
              l10n.onboardingMicPermissionDenied,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: errorColor,
              ),
            ),
          ],
        );

      case _MicPhase.verifying:
        return _LiveCaptureCard(
          key: const ValueKey('verifying'),
          probe: _probe!,
          accent: accent,
          surfaceVariant: surfaceVariant,
          textSecondary: textSecondary,
          label: l10n.onboardingMicTestRecording,
        );

      case _MicPhase.silent:
        return Container(
          key: const ValueKey('silent'),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.lg,
            vertical: WpSpacing.lg,
          ),
          decoration: BoxDecoration(
            color: surfaceVariant,
            borderRadius: WpRadius.borderLg,
            border: Border.all(color: warningColor.withValues(alpha: 0.6)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.micOff,
                size: WpIconSize.xxl,
                color: warningColor,
              ),
              const SizedBox(height: WpSpacing.sm),
              Text(
                l10n.onboardingMicSilent,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: textSecondary),
              ),
            ],
          ),
        );

      case _MicPhase.ready:
        return TweenAnimationBuilder<double>(
          key: const ValueKey('ready'),
          tween: Tween(begin: 0.0, end: 1.0),
          duration: WpMotion.smooth,
          curve: Curves.elasticOut,
          builder: (_, value, child) => Transform.scale(
            scale: 0.5 + (value * 0.5),
            child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: WpIconSize.xxl + 12,
                height: WpIconSize.xxl + 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: successColor.withValues(alpha: 0.12),
                ),
                child: Icon(
                  LucideIcons.circleCheck,
                  size: WpIconSize.xxl,
                  color: successColor,
                ),
              ),
              const SizedBox(height: WpSpacing.sm),
              Text(
                l10n.onboardingMicPermissionGranted,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: successColor,
                ),
              ),
              const SizedBox(height: WpSpacing.xxs),
              Text(
                l10n.onboardingMicTestDone,
                style: TextStyle(fontSize: 12, color: textSecondary),
              ),
            ],
          ),
        );
    }
  }
}

/// `id`-based equality so the "system default" sentinel (`null`) compares
/// correctly across rebuilds without depending on object identity.
bool _devicesEqual(InputDevice? a, InputDevice? b) {
  if (a == null && b == null) return true;
  if (a == null || b == null) return false;
  return a.id == b.id;
}

// =============================================================================
// Device picker — dropdown anchored under the status area
// =============================================================================

class _DevicePicker extends StatelessWidget {
  const _DevicePicker({
    required this.devices,
    required this.selected,
    required this.onSelected,
    required this.isDark,
    required this.highlight,
    required this.textPrimary,
    required this.textSecondary,
    required this.surfaceVariant,
    required this.accent,
    required this.l10n,
  });

  final List<InputDevice> devices;
  final InputDevice? selected;
  final ValueChanged<InputDevice?> onSelected;
  final bool isDark;
  final bool highlight;
  final Color textPrimary;
  final Color textSecondary;
  final Color surfaceVariant;
  final Color accent;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final label = selected?.label ?? l10n.onboardingMicDeviceSystemDefault;
    final borderColor = highlight
        ? accent
        : (isDark ? WpColorsDark.borderDefault : WpColorsLight.borderDefault);

    return PopupMenuButton<InputDevice?>(
      tooltip: l10n.onboardingMicDeviceLabel,
      onSelected: onSelected,
      position: PopupMenuPosition.under,
      color: isDark ? WpColorsDark.surface : WpColorsLight.surface,
      itemBuilder: (context) => <PopupMenuEntry<InputDevice?>>[
        PopupMenuItem<InputDevice?>(
          value: null,
          child: _DeviceEntry(
            label: l10n.onboardingMicDeviceSystemDefault,
            selected: selected == null,
            accent: accent,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
          ),
        ),
        const PopupMenuDivider(),
        for (final device in devices)
          PopupMenuItem<InputDevice?>(
            value: device,
            child: _DeviceEntry(
              label: device.label,
              selected: selected?.id == device.id,
              accent: accent,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.md,
          vertical: WpSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: surfaceVariant,
          borderRadius: WpRadius.borderMd,
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.mic, size: WpIconSize.sm, color: textSecondary),
            const SizedBox(width: WpSpacing.sm),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: textPrimary,
                ),
              ),
            ),
            const SizedBox(width: WpSpacing.sm),
            Icon(
              LucideIcons.chevronDown,
              size: WpIconSize.sm,
              color: textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceEntry extends StatelessWidget {
  const _DeviceEntry({
    required this.label,
    required this.selected,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
  });

  final String label;
  final bool selected;
  final Color accent;
  final Color textPrimary;
  final Color textSecondary;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: WpIconSize.sm + 4,
          child: selected
              ? Icon(LucideIcons.check, size: WpIconSize.sm, color: accent)
              : null,
        ),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: selected ? accent : textPrimary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Live capture card — waveform driven by real PCM amplitude
// =============================================================================

class _LiveCaptureCard extends StatelessWidget {
  const _LiveCaptureCard({
    super.key,
    required this.probe,
    required this.accent,
    required this.surfaceVariant,
    required this.textSecondary,
    required this.label,
  });

  final OnboardingMicProbe probe;
  final Color accent;
  final Color surfaceVariant;
  final Color textSecondary;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.lg,
        vertical: WpSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: surfaceVariant,
        borderRadius: WpRadius.borderLg,
        border: Border.all(color: accent),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            excludeSemantics: true,
            child: SizedBox(
              height: 40,
              child: _WaveformBars(
                level: probe.level,
                accent: accent,
                muted: textSecondary.withValues(alpha: 0.3),
              ),
            ),
          ),
          const SizedBox(height: WpSpacing.sm),
          Text(label, style: TextStyle(fontSize: 13, color: accent)),
        ],
      ),
    );
  }
}

// =============================================================================
// Waveform bars — rolling history buffer with smoothed per-bar heights
// =============================================================================

/// Scrolling waveform driven by the probe's live amplitude.
///
/// Instead of recomputing every bar from the current level on every frame
/// (which made the whole row twitch in unison), we push the current level
/// into a ring buffer at a fixed cadence and shift the existing values left.
/// Each bar height comes from one fixed slot in the buffer and is interpolated
/// to its new value by [AnimatedContainer] — so the visualisation reads as a
/// wave traveling right-to-left, with no whole-row flicker.
class _WaveformBars extends StatefulWidget {
  const _WaveformBars({
    required this.level,
    required this.accent,
    required this.muted,
  });

  /// Normalised live amplitude `[0.0, 1.0]` exposed by the probe.
  final ValueListenable<double> level;
  final Color accent;
  final Color muted;

  @override
  State<_WaveformBars> createState() => _WaveformBarsState();
}

class _WaveformBarsState extends State<_WaveformBars> {
  static const int _barCount = 28;

  /// Cadence at which a new sample joins the ring. ~14 Hz matches the
  /// perception of a steady scrolling wave without overdriving rebuilds.
  static const Duration _pushInterval = Duration(milliseconds: 70);

  /// AnimatedContainer duration — slightly longer than the push so each new
  /// bar slot is still mid-tween when the next push lands. That overlap is
  /// what gives the visualisation its "fluid" feel.
  static const Duration _animateDuration = Duration(milliseconds: 110);

  final List<double> _history = List<double>.filled(_barCount, 0.0);
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(_pushInterval, _push);
  }

  void _push(Timer _) {
    if (!mounted) return;
    final lvl = widget.level.value.clamp(0.0, 1.0);
    setState(() {
      for (var i = 0; i < _barCount - 1; i++) {
        _history[i] = _history[i + 1];
      }
      _history[_barCount - 1] = lvl;
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < _barCount; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.5),
            child: AnimatedContainer(
              duration: _animateDuration,
              curve: Curves.easeOut,
              width: 3,
              height: math.max(2.0, 40 * _history[i].clamp(0.05, 1.0)),
              decoration: BoxDecoration(
                color: _history[i] > 0.08 ? widget.accent : widget.muted,
                borderRadius: WpRadius.borderFull,
              ),
            ),
          ),
      ],
    );
  }
}
