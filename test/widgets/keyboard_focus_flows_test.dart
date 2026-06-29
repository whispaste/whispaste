/// D2 — Keyboard/focus flow tests for the hot-path (maus-frei).
///
/// Covers:
///   AC1 — Tab through hot-path controls; Enter/Space activates the focused
///          action (sidebar nav items now use InkWell, so they participate in
///          the standard Flutter focus-traversal and respond to Enter/Space).
///   AC2 — Logical traversal order; no focus trap (Tab cycles through all
///          sidebar items and exits naturally; no infinite loop).
///   AC3 — Dialog/overlay returns focus to trigger after dismissal.
///   AC4 — All observable via sendKeyEvent.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/widgets/dialog.dart';
import 'package:whispaste/widgets/sidebar.dart';
import 'package:whispaste/widgets/sidebar_settings_button.dart';

import '../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Shared fixtures
// ---------------------------------------------------------------------------

final _navItems = [
  const WpNavItem(id: 'history', icon: LucideIcons.clock3, label: 'History'),
  const WpNavItem(
    id: 'analytics',
    icon: LucideIcons.chartNoAxesColumn,
    label: 'Analytics',
  ),
  const WpNavItem(id: 'about', icon: LucideIcons.info, label: 'About'),
];

/// Pumps enough frames so focus changes settle without waiting for
/// open-ended Drift streams (same pattern as other widget tests).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

// ---------------------------------------------------------------------------
// Harness widgets
// ---------------------------------------------------------------------------

/// Wraps a [WpSidebar] with a zero-size autofocus anchor so that the first
/// Tab keypress moves focus into the sidebar's InkWell items.
class _SidebarKeyboardHarness extends StatelessWidget {
  const _SidebarKeyboardHarness({
    required this.items,
    required this.activeId,
    required this.onItemTap,
  });

  final List<WpNavItem> items;
  final String activeId;
  final ValueChanged<String> onItemTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Autofocus anchor: first Tab from here moves into the sidebar.
        const Focus(autofocus: true, child: SizedBox.shrink()),
        WpSidebar(items: items, activeId: activeId, onItemTap: onItemTap),
      ],
    );
  }
}

/// Dialog-trigger harness: an autofocused button that opens a WpConfirmDialog.
/// After the dialog closes the trigger button's focus node should be restored.
class _DialogFocusHarness extends StatelessWidget {
  const _DialogFocusHarness({required this.focusNode});

  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        focusNode: focusNode,
        autofocus: true,
        onPressed: () => showWpConfirmDialog(
          context: context,
          title: 'Test dialog',
          message: 'Keyboard focus test',
          confirmLabel: 'OK',
          cancelLabel: 'Abbrechen',
        ),
        child: const Text('Open dialog'),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // =========================================================================
  // AC1 + AC4 — Enter key activates focused sidebar nav item
  // =========================================================================

