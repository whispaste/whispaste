/// Source of optional context a profile may read (WP-33a). Kept in its own
/// library so the consent model and the profile model do not import each other.
library;

/// The optional context a profile may read at recording start. [none] is the
/// default; nothing is read unless a profile explicitly asks for it.
enum AppProfileContextSource {
  none('none'),
  selection('selection'),
  clipboard('clipboard');

  const AppProfileContextSource(this.storageValue);

  /// Value persisted in `app_profiles.context_source`.
  final String storageValue;

  static final Map<String, AppProfileContextSource> _byStorageValue = {
    for (final value in values) value.storageValue: value,
  };

  /// Parses a stored value. Unknown or missing values fall back to [none].
  static AppProfileContextSource fromStorage(String? value) =>
      _byStorageValue[value] ?? none;
}
