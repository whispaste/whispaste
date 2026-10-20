/// A [SettingRow] with a dropdown trailing control at the 800 x 600 minimum
/// window, where the 232 px rail leaves its content column about 450 px wide.
///
/// The trailing control is capped, so the row must neither overflow nor hide
/// its label, at normal and at 1.3x text scale.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/theme/tokens.dart';
import 'package:whispaste/features/settings/settings_widgets.dart';
import 'package:whispaste/widgets/wp_dropdown.dart';

import '../../fixtures/test_helpers.dart';

const _longLabels = [
  'Ein sehr langer Gerätename aus dem Betriebssystem',
  'Second device name that is also rather long',
  'Third',
];

Widget _narrowRow({double textScale = 1.0}) {
  return makeTestable(
    MediaQuery(
      data: MediaQueryData(
        size: const Size(800, 600),
        textScaler: TextScaler.linear(textScale),
      ),
      child: Builder(
        builder: (context) => Row(
          children: [
            SizedBox(
              width: 800 - WpLayout.sidebarWidth,
              child: SettingRow(
                icon: LucideIcons.mic,
                label: 'Mikrofon-Eingabe',
                trailing: settingsDropdown(
                  context: context,
                  value: _longLabels.first,
                  items: _longLabels,
                  onChanged: (_) {},
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    size: const Size(800, 600),
  );
}

void main() {
  for (final scale in const [1.0, 1.3]) {
    testWidgets(
      'narrow window: dropdown row does not overflow at text scale $scale',
      (tester) async {
        await tester.pumpWidget(_narrowRow(textScale: scale));
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('Mikrofon-Eingabe'), findsOneWidget);

        final trailing = find.byType(WpDropdown<String>);
        expect(trailing, findsOneWidget);
        expect(
          tester.getSize(trailing).width,
          lessThanOrEqualTo(kSettingDropdownMaxWidth + 0.01),
        );
      },
    );
  }
}
