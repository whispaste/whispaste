// Guard (security review R-10): no log call in lib/ may carry dictated text.
//
// The app promises that logs, and the log lines attached to error reports,
// never contain transcribed text. Log calls may report sizes
// (`transcript.length`), never the value. This scan flags every logging
// call (AppLogger methods, debugPrint, dev.log, print) whose arguments
// reference a transcript-like name — transcript*, *Transcript, text, *Text,
// dictation — other than through a size or emptiness accessor. A real
// exception goes into [_allowlist] with a reason.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// file -> name -> why it is not dictated text.
const _allowlist = <String, Map<String, String>>{
  'lib/core/logging/perf_instrumentation.dart': {
    'hotkeyText':
        'The hotkey label ("Ctrl+Shift+Space"), not dictated text; it names '
        'the shortcut a slow hotkey→text measurement belongs to.',
  },
  'lib/services/stt/whisper/whisper_ffi_engine.dart': {
    'text':
        'drainNativeLog forwards ggml/whisper log-callback lines (model, '
        'backend, errors). Segment text is never in them: whisper.cpp prints '
        'it only under print_realtime (printf, not the log callback), and both '
        'whisper_full call sites set print_realtime to false. Reasoning in the '
        'comment at drainNativeLog.',
  },
};

final _sensitive = RegExp(
  r'^(transcripts?|transcription|\w*Transcript|text|\w*[a-z]Text|'
  r'dictation|\w*Dictation)$',
);
const _safeAccessors = {
  'length',
  'isEmpty',
  'isNotEmpty',
  'runtimeType',
  'hashCode',
};
final _logCall = RegExp(
  r'\b(?:_?log(?:ger)?|_?[a-z]\w*Log)\.(?:debug|info|warning|error|fatal)\('
  r'|\bdebugPrint\(|\bdev\.log\(|\bprint\(',
);
final _fullLineComment = RegExp(r'^\s*//.*$', multiLine: true);
final _interpolation = RegExp(r'\$\{([^}]*)\}|\$([A-Za-z_]\w*)');
final _stringLiteral = RegExp(
  r"'(?:\\.|[^'\\])*'|"
  r'"(?:\\.|[^"\\])*"',
);
final _chain = RegExp(r'[A-Za-z_]\w*(?:\??\.[A-Za-z_]\w*)*');
final _chainDot = RegExp(r'\??\.');

/// Transcript-like names that the log calls in [source] pass on by value.
List<({int line, String name})> transcriptLeaks(String source) {
  final src = source.replaceAll(_fullLineComment, '');
  final leaks = <({int line, String name})>[];
  for (final call in _logCall.allMatches(src)) {
    var i = call.end;
    var depth = 1;
    while (i < src.length && depth > 0) {
      final c = src[i++];
      if (c == '(') depth++;
      if (c == ')') depth--;
    }
    final args = src.substring(call.end, i - 1);
    final expressions = [
      for (final m in _interpolation.allMatches(args)) m.group(1) ?? m[2]!,
      args.replaceAll(_stringLiteral, ' '),
    ];
    final line = '\n'.allMatches(src.substring(0, call.start)).length + 1;
    for (final expression in expressions) {
      for (final chain in _chain.allMatches(expression)) {
        final parts = chain[0]!.split(_chainDot);
        for (var k = 0; k < parts.length; k++) {
          if (!_sensitive.hasMatch(parts[k])) continue;
          final next = k + 1 < parts.length ? parts[k + 1] : null;
          if (!_safeAccessors.contains(next)) {
            leaks.add((line: line, name: parts[k]));
          }
          break;
        }
      }
    }
  }
  return leaks;
}

void main() {
  group('the detector', () {
    test('flags transcript values in interpolations and plain arguments', () {
      expect(
        transcriptLeaks('''
          _log.info('pasted: \$transcript');
          _log.warning('result \${result.text} done');
          debugPrint(finalText);
          _log.error(
            'multi-line \${job.rawTranscript}',
            e,
          );
          dev.log('x' + dictation);
        ''').map((l) => l.name),
        ['transcript', 'text', 'finalText', 'rawTranscript', 'dictation'],
      );
    });

    test('lets sizes, emptiness and unrelated names pass', () {
      expect(
        transcriptLeaks('''
          _log.info('pasted \${transcript.length} chars');
          _log.debug('empty: \${result.text.isEmpty}');
          _log.info('model \$modelName, \$durationMs ms');
          // _log.info('commented out: \$transcript');
          other.info('not a logger \$transcript');
        '''),
        isEmpty,
      );
    });
  });

  test('no log call in lib/ passes dictated text on', () {
    final problems = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (f) =>
              f.path.endsWith('.dart') &&
              !f.path.endsWith('.g.dart') &&
              !f.path.contains('${Platform.pathSeparator}generated'),
        );
    for (final file in files) {
      final path = file.path.replaceAll(r'\', '/');
      final allowed = _allowlist[path] ?? const {};
      for (final leak in transcriptLeaks(file.readAsStringSync())) {
        if (allowed.containsKey(leak.name)) continue;
        problems.add('$path:${leak.line} logs `${leak.name}`');
      }
    }
    expect(
      problems,
      isEmpty,
      reason:
          'Log the size (.length) instead of the text, or add an allowlist '
          'entry with a reason if the name is not dictated text.',
    );
  });

  test('allowlist entries have reasons', () {
    for (final entry in _allowlist.entries) {
      expect(File(entry.key).existsSync(), isTrue, reason: entry.key);
      for (final reason in entry.value.values) {
        expect(reason.trim(), isNotEmpty);
      }
    }
  });
}
