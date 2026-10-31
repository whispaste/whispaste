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
      expect(out.breadcrumbs!.single.data!['count'], 3);
    });
  });
}
