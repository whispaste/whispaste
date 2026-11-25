import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'overview_movable_card.dart' show applyOverviewMove, overviewBlockLabel;
import 'overview_navigation.dart' show overviewCustomizeRequestProvider;
import 'overview_providers.dart';

/// Ü3: "Übersicht anpassen" in the page head. Switches the figures, the
/// recent recordings, the notes, the status cards, the news and the
/// discovery tips on and off, stored locally, and
/// brings back a closed first-steps card. The cards are listed in page order;
/// Alt with the up or down arrow moves the entry in focus, and "Reihenfolge
/// zurücksetzen" brings back the default order (#1970). Visibility and order
/// share this one menu; dragging happens on the page itself.
///
/// Built on [WpIconButton] and [MenuAnchor], so the trigger has the shared
/// 48 px target, tooltip and accessible name. Keyboard: Enter or Space opens
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
    // "Try it" on a "New in this version" entry opens this menu (#1576).
    ref.listen(overviewCustomizeRequestProvider, (_, _) {
      if (!_controller.isOpen) _toggle();
    });
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

    void move(OverviewBlock b, {required bool later}) {
      final order = overviewMoveBlockStep(
        prefs.blockOrder,
        b,
        later: later,
        peers: OverviewBlock.values,
      );
      if (order == null) return;
      applyOverviewMove(
        context,
        ref,
        block: b,
        order: order,
        peers: OverviewBlock.values,
      );
    }

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
        // The cards in page order (#1970); Alt with an arrow key moves the
        // entry in focus, the same move as the card's grip.
        for (final (i, b) in prefs.blockOrder.indexed)
          CallbackShortcuts(
            key: ValueKey('overview-customize-move-${b.id}'),
            bindings: {
              const SingleActivator(
                LogicalKeyboardKey.arrowUp,
                alt: true,
              ): () =>
                  move(b, later: false),
              const SingleActivator(
                LogicalKeyboardKey.arrowDown,
                alt: true,
              ): () =>
                  move(b, later: true),
            },
            child: block(
              b.id,
              overviewBlockLabel(l10n, b),
              focusNode: i == 0 ? _firstEntry : null,
              on: prefs.isBlockShown(b),
              set: (on) => notifier.setBlockVisible(b, visible: on),
            ),
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
        MenuItemButton(
          key: const ValueKey('overview-customize-reset-order'),
          onPressed: prefs.layoutIsCustom
              ? () => unawaited(notifier.resetBlockOrder())
              : null,
          child: Text(l10n.overviewCustomizeResetOrder),
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
