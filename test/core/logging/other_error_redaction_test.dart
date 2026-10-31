import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/logging/crash_error_redaction.dart';

/// Other exception types that carry user content in their toString():
/// FormatException renders its source text, ArgumentError renders the
/// offending value, and FileSystemException renders the full local path,
/// which includes the account name.
const _secret = 'Mein Geheimtext vom Diktat';

void main() {
  test('a FormatException loses its source text', () {
    const error = FormatException(
      'Unexpected token',
      '{"text": "$_secret"}',
      3,
    );

    final text = redactForCrashReport(error).toString();

    expect(text, isNot(contains(_secret)));
    expect(text, contains('Unexpected token'));
  });

  test('an ArgumentError loses the invalid value', () {
    final error = ArgumentError.value(_secret, 'replacement', 'too long');

    final text = redactForCrashReport(error).toString();

    expect(text, isNot(contains(_secret)));
    expect(text, contains('too long'));
  });

  test('a RangeError stays a RangeError and keeps an int value', () {
    final error = RangeError.value(90210, 'index', 'out of range');

    final redacted = redactForCrashReport(error);

    expect(redacted, isA<RangeError>());
    final text = redacted.toString();
    expect(text, contains('90210'));
    expect(text, contains('out of range'));
  });

  test('a RangeError with a non-int value replaces the value', () {
    final error = RangeError.value(2.5, 'replacement', 'out of range');

    final text = redactForCrashReport(error).toString();

    expect(text, isNot(contains('2.5')));
    expect(text, contains('<redacted>'));
    expect(text, contains('out of range'));
  });

  test('a FileSystemException with an odd extension keeps only <ext>', () {
    const error = FileSystemException(
      'Cannot open file',
      '/home/max/Max.Mustermann',
    );

    final text = redactForCrashReport(error).toString();

    expect(text, isNot(contains('Mustermann')));
    expect(text, contains('<ext>'));
  });

  test('a path-like token in an exception message is shortened', () {
    final error = StateError('missing /home/max/private/Diktat.db here');

    final text = redactForCrashReport(error).toString();

    expect(text, isNot(contains('/home/max')));
    expect(text, contains('<file>.db'));
  });

  group('file names in free text', () {
    test('a macOS path keeps only the extension', () {
      expect(
        shortenFileNamesInText('open /Users/max/Music/Diktat.wav failed'),
        'open <file>.wav failed',
      );
    });

    test('a Windows path keeps only the extension', () {
      expect(
        shortenFileNamesInText(r'open C:\Users\max\AppData\model.bin failed'),
        r'open <file>.bin failed',
      );
    });

    test('a Linux path keeps only the extension', () {
      expect(
        shortenFileNamesInText('open /home/max/.config/app/notes.txt failed'),
        'open <file>.txt failed',
      );
    });

    test('a token whose extension is not plain becomes <path>', () {
      expect(
        shortenFileNamesInText('read /x/Max.Mustermann now'),
        'read <path>',
      );
    });

    test('a path without an extension becomes <path>', () {
      expect(
        shortenFileNamesInText('Projekt in /Users/max/Dokumente/Projekt'),
        'Projekt in <path>',
      );
    });

    test('paths with spaces keep no name part', () {
      expect(
        shortenFileNamesInText('/Users/Max Mustermann/a.txt'),
        '<file>.txt',
      );
      expect(
        shortenFileNamesInText('open /Users/max/Documents/Max Mustermann.wav'),
        'open <file>.wav',
      );
      expect(
        shortenFileNamesInText(r'open C:\Users\Max Mustermann\Brief.docx ok'),
        'open <file>.docx ok',
      );
    });

    test('a short extension inside a name does not end the path', () {
      expect(
        shortenFileNamesInText(
          'saved /Users/max/Aufnahmen/Interview 2026.05 Anna.wav ok',
        ),
        'saved <file>.wav ok',
      );
      expect(
        shortenFileNamesInText('/Users/max/Max Mustermann Notiz.final.wav'),
        '<file>.wav',
      );
    });

    test('a ~user path loses the user and the file name', () {
      final text = shortenFileNamesInText('read ~anna/Docs/rede.wav now');
      expect(text, 'read <file>.wav now');
      expect(text, isNot(contains('anna')));
    });

    test('a sentence-ending dot does not extend the path', () {
      expect(
        shortenFileNamesInText('open /tmp/a.wav failed.'),
        'open <file>.wav failed.',
      );
    });

    test('a UNC path is replaced completely', () {
      final text = shortenFileNamesInText(r'open \\nas\Max Mustermann\x.wav');
      expect(text, 'open <file>.wav');
      expect(text, isNot(contains('nas')));
      expect(text, isNot(contains('Mustermann')));
    });

    test('the probes lose the account name and the file names', () {
      const probes = [
        '/Users/max/Library/Application Support/WhisPaste/db.sqlite',
        '/Users/max/Documents/Max Mustermann.wav',
        r'C:\Users\max\AppData\Local\WhisPaste',
      ];
      for (final probe in probes) {
        final text = redactPathsInText(probe);
        expect(text, isNot(contains('max')), reason: probe);
        expect(text, isNot(contains('Mustermann')), reason: probe);
      }
      expect(redactPathsInText(probes[0]), '<file>.sqlite');
      expect(redactPathsInText(probes[1]), '<file>.wav');
      expect(redactPathsInText(probes[2]), '<path>');
    });

    test('a 512-character path is still shortened, 513 becomes <long>', () {
      final at512 = '/${'a' * 507}.wav';
      final at513 = '/${'a' * 508}.wav';
      expect(at512.length, 512);
      expect(shortenFileNamesInText(at512), '<file>.wav');
      expect(shortenFileNamesInText(at513), '<long>');
    });

    test('a path that starts inside a word is cut back to the word', () {
      expect(
        shortenFileNamesInText('Max Mustermann/Bericht.wav'),
        'Max <file>.wav',
      );
      expect(
        shortenFileNamesInText('Fehler: Max/Mustermann/Bericht.wav'),
        'Fehler: <file>.wav',
      );
    });

    test('word-led slashes without a known extension stay', () {
      const text = 'and/or 1/2 package:whispaste/app.dart';
      expect(shortenFileNamesInText(text), text);
    });

    test('quotes, brackets, commas and apostrophes do not end a path', () {
      expect(
        shortenFileNamesInText("open '/Users/max/x.wav' now"),
        "open '<file>.wav' now",
      );
      expect(
        shortenFileNamesInText('(/Users/max/Notes (old)/a.wav)'),
        '(<file>.wav)',
      );
      expect(shortenFileNamesInText("/Users/max/O'Brien/x.wav"), '<file>.wav');
      expect(shortenFileNamesInText('/Users/max/a, b/x.wav'), '<file>.wav');
      expect(shortenFileNamesInText('/Users/max/<dir>/x.wav'), '<file>.wav');
    });

    test('web URLs stay, file URLs are redacted', () {
      const url = 'GET https://api.example.com/v1/models/ggml-small.bin failed';
      expect(shortenFileNamesInText(url), url);
      expect(
        shortenFileNamesInText('open file:///Users/max/x.wav'),
        'open file:<file>.wav',
      );
    });

    test('redactPathsInMap redacts nested string leaves', () {
      final out = redactPathsInMap({
        'model': '/Users/max/m.bin',
        'nested': {
          'files': ['/home/max/a.wav', 3],
        },
        'count': 2,
      });
      expect(out['model'], '<file>.bin');
      expect(out['nested'], {
        'files': ['<file>.wav', 3],
      });
      expect(out['count'], 2);
    });

    test(
      'a 20,000-character token without spaces is handled in linear time',
      () {
        final text = '/${'a/' * 10000}';
        final watch = Stopwatch()..start();
        final result = shortenFileNamesInText(text);
        watch.stop();

        expect(result, '<long>');
        // ignore: avoid_print
        print(
          'shorten 20,000-char path token: ${watch.elapsedMilliseconds} ms',
        );
        expect(watch.elapsedMilliseconds, lessThan(500));
      },
    );

    test('percent-encoded separators do not hide a path', () {
      final out = redactPathsInText('Users%2Fanna%2FBericht.wav');
      expect(out, '<file>.wav');
      expect(out, isNot(contains('anna')));
      expect(
        redactPathsInText('q=%2Fhome%2Fanna%2Fnotes'),
        isNot(contains('anna')),
      );
      expect(redactPathsInText('50%2F100 done'), '50%2F100 done');
    });

    test('repeated encoding does not hide a path either', () {
      for (final text in [
        'Users%252Fanna%252FBericht.wav',
        'Users%25252Fanna%25252FBericht.wav',
        'Users%2525252Fanna%2525252FBericht.wav',
      ]) {
        final out = redactPathsInText(text);
        expect(out, '<file>.wav', reason: text);
        expect(out, isNot(contains('anna')), reason: text);
      }
      expect(redactPathsInText('50%252F100 done'), '50%252F100 done');
      expect(redactPathsInText('100%25 done'), '100%25 done');
    });

    test('text without a path is unchanged', () {
      const text = 'no file here, only a fraction 3/4 and a.b';
      expect(shortenFileNamesInText(text), text);
    });
  });

  test('a RangeError message with a path is redacted too', () {
    final error = RangeError.value(
      5,
      'index',
      'from /Users/max/Max Mustermann.txt',
    );

    final text = redactForCrashReport(error).toString();

    expect(text, isNot(contains('Mustermann')));
    expect(text, isNot(contains('max')));
    expect(text, contains('<file>.txt'));
    expect(text, contains('5'));
  });

  test('a FileSystemException keeps only the extension, not the file name', () {
    const error = FileSystemException(
      'Cannot open file',
      '/home/someone/private/ggml-small.bin.tmp',
    );

    final text = redactForCrashReport(error).toString();

    expect(text, isNot(contains('/home/someone')));
    expect(text, isNot(contains('ggml-small')));
    expect(text, contains('.tmp'));
  });

  test('other errors are returned unchanged', () {
    final error = StateError('plain');

    expect(identical(redactForCrashReport(error), error), isTrue);
  });
}
