/// The coffee support button ("Lade mich auf einen Kaffee ein"): one yellow
/// button, three possible routes. [coffeeSupportTargetProvider] decides for
/// this build whether it opens the store's native purchase, the external
/// coffee pages, or does not appear at all. A store build never reaches an
/// external link (see `support_capabilities.dart`).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/generated/wp_tokens.g.dart';
import '../core/theme/tokens.dart';
import '../services/support/support_capabilities.dart';
import '../services/support/support_state.dart';
import '../services/support_prompt_service.dart';
import '../services/telemetry_service.dart';
import 'external_link.dart';
import 'support_purchase_sheet.dart';
import 'wp_focus_ring.dart';

/// Opens an external coffee page. A launched link starts the prompt's quiet
/// period, and only once the launch succeeded. It never starts the monthly
/// follow-up (GR-021). [surface] names where the click happened (GR-022).
Future<void> openCoffeeLink(
  BuildContext context,
  WidgetRef ref, {
  required String url,
  required String target,
  required SupportLinkSurface surface,
}) async {
  // Read before the await: the ref may be gone once the page has closed.
  final telemetry = ref.read(telemetryProvider);
  final prompt = ref.read(supportPromptProvider.notifier);
  if (!await openExternalUrl(context, url)) return;
  recordLinkOpened(telemetry, surface, target);
  await prompt.markCoffeeLinkOpened();
}

/// External coffee pages in the install's drawn order (GR-025). The pair is
/// not shown while the draw loads (see [WpCoffeeSupportButton]), so no frame
/// ever shows the wrong order and then flips.
List<CoffeeLink> _orderedCoffeeLinks(WidgetRef ref) {
  final links = coffeeExternalLinks();
  final buyMeACoffeeFirst =
      ref.watch(coffeeBuyMeACoffeeFirstProvider).value ?? false;
  return buyMeACoffeeFirst ? links.reversed.toList() : links;
}

/// The yellow button itself: Kaffee-Gelb with dark ink, a coffee cup icon, a
/// focus ring and a stable [testId]. Pure visual; the caller decides the route.
class WpCoffeeButton extends StatefulWidget {
  const WpCoffeeButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.testId,
    this.expanded = false,
    this.autofocus = false,
  });

  final String label;
  final VoidCallback onPressed;
  final String testId;

  /// Fills the available width (dialogs, columns that stretch).
  final bool expanded;

  final bool autofocus;

  @override
  State<WpCoffeeButton> createState() => _WpCoffeeButtonState();
}

class _WpCoffeeButtonState extends State<WpCoffeeButton> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'WpCoffeeButton');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final button = FilledButton.icon(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onPressed: widget.onPressed,
      icon: const Icon(LucideIcons.coffee, size: WpIconSize.md),
      label: Text(widget.label),
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.pressed)
              ? WpCoffeeTokens.coffeeFillHover
              : WpCoffeeTokens.coffeeFill,
        ),
        foregroundColor: const WidgetStatePropertyAll(
          WpCoffeeTokens.coffeeOnFill,
        ),
        iconColor: const WidgetStatePropertyAll(WpCoffeeTokens.coffeeOnFill),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(0),
        minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: WpSpacing.lg),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: WpRadius.borderFull),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: WpTypography.body, fontWeight: FontWeight.w600),
        ),
      ),
    );
    Widget result = WpFocusRing(
      focusNode: _focusNode,
      radius: WpRadius.full,
      child: button,
    );
    if (widget.expanded) {
      result = SizedBox(width: double.infinity, child: result);
    }
    return Semantics(
      identifier: widget.testId,
      child: KeyedSubtree(key: ValueKey<String>(widget.testId), child: result),
    );
  }
}

/// Two stacked coffee buttons at their minimum height, incl. the gap between.
const double _coffeePairMinHeight = 48 + WpSpacing.xs + 48;

/// The coffee button as the app shows it, wired to the route of this build.
/// Renders nothing where [coffeeSupportTargetProvider] is hidden.
class WpCoffeeSupportButton extends ConsumerWidget {
  const WpCoffeeSupportButton({
    super.key,
    required this.testId,
    required this.surface,
    this.expanded = false,
  });

  /// Where the button sits, for the `linkOpened` event (GR-022).
  final SupportLinkSurface surface;

  /// Base test id. Extra external pages add a suffix (`-buy-me-a-coffee`).
  final String testId;

  /// Fills the available width.
  final bool expanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = ref.watch(coffeeSupportTargetProvider);
    final l10n = L10n.of(context);
    return switch (target) {
      CoffeeSupportTarget.hidden => const SizedBox.shrink(),
      CoffeeSupportTarget.storePurchase => WpCoffeeButton(
        label: l10n.coffeeButtonLabel,
        testId: testId,
        expanded: expanded,
        onPressed: () => unawaited(showWpSupportPurchaseDialog(context)),
      ),
      CoffeeSupportTarget.externalLinks =>
        ref.watch(coffeeBuyMeACoffeeFirstProvider).isLoading
            ? // Reserve the pair's height while the draw loads (UX-082): the
              // order is only shown once it is known, and nothing jumps.
              SizedBox(
                height: _coffeePairMinHeight,
                width: expanded ? double.infinity : null,
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: expanded
                    ? CrossAxisAlignment.stretch
                    : CrossAxisAlignment.center,
                children: [
                  // Equal rank: every external page gets the same yellow button, in
                  // list order, with its own brand label (never a primary/secondary split).
                  for (final (index, link) in _orderedCoffeeLinks(
                    ref,
                  ).indexed) ...[
                    if (index > 0) const SizedBox(height: WpSpacing.xs),
                    WpCoffeeButton(
                      label: link.idSuffix.isEmpty
                          ? l10n.aboutKofi
                          : l10n.coffeeBuyMeACoffeeLabel,
                      testId: '$testId${link.idSuffix}',
                      expanded: expanded,
                      onPressed: () => unawaited(
                        openCoffeeLink(
                          context,
                          ref,
                          url: link.url,
                          target: link.idSuffix.isEmpty
                              ? 'kofi'
                              : 'buymeacoffee',
                          surface: surface,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
    };
  }
}
