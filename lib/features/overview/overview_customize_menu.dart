import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/config/settings_provider.dart';
import '../../core/config/settings_sections.dart' show OnboardingSettings;
import '../../core/first_steps/first_steps.dart';
import '../../core/first_steps/first_steps_notifier.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/overview/overview_logic.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/wp_icon_button.dart';
import 'overview_providers.dart';

/// Ü3: "Übersicht anpassen" in the page head. Switches the figures, the
/// recent recordings and the discovery tips on and off, stored locally, and
/// brings back a closed first-steps card. No reordering: the order of the
/// page is part of its design.
///
/// Built on [WpIconButton] and [MenuAnchor], so the trigger has the shared
/// 44 px target, tooltip and accessible name. Keyboard: Enter or Space opens
/// the menu, the focus moves into its first entry, Escape closes it and gives
/// the focus back to the trigger.
class OverviewCustomizeMenu extends ConsumerStatefulWidget {
  const OverviewCustomizeMenu({super.key});

  @override
  ConsumerState<OverviewCustomizeMenu> createState() =>
      _OverviewCustomizeMenuState();
}

class _OverviewCustomizeMenuState extends ConsumerState<OverviewCustomizeMenu> {
  final MenuController _controller = MenuController();
  final FocusNode _firstEntry = FocusNode(debugLabel: 'OverviewCustomizeFirst');

  @override
  void dispose() {
    _firstEntry.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_controller.isOpen) {
      _controller.close();
      return;
    }
    _controller.open();
    // The entries are built on the frame after opening; the focus moves into
    // the first one then, so the arrow keys and Escape work from the keyboard.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controller.isOpen) _firstEntry.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final prefs = ref.watch(overviewPrefsProvider);
    final onboarding = ref.watch(
      settingsProvider.select(
        (s) => s.value?.onboarding ?? OnboardingSettings.defaults,
      ),
    );
    final canShowFirstSteps =
        onboarding.firstStepsArmed &&
        onboarding.firstStepsDismissed &&
        !firstStepsAllDone(parseFirstStepsDone(onboarding.firstStepsDone));
    final notifier = ref.read(overviewPrefsProvider.notifier);

    Widget block(
      String id,
      String label, {
      required bool on,
      required Future<void> Function(bool on) set,
      FocusNode? focusNode,
    }) => CheckboxMenuButton(
      key: ValueKey('overview-customize-$id'),
      focusNode: focusNode,
      value: on,
      onChanged: (next) => unawaited(set(next ?? !on)),
      child: Text(label),
    );

    return MenuAnchor(
      controller: _controller,
      alignmentOffset: const Offset(0, 4),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(WpColors.floatingSurface),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WpRadius.md),
          ),
        ),
      ),
      menuChildren: [
        block(
          'figures',
          l10n.overviewFiguresTitle,
          focusNode: _firstEntry,
          on: !prefs.hiddenBlocks.contains(OverviewBlock.figures),
          set: (on) =>
              notifier.setBlockVisible(OverviewBlock.figures, visible: on),
        ),
        block(
          'recent',
          l10n.overviewRecentTitle,
          on: !prefs.hiddenBlocks.contains(OverviewBlock.recent),
          set: (on) =>
              notifier.setBlockVisible(OverviewBlock.recent, visible: on),
        ),
        block(
          'dictation',
          l10n.overviewLastDictationTitle,
          on: !prefs.hiddenBlocks.contains(OverviewBlock.dictation),
          set: (on) =>
              notifier.setBlockVisible(OverviewBlock.dictation, visible: on),
        ),
        block(
          'storage',
          l10n.overviewStorageTitle,
          on: !prefs.hiddenBlocks.contains(OverviewBlock.storage),
          set: (on) =>
              notifier.setBlockVisible(OverviewBlock.storage, visible: on),
        ),
        block(
          'community',
          l10n.overviewCommunityMenu,
          on: !prefs.hiddenBlocks.contains(OverviewBlock.community),
          set: (on) =>
              notifier.setBlockVisible(OverviewBlock.community, visible: on),
        ),
        block(
          'tips',
          l10n.overviewCustomizeTips,
          on: !prefs.tips.off,
          set: (on) async {
            await notifier.setTipsOn(on: on);
            if (on) {
              await notifier.chooseTipForVisit(
                now: clock.now(),
                used: ref.read(overviewTipUsageProvider),
              );
            }
          },
        ),
        const Divider(height: 1),
        MenuItemButton(
          key: const ValueKey('overview-customize-first-steps'),
          onPressed: canShowFirstSteps
              ? () => unawaited(
                  ref.read(firstStepsNotifierProvider.notifier).showAgain(),
                )
              : null,
          child: Text(l10n.overviewCustomizeFirstSteps),
        ),
      ],
      builder: (context, controller, child) => WpIconButton(
        key: const ValueKey('overview-customize'),
        icon: LucideIcons.slidersHorizontal,
        tooltip: l10n.overviewCustomize,
        testId: 'overview-customize',
        onPressed: _toggle,
      ),
    );
  }
}
