/// The single list of favorite recognition languages.
///
/// Settings, the dock quick pick, the tray, the floating button menu and the
/// "next favorite language" hotkey all read the list from
/// `settings.stt.favoriteLanguages` and change it only through the functions
/// here (or the notifier in `language_favorites_provider.dart`, which wraps
/// them), so the order and the limit are the same everywhere.
library;

/// Most favorites a user can keep.
///
/// Five: the tray, dock and floating-button menus stay one short block, and
/// the cycle hotkey reaches every favorite in at most four presses. The old
/// limit was three; stored lists stay valid because the new one is larger.
const int maxFavoriteLanguages = 5;

/// Why a favorites change was not applied.
enum LanguageFavoritesRefusal {
  /// The list already holds [maxFavoriteLanguages] languages.
  limitReached,

  /// The code is empty, `auto` (no fixed language) or not in the list when
  /// unpinning.
  invalidCode,
}

/// Result of a favorites change: the list to store plus, when nothing changed
/// because of a rule, the [refusal] the UI can show as a hint.
class LanguageFavoritesChange {
  const LanguageFavoritesChange(this.favorites, [this.refusal]);

  /// The resulting list (the unchanged input when [refusal] is set).
  final List<String> favorites;
  final LanguageFavoritesRefusal? refusal;

  bool get applied => refusal == null;
}

bool _pinnable(String code) => code.trim().isNotEmpty && code != 'auto';

/// Normalizes a stored list: trimmed, de-duplicated, order kept, no `auto`
/// or empty entries, cut at [maxFavoriteLanguages]. Existing users keep their
/// favorites in the same order.
List<String> normalizeFavoriteLanguages(Iterable<String> raw) {
  final codes = <String>[];
  for (final part in raw) {
    final code = part.trim();
    if (!_pinnable(code) || codes.contains(code)) continue;
    codes.add(code);
    if (codes.length == maxFavoriteLanguages) break;
  }
  return List.unmodifiable(codes);
}

/// Parses the persisted comma-separated list.
List<String> parseFavoriteLanguageList(String raw) =>
    normalizeFavoriteLanguages(raw.split(','));

/// Pins [code] at the end of [favorites]. Already pinned: no change, applied.
LanguageFavoritesChange pinFavoriteLanguage(
  List<String> favorites,
  String code,
) {
  final c = code.trim();
  if (!_pinnable(c)) {
    return LanguageFavoritesChange(
      favorites,
      LanguageFavoritesRefusal.invalidCode,
    );
  }
  if (favorites.contains(c)) return LanguageFavoritesChange(favorites);
  if (favorites.length >= maxFavoriteLanguages) {
    return LanguageFavoritesChange(
      favorites,
      LanguageFavoritesRefusal.limitReached,
    );
  }
  return LanguageFavoritesChange(List.unmodifiable([...favorites, c]));
}

/// Unpins [code]. Not pinned: refused as [LanguageFavoritesRefusal.invalidCode].
LanguageFavoritesChange unpinFavoriteLanguage(
  List<String> favorites,
  String code,
) {
  if (!favorites.contains(code)) {
    return LanguageFavoritesChange(
      favorites,
      LanguageFavoritesRefusal.invalidCode,
    );
  }
  return LanguageFavoritesChange(
    List.unmodifiable(favorites.where((e) => e != code)),
  );
}

/// Pins [code] when it is not a favorite, unpins it otherwise (the star).
LanguageFavoritesChange toggleFavoriteLanguage(
  List<String> favorites,
  String code,
) => favorites.contains(code)
    ? unpinFavoriteLanguage(favorites, code)
    : pinFavoriteLanguage(favorites, code);
