/// Overlay & Floating Button settings sections.
library;

import 'dart:io';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/settings_enums.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/overlay_customization.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/floating_button/floating_button_controller_interface.dart';
import '../../../services/floating_button/floating_button_support.dart';
import '../../../services/floating_button/floating_button_support_provider.dart';
import '../../../widgets/floating_button/floating_button_view.dart';
import '../settings_widgets.dart';
import '../widgets/overlay_size_selector.dart';
import '../widgets/overlay_theme_swatches.dart';
import '../widgets/wp_settings_group.dart';
import '../widgets/overlay_preview_stage.dart';

// ---------------------------------------------------------------------------
// Recording Overlay section
// ---------------------------------------------------------------------------

class OverlaySection extends ConsumerWidget {
  const OverlaySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final effectiveMode = settings.effectiveOverlayMode;
    final isDesktop =
        Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    final floating = effectiveMode == OverlayMode.floating;
    final look = settings.overlayAppearance;
    final notifier = ref.read(settingsProvider.notifier);

    // Consolidated dropdown value: 'off' when overlay is disabled, real
    // position otherwise (back-compat: overlayStartPosition is never 'off').
    final startPosValue = floating
        ? settings.overlayStartPositionType.value
        : OverlayStartPosition.off.value;

    // Edge bar is not offered yet: its docking is not implemented on any
    // platform (WP-95 open point), so the picker lists only the shapes that
    // render. A stored edge bar shows as the pill it falls back to.
    const offeredForms = [OverlayForm.pill, OverlayForm.roundedRect];
    final formValue = offeredForms.contains(look.form)
        ? look.form
        : OverlayForm.pill;

