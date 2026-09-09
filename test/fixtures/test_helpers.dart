import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/services/hardware_info_service.dart';

/// Wraps a widget in [ProviderScope] + [MaterialApp] for testing.
///
/// Uses the real WhisPaste theme builder so tests exercise the actual
/// theme data the production app uses.
Widget makeTestable(
  Widget child, {
  Size size = const Size(1280, 800),
  List overrides = const [],
  Locale? locale,
  // Pre-built/pre-seeded database to serve `historyDatabaseProvider` with,
  // instead of a fresh empty one — lets a test seed rows (e.g. via a
  // service's own write methods) before the widget tree ever reads them.
  // `overrides` cannot carry a second `historyDatabaseProvider` override of
  // its own: Riverpod rejects overriding the same provider twice in one
  // `ProviderScope`.
  HistoryDatabase? db,
}) {
  final theme = wpDarkTheme();

  return ProviderScope(
    overrides: [
      historyDatabaseProvider.overrideWith((ref) {
        final resolved =
            db ?? HistoryDatabase.forTesting(NativeDatabase.memory());
        ref.onDispose(resolved.close);
        return resolved;
      }),
      // Prevent real GPU detection (spawns subprocess → pending timers).
      gpuInfoProvider.overrideWith(
        (ref) async => const GpuInfo(vendor: GpuVendor.none, name: 'Test'),
      ),
      ...overrides,
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      locale: locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(body: child),
      ),
    ),
  );
}
