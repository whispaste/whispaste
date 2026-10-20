import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/widgets/recording_dock_controls.dart';

WpDockChoiceSet _set({List<String> favorites = const []}) => WpDockChoiceSet(
  id: 'language',
  menuId: 'language',
  overline: 'Language',
  icon: LucideIcons.languages,
  current: 'en',
  currentLabel: 'English',
  onChanged: (_) {},
  searchHint: 'Search',
  noMatchesLabel: 'No matches',
  choices: [
    for (final e in const [
      ('auto', 'Auto'),
      ('de', 'German'),
      ('en', 'English'),
      ('fr', 'French'),
      ('ru', 'Russian'),
      ('es', 'Spanish'),
      ('it', 'Italian'),
      ('pt', 'Portuguese'),
      ('he', 'Hebrew'),
      ('nl', 'Dutch'),
      ('pl', 'Polish'),
    ])
      WpDockChoice(value: e.$1, label: e.$2),
  ],
  favoriteValues: favorites,
  favoritesLabel: 'Favorites',
  allLabel: 'All languages',
);

List<String> _ids(List<WpDockMenuSpec> entries) => [
  for (final e in entries)
    if (e is WpDockMenuAction) e.id,
];

void main() {
  test('without favorites the list is the flat option list', () {
    final entries = dockChoiceEntries(_set(), enabled: true);
    final searchable = entries.single as WpDockMenuSearchable;
    expect(searchable.entries.whereType<WpDockMenuHeader>(), isEmpty);
  });

  test('favorites head the list and appear exactly once', () {
    final entries = dockChoiceEntries(
      _set(favorites: ['ru', 'de']),
      enabled: true,
    );
    final searchable = entries.single as WpDockMenuSearchable;
    final headers = searchable.entries.whereType<WpDockMenuHeader>().toList();
    expect(headers.map((h) => h.text), ['Favorites', 'All languages']);

    final ids = _ids(searchable.entries);
    expect(ids.first, 'dock-menu-language-ru');
    expect(ids[1], 'dock-menu-language-de');
    expect(ids.where((id) => id == 'dock-menu-language-ru'), hasLength(1));
    expect(ids.where((id) => id == 'dock-menu-language-de'), hasLength(1));
    expect(ids, hasLength(11));
  });

  test('a search still finds a favorite, once, in the top block', () {
    final entries = dockChoiceEntries(_set(favorites: ['ru']), enabled: true);
    final searchable = entries.single as WpDockMenuSearchable;
    final filtered = filterDockMenuEntries(searchable.entries, 'russ');
    expect(_ids(filtered), ['dock-menu-language-ru']);
  });
}