    final previewRows = <Widget>[
      // ── Preview stage: top of the section, so every option below shows its effect ──
      if (floating)
        SettingsRowFrame(
          rowId: 'appearance-overlay-preview',
          child: WpOverlayPreviewStage(
            size: settings.overlaySizeType,
            background: settings.overlayBackgroundType,
            wave: settings.overlayWaveType,
            showButton: FloatingButtonSection.isSupportedPlatform,
            appearance: look,
            buttonLook: settings.floatingButtonLook,
          ),
        ),
    ];
    // Shared colours: their own card under the preview.
    final colourRows = <Widget>[
      if (floating) ...[
        WpSettingsRow(
          rowId: 'appearance-overlay-background',
          title: l10n.settingsOverlayBackground,
          subtitle: l10n.settingsOverlayBackgroundSubtitle,
          trailing: WpOverlayBackgroundSwatches(
            value: settings.overlayBackgroundType,
            onChanged: (preset) =>
                pickOverlayBackground(context, ref, settings, preset),
          ),
        ),
        WpSettingsRow(
          rowId: 'appearance-overlay-wave',
          title: l10n.settingsOverlayWave,
          subtitle: l10n.settingsOverlayWaveSubtitle,
          trailing: WpOverlayWaveSwatches(
            value: settings.overlayWaveType,
            background: settings.overlayBackgroundType,
            onChanged: (preset) => notifier.updateSettings(
              (s) => s.copyWith(overlayWave: preset.value),
            ),
          ),
        ),
      ],
    ];
    // Overlay options: their own card below the colours.
    final optionRows = <Widget>[
      // Start position (always visible on desktop; 'Aus' = off)
      if (isDesktop)
        WpSettingsRow(
          rowId: 'appearance-overlay-start',
          title: l10n.settingsOverlayStartPosition,
          subtitle: l10n.settingsOverlayStartPositionSubtitle,
          trailing: settingsDropdown(
            context: context,
            value: startPosValue,
            items: OverlayStartPosition.values.map((e) => e.value).toList(),
            labels: [
              l10n.settingsOff,
              l10n.settingsOverlayStartTopCenter,
              l10n.settingsOverlayStartBottomCenter,
              l10n.settingsOverlayStartLastPosition,
            ],
            onChanged: (v) {
              if (v == null) return;
              if (v == OverlayStartPosition.off.value) {
                notifier.updateSettings(
                  (s) => s.copyWith(
                    overlayMode: OverlayMode.off.value,
                    showOverlay: false,
                  ),
                );
              } else {
                notifier.updateSettings(
                  (s) => s.copyWith(
                    overlayMode: OverlayMode.floating.value,
                    showOverlay: true,
                    overlayStartPosition: v,
                  ),
                );
              }
            },
          ),
        ),
      if (floating) ...[
        WpSettingsRow(
          rowId: 'appearance-overlay-size',
          title: l10n.settingsOverlaySize,
          subtitle: l10n.settingsOverlaySizeSubtitle,
          trailing: WpOverlaySizeSelector(
            value: settings.overlaySizeType,
            onChanged: (size) => notifier.updateSettings(
              (s) => s.copyWith(overlaySize: size.value),
            ),
          ),
        ),
        // Live transcript (ticket 11). Off by default: the PRD keeps the
        // waveform-only overlay as the default (privacy/reduction); live text
        // is an opt-in error-transparency trade-off.
        WpSettingsRow(
          rowId: 'appearance-overlay-live-text',
          title: l10n.settingsOverlayLiveTranscript,
          subtitle: l10n.settingsOverlayLiveTranscriptSubtitle,
          semanticToggledValue: settings.overlayShowLiveTranscript,
          trailing: settingsToggle(
            value: settings.overlayShowLiveTranscript,
            onChanged: (v) => notifier.updateSettings(
              (s) => s.copyWith(overlayShowLiveTranscript: v),
            ),
          ),
        ),
        WpSettingsRow(
          rowId: 'appearance-overlay-form',
          title: l10n.settingsOverlayForm,
          subtitle: l10n.settingsOverlayFormSubtitle,
          trailing: settingsDropdown(
            context: context,
            value: formValue.value,
            items: offeredForms.map((f) => f.value).toList(),
            labels: [
              l10n.settingsOverlayFormPill,
              l10n.settingsOverlayFormRoundedRect,
            ],
            keyPrefix: 'overlay-form',
            onChanged: (v) {
              if (v == null) return;
              notifier.updateSettings((s) => s.copyWith(overlayForm: v));
            },
          ),
        ),
        WpSettingsRow(
          rowId: 'appearance-overlay-wave-style',
          title: l10n.settingsOverlayWaveStyle,
          subtitle: l10n.settingsOverlayWaveStyleSubtitle,
          trailing: settingsDropdown(
            context: context,
            value: look.waveStyle.value,
            items: OverlayWaveStyle.values.map((s) => s.value).toList(),
            labels: [
              l10n.settingsOverlayWaveBars,
              l10n.settingsOverlayWaveLine,
              l10n.settingsOverlayWaveDots,
            ],
            keyPrefix: 'overlay-wave-style',
            onChanged: (v) {
              if (v == null) return;
              notifier.updateSettings((s) => s.copyWith(overlayWaveStyle: v));
            },
          ),
        ),
        WpSettingsRow(
          rowId: 'appearance-overlay-wave-fluid',
          title: l10n.settingsOverlayWaveFluid,
          subtitle: l10n.settingsOverlayWaveFluidSubtitle,
          semanticToggledValue: look.waveFluid,
          trailing: settingsToggle(
            key: const ValueKey('overlay-wave-fluid-toggle'),
            value: look.waveFluid,
            onChanged: (v) =>
                notifier.updateSettings((s) => s.copyWith(overlayWaveFluid: v)),
          ),
        ),
        WpSettingsRow(
          rowId: 'appearance-overlay-show-timer',
          title: l10n.settingsOverlayShowTimer,
          subtitle: l10n.settingsOverlayShowTimerSubtitle,
          semanticToggledValue: look.showTimer,
          trailing: settingsToggle(
            key: const ValueKey('overlay-show-timer-toggle'),
            value: look.showTimer,
            onChanged: (v) =>
                notifier.updateSettings((s) => s.copyWith(overlayShowTimer: v)),
          ),
        ),
        WpSettingsRow(
          rowId: 'appearance-overlay-show-cancel',
          title: l10n.settingsOverlayShowCancel,
          subtitle: l10n.settingsOverlayShowCancelSubtitle,
          semanticToggledValue: look.showCancel,
          trailing: settingsToggle(
            key: const ValueKey('overlay-show-cancel-toggle'),
            value: look.showCancel,
            onChanged: (v) => notifier.updateSettings(
              (s) => s.copyWith(overlayShowCancel: v),
            ),
          ),
        ),
        WpSettingsRow(
          rowId: 'appearance-overlay-opacity',
          title: l10n.settingsOverlayOpacity,
          subtitle: l10n.settingsOverlayOpacitySubtitle,
          trailing: settingsDropdown(
            context: context,
            value: '${look.opacity.percent}',
            items: const ['100', '80', '60'],
            labels: [
              l10n.settingsOverlayOpacityFull,
              l10n.settingsOverlayOpacityReduced,
              l10n.settingsOverlayOpacitySubtle,
            ],
            keyPrefix: 'overlay-opacity',
            onChanged: (v) {
              if (v == null) return;
              notifier.updateSettings((s) => s.copyWith(overlayOpacity: v));
            },
          ),
        ),
      ],
    ];

