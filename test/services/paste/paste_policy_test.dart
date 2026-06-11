import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/services/paste/paste_policy.dart';

void main() {
  group('resolveAfterTranscriptionAction', () {
    group('when auto-paste is supported (Developer-ID / Windows / Linux)', () {
      for (final action in AfterTranscriptionAction.values) {
        test('keeps $action unchanged', () {
          expect(
            resolveAfterTranscriptionAction(action, autoPasteSupported: true),
            action,
          );
        });
      }
    });

    group('when auto-paste is unavailable (Mac App Store build)', () {
      test('downgrades paste to clipboard', () {
        expect(
          resolveAfterTranscriptionAction(
            AfterTranscriptionAction.paste,
            autoPasteSupported: false,
          ),
          AfterTranscriptionAction.clipboard,
        );
      });

      test('downgrades clipboardAndPaste to clipboard', () {
        expect(
          resolveAfterTranscriptionAction(
            AfterTranscriptionAction.clipboardAndPaste,
            autoPasteSupported: false,
          ),
          AfterTranscriptionAction.clipboard,
        );
      });

      test('leaves clipboard untouched', () {
        expect(
          resolveAfterTranscriptionAction(
            AfterTranscriptionAction.clipboard,
            autoPasteSupported: false,
          ),
          AfterTranscriptionAction.clipboard,
        );
      });

      test('leaves nothing untouched', () {
        expect(
          resolveAfterTranscriptionAction(
            AfterTranscriptionAction.nothing,
            autoPasteSupported: false,
          ),
          AfterTranscriptionAction.nothing,
        );
      });
    });
  });
}
