import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/text/markdown_plain_text.dart';

void main() {
  group('markdownToPlainText (#644)', () {
    test('removes the markers of a formatted snippet', () {
      const input =
          '## Greeting\n'
          '\n'
          'Hello **Anna**, thanks for _your_ message.\n'
          '> Quoted ~~old~~ line with ==highlight==\n'
          '- first `item`\n'
          '1. [Website](https://example.com)\n'
          '- [ ] open task\n'
          'See <https://example.com/a> and ![logo](logo.png).';
      const expected =
          'Greeting\n'
          '\n'
          'Hello Anna, thanks for your message.\n'
          'Quoted old line with highlight\n'
          '- first item\n'
          '1. Website (https://example.com)\n'
          '☐ open task\n'
          'See https://example.com/a and logo.';
      expect(markdownToPlainText(input), expected);
    });

    test('leaves text without Markdown unchanged', () {
      const input =
          'Price: 5 * 3 = 15, file snake_case_name.dart, a_b, '
          'C:\\Users\\me, 2 > 1, #hashtag';
      expect(markdownToPlainText(input), input);
    });

    test('resolves nested markers and escapes', () {
      expect(
        markdownToPlainText('**_both_** and \\*literal\\*'),
        'both and *literal*',
      );
      expect(markdownToPlainText('*__mixed__*'), 'mixed');
    });

    test('keeps code verbatim and drops the fence lines', () {
      const input = 'Run:\n```bash\necho **not bold**\n```\nDone';
      expect(markdownToPlainText(input), 'Run:\necho **not bold**\nDone');
      expect(markdownToPlainText('Use `**x**` here'), 'Use **x** here');
    });

    test('keeps Windows line endings and a closing heading hash', () {
      expect(markdownToPlainText('# Title #\r\n**a**\r\n'), 'Title\r\na\r\n');
    });

    test('a link whose label is its url shows the url once', () {
      expect(
        markdownToPlainText('[https://example.com](https://example.com)'),
        'https://example.com',
      );
    });
  });
}