    List<Widget> spaced(List<Widget> rows) => [
      for (var i = 0; i < rows.length; i++) ...[
        if (i > 0) settingsInlineBreak,
        rows[i],
      ],
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (previewRows.isNotEmpty)
          WpSettingsGroup(
            heading: l10n.settingsOverlayFloatingButton,
            children: spaced(previewRows),
          ),
        if (colourRows.isNotEmpty) ...[
          const SizedBox(height: WpSpacing.xl),
          WpSettingsGroup(
            heading: l10n.settingsOverlayColorsGroup,
            children: spaced(colourRows),
          ),
        ],
        if (optionRows.isNotEmpty) ...[
          const SizedBox(height: WpSpacing.xl),
          WpSettingsGroup(
            heading: l10n.settingsOverlayOptionsGroup,
            children: spaced(optionRows),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Floating Button section (Windows, macOS, Linux)
// ---------------------------------------------------------------------------

class FloatingButtonSection extends ConsumerWidget {
  const FloatingButtonSection({super.key});

  /// Whether the current platform supports the Floating Button.
  ///
  /// Uses [defaultTargetPlatform] instead of [Platform.isWindows/isMacOS] so
  /// that widget tests can override the platform via
  /// [debugDefaultTargetPlatformOverride] without touching real OS checks.
  ///
  /// Public so `settings_page.dart` can exclude this section's card entirely
  /// on unsupported platforms — otherwise the empty `SizedBox.shrink()` still
  /// sits inside `sectionCard`'s padded, bordered container, leaving a bare
  /// outline with nothing in it.
  static bool get isSupportedPlatform =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isSupportedPlatform) {
      return const SizedBox.shrink();
    }

    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;

    final notifier = ref.read(settingsProvider.notifier);
    final look = settings.floatingButtonLook;
    // The look rows describe a button that is not shown (UX-051): they are
    // dimmed and inert until the switch above turns the button on.
    final shown = settings.overlay.showFloatingButton;
    final lookReason = shown ? null : l10n.settingsFloatingButtonLookLocked;
    // Only Linux probes at runtime; Windows and macOS report full support.
    final support =
        ref.watch(floatingButtonSupportProvider).value ??
        FloatingButtonSupport.full;
    // Where the native host cannot run, the switch stays usable only to turn an
    // imported "on" state off. It never turns on a button that cannot appear.
    final switchable = support.available || settings.showFloatingButton;

    return WpSettingsGroup(
      heading: l10n.settingsFloatingButtonSection,
      children: [
        WpSettingsRow(
          rowId: 'appearance-floating-button',
          title: l10n.settingsShowFloatingButton,
          subtitle: l10n.settingsShowFloatingButtonSubtitle,
          disabledReason: support.available
              ? null
              : l10n.settingsFloatingButtonUnavailable,
          semanticToggledValue: settings.showFloatingButton,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              WpFloatingButtonView(
                state: FloatingButtonVisualState.idle,
                diameter: 32,
                background: settings.overlayBackgroundType,
                wave: settings.overlayWaveType,
                look: look,
              ),
              const SizedBox(width: WpSpacing.xs),
              settingsToggle(
                value: settings.showFloatingButton,
                onChanged: switchable
                    ? (v) => ref
                          .read(settingsProvider.notifier)
                          .updateSettings(
                            (s) => s.copyWith(showFloatingButton: v),
                          )
                    : null,
              ),
            ],
          ),
        ),
        _lookRow(
          context,
          shown: shown,
          child: WpSettingsRow(
            rowId: 'appearance-button-size',
            disabledReason: lookReason,
            title: l10n.settingsFloatingButtonSize,
            subtitle: l10n.settingsFloatingButtonSizeSubtitle,
            trailing: settingsDropdown(
              context: context,
              value: look.size,
              items: const ['small', 'medium', 'large'],
              labels: [
                l10n.settingsFloatingButtonSizeSmall,
                l10n.settingsFloatingButtonSizeMedium,
                l10n.settingsFloatingButtonSizeLarge,
              ],
              keyPrefix: 'floating-button-size',
              onChanged: (v) {
                if (v == null) return;
                notifier.updateSettings(
                  (s) => s.copyWith(floatingButtonSize: v),
                );
              },
            ),
          ),
        ),
        _lookRow(
          context,
          shown: shown,
          child: WpSettingsRow(
            rowId: 'appearance-button-shape',
            disabledReason: lookReason,
            title: l10n.settingsFloatingButtonShape,
            subtitle: l10n.settingsFloatingButtonShapeSubtitle,
            trailing: settingsDropdown(
              context: context,
              value: look.square ? 'square' : 'round',
              items: const ['round', 'square'],
              labels: [
                l10n.settingsFloatingButtonShapeRound,
                l10n.settingsFloatingButtonShapeSquare,
              ],
              keyPrefix: 'floating-button-shape',
              onChanged: (v) {
                if (v == null) return;
                notifier.updateSettings(
                  (s) => s.copyWith(floatingButtonShape: v),
                );
              },
            ),
          ),
        ),
        _lookRow(
          context,
          shown: shown,
          child: WpSettingsRow(
            rowId: 'appearance-button-ring',
            disabledReason: lookReason,
            title: l10n.settingsFloatingButtonRing,
            subtitle: l10n.settingsFloatingButtonRingSubtitle,
            semanticToggledValue: look.ring,
            trailing: settingsToggle(
              key: const ValueKey('floating-button-ring-toggle'),
              value: look.ring,
              onChanged: (v) => notifier.updateSettings(
                (s) => s.copyWith(floatingButtonRing: v),
              ),
            ),
          ),
        ),
        _lookRow(
          context,
          shown: shown,
          child: WpSettingsRow(
            rowId: 'appearance-button-idle-opacity',
            disabledReason: lookReason,
            title: l10n.settingsFloatingButtonIdleOpacity,
            subtitle: l10n.settingsFloatingButtonIdleOpacitySubtitle,
            trailing: settingsDropdown(
              context: context,
              value: look.idleOpacity,
              items: const ['100', '70', '40'],
              labels: [
                l10n.settingsOverlayOpacityFull,
                l10n.settingsFloatingButtonIdleOpacityReduced,
                l10n.settingsFloatingButtonIdleOpacitySubtle,
              ],
              keyPrefix: 'floating-button-idle-opacity',
              onChanged: (v) {
                if (v == null) return;
                notifier.updateSettings(
                  (s) => s.copyWith(floatingButtonIdleOpacity: v),
                );
              },
            ),
          ),
        ),
        if (support.limits.isNotEmpty) ...[
          settingsInlineBreak,
          WpSettingsRow(
            rowId: 'appearance-floating-button-wayland',
            title: l10n.settingsFloatingButtonWaylandTitle,
            subtitle: l10n.settingsFloatingButtonWaylandLimit,
            trailing: const Icon(Icons.info_outline_rounded),
          ),
        ],
      ],
    );
  }

  /// One look row, dimmed and inert while [shown] is false (UX-051). The same
  /// idiom as the hotkey rows: the row stays readable, and the switch above it
  /// is never affected.
  static Widget _lookRow(
    BuildContext context, {
    required bool shown,
    required Widget child,
  }) {
    return settingsDimmedWhen(context, enabled: shown, child: child);
  }
}
