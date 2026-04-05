import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/theme.dart';

/// Wraps a widget in [ProviderScope] + [MaterialApp] for testing.
///
/// Uses the real WhisPaste theme builders so tests exercise the actual
/// theme data the production app uses.
Widget makeTestable(
  Widget child, {
  Brightness brightness = Brightness.dark,
  Size size = const Size(1280, 800),
}) {
  final theme =
      brightness == Brightness.dark ? wpDarkTheme() : wpLightTheme();

  return ProviderScope(
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(body: child),
      ),
    ),
  );
}
