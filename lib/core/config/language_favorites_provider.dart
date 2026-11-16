import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'language_favorites.dart';
import 'settings_provider.dart';

/// The one place that changes the favorite languages. Every reader watches
/// `settingsProvider`, so a change shows up everywhere at once.
class LanguageFavoritesController extends Notifier<List<String>> {
  @override
  List<String> build() => ref.watch(
    settingsProvider.select(
      (s) => (s.value ?? AppSettings.defaults).stt.favoriteLanguages,
    ),
  );

  Future<LanguageFavoritesChange> _apply(
    LanguageFavoritesChange Function(List<String>) change,
  ) async {
    final current = (ref.read(settingsProvider).value ?? AppSettings.defaults)
        .stt
        .favoriteLanguages;
    final result = change(current);
    if (result.applied && result.favorites != current) {
      await ref
          .read(settingsProvider.notifier)
          .updateSettings(
            (s) => s.copyWithSections(
              stt: s.stt.copyWith(favoriteLanguages: result.favorites),
            ),
          );
    }
    return result;
  }

  Future<LanguageFavoritesChange> pin(String code) =>
      _apply((f) => pinFavoriteLanguage(f, code));

  Future<LanguageFavoritesChange> unpin(String code) =>
      _apply((f) => unpinFavoriteLanguage(f, code));

  /// Replaces the whole list (normalized: de-duplicated, limited).
  Future<LanguageFavoritesChange> replaceAll(List<String> codes) =>
      _apply((_) => LanguageFavoritesChange(normalizeFavoriteLanguages(codes)));
}

final languageFavoritesProvider =
    NotifierProvider<LanguageFavoritesController, List<String>>(
      LanguageFavoritesController.new,
    );
