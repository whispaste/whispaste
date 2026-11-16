// The start screen of a locked history offers the restore dialog once the key
// is known to be lost or unreadable, not while it only waits for consent.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/data_key_access.dart';
import 'package:whispaste/features/settings/data_key/data_key_flows.dart';
import 'package:whispaste/features/startup/data_key_locked_screen.dart';

import '../../fixtures/test_helpers.dart';

/// A recorded key (marker present); "Allow access" answers with [_answer].
class _RecordedKey extends DataKeyAccessNotifier {
  _RecordedKey(this._answer);

  final DataKeyAccessStatus _answer;

  @override
  DataKeyAccessStatus build() => DataKeyAccessStatus.ready;

  @override
  Future<DataKeyAccessStatus> request() async => _answer;
}

void main() {
  for (final answer in [DataKeyAccessStatus.lost, DataKeyAccessStatus.failed]) {
    testWidgets('${answer.name}: "Restore" appears and opens the restore '
        'flow', (tester) async {
      // The screen is taller than the default 800x600 surface; taps on the
      // lower buttons would miss.
      tester.view.physicalSize = const Size(1280, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var restores = 0;
      await tester.pumpWidget(
        makeTestable(
          const DataKeyLockedScreen(),
          overrides: [
            dataKeyAccessProvider.overrideWith(() => _RecordedKey(answer)),
            dataKeyLockedRestoreFlowProvider.overrideWithValue((_) async {
              restores++;
              return false;
            }),
          ],
        ),
      );
      await tester.pumpAndSettle();

      const restore = ValueKey('data-key-locked-restore');
      // Waiting for consent: "Allow access" is the one offer.
      expect(find.byKey(restore), findsNothing);

      await tester.tap(find.byKey(const ValueKey('data-key-locked-allow')));
      await tester.pumpAndSettle();
      expect(find.byKey(restore), findsOneWidget);

      await tester.tap(find.byKey(restore));
      await tester.pumpAndSettle();
      expect(restores, 1);
    });
  }
}
