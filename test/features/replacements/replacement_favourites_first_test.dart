import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';

void main() {
  Replacement entry(String id, {bool fav = false}) => Replacement(
    id: id,
    triggers: [id],
    replacement: id,
    createdAt: DateTime(2026),
    isFavorite: fav,
  );

  test('starred entries come first and keep the chosen order (#892)', () {
    final sorted = replacementFavouritesFirst([
      entry('a'),
      entry('b', fav: true),
      entry('c'),
      entry('d', fav: true),
    ]);
    expect(sorted.map((r) => r.id), ['b', 'd', 'a', 'c']);
  });
}
