/// Tests for delivery.dart: revealCommand, buildMailtoUrl, mailOpenCommand,
/// deliverReport.
///
/// No real processes are spawned — all tests use the injectable
/// [DeliveryLauncher] seam.
library;

import 'package:test/test.dart';
import 'package:whispaste_gpu_probe/whispaste_gpu_probe.dart';

void main() {
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
    test('calls launcher exactly twice (reveal + mail)', () async {
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

      expect(calls.first.$1, equals('open'));
      expect(calls.first.$2, equals(['-R', '/tmp/report.zip']));
    });

    test('second call opens mail client with a mailto URL', () async {
      final calls = <(String, List<String>)>[];
      Future<void> fakeLauncher(String exe, List<String> args) async {
        calls.add((exe, args));
      }

      await deliverReport(
        '/tmp/report.zip',
        platform: 'macos',
        launcher: fakeLauncher,
      );

      final mailArgs = calls[1].$2;
      expect(mailArgs, hasLength(1));
      expect(mailArgs.first, startsWith('mailto:'));
    });

    test(
      'mailto URL in second call contains GPU-Probe-Report subject',
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

        final mailtoUrl = calls[1].$2.first;
        expect(mailtoUrl, contains('GPU-Probe-Report'));
      },
    );

    test('uses xdg-open for reveal on linux', () async {
      final calls = <(String, List<String>)>[];
      Future<void> fakeLauncher(String exe, List<String> args) async {
        calls.add((exe, args));
      }

      await deliverReport(
        '/home/user/Desktop/report.zip',
        platform: 'linux',
        launcher: fakeLauncher,
      );

      expect(calls.first.$1, equals('xdg-open'));
      expect(calls.first.$2.first, equals('/home/user/Desktop'));
    });

    test('windows reveal uses explorer with /select, prefix', () async {
      final calls = <(String, List<String>)>[];
      Future<void> fakeLauncher(String exe, List<String> args) async {
        calls.add((exe, args));
      }

      await deliverReport(
        r'C:\Users\test\Desktop\report.zip',
        platform: 'windows',
        launcher: fakeLauncher,
      );

      expect(calls.first.$1, equals('explorer'));
      expect(
        calls.first.$2.first,
        equals(r'/select,C:\Users\test\Desktop\report.zip'),
      );
    });
  });
}
