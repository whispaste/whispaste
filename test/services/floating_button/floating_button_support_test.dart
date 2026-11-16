// Unit tests for the Linux floating-button support mapping (PAR-010).
//
// The native probe (getCapabilities) and the session type are inputs here, so
// the decision logic can be checked on any host. The real probe is covered by
// the Linux runtime check in the report, not by these tests.
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/floating_button/floating_button_support.dart';

void main() {
  group('linuxSessionTypeFrom', () {
    test('XDG_SESSION_TYPE=wayland is a Wayland session', () {
      expect(
        linuxSessionTypeFrom({'XDG_SESSION_TYPE': 'wayland'}),
        LinuxSessionType.wayland,
      );
    });

    test('XDG_SESSION_TYPE is compared case-insensitively', () {
      expect(
        linuxSessionTypeFrom({'XDG_SESSION_TYPE': 'Wayland'}),
        LinuxSessionType.wayland,
      );
    });

    test('XDG_SESSION_TYPE=x11 is an X11 session', () {
      expect(
        linuxSessionTypeFrom({'XDG_SESSION_TYPE': 'x11'}),
        LinuxSessionType.x11,
      );
    });

    test('WAYLAND_DISPLAY without a session type counts as Wayland', () {
      expect(
        linuxSessionTypeFrom({'WAYLAND_DISPLAY': 'wayland-0'}),
        LinuxSessionType.wayland,
      );
    });

    test('no hints at all is unknown, not guessed', () {
      expect(linuxSessionTypeFrom({}), LinuxSessionType.unknown);
    });
  });

  group('linuxFloatingButtonSupport', () {
    test('X11 backend on an X11 session has no limits', () {
      final support = linuxFloatingButtonSupport(
        x11Backend: true,
        session: LinuxSessionType.x11,
      );
      expect(support.available, isTrue);
      expect(support.limits, isEmpty);
    });

    test('Wayland via XWayland is available and names the limits', () {
      final support = linuxFloatingButtonSupport(
        x11Backend: true,
        session: LinuxSessionType.wayland,
      );
      expect(support.available, isTrue);
      expect(support.limits, {
        FloatingButtonLimit.alwaysOnTop,
        FloatingButtonLimit.freePositioning,
      });
    });

    test('unknown session on an X11 backend has no limits', () {
      final support = linuxFloatingButtonSupport(
        x11Backend: true,
        session: LinuxSessionType.unknown,
      );
      expect(support.available, isTrue);
      expect(support.limits, isEmpty);
    });

    test('a backend without X11 is unavailable, whatever the session', () {
      for (final session in LinuxSessionType.values) {
        final support = linuxFloatingButtonSupport(
          x11Backend: false,
          session: session,
        );
        expect(support.available, isFalse, reason: session.name);
      }
    });
  });
}
