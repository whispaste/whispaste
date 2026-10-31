import 'package:drift/native.dart';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/notes/data/notes_actions.dart';
import 'package:whispaste/services/hardware_info_service.dart';
import 'package:whispaste/services/system_user_name.dart';
import 'package:whispaste/services/desktop_paste/focused_target/linux_focused_target.dart'
    show linuxFocusEnvProvider;
import 'package:whispaste/widgets/toast.dart' show WpToastPopupObserver;

/// Wraps a widget in [ProviderScope] + [MaterialApp] for testing.
///
/// Uses the real WhisPaste theme builder so tests exercise the actual
/// theme data the production app uses.
Widget makeTestable(
  Widget child, {
  Size size = const Size(1280, 800),
  List overrides = const [],
  Locale? locale,
  // Defaults to the dark theme; goldens of light surfaces pass wpLightTheme().
  ThemeData? theme,
  // Pre-built/pre-seeded database to serve `historyDatabaseProvider` with,
  // instead of a fresh empty one — lets a test seed rows (e.g. via a
  // service's own write methods) before the widget tree ever reads them.
  // `overrides` cannot carry a second `historyDatabaseProvider` override of
  // its own: Riverpod rejects overriding the same provider twice in one
  // `ProviderScope`.
  HistoryDatabase? db,
  // Tests of the note image strip pass true to keep the real
  // noteAssetsProvider query instead of the empty default stream below.
  bool liveNoteAssets = false,
  // The GPU row states pass a graphics card here: `overrides` cannot carry a
  // second `gpuInfoProvider` override either.
  GpuInfo? gpuInfo,
  // Looping motion (the onboarding start scene) never settles; logic tests of
  // such screens pass true, as the app does under reduced motion.
  bool disableAnimations = false,
}) {
  final resolvedTheme = theme ?? wpDarkTheme();

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
        (ref) async =>
            gpuInfo ?? const GpuInfo(vendor: GpuVendor.none, name: 'Test'),
      ),
      // The about page reads the signed-in user's name in an isolate with a
      // 1 s timeout, which outlives a test that leaves the page early.
      systemFirstNameProvider.overrideWith((ref) async => null),
      // Without an override the Linux focus probe asks the real session bus
      // (on a GNOME test host) and leaves a 500 ms timer behind.
      linuxFocusEnvProvider.overrideWithValue(const <String, String>{}),
      // The note editor watches its image list. Without an override that is a
      // live Drift stream, whose teardown leaves a pending timer behind.
      // Tests of the image strip itself override this with their own store.
      if (!liveNoteAssets)
        noteAssetsProvider.overrideWith(
          (ref, noteId) => Stream.value(const <NoteAsset>[]),
        ),
      ...overrides,
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: resolvedTheme,
      locale: locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      navigatorObservers: [WpToastPopupObserver()],
      home: MediaQuery(
        data: MediaQueryData(size: size, disableAnimations: disableAnimations),
        child: Scaffold(body: child),
      ),
    ),
  );
}

/// The app's primary shortcut modifier: Cmd on macOS, Ctrl elsewhere.
/// Mirrors the `control: !Platform.isMacOS, meta: Platform.isMacOS` bindings.
LogicalKeyboardKey get primaryShortcutModifier =>
    Platform.isMacOS ? LogicalKeyboardKey.meta : LogicalKeyboardKey.control;
