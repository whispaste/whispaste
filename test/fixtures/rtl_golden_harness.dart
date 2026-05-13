/// Harness for RTL golden tests.
///
/// Wraps a widget in a [MaterialApp] configured for the Hebrew locale so that
/// Flutter sets [Directionality.rtl] automatically, matching real-app
/// behaviour without a running [ProviderScope] or window services.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/services/hardware_info_service.dart';

/// Wraps [child] in a [ProviderScope] + [MaterialApp] with locale set to
/// Hebrew so Flutter propagates [TextDirection.rtl] through the widget tree.
///
/// [brightness] controls the theme; [size] the virtual screen dimensions.
/// Additional [overrides] are merged into the [ProviderScope].
Widget wrapForRtlGolden(
  Widget child, {
  Brightness brightness = Brightness.dark,
  Size size = const Size(400, 600),
  List overrides = const [],
}) {
  final theme = brightness == Brightness.dark ? wpDarkTheme() : wpLightTheme();

  return ProviderScope(
    overrides: [
      historyDatabaseProvider.overrideWith((ref) {
        final db = HistoryDatabase.forTesting(NativeDatabase.memory());
        ref.onDispose(db.close);
        return db;
      }),
      gpuInfoProvider.overrideWith(
        (ref) async => const GpuInfo(vendor: GpuVendor.none, name: 'Test'),
      ),
      ...overrides,
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('he'),
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(body: child),
      ),
    ),
  );
}
