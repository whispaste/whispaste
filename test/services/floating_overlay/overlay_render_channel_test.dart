import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller_interface.dart';
import 'package:whispaste/services/floating_overlay/overlay_render_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const name = 'test/overlay_render';
  const codec = StandardMethodCodec();
  final binaryMessenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<void> sendFromNative(String method, Object? args) {
    return binaryMessenger.handlePlatformMessage(
      name,
      codec.encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
  }

  group('OverlayRenderChannel — inbound (native → render engine)', () {
    test('updateSnapshot rebuilds the snapshot via fromMap', () async {
      FloatingOverlaySnapshot? received;
      final channel = OverlayRenderChannel(
        name: name,
        onSnapshot: (s) => received = s,
        onWaveformBars: (_) {},
        onOpacity: (_) {},
      );
      addTearDown(channel.dispose);

      const snap = FloatingOverlaySnapshot(
        visible: true,
        state: OverlayVisualState.transcribing,
        isDark: false,
        compact: true,
        label: 'Transcribing',
        elapsed: '0:03',
      );
      await sendFromNative('updateSnapshot', snap.toMap());

      expect(received, isNotNull);
      expect(received!.visible, isTrue);
      expect(received!.state, OverlayVisualState.transcribing);
      expect(received!.compact, isTrue);
      expect(received!.label, 'Transcribing');
      expect(received!.elapsed, '0:03');
    });

    test('setWaveformBars forwards a normalised double list', () async {
      List<double>? bars;
      final channel = OverlayRenderChannel(
        name: name,
        onSnapshot: (_) {},
        onWaveformBars: (b) => bars = b,
        onOpacity: (_) {},
      );
      addTearDown(channel.dispose);

      await sendFromNative('setWaveformBars', {
        'bars': [0.1, 0.5, 1.0],
      });

      expect(bars, [0.1, 0.5, 1.0]);
    });

    test('setOpacity forwards the master opacity', () async {
      double? opacity;
      final channel = OverlayRenderChannel(
        name: name,
        onSnapshot: (_) {},
        onWaveformBars: (_) {},
        onOpacity: (o) => opacity = o,
      );
      addTearDown(channel.dispose);

      await sendFromNative('setOpacity', {'opacity': 0.65});

      expect(opacity, 0.65);
    });
  });

  group('OverlayRenderChannel — outbound (render engine → native)', () {
    test('startDrag / bodyClicked / showContextMenu invoke the host', () async {
      final calls = <String>[];
      const probe = MethodChannel(name);
      binaryMessenger.setMockMethodCallHandler(probe, (call) async {
        calls.add(call.method);
        return null;
      });
      addTearDown(() => binaryMessenger.setMockMethodCallHandler(probe, null));

      final channel = OverlayRenderChannel(
        name: name,
        onSnapshot: (_) {},
        onWaveformBars: (_) {},
        onOpacity: (_) {},
      );
      addTearDown(channel.dispose);

      channel.startDrag();
      channel.bodyClicked();
      channel.showContextMenu();
      await Future<void>.delayed(Duration.zero);

      expect(calls, ['startDrag', 'bodyClicked', 'showContextMenu']);
    });
  });
}
