/// Provider tests for the multiline paste preview (WP-38 / 8.5). Nothing is
/// inserted by this provider; it only holds the request and resolves the
/// caller's wait with the user's decision.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/automation_api/multiline_paste_confirmation.dart';

void main() {
  late ProviderContainer container;
  MultilinePasteConfirmation notifier() =>
      container.read(multilinePasteConfirmationProvider.notifier);

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() => container.dispose());

  group('needsMultilinePreview', () {
    test('single-line text needs no preview', () {
      expect(needsMultilinePreview('Hallo Welt'), isFalse);
      expect(needsMultilinePreview(''), isFalse);
    });

    test('a line feed or carriage return needs the preview', () {
      expect(needsMultilinePreview('a\nb'), isTrue);
      expect(needsMultilinePreview('a\r\nb'), isTrue);
      expect(needsMultilinePreview('a\rb'), isTrue);
    });
  });

  test('a request is shown, and confirm resolves it with true', () async {
    final pending = notifier().request('Zeile 1\nZeile 2');
    final shown = container.read(multilinePasteConfirmationProvider);
    expect(shown?.text, 'Zeile 1\nZeile 2');
    expect(shown?.lineCount, 2);

    notifier().confirm();
    expect(await pending, isTrue);
    expect(container.read(multilinePasteConfirmationProvider), isNull);
  });

  test(
    'cancel resolves the request with false and clears the preview',
    () async {
      final pending = notifier().request('a\nb');
      notifier().cancel();
      expect(await pending, isFalse);
      expect(container.read(multilinePasteConfirmationProvider), isNull);
    },
  );

  test('no decision in time resolves with false', () async {
    final pending = notifier().request(
      'a\nb',
      timeout: const Duration(milliseconds: 20),
    );
    expect(await pending, isFalse);
    expect(container.read(multilinePasteConfirmationProvider), isNull);
  });

  test('a second request while one is open is refused, not queued', () async {
    final first = notifier().request('a\nb');
    final second = await notifier().request('c\nd');
    expect(second, isFalse);
    expect(container.read(multilinePasteConfirmationProvider)?.text, 'a\nb');

    notifier().confirm();
    expect(await first, isTrue);
  });

  test('confirm or cancel with nothing pending does nothing', () {
    notifier().confirm();
    notifier().cancel();
    expect(container.read(multilinePasteConfirmationProvider), isNull);
  });
}
