import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/side_panel/side_panel_snapshot.dart';
import 'package:whispaste/widgets/side_panel/side_panel_view.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  testWidgets('a section whose load failed says so instead of looking empty', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(
        const WpSidePanelView(
          snapshot: SidePanelSnapshot(
            failedSections: {SidePanelSection.transcriptions},
          ),
          onRowTap: _noopTap,
          onClose: _noopClose,
        ),
      ),
    );

    expect(
      find.text('Something went wrong. Please try again.'),
      findsOneWidget,
    );
    expect(
      find.text('Close and reopen the panel to try again.'),
      findsOneWidget,
    );
    expect(find.text('No recordings yet'), findsNothing);
  });
}

void _noopTap(SidePanelSection section, String id) {}
void _noopClose() {}
