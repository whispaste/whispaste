/// Unit tests for the delivery step (reveal + mailto).
///
/// All tests are headless / CI-safe — no real process is spawned, no mail
/// client or Finder is opened. A fake [ProcessLauncher] captures calls.
library;

import 'package:test/test.dart';
import 'package:whispaste_diagnostics/src/cli/delivery.dart';

void main() {
  // -------------------------------------------------------------------------
  // revealCommand
  // -------------------------------------------------------------------------
  group('revealCommand', () {
    const zipPath =
        '/Users/test/Desktop/WhisPaste-Diagnose-20260609-120000.zip';

    test('macOS: open -R <zipPath>', () {
      final cmd = revealCommand(zipPath, platform: 'macos');
      expect(cmd.executable, equals('open'));
      expect(cmd.arguments, equals(['-R', zipPath]));
    });

    test('Windows: explorer /select,<zipPath>', () {
      const winPath = r'C:\Users\test\Desktop\WhisPaste-Diagnose.zip';
      final cmd = revealCommand(winPath, platform: 'windows');
      expect(cmd.executable, equals('explorer'));
      expect(cmd.arguments, equals(['/select,$winPath']));
    });

    test('Linux fallback: xdg-open on parent directory', () {
      final cmd = revealCommand(zipPath, platform: 'linux');
      expect(cmd.executable, equals('xdg-open'));
      // argument is the parent directory of the zip
      expect(cmd.arguments, hasLength(1));
      expect(cmd.arguments.first, endsWith('/Desktop'));
    });
  });

  // -------------------------------------------------------------------------
  // buildMailtoUrl
  // -------------------------------------------------------------------------
  group('buildMailtoUrl', () {
    test('starts with mailto: scheme', () {
      final url = buildMailtoUrl();
      expect(url, startsWith('mailto:'));
    });

    test('default To address is correct', () {
      final url = buildMailtoUrl();
      expect(
        url,
        contains(Uri.encodeComponent('silvio-lindstedt@outlook.com')),
      );
    });

    test('default Subject is correct', () {
      final url = buildMailtoUrl();
      expect(url, contains(Uri.encodeComponent('WhisPaste Diagnose-Report')));
    });

    test('default Body contains attach-hint', () {
      final url = buildMailtoUrl();
      // The body must contain the attach-hint (German, may include umlauts).
      expect(
        url,
        contains(Uri.encodeComponent('ZIP-Datei vom Desktop anhängen')),
      );
    });

    test('percent-encodes spaces in subject', () {
      final url = buildMailtoUrl(subject: 'Hello World');
      // RFC 3986: spaces → %20 (Uri.encodeComponent uses %20)
      expect(url, contains('Hello%20World'));
    });

    test('percent-encodes German umlauts in body', () {
      final url = buildMailtoUrl(body: 'Bitte anhängen');
      // ä → %C3%A4
      expect(url, contains('%C3%A4'));
    });

    test('custom To/Subject/Body are reflected in URL', () {
      final url = buildMailtoUrl(
        to: 'test@example.com',
        subject: 'My Subject',
        body: 'My body text',
      );
      expect(url, contains(Uri.encodeComponent('test@example.com')));
      expect(url, contains(Uri.encodeComponent('My Subject')));
      expect(url, contains(Uri.encodeComponent('My body text')));
    });

    test('URL round-trips: decoded values match originals', () {
      const to = 'silvio-lindstedt@outlook.com';
      const subject = 'WhisPaste Diagnose-Report';
      const body = 'bitte anhängen Ü ö';
      final url = buildMailtoUrl(to: to, subject: subject, body: body);

      // Strip "mailto:<to>?" prefix and parse query.
      final afterMailto = url.replaceFirst('mailto:', '');
      final qIndex = afterMailto.indexOf('?');
      final decodedTo = Uri.decodeComponent(afterMailto.substring(0, qIndex));
      final query = Uri.splitQueryString(afterMailto.substring(qIndex + 1));

      expect(decodedTo, equals(to));
      expect(query['subject'], equals(subject));
      expect(query['body'], equals(body));
    });
  });

  // -------------------------------------------------------------------------
  // mailOpenCommand
  // -------------------------------------------------------------------------
  group('mailOpenCommand', () {
    const mailtoUrl = 'mailto:test%40example.com?subject=Test';

    test('macOS: open <mailtoUrl>', () {
      final cmd = mailOpenCommand(mailtoUrl, platform: 'macos');
      expect(cmd.executable, equals('open'));
      expect(cmd.arguments, equals([mailtoUrl]));
    });

    test('Windows: cmd /c start "" <mailtoUrl>', () {
      final cmd = mailOpenCommand(mailtoUrl, platform: 'windows');
      expect(cmd.executable, equals('cmd'));
      expect(cmd.arguments, equals(['/c', 'start', '', mailtoUrl]));
    });

    test('Linux fallback: xdg-open <mailtoUrl>', () {
      final cmd = mailOpenCommand(mailtoUrl, platform: 'linux');
      expect(cmd.executable, equals('xdg-open'));
      expect(cmd.arguments, equals([mailtoUrl]));
    });
  });

  // -------------------------------------------------------------------------
  // deliverReport — orchestration with fake launcher
  // -------------------------------------------------------------------------
  group('deliverReport', () {
    const zipPath = '/tmp/WhisPaste-Diagnose-20260609-120000.zip';

    test('calls launcher exactly twice (reveal + mail)', () async {
      final calls = <(String, List<String>)>[];
      Future<void> fakeLauncher(String exe, List<String> args) async {
        calls.add((exe, args));
      }

      await deliverReport(zipPath, platform: 'macos', launcher: fakeLauncher);

      expect(calls, hasLength(2));
    });

    test('macOS: first call is the reveal command', () async {
      final calls = <(String, List<String>)>[];
      Future<void> fakeLauncher(String exe, List<String> args) async {
        calls.add((exe, args));
      }

      await deliverReport(zipPath, platform: 'macos', launcher: fakeLauncher);

      final (exe, args) = calls[0];
      expect(exe, equals('open'));
      expect(args, equals(['-R', zipPath]));
    });

    test('macOS: second call is the mail-open command', () async {
      final calls = <(String, List<String>)>[];
      Future<void> fakeLauncher(String exe, List<String> args) async {
        calls.add((exe, args));
      }

      await deliverReport(zipPath, platform: 'macos', launcher: fakeLauncher);

      final (exe, args) = calls[1];
      expect(exe, equals('open'));
      // The argument should be the mailto URL.
      expect(args, hasLength(1));
      expect(args.first, startsWith('mailto:'));
    });

    test('Windows: uses explorer for reveal and cmd for mail', () async {
      final calls = <(String, List<String>)>[];
      Future<void> fakeLauncher(String exe, List<String> args) async {
        calls.add((exe, args));
      }

      const winZip = r'C:\Users\test\Desktop\WhisPaste-Diagnose.zip';
      await deliverReport(winZip, platform: 'windows', launcher: fakeLauncher);

      expect(calls, hasLength(2));
      expect(calls[0].$1, equals('explorer'));
      expect(calls[1].$1, equals('cmd'));
    });

    test(
      'launcher is NOT called with real Process (no network / no backend)',
      () async {
        // This test verifies the no-backend contract: the fake launcher is used
        // and no real HTTP or upload call can be inferred from the commands.
        final executables = <String>[];
        Future<void> fakeLauncher(String exe, List<String> args) async {
          executables.add(exe);
        }

        await deliverReport(zipPath, platform: 'macos', launcher: fakeLauncher);

        // Only 'open' is used on macOS — no curl, wget, http, upload, etc.
        for (final exe in executables) {
          expect(
            exe,
            isNot(anyOf(contains('curl'), contains('wget'), contains('http'))),
          );
        }
      },
    );
  });
}
