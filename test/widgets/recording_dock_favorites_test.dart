import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/widgets/recording_dock.dart';
import 'package:whispaste/widgets/recording_dock_controls.dart';

import '../fixtures/test_helpers.dart';

WpDockChoiceSet _set({
  List<String> favorites = const [],
  String current = 'en',
  ValueChanged<String>? onToggle,
  List<(String, String)> extra = const [],
}) => WpDockChoiceSet(
  id: 'language',
  menuId: 'language',
  overline: 'Language',
  icon: LucideIcons.languages,
  current: current,
  currentLabel: current,
  onChanged: (_) {},
  searchHint: 'Search',
  noMatchesLabel: 'No matches',
  choices: [
    for (final e in [
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
      ...extra,
    ])
      WpDockChoice(value: e.$1, label: e.$2),
  ],
  favoriteValues: favorites,
  favoritesLabel: 'Favorites',
  allLabel: 'All languages',
  leadingValues: const ['auto'],
  pinning: WpDockChoicePinning(
    onToggle: onToggle ?? (_) {},
    pinLabel: 'Pin',
    unpinLabel: 'Unpin',
    max: 5,
    limitLabel: 'Up to 5 favorites.',
  ),
);

List<WpDockMenuSpec> _rows(WpDockChoiceSet set) =>
    (dockChoiceEntries(set, enabled: true).single as WpDockMenuSearchable)
        .entries;

WpDockMenuPin? _pin(List<WpDockMenuSpec> rows, String value) => rows
    .whereType<WpDockMenuAction>()
    .firstWhere((r) => r.id == 'dock-menu-language-$value')
    .pin;

/// The dock with the language dropdown, pinning through [favorites] the way
/// the settings provider does in the app.
class _Host extends StatefulWidget {
  const _Host({required this.favorites, this.current = 'en', this.extra});

  final List<String> favorites;
  final String current;
  final List<(String, String)>? extra;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late List<String> _favorites = widget.favorites;

  @override
  Widget build(BuildContext context) => WpRecordingDock(
    sttModeLabel: 'Whisper · small',
    language: _set(
      favorites: _favorites,
      current: widget.current,
      extra: widget.extra ?? const [],
      onToggle: (code) => setState(
        () => _favorites = _favorites.contains(code)
            ? [..._favorites.where((c) => c != code)]
            : [..._favorites, code],
      ),
    ),
    microphoneLabel: 'Built-in',
    microphoneOptions: const ['Built-in'],
    onMicrophoneChanged: (_) {},
    afterActionLabel: 'Copy',
    afterAction: null,
  );
}

Future<void> _pumpHost(WidgetTester tester, _Host host) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(1224, 800);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    makeTestable(
      Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(width: 1224, child: host),
      ),
      size: const Size(1224, 800),
      locale: const Locale('en'),
    ),
  );
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('dock-language')));
  await tester.pumpAndSettle();
}

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
    expect(ids.take(3), [
      'dock-menu-language-auto',
      'dock-menu-language-ru',
      'dock-menu-language-de',
    ]);
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

  test('every language but auto-detect carries a pin', () {
    final rows = _rows(_set(favorites: ['ru']));
    expect(_pin(rows, 'auto'), isNull);
    expect(_pin(rows, 'de')!.id, 'dock-menu-language-de-pin');
    expect(_pin(rows, 'de')!.pinned, isFalse);
    expect(_pin(rows, 'ru')!.pinned, isTrue);
    expect(_pin(rows, 'de')!.onToggle, isNotNull);
  });

  test('at the limit only unpinning is possible and the hint shows', () {
    final full = ['de', 'fr', 'ru', 'es', 'it'];
    final rows = _rows(_set(favorites: full));
    expect(_pin(rows, 'nl')!.onToggle, isNull);
    expect(_pin(rows, 'de')!.onToggle, isNotNull);
    expect(
      rows.whereType<WpDockMenuInfo>().map((i) => i.id),
      contains('dock-menu-language-favorites-limit'),
    );
    expect(
      _rows(
        _set(favorites: full.take(4).toList()),
      ).whereType<WpDockMenuInfo>().map((i) => i.id),
      isNot(contains('dock-menu-language-favorites-limit')),
    );
  });

  testWidgets('pinning and unpinning in the open popup reorders it', (
    tester,
  ) async {
    await _pumpHost(tester, const _Host(favorites: ['ru']));
    // The rows of [values] from top to bottom.
    List<String> order(List<String> values) => [...values]
      ..sort(
        (a, b) => tester
            .getTopLeft(find.byKey(ValueKey('dock-menu-language-$a')))
            .dy
            .compareTo(
              tester
                  .getTopLeft(find.byKey(ValueKey('dock-menu-language-$b')))
                  .dy,
            ),
      );
    const watched = ['auto', 'de', 'en', 'ru', 'pl'];
    final pin = find.byKey(const ValueKey('dock-menu-language-pl-pin'));

    expect(order(watched), ['auto', 'ru', 'de', 'en', 'pl']);
    await tester.tap(pin);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dock-menu-panel')), findsOneWidget);
    expect(order(watched), ['auto', 'ru', 'pl', 'de', 'en']);

    await tester.tap(pin);
    await tester.pumpAndSettle();
    expect(order(watched), ['auto', 'ru', 'de', 'en', 'pl']);
  });

  testWidgets('the keyboard pins a language too', (tester) async {
    await _pumpHost(tester, const _Host(favorites: []));
    final pin = find.byKey(const ValueKey('dock-menu-language-pl-pin'));
    tester
        .widget<Focus>(find.descendant(of: pin, matching: find.byType(Focus)))
        .focusNode!
        .requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dock-menu-panel')), findsOneWidget);
    expect(find.text('Favorites'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('dock-menu-language-pl'))).dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const ValueKey('dock-menu-language-de')))
            .dy,
      ),
    );
  });

  testWidgets('the active language is in view when the popup opens', (
    tester,
  ) async {
    await _pumpHost(
      tester,
      _Host(
        favorites: const [],
        current: 'zz39',
        extra: [for (var i = 0; i < 40; i++) ('zz$i', 'Zlang $i')],
      ),
    );
    final panel = tester.getRect(find.byKey(const ValueKey('dock-menu-panel')));
    final row = tester.getRect(
      find.byKey(const ValueKey('dock-menu-language-zz39')),
    );
    expect(panel.top, lessThanOrEqualTo(row.top));
    expect(panel.bottom, greaterThanOrEqualTo(row.bottom));
  });
}
