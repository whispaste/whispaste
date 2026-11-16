import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/side_panel/side_panel_snapshot.dart';

void main() {
  group('SidePanelSnapshot.failedSections', () {
    test('round-trips through the channel map', () {
      const snapshot = SidePanelSnapshot(
        failedSections: {
          SidePanelSection.transcriptions,
          SidePanelSection.snippets,
        },
      );

      final decoded = SidePanelSnapshot.fromMap(snapshot.toMap());

      expect(decoded.failedSections, {
        SidePanelSection.transcriptions,
        SidePanelSection.snippets,
      });
    });

    test('defaults to no failed section and tolerates a malformed value', () {
      expect(const SidePanelSnapshot().failedSections, isEmpty);

      final decoded = SidePanelSnapshot.fromMap({
        'failedSections': ['noSuchSection', 42],
      });

      expect(decoded.failedSections, isEmpty);
    });
  });
}
