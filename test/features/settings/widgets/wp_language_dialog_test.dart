import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/language_favorites.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/features/settings/widgets/wp_language_dialog.dart';
import 'package:whispaste/widgets/wp_favourite_star.dart';

import '../../../fixtures/test_helpers.dart';

const _options = <WpLanguageOption>[
  WpLanguageOption(code: 'en', name: 'English', endonym: 'English'),
  WpLanguageOption(code: 'de', name: 'German', endonym: 'Deutsch'),
  WpLanguageOption(code: 'fr', name: 'French', endonym: 'Français'),
  WpLanguageOption(
    code: 'pt',
    name: 'Portuguese',
    endonym: 'Português (Brasil)',
  ),
  WpLanguageOption(code: 'ru', name: 'Russian', endonym: 'Русский'),
];

Finder _tile(String code) =>
    find.byKey(ValueKey('stt-language-dialog-tile-$code'));

Finder _search() => find.descendant(
  of: find.byKey(const ValueKey('stt-language-dialog-search')),
  matching: find.byType(EditableText),
);

Widget _dialog({
  WpLanguageSelection initial = const WpLanguageSelection(
    autoDetect: false,
    codes: ['de'],
  ),
  required void Function(WpLanguageSelection) onSave,
  VoidCallback? onCancel,
}) => WpLanguageDialog(
  options: _options,
  initial: initial,
  onSave: onSave,
  onCancel: onCancel ?? () {},
);

