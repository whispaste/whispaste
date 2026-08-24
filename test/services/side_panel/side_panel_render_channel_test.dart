import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/side_panel/side_panel_render_channel.dart';
import 'package:whispaste/services/side_panel/side_panel_snapshot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const name = 'test/side_panel_render';
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

  group('SidePanelRenderChannel — inbound (native → render engine)', () {
    test('updateSnapshot rebuilds the snapshot via fromMap', () async {
      SidePanelSnapshot? received;
      final channel = SidePanelRenderChannel(
        name: name,
        onSnapshot: (s) => received = s,
      );
      addTearDown(channel.dispose);

      const snap = SidePanelSnapshot(
        visible: true,
        transcriptions: [SidePanelRow(id: 't1', title: 'Hello')],
      );
      await sendFromNative('updateSnapshot', snap.toMap());

      expect(received, isNotNull);
      expect(received!.visible, isTrue);
      expect(received!.transcriptions.single.id, 't1');
      expect(received!.transcriptions.single.title, 'Hello');
    });

    test('unknown methods are ignored', () async {
      var called = false;
      final channel = SidePanelRenderChannel(
        name: name,
        onSnapshot: (_) => called = true,
      );
      addTearDown(channel.dispose);

      await sendFromNative('somethingElse', null);

      expect(called, isFalse);
    });
  });

  group('SidePanelRenderChannel — outbound (render engine → native)', () {
    test('rowClicked sends the section name and id', () async {
      final calls = <MethodCall>[];
      const probe = MethodChannel(name);
      binaryMessenger.setMockMethodCallHandler(probe, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => binaryMessenger.setMockMethodCallHandler(probe, null));

      final channel = SidePanelRenderChannel(name: name, onSnapshot: (_) {});
      addTearDown(channel.dispose);

      channel.rowClicked(SidePanelSection.snippets, 'snip-1');
      await Future<void>.delayed(Duration.zero);

      expect(calls, hasLength(1));
      expect(calls.single.method, 'rowClicked');
      expect(calls.single.arguments, {'section': 'snippets', 'id': 'snip-1'});
    });

    test('hoverLeft invokes the host with no arguments', () async {
      final calls = <MethodCall>[];
      const probe = MethodChannel(name);
      binaryMessenger.setMockMethodCallHandler(probe, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => binaryMessenger.setMockMethodCallHandler(probe, null));

      final channel = SidePanelRenderChannel(name: name, onSnapshot: (_) {});
      addTearDown(channel.dispose);

      channel.hoverLeft();
      await Future<void>.delayed(Duration.zero);

      expect(calls, hasLength(1));
      expect(calls.single.method, 'hoverLeft');
    });

    test('notifyReady / reportError invoke the host', () async {
      final calls = <MethodCall>[];
      const probe = MethodChannel(name);
      binaryMessenger.setMockMethodCallHandler(probe, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => binaryMessenger.setMockMethodCallHandler(probe, null));

      final channel = SidePanelRenderChannel(name: name, onSnapshot: (_) {});
      addTearDown(channel.dispose);

      channel.notifyReady();
      channel.reportError('boom');
      await Future<void>.delayed(Duration.zero);

      expect(calls, hasLength(2));
      expect(calls[0].method, 'ready');
      expect(calls[1].method, 'reportError');
      expect(calls[1].arguments, {'message': 'boom'});
    });
  });
}
