import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/floating_overlay/overlay_render_channel.dart';

/// WP-84 phase 2, plan items 1 and 6: the render engine acknowledges the first
/// painted frame after each hidden→visible show. No real engine is booted; the
/// heartbeat is driven by the widget test binding's frame pump.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OverlayFrameHeartbeat', () {
    testWidgets('one acknowledgement per show, after a frame is drawn', (
      tester,
    ) async {
      var acks = 0;
      final heartbeat = OverlayFrameHeartbeat(onFrame: () => acks++);

      heartbeat.onSnapshot(visible: true);
      expect(acks, 0, reason: 'nothing is painted until a frame runs');

      await tester.pump();
      expect(acks, 1);
    });

    testWidgets('further visible snapshots within one show do not re-ack', (
      tester,
    ) async {
      var acks = 0;
      final heartbeat = OverlayFrameHeartbeat(onFrame: () => acks++);

      heartbeat.onSnapshot(visible: true);
      await tester.pump();
      heartbeat.onSnapshot(visible: true);
      heartbeat.onSnapshot(visible: true);
      await tester.pump();

      expect(acks, 1);
    });

    testWidgets('a hide followed by a show acknowledges the new show', (
      tester,
    ) async {
      var acks = 0;
      final heartbeat = OverlayFrameHeartbeat(onFrame: () => acks++);

      heartbeat.onSnapshot(visible: true);
      await tester.pump();
      heartbeat.onSnapshot(visible: false);
      heartbeat.onSnapshot(visible: true);
      await tester.pump();

      expect(acks, 2);
    });

    testWidgets('a hidden snapshot never acknowledges', (tester) async {
      var acks = 0;
      final heartbeat = OverlayFrameHeartbeat(onFrame: () => acks++);

      heartbeat.onSnapshot(visible: false);
      await tester.pump();

      expect(acks, 0);
    });

    testWidgets('a show that is hidden before its frame does not ack', (
      tester,
    ) async {
      var acks = 0;
      final heartbeat = OverlayFrameHeartbeat(onFrame: () => acks++);

      heartbeat.onSnapshot(visible: true);
      heartbeat.onSnapshot(visible: false);
      await tester.pump();

      expect(acks, 0, reason: 'a hidden shell is not a frame the user sees');
    });
  });
}
