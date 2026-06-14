import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/floating_button/floating_button_controller_interface.dart';
import 'package:whispaste/services/floating_button/floating_button_render_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const name = 'test/button_render';
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

  group('FloatingButtonRenderChannel — inbound (native → render engine)', () {
    test('setState fires onState with the correct parsed enum value', () async {
      FloatingButtonVisualState? received;
      final channel = FloatingButtonRenderChannel(
        name: name,
        onState: (s) => received = s,
        onDiameter: (_) {},
      );
      addTearDown(channel.dispose);

      await sendFromNative('setState', {'state': 'recording'});

      expect(received, FloatingButtonVisualState.recording);
    });

    test('setState parses all known states correctly', () async {
      for (final state in FloatingButtonVisualState.values) {
        FloatingButtonVisualState? received;
        final channel = FloatingButtonRenderChannel(
          name: name,
          onState: (s) => received = s,
          onDiameter: (_) {},
        );
        addTearDown(channel.dispose);

        await sendFromNative('setState', {'state': state.name});

        expect(received, state, reason: 'Expected $state from "${state.name}"');
      }
    });

    test('setState ignores unknown state names without throwing', () async {
      FloatingButtonVisualState? received;
      final channel = FloatingButtonRenderChannel(
        name: name,
        onState: (s) => received = s,
        onDiameter: (_) {},
      );
      addTearDown(channel.dispose);

      await sendFromNative('setState', {'state': 'unknown_future_state'});

      expect(received, isNull);
    });

    test('setDiameter fires onDiameter with the correct double', () async {
      double? received;
      final channel = FloatingButtonRenderChannel(
        name: name,
        onState: (_) {},
        onDiameter: (d) => received = d,
      );
      addTearDown(channel.dispose);

      await sendFromNative('setDiameter', {'diameter': 80.0});

      expect(received, 80.0);
    });

    test('setSize alias also fires onDiameter', () async {
      double? received;
      final channel = FloatingButtonRenderChannel(
        name: name,
        onState: (_) {},
        onDiameter: (d) => received = d,
      );
      addTearDown(channel.dispose);

      await sendFromNative('setSize', {'size': 44.0});

      expect(received, 44.0);
    });

    test(
      'setTheme is accepted and ignored without calling any callback',
      () async {
        var called = false;
        final channel = FloatingButtonRenderChannel(
          name: name,
          onState: (_) => called = true,
          onDiameter: (_) => called = true,
        );
        addTearDown(channel.dispose);

        await sendFromNative('setTheme', {'isDark': true});

        expect(called, isFalse);
      },
    );
  });

  group('FloatingButtonRenderChannel — outbound (render engine → native)', () {
    test(
      'clicked / startDrag / showContextMenu / ready invoke the host',
      () async {
        final calls = <String>[];
        const probe = MethodChannel(name);
        binaryMessenger.setMockMethodCallHandler(probe, (call) async {
          calls.add(call.method);
          return null;
        });
        addTearDown(
          () => binaryMessenger.setMockMethodCallHandler(probe, null),
        );

        final channel = FloatingButtonRenderChannel(
          name: name,
          onState: (_) {},
          onDiameter: (_) {},
        );
        addTearDown(channel.dispose);

        channel.clicked();
        channel.startDrag();
        channel.showContextMenu();
        channel.notifyReady();
        await Future<void>.delayed(Duration.zero);

        expect(calls, ['clicked', 'startDrag', 'showContextMenu', 'ready']);
      },
    );
  });
}
