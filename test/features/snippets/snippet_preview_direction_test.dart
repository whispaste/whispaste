import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/snippets/snippets_page.dart';

const _fsi = '\u2068';
const _pdi = '\u2069';

void main() {
  group('snippetPreviewForDisplay (UX-036)', () {
    test('isolates a Latin body so a trailing "." stays at its end', () {
      const body = 'Punkt 1.';

      expect(snippetPreviewForDisplay(body), '$_fsi$body$_pdi');
    });

    test('isolates a Hebrew body and keeps its text unchanged inside', () {
      const body = 'שלום, זה נקודה.';

      expect(snippetPreviewForDisplay(body), '$_fsi$body$_pdi');
    });

    test('isolates a Hebrew body with a Latin ending as one unit', () {
      const body = 'שלום, see you.';

      expect(snippetPreviewForDisplay(body), '$_fsi$body$_pdi');
    });

    test('leaves the direction to the isolate, not to a guess', () {
      const body = '1. שלום';

      expect(snippetPreviewForDisplay(body), '$_fsi$body$_pdi');
    });
  });
}
