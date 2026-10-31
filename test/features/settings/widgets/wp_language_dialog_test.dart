import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/features/settings/widgets/wp_language_dialog.dart';
import 'package:whispaste/widgets/wp_icon_button.dart';

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
    expect(find.text('Recognition language'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('stt-language-dialog-auto')),
      findsOneWidget,
    );
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

  testWidgets('a star toggles a favorite and reports it at once', (
    tester,
  ) async {
    List<String>? reported;
    await tester.pumpWidget(
      makeTestable(
        WpLanguageDialog(
          options: _options,
          initial: const WpLanguageSelection(autoDetect: false, codes: ['de']),
          onSave: (_) {},
          onCancel: () {},
          onFavoritesChanged: (f) => reported = f,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('stt-language-dialog-fav-ru')));
    await tester.pump();
    expect(reported, ['ru']);
    await tester.tap(find.byKey(const ValueKey('stt-language-dialog-fav-ru')));
    await tester.pump();
    expect(reported, isEmpty);
  });

  testWidgets('a fourth favorite is blocked until one is removed', (
    tester,
  ) async {
    List<String>? reported;
    await tester.pumpWidget(
      makeTestable(
        WpLanguageDialog(
          options: _options,
          initial: const WpLanguageSelection(autoDetect: false, codes: ['de']),
          favorites: const ['en', 'de', 'fr'],
          onSave: (_) {},
          onCancel: () {},
          onFavoritesChanged: (f) => reported = f,
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('stt-language-dialog-favorites-limit')),
      findsOneWidget,
    );
    final blocked = tester.widget<WpIconButton>(
      find.byKey(const ValueKey('stt-language-dialog-fav-ru')),
    );
    expect(blocked.onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('stt-language-dialog-fav-ru')));
    await tester.pump();
    expect(reported, isNull);
  });
}
