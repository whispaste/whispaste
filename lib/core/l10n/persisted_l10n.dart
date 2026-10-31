import 'package:flutter/widgets.dart';

import 'generated/app_localizations.dart';
import 'persisted_locale.dart';

/// Locale codes WhisPaste ships translations for.
///
/// Derived from [L10n.supportedLocales] rather than duplicated as a literal
/// set: a hardcoded copy silently drifted out of sync when 'ru' was added
/// (floating render engines kept falling back to English for it) even
/// though every other locale-aware picker already reads the generated list.
final _supported = L10n.supportedLocales.map((l) => l.languageCode).toSet();

/// Resolves [L10n] from the persisted locale without a [Localizations]
/// ancestor.
///
/// The floating render engines run in their own Flutter engines with no
/// `MaterialApp`/`Localizations` above them, so `L10n.of(context)` is
/// unavailable. They read the `locale` mirror the main engine keeps next to
/// the database and look the strings up directly.
///
/// This deliberately does NOT read `app_settings` from SQLite any more: doing
/// so made every lazily booted engine open and close its own SQLite
/// connection, which is what turned a replaced-on-disk `sqlite3.framework`
/// into a hard `SIGSEGV` inside `sqlite3Close`. [writeLocaleMirror] carries
/// the full analysis.
///
/// Falls back to English when nothing is mirrored yet (only reachable before
/// the main engine has loaded settings once) or the mirrored code is not a
/// supported locale.
Future<L10n> resolvePersistedL10n() async {
  const fallback = 'en';
  final stored = readLocaleMirror();
  final code = stored != null && _supported.contains(stored)
      ? stored
      : fallback;
  return lookupL10n(Locale(code));
}
