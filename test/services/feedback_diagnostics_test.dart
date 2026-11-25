/// The opt-in diagnostics attachment of a feedback message (#2187): which log
/// lines may leave the device and in what form, and the 64 KiB bound the API
/// accepts.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/feedback_diagnostics.dart';
import 'package:whispaste_diagnostics/whispaste_diagnostics.dart';

void main() {
  group('sanitizeFeedbackLogLine', () {
    test('drops lines with tokens and keys', () {
      // Token shapes are assembled at run time so no secret scanner mistakes
      // the fixtures for real credentials.
      final filler = 'Ab1' * 8;
      for (final line in [
        'Upload failed: token=$filler',
        'Authorization: Bearer abcdefghijkl',
        'OpenAI key ${'sk'}-proj$filler rejected',
        'HF download with ${'hf'}_$filler failed',
        'Session ${'eyJ'}hbGciOiJIUzI1NiJ9.${'eyJ'}zdWIiOiIxMjM0NTY3ODkwIn0.sig',
        'GitHub ${'gh'}p_$filler refused',
        '{"client_secret": "s3cr3t-value"}',
        'GET https://api.example.test/v1/x?key=$filler&lang=de',
        'password: hunter2',
      ]) {
        expect(sanitizeFeedbackLogLine(line), isNull, reason: line);
      }
    });

    test('replaces e-mail addresses', () {
      final out = sanitizeFeedbackLogLine(
        'Newsletter bound to max.mustermann+wp@example.co.uk (ok)',
      )!;
      expect(out, isNot(contains('mustermann')));
      expect(out, contains('<email>'));
      expect(out, contains('(ok)'));
    });

    test('replaces paths with account names on every system', () {
      for (final line in const [
        'Model missing: /Users/erika/Library/Application Support/x/ggml.bin',
        r'Model missing: C:\Users\Erika Muster\AppData\Roaming\x\ggml.bin',
        'Model missing: /home/erika/.local/share/whispaste/ggml.bin',
      ]) {
        final out = sanitizeFeedbackLogLine(line)!;
        expect(out, isNot(contains('erika')), reason: line);
        expect(out, isNot(contains('Erika')), reason: line);
        expect(out, startsWith('Model missing: '), reason: line);
      }
    });

    test('replaces dictated and copied text in fields and quotes', () {
      for (final (line, secret) in const [
        ('Smart mode input {"text": "Liebe Grüße an Oma"}', 'Oma'),
        ("polish failed: transcript='Treffen um neun bei Anna'", 'Anna'),
        ('Clipboard restore: clipboard=Kontonummer 1234 5678', '1234'),
        ('LLM said: "Hier ist dein überarbeiteter Brief an Anna"', 'Anna'),
        ('Paste of „Mein Passwort lautet Sommer“ failed', 'Sommer'),
      ]) {
        final out = sanitizeFeedbackLogLine(line)!;
        expect(out, isNot(contains(secret)), reason: line);
        expect(out, contains('<text>'), reason: line);
      }
    });

    test('keeps technical lines readable', () {
      const lines = [
        '2026-11-24 10:00:01 INFO Recorder: Phase recording → done',
        '2026-11-24 10:00:02 INFO Orchestrator: Pasted transcript (42 chars)',
        'WARNING Whisper: backend metal unavailable, using cpu',
        'package:whispaste/services/recording_orchestrator.dart:5015',
      ];
      for (final line in lines) {
        expect(sanitizeFeedbackLogLine(line), line);
      }
    });

    test('cuts overlong lines', () {
      final out = sanitizeFeedbackLogLine('x' * 2000)!;
      expect(out.length, lessThan(kFeedbackLogLineMaxChars + 10));
      expect(out, endsWith('<cut>'));
    });
  });

  group('buildFeedbackDiagnosticAttachment', () {
    test('keeps crash logs of previous sessions and drops secrets', () {
      final logs = readFullLog(
        logFilePath: '/logs/app.log',
        fileReader: (path) => switch (path) {
          '/logs/app.log.1' => ['decoder crashed', 'token=secret'],
          '/logs/app.log' => [
            'restarted',
            'saved /Users/erika/Music/Bericht.wav',
          ],
          _ => null,
        },
      );
      final report = buildFeedbackDiagnosticAttachment('App test', logs.lines);
      expect(report, startsWith('App test\n'));
      expect(report, contains('decoder crashed\nrestarted'));
      expect(report, isNot(contains('secret')));
      expect(report, isNot(contains('erika')));
      expect(report, isNot(contains('Bericht')));
      expect(report, contains('<file>.wav'));
    });

    test('raw lines are cleaned even when they skip the log reader', () {
      final report = buildFeedbackDiagnosticAttachment('App test', const [
        'mail from someone@example.org',
        'Bearer abcdefghijklmnop',
      ]);
      expect(report, isNot(contains('someone@')));
      expect(report, isNot(contains('abcdefghijklmnop')));
    });

    test('UTF-8 byte limit keeps the most recent complete lines', () {
      final lines = List.generate(10000, (i) => '$i: Fehler 🎤');
      final report = buildFeedbackDiagnosticAttachment('App test', lines);
      expect(
        utf8.encode(report).length,
        lessThanOrEqualTo(kFeedbackDiagnosticsMaxBytes),
      );
      expect(report, endsWith(lines.last));
      expect(report, isNot(contains('\n0: Fehler')));
    });
  });
}
