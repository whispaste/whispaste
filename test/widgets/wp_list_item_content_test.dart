/// Pure logic of the shared list-item row (#1498): meta segments never leave
/// an empty slot between two separators, a preview is only printed when it
/// adds to the title, and the spoken preview stays short.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/wp_list_item_content.dart';

String _plain(List<InlineSpan> spans) =>
    TextSpan(children: spans).toPlainText();

void main() {
  test('meta segments drop missing facts, no empty slot (#1498)', () {
    final spans = WpListItemMeta.join([
      [const TextSpan(text: '18:08')],
      null,
      [const TextSpan(text: '  ')],
      const [],
      [const TextSpan(text: '0s')],
      [
        const TextSpan(children: [TextSpan(text: '')]),
      ],
      [const TextSpan(text: 'DE')],
      [const WidgetSpan(child: SizedBox.shrink())],
    ]);
    expect(_plain(spans), '18:08 · 0s · DE · ￼');
    expect(WpListItemMeta.join([null, const []]), isEmpty);
  });

  test('previewDiffers ignores case, spacing and trailing punctuation', () {
    expect(
      WpListItemContent.previewDiffers('Hello world', 'hello  world.'),
      isFalse,
    );
    expect(WpListItemContent.previewDiffers('Hello', ''), isFalse);
    expect(WpListItemContent.previewDiffers('Hello', 'Hello there'), isTrue);
  });

  test('spokenPreview stays silent for a generated title, short otherwise', () {
    final long = List.filled(60, 'word').join(' ');
    // A generated title is the opening of the text: nothing new to say.
    expect(WpListItemContent.spokenPreview('Word word word', long), isNull);
    expect(WpListItemContent.spokenPreview('Buy milk', 'buy milk.'), isNull);
    expect(
      WpListItemContent.spokenPreview('Shopping', 'Buy milk  and\neggs'),
      'Buy milk and eggs',
    );
    final spoken = WpListItemContent.spokenPreview('Shopping', long)!;
    expect(
      spoken.length,
      lessThanOrEqualTo(WpListItemContent.spokenPreviewLimit + 1),
    );
    expect(spoken, endsWith('…'));
  });
}