void main() {
  setUp(() => WpColors.activate(wpLightColors));
  tearDown(() => WpColors.activate(wpLightColors));

  testWidgets(
    'expected languages toggle independently and allow clearing all',
    (tester) async {
      WpLanguageSelection? saved;
      await tester.pumpWidget(
        makeTestable(
          WpLanguageDialog(
            multiple: true,
            options: _options,
            initial: const WpLanguageSelection(autoDetect: false),
            onSave: (s) => saved = s,
            onCancel: () {},
          ),
        ),
      );
      await tester.tap(_tile('de'));
      await tester.tap(_tile('en'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('stt-language-dialog-save')));
      expect(saved!.codes, ['de', 'en']);
      await tester.tap(_tile('de'));
      await tester.tap(_tile('en'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('stt-language-dialog-save')));
      expect(saved!.codes, isEmpty);
    },
  );

  testWidgets('shows one tile per language with name and endonym', (
    tester,
  ) async {
    await tester.pumpWidget(makeTestable(_dialog(onSave: (_) {})));

    for (final o in _options) {
      expect(_tile(o.code), findsOneWidget);
    }
    expect(
      find.descendant(of: _tile('de'), matching: find.text('German')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _tile('de'), matching: find.text('Deutsch')),
      findsOneWidget,
    );
    expect(find.text('Languages'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('stt-language-dialog-auto')),
      findsOneWidget,
    );
  });

  test('second line hides a repeated name and a bare code', () {
    const cases = {
      WpLanguageOption(code: 'de', name: 'German', endonym: 'Deutsch'):
          'Deutsch',
      WpLanguageOption(code: 'de', name: 'Deutsch', endonym: 'Deutsch'): null,
      WpLanguageOption(code: 'en', name: 'English', endonym: 'english'): null,
      WpLanguageOption(code: 'ga', name: 'Irish', endonym: 'ga'): null,
      WpLanguageOption(code: 'xx', name: 'xx', endonym: ''): null,
    };
    for (final MapEntry(key: option, value: expected) in cases.entries) {
      expect(option.secondLine, expected, reason: option.code);
    }
  });

  testWidgets('search matches the localized name and the endonym', (
    tester,
  ) async {
    await tester.pumpWidget(makeTestable(_dialog(onSave: (_) {})));

    await tester.enterText(_search(), 'german');
    await tester.pump();
    expect(_tile('de'), findsOneWidget);
    expect(_tile('fr'), findsNothing);

    await tester.enterText(_search(), 'Deutsch');
    await tester.pump();
    expect(_tile('de'), findsOneWidget);
    expect(_tile('en'), findsNothing);
  });

  testWidgets('search ignores accents and case', (tester) async {
    await tester.pumpWidget(makeTestable(_dialog(onSave: (_) {})));

    await tester.enterText(_search(), 'FRANCAIS');
    await tester.pump();
    expect(_tile('fr'), findsOneWidget);

    await tester.enterText(_search(), 'portugues');
    await tester.pump();
    expect(_tile('pt'), findsOneWidget);
  });

  testWidgets('a search without matches shows the empty state', (tester) async {
    await tester.pumpWidget(makeTestable(_dialog(onSave: (_) {})));

    await tester.enterText(_search(), 'zzzz');
    await tester.pump();
    expect(_tile('de'), findsNothing);
    expect(find.text('No language found'), findsOneWidget);
  });

  testWidgets(
    'tapping a tile selects it, shows it in the panel and turns auto off',
    (tester) async {
      await tester.pumpWidget(
        makeTestable(
          _dialog(
            initial: const WpLanguageSelection(autoDetect: true),
            onSave: (_) {},
          ),
        ),
      );

      await tester.tap(_tile('fr'));
      await tester.pump();

      final panel = find.byKey(const ValueKey('stt-language-dialog-selected'));
      expect(
        find.descendant(of: panel, matching: find.text('French')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Switch>(
              find.byKey(const ValueKey('stt-language-dialog-auto')),
            )
            .value,
        isFalse,
      );
    },
  );

  testWidgets('the selected tile is exposed as selected in semantics', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(makeTestable(_dialog(onSave: (_) {})));

    expect(
      tester.getSemantics(_tile('de')).flagsCollection.isSelected,
      ui.Tristate.isTrue,
    );
    expect(
      tester.getSemantics(_tile('en')).flagsCollection.isSelected,
      ui.Tristate.isFalse,
    );
    handle.dispose();
  });

  testWidgets('auto on dims the grid but tiles stay tappable', (tester) async {
    await tester.pumpWidget(
      makeTestable(
        _dialog(
          initial: const WpLanguageSelection(autoDetect: true),
          onSave: (_) {},
        ),
      ),
    );

    final grid = tester.widget<Opacity>(
      find.byKey(const ValueKey('stt-language-dialog-grid')),
    );
    expect(grid.opacity, lessThan(1));

    await tester.tap(_tile('ru'));
    await tester.pump();
    expect(
      tester
          .widget<Switch>(
            find.byKey(const ValueKey('stt-language-dialog-auto')),
          )
          .value,
      isFalse,
    );
  });

  testWidgets('save writes the chosen language and closes with it', (
    tester,
  ) async {
    WpLanguageSelection? saved;
    await tester.pumpWidget(makeTestable(_dialog(onSave: (s) => saved = s)));

    await tester.tap(_tile('fr'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('stt-language-dialog-save')));
    await tester.pump();

    expect(saved, isNotNull);
    expect(saved!.autoDetect, isFalse);
    expect(saved!.codes, ['fr']);
    expect(saved!.sttCode, 'fr');
  });

  testWidgets('save with auto on writes auto', (tester) async {
    WpLanguageSelection? saved;
    await tester.pumpWidget(
      makeTestable(
        _dialog(
          initial: const WpLanguageSelection(autoDetect: true),
          onSave: (s) => saved = s,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('stt-language-dialog-save')));
    await tester.pump();
    expect(saved!.sttCode, 'auto');
  });

  testWidgets('save stays inert while auto is off and no language is chosen', (
    tester,
  ) async {
    WpLanguageSelection? saved;
    await tester.pumpWidget(
      makeTestable(
        _dialog(
          initial: const WpLanguageSelection(autoDetect: true),
          onSave: (s) => saved = s,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('stt-language-dialog-auto')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('stt-language-dialog-save')));
    await tester.pump();
    expect(saved, isNull);
  });

  testWidgets('cancel button and Escape both cancel without saving', (
    tester,
  ) async {
    var saves = 0;
    var cancels = 0;
    await tester.pumpWidget(
      makeTestable(_dialog(onSave: (_) => saves++, onCancel: () => cancels++)),
    );

    await tester.tap(_tile('fr'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('stt-language-dialog-cancel')));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(cancels, 2);
    expect(saves, 0);
  });

  testWidgets('keyboard: typing filters once the search field has focus', (
    tester,
  ) async {
    await tester.pumpWidget(makeTestable(_dialog(onSave: (_) {})));

    await tester.tap(_search());
    await tester.pump();
    await tester.enterText(_search(), 'ru');
    await tester.pump();
    expect(_tile('ru'), findsOneWidget);
    expect(_tile('en'), findsNothing);
  });

  testWidgets('the row shows the current choice and opens the dialog', (
    tester,
  ) async {
    WpLanguageSelection? changed;
    await tester.pumpWidget(
      makeTestable(
        Builder(
          builder: (context) => WpLanguageRow(
            title: 'Recognition language',
            value: const WpLanguageSelection(autoDetect: false, codes: ['de']),
            options: _options,
            onChanged: (s) => changed = s,
          ),
        ),
      ),
    );

    expect(find.text('German'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('stt-language-row-change')));
    await tester.pumpAndSettle();

    await tester.tap(_tile('ru'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('stt-language-dialog-save')));
    await tester.pumpAndSettle();

    expect(changed?.codes, ['ru']);
  });

  testWidgets('the row shows Auto-detect when auto is on', (tester) async {
    await tester.pumpWidget(
      makeTestable(
        WpLanguageRow(
          title: 'Recognition language',
          value: const WpLanguageSelection(autoDetect: true),
          options: _options,
          onChanged: (_) {},
        ),
      ),
    );
    expect(find.text('Auto-detect'), findsOneWidget);
  });

  // Favorites by star in the dialog (#1610): the only place to set them, a
  // group of their own on top, in the stored order.

  Widget favDialog({
    List<String> favorites = const [],
    required void Function(List<String>) onFavoritesChanged,
  }) => WpLanguageDialog(
    options: _options,
    initial: const WpLanguageSelection(autoDetect: false, codes: ['de']),
    onSave: (_) {},
    onCancel: () {},
    favorites: favorites,
    onFavoritesChanged: onFavoritesChanged,
  );

  WpFavouriteStar star(WidgetTester tester, String key) =>
      tester.widget<WpFavouriteStar>(find.byKey(ValueKey(key)));

  /// Codes of the favorites group, in the order the group shows them.
  List<String> group(WidgetTester tester) => [
    for (final w in tester.widgetList<Semantics>(
      find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith(
              'stt-language-dialog-favorites-tile-',
            ),
      ),
    ))
      (w.key! as ValueKey<String>).value.split('-').last,
  ];

  testWidgets('a star toggles a favorite and reports it at once', (
    tester,
  ) async {
    List<String>? reported;
    await tester.pumpWidget(
      makeTestable(favDialog(onFavoritesChanged: (f) => reported = f)),
    );
    expect(star(tester, 'stt-language-dialog-fav-ru').isFavourite, isFalse);
    expect(group(tester), isEmpty);

    await tester.tap(find.byKey(const ValueKey('stt-language-dialog-fav-ru')));
    await tester.pump();
    expect(reported, ['ru']);
    // Filled at once, and listed in the favorites group on top.
    expect(star(tester, 'stt-language-dialog-fav-ru').isFavourite, isTrue);
    expect(group(tester), ['ru']);

    await tester.tap(find.byKey(const ValueKey('stt-language-dialog-fav-ru')));
    await tester.pump();
    expect(reported, isEmpty);
    expect(group(tester), isEmpty);
  });

  testWidgets('the star carries a name with the language and a toggle state', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      makeTestable(favDialog(favorites: ['fr'], onFavoritesChanged: (_) {})),
    );
    final on = tester.getSemantics(
      find.byKey(const ValueKey('stt-language-dialog-fav-fr')),
    );
    expect(on.label, contains('French'));
    expect(on.flagsCollection.isToggled, ui.Tristate.isTrue);
    final off = tester.getSemantics(
      find.byKey(const ValueKey('stt-language-dialog-fav-ru')),
    );
    expect(off.flagsCollection.isToggled, ui.Tristate.isFalse);
    handle.dispose();
  });

  testWidgets('the group keeps the stored order and new favorites go last', (
    tester,
  ) async {
    List<String>? reported;
    await tester.pumpWidget(
      makeTestable(
        favDialog(
          favorites: ['ru', 'en', 'fr'],
          onFavoritesChanged: (f) => reported = f,
        ),
      ),
    );
    // Not alphabetical: the order the user starred them in.
    expect(group(tester), ['ru', 'en', 'fr']);

    await tester.tap(find.byKey(const ValueKey('stt-language-dialog-fav-de')));
    await tester.pump();
    expect(reported, ['ru', 'en', 'fr', 'de']);
    expect(group(tester), ['ru', 'en', 'fr', 'de']);

    // The star in the group removes it too; the others keep their places.
    await tester.tap(
      find.byKey(const ValueKey('stt-language-dialog-favorites-fav-en')),
    );
    await tester.pump();
    expect(reported, ['ru', 'fr', 'de']);
    expect(group(tester), ['ru', 'fr', 'de']);
  });

  testWidgets('a favorite tile picks the language like its grid tile', (
    tester,
  ) async {
    WpLanguageSelection? saved;
    await tester.pumpWidget(
      makeTestable(
        WpLanguageDialog(
          options: _options,
          initial: const WpLanguageSelection(autoDetect: true),
          onSave: (s) => saved = s,
          onCancel: () {},
          favorites: const ['fr'],
          onFavoritesChanged: (_) {},
        ),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('stt-language-dialog-favorites-tile-fr')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('stt-language-dialog-save')));
    await tester.pump();
    expect(saved?.sttCode, 'fr');
  });

  testWidgets('searching hides the favorites group, the stars stay', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(favDialog(favorites: ['fr'], onFavoritesChanged: (_) {})),
    );
    expect(
      find.byKey(const ValueKey('stt-language-dialog-favorites-heading')),
      findsOneWidget,
    );
    await tester.enterText(_search(), 'fren');
    await tester.pump();
    expect(
      find.byKey(const ValueKey('stt-language-dialog-favorites-heading')),
      findsNothing,
    );
    expect(group(tester), isEmpty);
    expect(star(tester, 'stt-language-dialog-fav-fr').isFavourite, isTrue);
  });

  testWidgets('without the favorites callback there are no stars or group', (
    tester,
  ) async {
    await tester.pumpWidget(makeTestable(_dialog(onSave: (_) {})));
    expect(find.byType(WpFavouriteStar), findsNothing);
    expect(
      find.byKey(const ValueKey('stt-language-dialog-favorites-heading')),
      findsNothing,
    );
  });

  testWidgets('one favorite past the limit is blocked until one is removed', (
    tester,
  ) async {
    List<String>? reported;
    await tester.pumpWidget(
      makeTestable(
        favDialog(
          // Exactly at the limit, without 'ru'.
          favorites: const [
            'en',
            'de',
            'fr',
            'pt',
            'it',
            'ja',
          ].take(maxFavoriteLanguages).toList(),
          onFavoritesChanged: (f) => reported = f,
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('stt-language-dialog-favorites-limit')),
      findsOneWidget,
    );
    expect(star(tester, 'stt-language-dialog-fav-ru').onToggle, isNull);
    await tester.tap(find.byKey(const ValueKey('stt-language-dialog-fav-ru')));
    await tester.pump();
    expect(reported, isNull);

    await tester.tap(find.byKey(const ValueKey('stt-language-dialog-fav-en')));
    await tester.pump();
    expect(reported, ['de', 'fr', 'pt', 'it']);
    expect(star(tester, 'stt-language-dialog-fav-ru').onToggle, isNotNull);
  });
}