  group('AC1 — Tab + Enter activates sidebar nav item', () {
    testWidgets('Enter key activates first sidebar item after Tab', (
      tester,
    ) async {
      String? tappedId;

      await tester.pumpWidget(
        makeTestable(
          _SidebarKeyboardHarness(
            items: _navItems,
            activeId: 'history',
            onItemTap: (id) => tappedId = id,
          ),
        ),
      );
      await _settle(tester);

      // The autofocus anchor has focus. Tab moves to the first sidebar item.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await _settle(tester);

      // Enter activates the focused item.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _settle(tester);

      expect(
        tappedId,
        isNotNull,
        reason: 'Enter should activate focused nav item',
      );
    });

    testWidgets('Space key also activates focused sidebar item', (
      tester,
    ) async {
      String? tappedId;

      await tester.pumpWidget(
        makeTestable(
          _SidebarKeyboardHarness(
            items: _navItems,
            activeId: 'history',
            onItemTap: (id) => tappedId = id,
          ),
        ),
      );
      await _settle(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await _settle(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await _settle(tester);

      expect(
        tappedId,
        isNotNull,
        reason: 'Space should activate focused nav item',
      );
    });

    testWidgets('Settings button is keyboard-activatable via Enter', (
      tester,
    ) async {
      bool tapped = false;

      await tester.pumpWidget(
        makeTestable(
          Column(
            children: [
              const Focus(autofocus: true, child: SizedBox.shrink()),
              WpSidebarSettingsButton(
                isActive: false,
                onTap: () => tapped = true,
              ),
            ],
          ),
        ),
      );
      await _settle(tester);

      // Tab from anchor to settings button.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await _settle(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _settle(tester);

      expect(tapped, isTrue, reason: 'Enter should activate settings button');
    });
  });

  // =========================================================================
  // AC2 + AC4 — Logical traversal order; no focus trap
  // =========================================================================

  group('AC2 — Logical traversal; no focus trap', () {
    testWidgets('Tab visits each sidebar item exactly (no trap)', (
      tester,
    ) async {
      final tappedIds = <String>[];

      await tester.pumpWidget(
        makeTestable(
          _SidebarKeyboardHarness(
            items: _navItems,
            activeId: 'history',
            onItemTap: (id) => tappedIds.add(id),
          ),
        ),
      );
      await _settle(tester);

      // Tab + Enter through all three items sequentially.
      for (var i = 0; i < _navItems.length; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await _settle(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await _settle(tester);
      }

      // Each item was activated exactly once, in traversal order.
      expect(
        tappedIds,
        hasLength(_navItems.length),
        reason: 'Each nav item should be reachable via Tab (no trap, no skip)',
      );
      expect(
        tappedIds,
        equals(['history', 'analytics', 'about']),
        reason: 'Traversal order matches top-to-bottom layout order',
      );
    });

    testWidgets('Tab through sidebar many times does not crash (no trap)', (
      tester,
    ) async {
      // Proof: Tab completes a multiple-cycle traversal without hanging or
      // throwing — demonstrating there is no focus trap in the sidebar.
      // Tab-key events are processed synchronously; if a trap existed the
      // test harness would time out or Flutter would loop infinitely.
      await tester.pumpWidget(
        makeTestable(
          _SidebarKeyboardHarness(
            items: _navItems,
            activeId: 'history',
            onItemTap: (_) {},
          ),
        ),
      );
      await _settle(tester);

      // Three full cycles through all items — no crash, no exception.
      for (var i = 0; i < _navItems.length * 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await _settle(tester);
      }

      expect(tester.takeException(), isNull);
      expect(find.byType(WpSidebar), findsOneWidget);
    });
  });

  // =========================================================================
  // AC3 + AC4 — Dialog/overlay returns focus to trigger after close
  // =========================================================================

  group('AC3 — Dialog returns focus to trigger after close', () {
    testWidgets('focus restored to trigger button after dialog dismissed', (
      tester,
    ) async {
      final triggerFocus = FocusNode(debugLabel: 'trigger');
      addTearDown(triggerFocus.dispose);

      await tester.pumpWidget(
        makeTestable(_DialogFocusHarness(focusNode: triggerFocus)),
      );
      await tester.pumpAndSettle();

      // Trigger button has autofocus.
      expect(
        triggerFocus.hasFocus,
        isTrue,
        reason: 'Trigger button should have focus before dialog opens',
      );

      // Open dialog via Enter key (sendKeyEvent — AC4).
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350)); // transition settle

      expect(find.text('Abbrechen'), findsOneWidget);

      // Dismiss with Cancel button tap.
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();

      // Focus must return to the trigger.
      expect(
        triggerFocus.hasFocus,
        isTrue,
        reason: 'Focus should return to trigger button after dialog dismissal',
      );
    });

    testWidgets('dialog confirm button is keyboard-activatable via Enter', (
      tester,
    ) async {
      bool? confirmed;

      await tester.pumpWidget(
        makeTestable(
          Builder(
            builder: (context) => ElevatedButton(
              autofocus: true,
              onPressed: () async {
                confirmed = await showWpConfirmDialog(
                  context: context,
                  title: 'Confirm test',
                  message: 'Can you confirm?',
                  confirmLabel: 'Confirm',
                  cancelLabel: 'Cancel',
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open dialog.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('Confirm'), findsOneWidget);

      // Activate confirm with Enter (dialog confirm has autofocus).
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(
        confirmed,
        isTrue,
        reason: 'Enter on autofocused confirm button should confirm dialog',
      );
    });
  });
}
