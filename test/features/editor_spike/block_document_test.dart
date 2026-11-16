import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/notes/blocks/block_document.dart';

import 'package:whispaste/features/editor_spike/spike_corpus.dart';

void main() {
  void expectRoundTrip(String source) {
    expect(BlockDocument.parse(source).toMarkdown(), source);
  }

  group('round trip', () {
    test('headings, paragraphs and blank lines', () {
      expectRoundTrip(
        '# Titel\n\nErster Absatz\nzweite Zeile.\n\n\n## Zwei\nText',
      );
    });

    test('leading blank lines and trailing newline', () {
      expectRoundTrip('\n\n  \nAbsatz\n');
      expectRoundTrip('Absatz ohne Zeilenende');
      expectRoundTrip('');
      expectRoundTrip('\n');
    });

    test('lists with continuation lines', () {
      expectRoundTrip('- eins\n- zwei\n  weiter\n1. drei\n2) vier\n\nEnde\n');
    });

    test('code fences keep blank lines and markers inside', () {
      expectRoundTrip(
        'Vorher\n```dart\n# no heading\n\n- no list\n```\nNachher\n'
        '~~~\nopen fence until end',
      );
    });

    test('CRLF line endings', () {
      expectRoundTrip('# Titel\r\n\r\nAbsatz\r\nZeile\r\n\r\n- Punkt\r\n');
    });

    test('20k-word single paragraph', () {
      expectRoundTrip(singleParagraph(20000));
    });
  });

  group('block structure', () {
    test('headings and list items are their own blocks', () {
      final doc = BlockDocument.parse('# A\nText\n- x\n- y\n### B\n');
      expect(doc.blocks.map((b) => b.kind).toList(), [
        BlockKind.heading,
        BlockKind.paragraph,
        BlockKind.listItem,
        BlockKind.listItem,
        BlockKind.heading,
      ]);
      expect(doc.blocks.first.headingLevel, 1);
      expect(doc.blocks.last.headingLevel, 3);
    });

    test('a code fence is one block', () {
      final doc = BlockDocument.parse('```\na\n\nb\n```\n');
      expect(doc.blocks, hasLength(1));
      expect(doc.blocks.single.kind, BlockKind.codeFence);
    });
  });

  group('editing', () {
    test('editing one block changes only that block', () {
      final doc = BlockDocument.parse('# Titel\n\nAlt\n\nRest\n');
      doc.updateBlock(1, 'Neu und länger');
      expect(doc.toMarkdown(), '# Titel\n\nNeu und länger\n\nRest\n');
    });

    test('a blank line typed into a block splits it', () {
      final doc = BlockDocument.parse('Eins\n\nEnde\n');
      final count = doc.updateBlock(0, 'Eins\n\n## Zwei');
      expect(count, 2);
      expect(doc.blocks[1].kind, BlockKind.heading);
      expect(doc.toMarkdown(), 'Eins\n\n## Zwei\n\nEnde\n');
    });

    test('typing a heading marker turns a paragraph into a heading', () {
      final doc = BlockDocument.parse('Text\n');
      doc.updateBlock(0, '## Text');
      expect(doc.blocks.single.kind, BlockKind.heading);
      expect(doc.toMarkdown(), '## Text\n');
    });

    test('clearing a block keeps the document text exact', () {
      final doc = BlockDocument.parse('A\n\nB\n\nC\n');
      doc.updateBlock(1, '');
      expect(doc.toMarkdown(), 'A\n\n\n\nC\n');
    });

    test('merge with previous drops the separator between them', () {
      final doc = BlockDocument.parse('Erster.\n\nZweiter.\n');
      final caret = doc.mergeWithPrevious(1);
      expect(caret, 'Erster.'.length);
      expect(doc.toMarkdown(), 'Erster.Zweiter.\n');
      expect(doc.mergeWithPrevious(0), -1);
    });
  });

  group('soft split', () {
    test('short content is one segment', () {
      expect(BlockDocument.segmentBounds('kurz'), [0, 4]);
    });

    test('long content splits at sentence ends within the limit', () {
      final text = singleParagraph(20000).trimRight();
      final bounds = BlockDocument.segmentBounds(text);
      expect(bounds.first, 0);
      expect(bounds.last, text.length);
      for (var k = 1; k < bounds.length; k++) {
        expect(bounds[k] - bounds[k - 1], lessThanOrEqualTo(2000));
        if (k < bounds.length - 1) {
          expect('.!?'.contains(text[bounds[k] - 2]), isTrue);
        }
      }
      // Segments concatenate back to the content.
      final joined = StringBuffer();
      for (var k = 1; k < bounds.length; k++) {
        joined.write(text.substring(bounds[k - 1], bounds[k]));
      }
      expect(joined.toString(), text);
    });

    test('text without spaces is cut hard at the limit', () {
      final bounds = BlockDocument.segmentBounds('x' * 4500);
      expect(bounds, [0, 2000, 4000, 4500]);
    });

    test('soft split never changes toMarkdown', () {
      final source = singleParagraph(20000);
      final doc = BlockDocument.parse(source);
      BlockDocument.segmentBounds(doc.blocks.single.content);
      expect(doc.toMarkdown(), source);
    });
  });

  group('plain-text migration and export', () {
    const samples = [
      'Einkauf: Milch, Brot\nMorgen anrufen\n\nNeuer Absatz',
      '# keine Überschrift\n- kein Punkt\n1. keine Nummer\n> kein Zitat',
      'Stern * und _unter_strich_ und `code` und [klammer](x) <tag>',
      'snake_case_name und a\\b und Ende\\',
      '```\nkein Code\n```\n~~~',
      '   # eingerückt\r\nCRLF-Zeile\r\n\r\nNach Leerzeile\r\n',
      '---\n===\n+ plus\n2) zwei',
      '',
      '\n\nnur Leerzeilen davor\n\n',
    ];

    test('escaped plain text renders back to exactly the original', () {
      for (final plain in [...samples, germanProse(2000)]) {
        final md = BlockDocument.escapePlainText(plain);
        final doc = BlockDocument.parse(md);
        expect(doc.toMarkdown(), md, reason: 'round trip of $plain');
        expect(doc.toPlainText(), plain, reason: plain);
      }
    });

    test('escaped plain text forms no structure', () {
      final doc = BlockDocument.parse(
        BlockDocument.escapePlainText(samples[1]),
      );
      expect(doc.blocks.map((b) => b.kind).toSet(), {BlockKind.paragraph});
    });

    test('plain-text export drops Markdown syntax only', () {
      final doc = BlockDocument.parse(
        '## Kopf\n\nEin **fetter** und `code` Text.\n\n- Punkt\n\n'
        '```dart\nvar a_b = 1;\n```\n',
      );
      expect(
        doc.toPlainText(),
        'Kopf\n\nEin fetter und code Text.\n\n- Punkt\n\nvar a_b = 1;\n',
      );
    });
  });
}
