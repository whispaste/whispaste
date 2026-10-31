import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/overlay_customization.dart';
import 'package:whispaste/services/floating_button/floating_button_controller_interface.dart';
import 'package:whispaste/services/floating_button/floating_button_render_channel.dart';
import 'package:whispaste/services/floating_button/idle_capsule.dart';
import 'package:whispaste/widgets/floating_button/floating_button_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('IdleCapsuleHover', () {
    test('opens at once on enter and closes after the delay on exit', () {
      fakeAsync((async) {
        final changes = <bool>[];
        final hover = IdleCapsuleHover(
          hoverSupported: true,
          onExpandedChanged: changes.add,
        );

        hover.pointerEnter();
        expect(hover.expanded, isTrue);

        hover.pointerExit();
        async.elapse(
          IdleCapsule.collapseDelay - const Duration(milliseconds: 1),
        );
        expect(hover.expanded, isTrue, reason: 'still open during the delay');

        async.elapse(const Duration(milliseconds: 1));
        expect(hover.expanded, isFalse);
        expect(changes, [true, false]);
        hover.dispose();
      });
    });

    test('a pointer that returns within the delay keeps the pill open', () {
      fakeAsync((async) {
        final changes = <bool>[];
        final hover = IdleCapsuleHover(
          hoverSupported: true,
          onExpandedChanged: changes.add,
        );

        hover.pointerEnter();
        hover.pointerExit();
        async.elapse(const Duration(milliseconds: 100));
        hover.pointerEnter();
        async.elapse(IdleCapsule.collapseDelay * 2);

        expect(hover.expanded, isTrue);
        expect(changes, [true], reason: 'no close and reopen in between');
        hover.dispose();
      });
    });

    test('never opens where hover is not supported (Wayland)', () {
      fakeAsync((async) {
        final changes = <bool>[];
        final hover = IdleCapsuleHover(
          hoverSupported: false,
          onExpandedChanged: changes.add,
        );

        hover.pointerEnter();
        hover.pointerExit();
        async.elapse(IdleCapsule.collapseDelay);

        expect(hover.expanded, isFalse);
        expect(changes, isEmpty);
        hover.dispose();
      });
    });

    test('reset closes the pill at once and cancels a pending collapse', () {
      fakeAsync((async) {
        final changes = <bool>[];
        final hover = IdleCapsuleHover(
          hoverSupported: true,
          onExpandedChanged: changes.add,
        );

        hover.pointerEnter();
        hover.pointerExit();
        hover.reset();
        expect(hover.expanded, isFalse);

        async.elapse(IdleCapsule.collapseDelay);
        expect(changes, [true, false], reason: 'no second close after reset');
        hover.dispose();
      });
    });

    test('a Wayland session is detected from the environment', () {
      expect(
        IdleCapsule.isWaylandSession({'XDG_SESSION_TYPE': 'wayland'}),
        isTrue,
      );
      expect(
        IdleCapsule.isWaylandSession({'WAYLAND_DISPLAY': 'wayland-0'}),
        isTrue,
      );
      expect(
        IdleCapsule.isWaylandSession({'XDG_SESSION_TYPE': 'x11'}),
        isFalse,
      );
      expect(IdleCapsule.isWaylandSession(const {}), isFalse);
    });
  });

  group('WpFloatingButtonView capsule form', () {
    const capsuleOn = FloatingButtonLook(idleCapsule: true);

    test('the setting off keeps the classic disc at every state', () {
      for (final state in FloatingButtonVisualState.values) {
        expect(
          WpFloatingButtonView.isCapsule(
            state: state,
            look: FloatingButtonLook.defaults,
          ),
          isFalse,
        );
      }
      expect(
        WpFloatingButtonView.contentSizeFor(
          state: FloatingButtonVisualState.idle,
          diameter: 56,
          look: FloatingButtonLook.defaults,
          expanded: true,
        ),
        const Size(56, 56),
      );
    });

    test('only the idle button is a capsule; recording keeps the disc', () {
      expect(
        WpFloatingButtonView.isCapsule(
          state: FloatingButtonVisualState.idle,
          look: capsuleOn,
        ),
        isTrue,
      );
      expect(
        WpFloatingButtonView.contentSizeFor(
          state: FloatingButtonVisualState.recording,
          diameter: 56,
          look: capsuleOn,
          expanded: false,
        ),
        const Size(56, 56),
      );
    });

    test('rest and hover sizes follow IdleCapsule', () {
      expect(
        WpFloatingButtonView.contentSizeFor(
          state: FloatingButtonVisualState.idle,
          diameter: 56,
          look: capsuleOn,
          expanded: false,
        ),
        const Size(IdleCapsule.idleWidth, IdleCapsule.idleHeight),
      );
      expect(
        WpFloatingButtonView.contentSizeFor(
          state: FloatingButtonVisualState.idle,
          diameter: 56,
          look: capsuleOn,
          expanded: true,
        ),
        const Size(IdleCapsule.hoverWidth, IdleCapsule.hoverHeight),
      );
    });

    test('the flag survives the render-engine theme payload', () {
      final map = capsuleOn.toThemeMap();
      expect(map['idleCapsule'], isTrue);
      expect(FloatingButtonLook.fromThemeMap(map).idleCapsule, isTrue);
      expect(
        FloatingButtonLook.fromThemeMap(
          FloatingButtonLook.defaults.toThemeMap(),
        ).idleCapsule,
        isFalse,
      );
    });
  });

  group('FloatingButtonRenderChannel.setWindowSize', () {
    test('sends the content size to the native shell', () async {
      const name = 'test/button_render_capsule';
      const probe = MethodChannel(name);
      final binaryMessenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      binaryMessenger.setMockMethodCallHandler(probe, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => binaryMessenger.setMockMethodCallHandler(probe, null));

      final channel = FloatingButtonRenderChannel(
        name: name,
        onState: (_) {},
        onDiameter: (_) {},
      );
      addTearDown(channel.dispose);

      channel.setWindowSize(const Size(112, 28), expanded: true);
      await Future<void>.delayed(Duration.zero);

      expect(calls.single.method, 'setWindowSize');
      expect(calls.single.arguments, {
        'width': 112.0,
        'height': 28.0,
        'expanded': true,
      });
    });
  });
}
