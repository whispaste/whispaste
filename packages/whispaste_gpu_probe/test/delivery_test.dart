/// Tests for delivery.dart: openInBrowserCommand, revealCommand,
/// buildMailtoUrl, mailOpenCommand, deliverReport.
///
/// No real processes are spawned — all tests use the injectable
/// [DeliveryLauncher] seam.
library;

import 'package:test/test.dart';
import 'package:whispaste_gpu_probe/whispaste_gpu_probe.dart';

void main() {
  // ---------------------------------------------------------------------------
  // openInBrowserCommand
  // ---------------------------------------------------------------------------

  group('openInBrowserCommand', () {
    test('macOS: open <htmlPath>', () {
      final cmd = openInBrowserCommand(
        '/tmp/report.html',
        platformOverride: 'macos',
      );
      expect(cmd, equals(['open', '/tmp/report.html']));
    });

    test('windows: cmd /c start "" <htmlPath>', () {
      final cmd = openInBrowserCommand(
        r'C:\Users\test\Desktop\report.html',
        platformOverride: 'windows',
      );
      expect(
        cmd,
        equals([
          'cmd',
          '/c',
          'start',
          '',
          r'C:\Users\test\Desktop\report.html',
        ]),
      );
    });

    test('linux: xdg-open <htmlPath>', () {
      final cmd = openInBrowserCommand(
        '/home/user/Desktop/report.html',
        platformOverride: 'linux',
      );
      expect(cmd, equals(['xdg-open', '/home/user/Desktop/report.html']));
    });
  });

  // ---------------------------------------------------------------------------
  // revealCommand
  // ---------------------------------------------------------------------------

  group('revealCommand', () {
    test('macOS: open -R <zipPath>', () {
      final cmd = revealCommand('/tmp/report.zip', platform: 'macos');
      expect(cmd.executable, equals('open'));
      expect(cmd.arguments, equals(['-R', '/tmp/report.zip']));
    });

    test('windows: explorer /select,<zipPath>', () {
      final cmd = revealCommand(
        r'C:\Users\test\Desktop\report.zip',
        platform: 'windows',
      );
      expect(cmd.executable, equals('explorer'));
      expect(
        cmd.arguments,
        equals([r'/select,C:\Users\test\Desktop\report.zip']),
      );
    });

    test('linux: xdg-open <parent dir>', () {
      final cmd = revealCommand(
        '/home/user/Desktop/report.zip',
        platform: 'linux',
      );
      expect(cmd.executable, equals('xdg-open'));
      expect(cmd.arguments, hasLength(1));
      // Parent directory of the zip file.
      expect(cmd.arguments.first, equals('/home/user/Desktop'));
    });
  });

  // ---------------------------------------------------------------------------
  // buildMailtoUrl
  // ---------------------------------------------------------------------------

  group('buildMailtoUrl', () {
    test('default subject contains GPU-Probe-Report', () {
      final url = buildMailtoUrl();
      expect(url, contains('GPU-Probe-Report'));
    });

    test('default recipient is the support address', () {
      final url = buildMailtoUrl();
      expect(url, startsWith('mailto:'));
      expect(url, contains('silvio-lindstedt'));
    });

    test('custom subject is percent-encoded', () {
      final url = buildMailtoUrl(subject: 'Test Subject');
      expect(url, contains('Test%20Subject'));
    });

    test('custom body is percent-encoded', () {
      final url = buildMailtoUrl(body: 'Hello World');
      expect(url, contains('Hello%20World'));
    });

    test('default body mentions GPU-Probe-Report', () {
      final url = buildMailtoUrl();
      // The body is percent-encoded; decode to check.
      final uri = Uri.parse(
        url.replaceFirst('mailto:', 'mailto:test@test.com'),
      );
      final body = uri.queryParameters['body'] ?? '';
      expect(body, contains('GPU-Probe-Report'));
    });
  });

  // ---------------------------------------------------------------------------
  // mailOpenCommand
  // ---------------------------------------------------------------------------

  group('mailOpenCommand', () {
    test('macOS: open <mailtoUrl>', () {
      const url = 'mailto:test@example.com';
      final cmd = mailOpenCommand(url, platform: 'macos');
      expect(cmd.executable, equals('open'));
      expect(cmd.arguments, equals([url]));
    });

    test('windows: cmd /c start "" <mailtoUrl>', () {
      const url = 'mailto:test@example.com';
      final cmd = mailOpenCommand(url, platform: 'windows');
      expect(cmd.executable, equals('cmd'));
      expect(cmd.arguments, equals(['/c', 'start', '', url]));
    });

    test('linux: xdg-open <mailtoUrl>', () {
      const url = 'mailto:test@example.com';
      final cmd = mailOpenCommand(url, platform: 'linux');
      expect(cmd.executable, equals('xdg-open'));
      expect(cmd.arguments, equals([url]));
    });
  });

  // ---------------------------------------------------------------------------
  // deliverReport — injectable fake launcher
  // ---------------------------------------------------------------------------

  group('deliverReport', () {
    test(
      'calls launcher exactly twice (reveal + browser); no mail client',
      () async {
        final calls = <(String, List<String>)>[];
        Future<void> fakeLauncher(String exe, List<String> args) async {
          calls.add((exe, args));
        }

        await deliverReport(
          '/tmp/report.zip',
          platform: 'macos',
          launcher: fakeLauncher,
        );

        expect(calls, hasLength(2));
      },
    );

    test('mail-open command is never invoked by deliverReport', () async {
      final calls = <(String, List<String>)>[];
      Future<void> fakeLauncher(String exe, List<String> args) async {
        calls.add((exe, args));
      }

      await deliverReport(
        '/tmp/report.zip',
        platform: 'macos',
        launcher: fakeLauncher,
      );

      // No call should contain a mailto: URL.
      for (final (_, args) in calls) {
        for (final arg in args) {
          expect(arg, isNot(startsWith('mailto:')));
        }
      }
    });

    test('first call is the reveal command (open -R on macOS)', () async {
      final calls = <(String, List<String>)>[];
      Future<void> fakeLauncher(String exe, List<String> args) async {
        calls.add((exe, args));
      }

      await deliverReport(
        '/tmp/report.zip',
        platform: 'macos',
        launcher: fakeLauncher,
      );

      expect(calls[0].$1, equals('open'));
      expect(calls[0].$2, equals(['-R', '/tmp/report.zip']));
    });

    test('second call opens browser with html path (open on macOS)', () async {
      final calls = <(String, List<String>)>[];
      Future<void> fakeLauncher(String exe, List<String> args) async {
        calls.add((exe, args));
      }

      await deliverReport(
        '/tmp/report.zip',
        platform: 'macos',
        launcher: fakeLauncher,
      );

      expect(calls[1].$1, equals('open'));
      expect(calls[1].$2, equals(['/tmp/report.html']));
    });

    test('second call on windows uses cmd /c start for html', () async {
      final calls = <(String, List<String>)>[];
      Future<void> fakeLauncher(String exe, List<String> args) async {
        calls.add((exe, args));
      }

      await deliverReport(
        r'C:\Users\test\Desktop\report.zip',
        platform: 'windows',
        launcher: fakeLauncher,
      );

      expect(calls[1].$1, equals('cmd'));
      expect(
        calls[1].$2,
        equals(['/c', 'start', '', r'C:\Users\test\Desktop\report.html']),
      );
    });

    test('second call on linux uses xdg-open for html', () async {
      final calls = <(String, List<String>)>[];
      Future<void> fakeLauncher(String exe, List<String> args) async {
        calls.add((exe, args));
      }

      await deliverReport(
        '/home/user/Desktop/report.zip',
        platform: 'linux',
        launcher: fakeLauncher,
      );

      expect(calls[1].$1, equals('xdg-open'));
      expect(calls[1].$2, equals(['/home/user/Desktop/report.html']));
    });

    test('uses xdg-open for reveal on linux (first call)', () async {
      final calls = <(String, List<String>)>[];
      Future<void> fakeLauncher(String exe, List<String> args) async {
        calls.add((exe, args));
      }

      await deliverReport(
        '/home/user/Desktop/report.zip',
        platform: 'linux',
        launcher: fakeLauncher,
      );

      expect(calls[0].$1, equals('xdg-open'));
      expect(calls[0].$2.first, equals('/home/user/Desktop'));
    });

    test(
      'windows reveal uses explorer with /select, prefix (first call)',
      () async {
        final calls = <(String, List<String>)>[];
        Future<void> fakeLauncher(String exe, List<String> args) async {
          calls.add((exe, args));
        }

        await deliverReport(
          r'C:\Users\test\Desktop\report.zip',
          platform: 'windows',
          launcher: fakeLauncher,
        );

        expect(calls[0].$1, equals('explorer'));
        expect(
          calls[0].$2.first,
          equals(r'/select,C:\Users\test\Desktop\report.zip'),
        );
      },
    );
  });
}
