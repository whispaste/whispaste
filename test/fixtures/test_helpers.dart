import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/notes/data/notes_actions.dart';
import 'package:whispaste/services/hardware_info_service.dart';
import 'package:whispaste/services/system_user_name.dart';
import 'package:whispaste/services/desktop_paste/focused_target/linux_focused_target.dart'
    show linuxFocusEnvProvider;
import 'package:whispaste/widgets/wp_notice_bar.dart' show WpNoticeBar;

/// Finds a labelled `WpTextField` by its semantics label.
///
/// Since #1500 the field announces its label followed by its placeholder in
/// one merged node (`"Find in this text\n<hint>"`), so an exact
/// `find.bySemanticsLabel(label)` no longer matches. Match the label as the
/// start of the node's text instead.
Finder findByFieldLabel(String label) =>
    find.bySemanticsLabel(RegExp('^${RegExp.escape(label)}'));

/// A fresh in-memory [HistoryDatabase] for widget tests and generators.
///
/// Streams close with their last listener: drift's default waits one
/// event-loop turn, which a widget test reports as a pending timer once the
/// tree is gone ("A Timer is still pending", #1988).
HistoryDatabase openInMemoryTestDatabase() => HistoryDatabase.forTesting(
  DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
);

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
  // Pages that report through the notice bar (undo, hints without a fixed
  // place) pass true; the app places the bar below the page content.
  bool noticeBar = false,
}) {
  final resolvedTheme = theme ?? wpDarkTheme();

  return ProviderScope(
    overrides: [
      historyDatabaseProvider.overrideWith((ref) {
        final resolved = db ?? openInMemoryTestDatabase();
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
      // The margin marks of a quick note (#803) are a live Drift stream too.
      noteAppendsProvider.overrideWith(
        (ref, noteId) => Stream.value(const <NoteAppend>[]),
      ),
      ...overrides,
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: resolvedTheme,
      locale: locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: size, disableAnimations: disableAnimations),
        child: Scaffold(
          body: noticeBar
              ? Column(
                  children: [
                    Expanded(child: child),
                    const WpNoticeBar(),
                  ],
                )
              : child,
        ),
      ),
    ),
  );
}

/// The app's primary shortcut modifier: Cmd on macOS, Ctrl elsewhere.
/// Reads the same seam as the app bindings (`defaultTargetPlatform`, #198),
/// so a test pinned via `TargetPlatformVariant` presses the matching key.
LogicalKeyboardKey get primaryShortcutModifier =>
    defaultTargetPlatform == TargetPlatform.macOS
    ? LogicalKeyboardKey.meta
    : LogicalKeyboardKey.control;

/// Triggers the note-editor head action `notes-editor-<action>` wherever the
/// head's width budget put it: the row button, or the overflow menu entry
/// `notes-editor-menu-<action>` once it collapsed there (#1498).
Future<void> tapNoteHeadAction(WidgetTester tester, String action) async {
  final inRow = find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.identifier == 'notes-editor-$action',
  );
  if (inRow.evaluate().isNotEmpty) {
    await tester.tap(inRow.first);
  } else {
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.identifier == 'notes-editor-more',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('notes-editor-menu-$action')));
  }
  await tester.pumpAndSettle();
}

/// Answers the hotkey plugin's channels with nothing, or removes the answer
/// again when [on] is false. A journey that reaches a session key (Escape to
/// cancel, the notice action key) would otherwise fail on the plugin's
/// missing event stream: no global hotkey exists in the test host.
void mockHotkeyPluginChannels({required bool on}) {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final name in const [
    'dev.leanflutter.plugins/hotkey_manager',
    'dev.leanflutter.plugins/hotkey_manager_event',
  ]) {
    messenger.setMockMethodCallHandler(
      MethodChannel(name),
      on ? (call) async => null : null,
    );
  }
}
