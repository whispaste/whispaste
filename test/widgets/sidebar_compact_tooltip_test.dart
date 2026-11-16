// Icon-only rail (UX-010): a keyboard user who reaches a nav entry must see
// its name, not only a hover user.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/widgets/sidebar.dart';

void main() {
  testWidgets('focusing an icon-only nav entry shows its name as tooltip', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: wpDarkTheme(),
        home: Scaffold(
          body: WpSidebar(
            compact: true,
            items: const [
              WpNavItem(
                id: 'history',
                icon: LucideIcons.mic,
                label: 'Recordings',
              ),
              WpNavItem(
                id: 'notes',
                icon: LucideIcons.stickyNote,
                label: 'Notes',
              ),
            ],
            activeId: 'history',
            onItemTap: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byTooltip('Notes'), findsOneWidget);

    final ink = tester.widget<InkWell>(
      find.byKey(const ValueKey('sidebar-nav-notes')),
    );
    ink.focusNode!.requestFocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Notes'), findsOneWidget);

    ink.focusNode!.unfocus();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Notes'), findsNothing);
  });
}
