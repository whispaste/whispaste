import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/language_cycle.dart';
import 'package:whispaste/core/config/language_favorites.dart';
import 'package:whispaste/core/config/language_favorites_provider.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';

class _InMemorySettings extends SettingsNotifier {
  _InMemorySettings(this._initial);
  final AppSettings _initial;

  @override
  Future<AppSettings> build() async => _initial;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    state = AsyncData(updater(state.value ?? _initial));
  }
}

Future<ProviderContainer> _container(List<String> favorites) async {
  final c = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(
        () => _InMemorySettings(
          AppSettings(stt: SttSettings(favoriteLanguages: favorites)),
        ),
      ),
    ],
  );
  addTearDown(c.dispose);
  await c.read(settingsProvider.future);
  return c;
}

void main() {
  group('pure logic', () {
    test('limit is five', () => expect(maxFavoriteLanguages, 5));

    test('pin appends, pinned again is a no-op', () {
      final a = pinFavoriteLanguage(const ['de'], 'en');
      expect(a.favorites, ['de', 'en']);
      expect(a.applied, isTrue);
      expect(pinFavoriteLanguage(a.favorites, 'en').favorites, ['de', 'en']);
    });

    test('pin at the limit gives a reason', () {
      final full = ['de', 'en', 'es', 'fr', 'it'];
      final r = pinFavoriteLanguage(full, 'pt');
      expect(r.refusal, LanguageFavoritesRefusal.limitReached);
      expect(r.favorites, full);
    });

    test('auto and empty cannot be pinned', () {
      expect(
        pinFavoriteLanguage(const [], 'auto').refusal,
        LanguageFavoritesRefusal.invalidCode,
      );
      expect(
        pinFavoriteLanguage(const [], ' ').refusal,
        LanguageFavoritesRefusal.invalidCode,
      );
    });

    test('unpin removes, unknown is refused', () {
      expect(unpinFavoriteLanguage(const ['de', 'en'], 'de').favorites, ['en']);
      expect(
        unpinFavoriteLanguage(const ['de'], 'xx').refusal,
        LanguageFavoritesRefusal.invalidCode,
      );
    });

    // The star is the only way to reorder (#1610): off and on again moves a
    // language to the end, everything else keeps its place.
    test('toggling off and on again moves a language to the end', () {
      const f = ['de', 'en', 'ru'];
      final off = toggleFavoriteLanguage(f, 'de');
      expect(off.favorites, ['en', 'ru']);
      expect(toggleFavoriteLanguage(off.favorites, 'de').favorites, [
        'en',
        'ru',
        'de',
      ]);
    });

    test('toggle pins and unpins', () {
      final on = toggleFavoriteLanguage(const [], 'de');
      expect(on.favorites, ['de']);
      expect(toggleFavoriteLanguage(on.favorites, 'de').favorites, isEmpty);
    });
  });

  group('migration of stored data', () {
    test('existing three favorites keep their order', () {
      expect(parseFavoriteLanguageList('ru,de,en'), ['ru', 'de', 'en']);
      expect(
        SttSettings.fromMap(const {
          'stt_favorite_languages': 'ru,de,en',
        }).favoriteLanguages,
        ['ru', 'de', 'en'],
      );
    });

    test('duplicates, blanks and auto dropped, cut at the limit', () {
      expect(parseFavoriteLanguageList(' de,,de,auto,en,es,fr,it,pt'), [
        'de',
        'en',
        'es',
        'fr',
        'it',
      ]);
    });
  });

  group('shared controller', () {
    test('pin/unpin write to settings and every reader sees it', () async {
      final c = await _container(const ['de']);
      final n = c.read(languageFavoritesProvider.notifier);
      await n.pin('en');
      await n.pin('ru');
      expect(c.read(languageFavoritesProvider), ['de', 'en', 'ru']);
      expect(c.read(settingsProvider).value!.stt.favoriteLanguages, [
        'de',
        'en',
        'ru',
      ]);
      await n.unpin('de');
      expect(c.read(languageFavoritesProvider), ['en', 'ru']);
    });

    test('the dialog\'s star list is stored in its order (#1610)', () async {
      final c = await _container(const ['de', 'en']);
      // What the language dialog reports after a star: the full list.
      await c.read(languageFavoritesProvider.notifier).replaceAll(const [
        'de',
        'en',
        'ru',
      ]);
      expect(c.read(settingsProvider).value!.stt.favoriteLanguages, [
        'de',
        'en',
        'ru',
      ]);
    });

    test(
      'a change in settings shows in the controller (other direction)',
      () async {
        final c = await _container(const ['de']);
        c.listen(languageFavoritesProvider, (_, _) {});
        await c
            .read(settingsProvider.notifier)
            .updateSettings(
              (s) => s.copyWithSections(
                stt: s.stt.copyWith(favoriteLanguages: ['fr', 'de']),
              ),
            );
        expect(c.read(languageFavoritesProvider), ['fr', 'de']);
      },
    );

    test('limit reason is returned and nothing is stored', () async {
      final c = await _container(const ['de', 'en', 'es', 'fr', 'it']);
      final r = await c.read(languageFavoritesProvider.notifier).pin('pt');
      expect(r.refusal, LanguageFavoritesRefusal.limitReached);
      expect(c.read(languageFavoritesProvider), hasLength(5));
    });

    test('next favorite follows the new order', () async {
      final c = await _container(const ['de', 'en', 'ru']);
      final n = c.read(languageFavoritesProvider.notifier);
      // Star off and on again: German moves to the end.
      await n.unpin('de');
      await n.pin('de');
      final favs = c.read(languageFavoritesProvider);
      expect(favs, ['en', 'ru', 'de']);
      expect(nextFavoriteLanguage(current: 'ru', favorites: favs), 'de');
      expect(nextFavoriteLanguage(current: 'de', favorites: favs), 'en');
    });
  });
}
