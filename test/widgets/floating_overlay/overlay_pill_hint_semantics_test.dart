/// #633: a pill hint carries its own stable testID, and a hint the main
/// engine has read out already is no live region, so it is heard once.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller_interface.dart';
import 'package:whispaste/widgets/floating_overlay/floating_overlay_view.dart';

FloatingOverlaySnapshot _hint({String? id, bool announced = false}) =>
    FloatingOverlaySnapshot(
      visible: true,
      state: OverlayVisualState.done,
      label: 'Profile: Mail',
      doneMessage: 'Profile: Mail',
      pillHintId: id,
      announced: announced,
    );

Future<SemanticsNode?> _pill(
  WidgetTester tester,
  FloatingOverlaySnapshot s,
) async {
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: WpFloatingOverlayView(snapshot: s),
      ),
    ),
  );
  final finder = find.semantics.byPredicate((n) => n.label == 'Profile: Mail');
  return finder.evaluate().isEmpty ? null : finder.evaluate().first;
}

void main() {
  testWidgets('a read-out hint has its testID and no live region', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final node = await _pill(
      tester,
      _hint(id: 'profile-switched', announced: true),
    );
    expect(node, isNotNull);
    final data = node!.getSemanticsData();
    expect(data.identifier, 'overlay-pill-hint');
    expect(data.flagsCollection.isLiveRegion, isFalse);
    handle.dispose();
  });

  testWidgets('a status change the overlay owns stays a live region', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final node = await _pill(tester, _hint());
    expect(node, isNotNull);
    final data = node!.getSemanticsData();
    expect(data.identifier, isEmpty);
    expect(data.flagsCollection.isLiveRegion, isTrue);
    handle.dispose();
  });
}
