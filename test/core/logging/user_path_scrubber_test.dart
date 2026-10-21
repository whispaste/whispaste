/// Crash reports must not carry the OS account name. Home directories show up
/// in log breadcrumbs (`Preflight OK: model=/Users/<name>/...`), exception
/// values (`FileSystemException: ... C:\Users\<name>\...`) and messages.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:whispaste/core/logging/crash_reporter.dart';
import 'package:whispaste/core/logging/user_path_scrubber.dart';

void main() {
  group('scrubUserPaths', () {
    test('macOS home directory, incl. sandbox container paths', () {
      expect(
        scrubUserPaths(
          'model=/Users/alice/Library/Containers/de.whispaste.app/Data/m.bin',
        ),
        'model=/Users/<user>/Library/Containers/de.whispaste.app/Data/m.bin',
      );
    });

    test('Linux home directory', () {
      expect(
        scrubUserPaths('open /home/bob.smith/.local/share/whispaste/x.db'),
        'open /home/<user>/.local/share/whispaste/x.db',
      );
    });

    test('Windows profile with either slash and any drive/case', () {
      expect(
        scrubUserPaths(r'Cannot delete C:\Users\Carol\AppData\Roaming\x.log'),
        r'Cannot delete C:\Users\<user>\AppData\Roaming\x.log',
      );
      expect(
        scrubUserPaths('d:/users/carol/AppData/Local/x'),
        'd:/users/<user>/AppData/Local/x',
      );
    });

    test('the known home directory collapses to ~ (custom locations)', () {
      expect(
        scrubUserPaths(
          'path=/srv/profiles/dave/models',
          home: '/srv/profiles/dave',
        ),
        'path=~/models',
      );
    });

    test('a home directory is not matched inside a longer account name', () {
      expect(
        scrubUserPaths(
          r'Adreno GPU C:\Users\silvio\drv',
          home: r'C:\Users\silvi',
        ),
        r'Adreno GPU C:\Users\<user>\drv',
      );
    });

    test('the bare account name is replaced as a whole word', () {
      expect(
        scrubUserPaths('host erin-mbp user erin', userName: 'erin'),
        'host <user>-mbp user <user>',
      );
      // Not inside other words.
      expect(scrubUserPaths('generic', userName: 'eric'), 'generic');
    });

    test('very short account names are left alone (too many false hits)', () {
      expect(scrubUserPaths('a b c', userName: 'a'), 'a b c');
    });

    test('an account name with a space is replaced whole', () {
      final out = scrubUserPaths(
        '/Users/Max Mustermann/x.wav',
        home: '/nowhere',
        userName: 'nobody',
      );
      expect(out, '/Users/<user>/x.wav');
    });

    test('brackets and separators in the account name are replaced whole', () {
      expect(
        scrubUserPaths('/Users/Max (Büro)/x.wav', home: '/nowhere'),
        '/Users/<user>/x.wav',
      );
      expect(scrubUserPaths('/home/a;b/x', home: '/nowhere'), '/home/<user>/x');
    });

    test('error text after the path on the same line stays', () {
      expect(
        scrubUserPaths(
          'Cannot open /Users/anna: permission denied',
          home: '/nowhere',
        ),
        'Cannot open /Users/<user>: permission denied',
      );
      expect(
        scrubUserPaths(
          "path = '/Users/anna' (OS Error: denied, errno = 13)",
          home: '/nowhere',
        ),
        "path = '/Users/<user>' (OS Error: denied, errno = 13)",
      );
    });

    test('when in doubt, the account segment is redacted to the separator', () {
      expect(
        scrubUserPaths(
          'Cannot open /Users/anna permission denied',
          home: '/nowhere',
        ),
        'Cannot open /Users/<user>',
      );
      expect(
        scrubUserPaths(r'C:\Users\Muster, Max\x.wav', home: '/nowhere'),
        r'C:\Users\<user>\x.wav',
      );
      expect(
        scrubUserPaths('/Users/Muster, Max/x.wav', home: '/nowhere'),
        '/Users/<user>/x.wav',
      );
      expect(
        scrubUserPaths('/home/anna, errno = 2', home: '/nowhere'),
        '/home/<user>',
      );
    });

    test('text without paths is unchanged', () {
      expect(
        scrubUserPaths('Whisper model failed to load'),
        'Whisper model failed to load',
      );
    });
  });

  group('scrubUserPathsInMap (Sentry extras context)', () {
    test('scrubs String leaves recursively in maps and lists', () {
      final out = scrubUserPathsInMap(
        {
          'model': '/Users/alice/m.bin',
          'count': 3,
          'enabled': true,
          'nested': {
            'paths': ['/home/alice/a.wav', 42],
            'deeper': {'note': 'alice was here'},
          },
        },
        home: '/Users/alice',
        userName: 'alice',
      );

      expect(out['model'], isNot(contains('alice')));
      expect(out['count'], 3);
      expect(out['enabled'], isTrue);
      final nested = out['nested'] as Map<String, dynamic>;
      expect((nested['paths'] as List)[0], isNot(contains('alice')));
      expect((nested['paths'] as List)[1], 42);
      expect(
        (nested['deeper'] as Map<String, dynamic>)['note'],
        isNot(contains('alice')),
      );
    });

    test('does not mutate the input map', () {
      final input = <String, dynamic>{'p': '/Users/alice/x'};
      scrubUserPathsInMap(input, home: '/Users/alice', userName: 'alice');
      expect(input['p'], '/Users/alice/x');
    });
  });

  group('CrashReporter.beforeSend scrubs user paths', () {
    test('message, exception value, breadcrumb message and data', () {
      final event = SentryEvent(
        message: SentryMessage('Preflight OK: model=/Users/alice/m.bin'),
        exceptions: [
          SentryException(
            type: 'FileSystemException',
            value: r'Cannot open C:\Users\Alice\AppData\Roaming\x.db',
          ),
        ],
        breadcrumbs: [
          Breadcrumb(
            message: 'loaded /home/alice/.cache/w.bin',
            data: {'path': '/Users/alice/x', 'count': 3},
          ),
        ],
      );

      final out = CrashReporter.beforeSend(event, Hint());

      expect(out, isNotNull);
      final serialized = [
        out!.message!.formatted,
        out.exceptions!.single.value,
        out.breadcrumbs!.single.message,
        '${out.breadcrumbs!.single.data}',
      ].join('\n');
      expect(serialized.toLowerCase(), isNot(contains('alice')));
      expect(out.message!.formatted, 'Preflight OK: model=<file>.bin');
      expect(out.exceptions!.single.value, 'Cannot open <file>.db');
      expect(out.breadcrumbs!.single.message, 'loaded <file>.bin');
      expect(out.breadcrumbs!.single.data!['path'], '<path>');
      expect(out.breadcrumbs!.single.data!['count'], 3);
    });

    test('transaction name and stack frame paths', () {
      final event = SentryEvent(
        transaction: '/Users/alice/x.wav',
        exceptions: [
          SentryException(
            type: 'StateError',
            value: 'boom',
            stackTrace: SentryStackTrace(
              frames: [
                SentryStackFrame(
                  absPath: 'file:///Users/alice/proj/lib/a.dart',
                  fileName: '/Users/alice/proj/lib/a.dart',
                ),
                SentryStackFrame(absPath: 'package:whispaste/app.dart'),
              ],
            ),
          ),
        ],
      );

      final out = CrashReporter.beforeSend(event, Hint())!;

      expect(out.transaction, '<file>.wav');
      final frames = out.exceptions!.single.stackTrace!.frames;
      expect(frames[0].absPath, 'file:<file>.dart');
      expect(frames[0].fileName, '<file>.dart');
      expect(frames[1].absPath, 'package:whispaste/app.dart');
    });

    test('culprit and request parts', () {
      final event = SentryEvent(
        culprit: 'open /Users/alice/x.wav',
        request: SentryRequest(
          url: 'file:///Users/alice/a.wav',
          queryString: 'file=%2FUsers%2Falice%2Fb.wav',
          cookies: 'session=secret; last=/home/alice/c.txt',
          headers: {
            'X-File': r'C:\Users\alice\d.wav',
            'Authorization': 'Bearer secret',
            'proxy-authorization': 'Basic secret',
            'Cookie': 'session=secret',
            'Set-Cookie': 'session=secret',
          },
        ),
      );

      final out = CrashReporter.beforeSend(event, Hint())!;

      expect(out.culprit, 'open <file>.wav');
      final request = out.request!;
      expect(request.url, 'file:<file>.wav');
      expect(request.queryString, 'file=<file>.wav');
      expect(request.cookies, isNull);
      expect(request.headers, {'X-File': '<file>.wav'});
      final json = request.toJson().toString();
      expect(json, isNot(contains('alice')));
      expect(json, isNot(contains('secret')));
    });
  });

  group('CrashReporter.beforeBreadcrumb scrubs user paths', () {
    test('message and nested data (maps and lists) carry no account name', () {
      final crumb = Breadcrumb(
        message: r'loaded C:\Users\Alice\AppData\x.bin',
        data: {
          'paths': [r'C:\Users\Alice\a.wav', '/home/alice/b.wav'],
          'nested': {'file': '/Users/alice/c.db', 'count': 2},
        },
      );

      final out = CrashReporter.beforeBreadcrumb(crumb, Hint());

      expect(out, isNotNull);
      final serialized = '${out!.message} ${out.data}';
      expect(serialized.toLowerCase(), isNot(contains('alice')));
      final nested = out.data!['nested']! as Map<String, dynamic>;
      expect(nested['count'], 2, reason: 'non-string leaves are kept');
    });

    test('a percent-encoded Windows file URL is scrubbed as well', () {
      final crumb = Breadcrumb(
        message: 'open file:///C%3A%5CUsers%5CAlice%5Cx.wav',
      );

      final out = CrashReporter.beforeBreadcrumb(crumb, Hint());

      expect(out!.message!.toLowerCase(), isNot(contains('alice')));
    });

    test('a native log line from the ring carries no account name', () {
      // Shape of a line drained from the native log ring (drainNativeLog),
      // logged through AppLogger and turned into a breadcrumb.
      final crumb = Breadcrumb(
        message:
            r'WhisperFfiEngine: ggml: model C:\Users\Alice\m.bin, '
            '/Users/alice/Library/Containers/x/y.so',
        category: 'native',
      );

      final out = CrashReporter.beforeBreadcrumb(crumb, Hint());

      expect(out!.message!.toLowerCase(), isNot(contains('alice')));
      expect(out.category, 'native');
    });

    test('a breadcrumb without user paths passes through unchanged', () {
      final crumb = Breadcrumb(message: 'stt: idle', category: 'stt');

      final out = CrashReporter.beforeBreadcrumb(crumb, Hint());

      expect(out!.message, 'stt: idle');
      expect(out.category, 'stt');
    });
  });
}
