/// The language the "next favorite language" hotkey switches to.
///
/// Walks [favorites] in their stored order and wraps around. A current
/// language that is not a favorite (for example `auto`) jumps to the first
/// favorite. Returns `null` when there are no favorites to switch to.
String? nextFavoriteLanguage({
  required String current,
  required List<String> favorites,
}) {
  if (favorites.isEmpty) return null;
  final index = favorites.indexOf(current);
  if (index < 0) return favorites.first;
  return favorites[(index + 1) % favorites.length];
}

/// Label of the dictation-language chip for [code]: the uppercase code
/// (`DE`). Returns null when no chip should show: `auto` has no fixed
/// language, and an empty code has nothing to show.
String? languageChipLabelFor(String code) {
  final trimmed = code.trim();
  if (trimmed.isEmpty || trimmed == 'auto') return null;
  return trimmed.toUpperCase();
}
