import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:whispaste/services/snippets/interactive_snippet_composer.dart';
import 'package:whispaste/services/snippets/system_variables.dart';

void main() {
  final now = DateTime(2026, 11, 10, 14, 5);

  setUpAll(() => initializeDateFormatting());

  SystemVariablesResult run(String t, {String clipboard = ''}) =>
      resolveSystemVariables(
        t,
        now: now,
        locale: 'de_DE',
        clipboard: clipboard,
        title: 'Gruß',
      );

  test('template plus fixed clock gives fixed text', () {
    expect(
      run(
        r'{$title} am {$date:yyyy-MM-dd} um {$time:HH:mm}: {$clipboard}',
        clipboard: 'X',
      ).text,
      'Gruß am 2026-11-10 um 14:05: X',
    );
  });

  test('default date and time follow the locale', () {
    expect(run(r'{$date}').text, '10.11.2026');
    expect(run(r'{$time}').text, contains('14:05'));
  });

  test('unknown variable and bad format stay verbatim and are reported', () {
    const t = r'a {$nope} b {$date:{x} c {$date:QQQQQQ}';
    expect(run(t).text, contains(r'{$nope}'));
    expect(unknownSystemVariables(r'{$nope} {$date} {$time:HH:mm}'), [
      r'{$nope}',
    ]);
  });

  test('clipboard content is never expanded again; empty is empty', () {
    expect(run(r'[{$clipboard}]', clipboard: r'{$date}').text, r'[{$date}]');
    expect(run(r'[{$clipboard}]').text, '[]');
  });

  test('cursor mark is removed and its position reported', () {
    final r = run(r'Hallo {$cursor}Welt');
    expect(r.text, 'Hallo Welt');
    expect(r.cursorFromEnd, 4);
    expect(run('ohne').cursorFromEnd, isNull);
  });

  test('does not touch interactive {{field}} placeholders', () {
    final resolved = run(r'{{name}} {$date:yyyy}').text;
    expect(resolved, '{{name}} 2026');
    expect(
      composeInteractiveSnippetText(
        template: resolved,
        fieldNames: ['name'],
        fieldTranscripts: ['Anna'],
      ),
      'Anna 2026',
    );
  });
}
