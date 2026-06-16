/// Overlay & Floating Button settings sections.
library;

import 'dart:io';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_enums.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/floating_button/floating_button_controller_interface.dart';
import '../../../widgets/floating_button/floating_button_view.dart';
import '../../../widgets/overlay_preview.dart';
import '../../../widgets/section.dart';
import '../settings_widgets.dart';

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

    return WpSection(
      title: l10n.settingsOverlayFloatingButton,
      subtitle: l10n.settingsOverlayFloatingButtonSubtitle,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // ── Floating overlay toggle (desktop only) ───────────────────
          if (isDesktop) ...[
            SettingRow(
              icon: LucideIcons.layers,
              label: l10n.settingsShowOverlay,
              subtitle: l10n.settingsShowOverlaySubtitle,
              semanticToggledValue: effectiveMode == OverlayMode.floating,
              trailing: settingsToggle(
                value: effectiveMode == OverlayMode.floating,
                onChanged: (v) => ref
                    .read(settingsProvider.notifier)
                    .updateSettings(
                      (s) => s.copyWith(
                        overlayMode: v
                            ? OverlayMode.floating.value
                            : OverlayMode.off.value,
                        showOverlay: v,
                      ),
                    ),
              ),
            ),
          ],

          // ── Floating overlay settings (visible when enabled) ─────────
          if (effectiveMode == OverlayMode.floating) ...[
            const Divider(height: 1),
            SettingRow(
              icon: LucideIcons.mapPin,
              label: l10n.settingsOverlayStartPosition,
              subtitle: l10n.settingsOverlayStartPositionSubtitle,
              trailing: settingsDropdown(
                context: context,
                value: settings.overlayStartPositionType.value,
                items: OverlayStartPosition.values.map((e) => e.value).toList(),
                labels: [
                  l10n.settingsOverlayStartTopCenter,
                  l10n.settingsOverlayStartBottomCenter,
                  l10n.settingsOverlayStartLastPosition,
                ],
                onChanged: (v) {
                  if (v == null) return;
                  ref
                      .read(settingsProvider.notifier)
                      .updateSettings(
                        (s) => s.copyWith(overlayStartPosition: v),
                      );
                },
              ),
            ),
            const Divider(height: 1),
            SettingRow(
              icon: LucideIcons.maximize2,
              label: l10n.settingsOverlaySize,
              subtitle: l10n.settingsOverlaySizeSubtitle,
              trailing: settingsDropdown(
                context: context,
                value: settings.overlaySizeType.value,
                items: FloatingOverlaySize.values.map((e) => e.value).toList(),
                labels: [
                  l10n.settingsOverlaySizeNormal,
                  l10n.settingsOverlaySizeCompact,
                ],
                onChanged: (v) {
                  if (v == null) return;
                  ref
                      .read(settingsProvider.notifier)
                      .updateSettings((s) => s.copyWith(overlaySize: v));
                },
              ),
            ),
            const Divider(height: 1),
            OverlayRealPreview(size: settings.overlaySizeType),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Floating Button section (Windows / macOS only)
// ---------------------------------------------------------------------------

class FloatingButtonSection extends ConsumerWidget {
  const FloatingButtonSection({super.key});

  /// Whether the current platform supports the Floating Button.
  ///
  /// Uses [defaultTargetPlatform] instead of [Platform.isWindows/isMacOS] so
  /// that widget tests can override the platform via
  /// [debugDefaultTargetPlatformOverride] without touching real OS checks.
  static bool get _isSupportedPlatform =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_isSupportedPlatform) {
      return const SizedBox.shrink();
    }

    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;

    return WpSection(
      title: l10n.settingsFloatingButtonSection,
      subtitle: l10n.settingsFloatingButtonSectionSubtitle,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SettingRow(
            icon: LucideIcons.circle,
            label: l10n.settingsShowFloatingButton,
            subtitle: l10n.settingsShowFloatingButtonSubtitle,
            semanticToggledValue: settings.showFloatingButton,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const FloatingButtonView(
                  state: FloatingButtonVisualState.idle,
                  diameter: 32,
                ),
                const SizedBox(width: WpSpacing.xs),
                settingsToggle(
                  value: settings.showFloatingButton,
                  onChanged: (v) => ref
                      .read(settingsProvider.notifier)
                      .updateSettings((s) => s.copyWith(showFloatingButton: v)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
