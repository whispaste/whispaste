import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'generated/app_localizations.dart';

/// The operating system's language preference list, in order.
///
/// Read once by the settings on a first start, when no `locale` has been
/// stored yet. Tests override it instead of touching the platform.
final systemLocalesProvider = Provider<List<Locale>>(
  (ref) => PlatformDispatcher.instance.locales,
);

/// Language code for a first start: the first system language that WhisPaste
/// ships a translation for, otherwise English.
String initialLocaleCode(Iterable<Locale> systemLocales) {
  final supported = L10n.supportedLocales.map((l) => l.languageCode).toSet();
  for (final locale in systemLocales) {
    if (supported.contains(locale.languageCode)) return locale.languageCode;
  }
  return 'en';
}
