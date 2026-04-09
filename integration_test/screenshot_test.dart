/// Integration-test screenshot engine for WhisPaste.
///
/// Runs against a real Windows desktop window, capturing the FULL app chrome
/// (sidebar, title bar, status bar, frame gradient, watermark) as transparent
/// PNGs with rounded corners — ready for store listings and website gallery.
///
/// Run:
///   flutter test integration_test/screenshot_test.dart -d windows
///
/// Output structure:
///   screenshots/{locale}/{theme}/01_workspace_overview.png
///   screenshots/{locale}/{theme}/02_workspace_detail.png
///   ...
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OffsetLayer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';

import 'package:whispaste/app.dart'
    show wpNavItems, wpPageTitle;
import 'package:whispaste/core/config/settings_labels.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/analytics_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/core/theme/tokens.dart';
import 'package:whispaste/features/analytics/analytics_page.dart';
import 'package:whispaste/features/history/history_page.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';
import 'package:whispaste/features/settings/settings_page.dart';
import 'package:whispaste/services/audio_service.dart';
import 'package:whispaste/services/hardware_info_service.dart' as hw;
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/stt_service.dart';
import 'package:whispaste/widgets/fab.dart';
import 'package:whispaste/widgets/frame_watermark.dart';
import 'package:whispaste/widgets/recording_indicator_bar.dart';
import 'package:whispaste/widgets/sidebar.dart';
import 'package:whispaste/widgets/sidebar_settings_button.dart';
import 'package:whispaste/widgets/status_bar.dart';
import 'package:whispaste/widgets/title_bar.dart';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

/// Window size for screenshots — Full HD, non-maximized for rounded corners.
const _windowSize = Size(1920, 1080);

/// Corner radius for the app window appearance in screenshots.
const _windowCornerRadius = 12.0;

/// Output directory for captured screenshots.
const _outputDir = 'screenshots';

const _locales = ['en', 'de'];

final _screens = <_ScreenDef>[
  _ScreenDef(
    name: '01_workspace_overview',
    pageId: 'history',
    builder: () => const HistoryPage(),
    needsDemoData: true,
  ),
  _ScreenDef(
    name: '02_workspace_detail',
    pageId: 'history',
    builder: () => const HistoryPage(),
    needsDemoData: true,
    arrange: _openFirstHistoryEntry,
  ),
  _ScreenDef(
    name: '03_voice_shortcuts',
    pageId: 'replacements',
    builder: () => const ReplacementsPage(),
    needsDemoData: true,
    textReplacementsEnabled: true,
  ),
  _ScreenDef(
    name: '04_settings',
    pageId: 'settings',
    builder: () => const SettingsPage(),
    arrange: _scrollToHotkeySection,
  ),
  _ScreenDef(
    name: '05_analytics',
    pageId: 'analytics',
    builder: () => const AnalyticsPage(),
  ),
];

// ---------------------------------------------------------------------------
// Test suite
// ---------------------------------------------------------------------------

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  // Single testWidgets for all locale/theme combos — avoids the framework's
  // inter-test pumpAndSettle which hangs on infinite animations (FAB breathe).
  testWidgets('Store screenshots', (tester) async {
    // Configure window — not maximized, for rounded-corner screenshots
    await tester.runAsync(() async {
      await windowManager.ensureInitialized();
      await windowManager.setSize(_windowSize);
      await windowManager.center();
    });
    await _settle(tester, const Duration(seconds: 2));

    for (final locale in _locales) {
      for (final themeLabel in ['dark', 'light']) {
        final themeMode =
            themeLabel == 'dark' ? ThemeMode.dark : ThemeMode.light;

        // ignore: avoid_print
        print('\n=== $locale / $themeLabel ===');

        // Fresh in-memory database per combo
        final db = await tester.runAsync(() async {
          final d = HistoryDatabase.forTesting(NativeDatabase.memory());
          await _seedDemoData(d, locale: locale);
          return d;
        });

        for (final screen in _screens) {
          // ignore: avoid_print
          print('  Rendering: ${screen.name}');

          final settings = AppSettings.defaults.copyWith(
            locale: locale,
            themeMode: themeMode,
            textReplacementsEnabled: screen.textReplacementsEnabled,
            hotkeyEnabled: true,
            hotkeyKey: 'D',
            hotkeyModifiers: 'ctrl+shift',
            onboardingCompleted: true,
          );

          final app = _buildScreenshotApp(
            db: db!,
            settings: settings,
            themeMode: themeMode,
            locale: locale,
            pageId: screen.pageId,
            child: screen.builder(),
          );

          await tester.pumpWidget(app);
          await _settle(tester, const Duration(seconds: 1));

          // Run any screen-specific arrangement (open detail, scroll, etc.)
          if (screen.arrange != null) {
            await screen.arrange!(tester, locale);
            await _settle(tester);
          }

          // Capture
          final path = '$_outputDir/$locale/$themeLabel/${screen.name}.png';
          await _captureScreen(tester, path);
        }

        // In-memory DB is GC'd — no explicit close needed.
        // (db.close() hangs because Riverpod providers still hold stream
        // subscriptions; they're disposed on the next pumpWidget anyway.)
      }
    }

    // ignore: avoid_print
    print('\nDone! All screenshots generated.');
  });
}

// ---------------------------------------------------------------------------
// Screenshot app builder
// ---------------------------------------------------------------------------

Widget _buildScreenshotApp({
  required HistoryDatabase db,
  required AppSettings settings,
  required ThemeMode themeMode,
  required String locale,
  required String pageId,
  required Widget child,
}) {
  return ProviderScope(
    overrides: [
      historyDatabaseProvider.overrideWithValue(db),
      settingsProvider.overrideWith(() => _MockSettingsNotifier(settings)),
      analyticsProvider.overrideWith((ref) async => _sampleAnalytics),
      modelDownloadProvider.overrideWith(() => _MockModelDownloadNotifier()),
      audioInputDevicesProvider.overrideWith(
        (ref) async => <String>['USB Microphone', 'Desk Mic'],
      ),
      hw.gpuInfoProvider.overrideWith(
        (ref) async =>
            const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'Screenshot'),
      ),
      sttServiceProvider.overrideWith(() => _MockSttServiceNotifier()),
      recordingProvider.overrideWith(() => _MockRecordingNotifier()),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: wpLightTheme().copyWith(
        scaffoldBackgroundColor: Colors.transparent,
      ),
      darkTheme: wpDarkTheme().copyWith(
        scaffoldBackgroundColor: Colors.transparent,
      ),
      themeMode: themeMode,
      locale: Locale(locale),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: _ScreenshotShell(
        pageId: pageId,
        settings: settings,
        child: child,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Screenshot shell — visual replica of _AppShell, without service side effects
// ---------------------------------------------------------------------------

/// Replicates the full app chrome layout from `_AppShell` (lib/app.dart)
/// without [ServiceBootstrapWidget] or [RecordingBehaviorWidget].
///
/// Uses the REAL extracted widgets (sidebar, title bar, status bar, watermark,
/// recording indicator bar, settings button) to prevent screenshot drift.
class _ScreenshotShell extends StatelessWidget {
  const _ScreenshotShell({
    required this.pageId,
    required this.settings,
    required this.child,
  });

  final String pageId;
  final AppSettings settings;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);
    final navItems = wpNavItems(l10n);
    final statusBarModel =
        buildStatusBarModel(settings: settings, l10n: l10n);

    const contentRadius = BorderRadius.only(
      topLeft: Radius.circular(WpRadius.xl),
      bottomLeft: Radius.circular(WpRadius.xl),
    );

    final contentDecoration = BoxDecoration(
      gradient: isDark
          ? WpColorsDark.warmSurfaceGradient
          : WpColorsLight.warmSurfaceGradient,
      borderRadius: contentRadius,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ClipRRect(
        borderRadius: BorderRadius.circular(_windowCornerRadius),
        child: Stack(
          children: [
            // Frame gradient background
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: isDark
                    ? WpColorsDark.frameGradient
                    : WpColorsLight.frameGradient,
              ),
              child: const SizedBox.expand(),
            ),
            // Watermark pattern
            Positioned.fill(child: WpFrameWatermark(isDark: isDark)),
            // Main layout — mirrors _AppShell exactly
            Column(
              children: [
                WpTitleBar(actions: [_ScreenshotThemeToggle(isDark: isDark)]),
                Expanded(
                  child: Row(
                    children: [
                      WpSidebar(
                        items: navItems,
                        activeId: pageId,
                        onItemTap: (_) {},
                        bottomItems: [
                          WpSidebarSettingsButton(
                            isActive: pageId == 'settings',
                            onTap: () {},
                          ),
                        ],
                      ),
                      // Content area — rounded panel with warm gradient
                      Expanded(
                        child: Container(
                          decoration: contentDecoration,
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              // Recording indicator — idle = height 0
                              const WpRecordingIndicatorBar(
                                  phase: RecordingPhase.idle),
                              // Page header
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  WpSpacing.xl,
                                  WpSpacing.lg,
                                  WpSpacing.xl,
                                  WpSpacing.xs,
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      wpPageTitle(pageId, navItems, l10n),
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineLarge,
                                    ),
                                  ],
                                ),
                              ),
                              // Page content
                              Expanded(child: child),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Status bar — full width on the frame
                WpStatusBar(
                  sttModeLabel: statusBarModel.sttModeLabel,
                  postProcessingLabel: statusBarModel.postProcessingLabel,
                  sttState: SttServerState.ready,
                  recordingPhase: RecordingPhase.idle,
                  afterActionLabel: afterTranscriptionStatusLabel(
                      settings.afterTranscriptionAction, l10n),
                  afterAction: settings.afterTranscriptionAction,
                  hotkeyLabel: formatHotkeyShortcut(
                      settings.hotkeyModifiers, settings.hotkeyKey),
                  hotkeyEnabled: settings.hotkeyEnabled,
                  onHotkeyTap: () {},
                  onSttTap: () {},
                  onPostProcessTap: () {},
                  onAfterActionChanged: (_) {},
                ),
              ],
            ),
          ],
        ),
      ),
      // FAB — idle state with accent gradient
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(
          bottom: WpLayout.statusBarHeight,
        ),
        child: WpRecordingFab(
          phase: RecordingPhase.idle,
          readiness: RecordingReadiness.ready,
          onPressed: () {},
        ),
      ),
    );
  }
}

/// Non-interactive theme toggle icon for screenshots.
class _ScreenshotThemeToggle extends StatelessWidget {
  const _ScreenshotThemeToggle({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final mutedColor =
        isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    return IconButton(
      icon: Icon(
        isDark ? LucideIcons.moon : LucideIcons.sun,
        color: mutedColor,
        size: 16,
      ),
      onPressed: () {},
      splashRadius: 16,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 32),
      padding: EdgeInsets.zero,
    );
  }
}

// ---------------------------------------------------------------------------
// Capture helpers
// ---------------------------------------------------------------------------

/// Let animations settle without requiring `pumpAndSettle` (which hangs on
/// infinite animations like the FAB breathe or Lottie loops).
Future<void> _settle(WidgetTester tester,
    [Duration d = const Duration(milliseconds: 500)]) async {
  await tester.runAsync(() => Future.delayed(d));
  await tester.pump();
}

/// Capture the current render tree as a transparent PNG.
///
/// GPU-based [OffsetLayer.toImage] and [ui.Image.toByteData] are real async
/// operations that MUST run inside [WidgetTester.runAsync] — otherwise the
/// test event loop deadlocks.
Future<void> _captureScreen(WidgetTester tester, String path) async {
  // Pump a few extra frames so layout is fully stable.
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }

  final bytes = await tester.runAsync<List<int>>(() async {
    final renderView = tester.binding.renderViews.first;
    final layer = renderView.debugLayer! as OffsetLayer;
    final image =
        await layer.toImage(renderView.paintBounds, pixelRatio: 1.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('Failed to convert image to PNG bytes');
    }
    return byteData.buffer.asUint8List();
  });

  if (bytes == null || bytes.isEmpty) {
    throw StateError('Screenshot capture returned no data for $path');
  }

  final file = File(path);
  await file.parent.create(recursive: true);
  file.writeAsBytesSync(bytes);

  // ignore: avoid_print
  print('  Screenshot saved: $path (${bytes.length} bytes)');
}

// ---------------------------------------------------------------------------
// Screen arrangement helpers
// ---------------------------------------------------------------------------

Future<void> _openFirstHistoryEntry(
    WidgetTester tester, String locale) async {
  final firstTitle = locale == 'de'
      ? 'Wöchentliche Standup-Notizen'
      : 'Weekly standup notes';
  final finder = find.text(firstTitle);
  if (finder.evaluate().isNotEmpty) {
    await tester.tap(finder.first);
    await _settle(tester);
  }
}

Future<void> _scrollToHotkeySection(
    WidgetTester tester, String locale) async {
  final sectionTitle =
      locale == 'de' ? 'Tastenkürzel' : 'Keyboard Shortcut';
  final target = find.text(sectionTitle);
  // Find the scrollable that belongs to the content panel (not sidebar)
  final scrollable = find.byType(Scrollable);
  if (scrollable.evaluate().length > 1) {
    // Use the last scrollable — the content panel's scrollable
    await tester.dragUntilVisible(
      target,
      scrollable.last,
      const Offset(0, -320),
    );
  } else if (scrollable.evaluate().isNotEmpty) {
    await tester.dragUntilVisible(
      target,
      scrollable.first,
      const Offset(0, -320),
    );
  }
}

// ---------------------------------------------------------------------------
// Screen definitions
// ---------------------------------------------------------------------------

class _ScreenDef {
  const _ScreenDef({
    required this.name,
    required this.pageId,
    required this.builder,
    this.needsDemoData = false,
    this.textReplacementsEnabled = false,
    this.arrange,
  });

  final String name;
  final String pageId;
  final Widget Function() builder;
  final bool needsDemoData;
  final bool textReplacementsEnabled;
  final Future<void> Function(WidgetTester tester, String locale)? arrange;
}

// ---------------------------------------------------------------------------
// Demo data — localized, realistic entries
// ---------------------------------------------------------------------------

Future<void> _seedDemoData(
  HistoryDatabase db, {
  required String locale,
}) async {
  final now = DateTime.now();
  final isGerman = locale == 'de';

  final tagLabels = isGerman
      ? ['Arbeit', 'Privat', 'Meeting', 'Idee', 'E-Mail']
      : ['Work', 'Personal', 'Meeting', 'Idea', 'Email'];

  final tagIds = <String, String>{};
  for (final tag in tagLabels) {
    final id =
        'tag-${tag.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}';
    tagIds[tag] = id;
    await db.into(db.tags).insert(
          TagsCompanion(
            id: Value(id),
            name: Value(tag),
            createdAt: Value(now),
          ),
        );
  }

  final entries = isGerman ? _demoEntriesDe : _demoEntriesEn;
  for (final entry in entries) {
    final ts = now.subtract(Duration(minutes: entry.minutesAgo));
    await db.into(db.historyEntries).insert(
          HistoryEntriesCompanion(
            id: Value(entry.id),
            title: Value(entry.title),
            content: Value(entry.content),
            timestamp: Value(ts),
            durationSec: Value(entry.durationSec),
            processingDurationSec: const Value(0.8),
            language: Value(locale),
            model: Value(entry.model),
            isLocal: const Value(true),
            pinned: Value(entry.pinned),
            source: const Value('dictation'),
          ),
        );

    for (final tagName in entry.tags) {
      final tagId = tagIds[tagName]!;
      await db.into(db.entryTags).insert(
            EntryTagsCompanion(
              entryId: Value(entry.id),
              tagId: Value(tagId),
            ),
          );
    }
  }

  final replacements = isGerman ? _replacementsDe : _replacementsEn;
  for (var i = 0; i < replacements.length; i++) {
    final (trigger, replacement) = replacements[i];
    await db.into(db.textReplacements).insert(
          TextReplacementsCompanion(
            id: Value('repl-$locale-$i'),
            trigger: Value(trigger),
            replacement: Value(replacement),
            createdAt: Value(now),
          ),
        );
  }
}

// -- English demo entries ---------------------------------------------------

const _demoEntriesEn = <_DemoEntry>[
  _DemoEntry(
    id: 'demo-1',
    title: 'Weekly standup notes',
    content:
        'The backend team shipped the new auth flow last night, which means '
        'we can start integration testing today. Frontend is on track for the '
        'design review on Thursday — Sarah already pushed the updated '
        'components to staging.\n\n'
        'Mobile team needs one more day for the push notification integration '
        'because the certificate renewal took longer than expected. No '
        'blockers reported. Action items: schedule the cross-team sync for '
        'Friday, and send the updated timeline to stakeholders.',
    durationSec: 42.3,
    minutesAgo: 15,
    tags: ['Work', 'Meeting'],
    model: 'Whisper Large v3',
    pinned: true,
  ),
  _DemoEntry(
    id: 'demo-2',
    title: 'Email to client — project update',
    content:
        'Hi Sarah, quick update on the project. We are ahead of schedule on '
        'the dashboard redesign and the new analytics view should be ready '
        'for testing by next Monday. I will send the staging link right away.',
    durationSec: 28.7,
    minutesAgo: 45,
    tags: ['Work', 'Email'],
    model: 'Whisper Large v3',
  ),
  _DemoEntry(
    id: 'demo-3',
    title: 'Product idea — voice shortcuts',
    content:
        'Voice shortcuts could expand into full phrases. Saying "sign off" '
        'would insert the email signature automatically and save time on '
        'repetitive writing throughout the day.',
    durationSec: 18.5,
    minutesAgo: 120,
    tags: ['Idea'],
    model: 'Whisper Medium',
    pinned: true,
  ),
  _DemoEntry(
    id: 'demo-4',
    title: 'Grocery list for the weekend',
    content:
        'Avocados, sourdough bread, cherry tomatoes, mozzarella, fresh basil, '
        'olive oil, pasta, chicken breast, garlic, onions, and dark chocolate.',
    durationSec: 12.1,
    minutesAgo: 180,
    tags: ['Personal'],
    model: 'Whisper Medium',
  ),
  _DemoEntry(
    id: 'demo-5',
    title: 'Meeting recap — Q2 planning',
    content:
        'Key takeaways: revenue target is fifteen percent growth, three new '
        'engineering hires approved, and the September launch date is locked. '
        'Follow up with design on the brand refresh.',
    durationSec: 55.8,
    minutesAgo: 360,
    tags: ['Work', 'Meeting'],
    model: 'Whisper Large v3',
  ),
];

// -- German demo entries ----------------------------------------------------

const _demoEntriesDe = <_DemoEntry>[
  _DemoEntry(
    id: 'demo-1',
    title: 'Wöchentliche Standup-Notizen',
    content:
        'Das Backend-Team hat den neuen Login-Ablauf gestern Abend '
        'ausgeliefert, sodass wir heute mit den Integrationstests starten '
        'können. Das Frontend liegt für das Design-Review am Donnerstag im '
        'Plan — Sarah hat die aktualisierten Komponenten bereits auf Staging '
        'gepusht.\n\n'
        'Mobile braucht noch einen Tag für die Push-Integration, weil die '
        'Zertifikatserneuerung länger gedauert hat als geplant. Keine '
        'Blocker. Aktionspunkte: Cross-Team-Sync für Freitag einplanen und '
        'aktualisierte Timeline an die Stakeholder schicken.',
    durationSec: 42.3,
    minutesAgo: 15,
    tags: ['Arbeit', 'Meeting'],
    model: 'Whisper Large v3',
    pinned: true,
  ),
  _DemoEntry(
    id: 'demo-2',
    title: 'E-Mail an Kundin — Projektupdate',
    content:
        'Hi Sarah, hier ein kurzes Update zum Projekt. Beim Dashboard-Redesign '
        'liegen wir vor dem Plan und die neue Statistikansicht sollte bis '
        'Montag testbar sein. Den Staging-Link schicke ich dir direkt danach.',
    durationSec: 28.7,
    minutesAgo: 45,
    tags: ['Arbeit', 'E-Mail'],
    model: 'Whisper Large v3',
  ),
  _DemoEntry(
    id: 'demo-3',
    title: 'Produktidee — Sprachkürzel',
    content:
        'Sprachkürzel könnten ganze Phrasen einfügen. Wenn ich '
        '"Grußformel" sage, wird automatisch meine Abschlussformel '
        'eingesetzt. Das spart täglich Tipparbeit.',
    durationSec: 18.5,
    minutesAgo: 120,
    tags: ['Idee'],
    model: 'Whisper Medium',
    pinned: true,
  ),
  _DemoEntry(
    id: 'demo-4',
    title: 'Einkaufsliste für das Wochenende',
    content:
        'Avocados, Sauerteigbrot, Cherrytomaten, Mozzarella, frisches Basilikum, '
        'Olivenöl, Pasta, Hähnchen, Knoblauch, Zwiebeln und dunkle Schokolade.',
    durationSec: 12.1,
    minutesAgo: 180,
    tags: ['Privat'],
    model: 'Whisper Medium',
  ),
  _DemoEntry(
    id: 'demo-5',
    title: 'Meeting-Zusammenfassung — Q2-Planung',
    content:
        'Wichtigste Punkte: fünfzehn Prozent Wachstumsziel, drei neue Stellen '
        'im Engineering und der September-Launch bleibt gesetzt. Bitte mit dem '
        'Design-Team das Marken-Refresh nachziehen.',
    durationSec: 55.8,
    minutesAgo: 360,
    tags: ['Arbeit', 'Meeting'],
    model: 'Whisper Large v3',
  ),
];

// -- Voice shortcuts (replacements) — expanded to 10 entries ----------------

const _replacementsEn = <(String, String)>[
  ('sign off', 'Best regards,\nAlex'),
  ('my email', 'alex@whispaste.dev'),
  ('meeting link', 'https://meet.example.com/team-sync'),
  ('brb', 'Be right back, give me just a moment.'),
  ('on my way', "I'm on my way, be there in 5 minutes!"),
  ('phone number', '+1 (555) 123-4567'),
  ('address', '742 Evergreen Terrace, Suite 201'),
  ('thanks', 'Thank you so much, I really appreciate it!'),
  ('follow up', 'Just following up on our last conversation — any updates?'),
  ('schedule', 'Let me check my calendar and get back to you shortly.'),
];

const _replacementsDe = <(String, String)>[
  ('grußformel', 'Viele Grüße,\nAlex'),
  ('meine mail', 'alex@whispaste.dev'),
  ('meeting link', 'https://meet.example.com/team-sync'),
  ('bin gleich zurück', 'Bin gleich wieder da, gib mir bitte einen Moment.'),
  ('bin unterwegs', 'Bin unterwegs, bin in 5 Minuten da!'),
  ('telefonnummer', '+49 (151) 123 456 78'),
  ('adresse', 'Musterstraße 42, 10115 Berlin'),
  ('danke', 'Vielen Dank, das weiß ich wirklich zu schätzen!'),
  ('nachfrage', 'Kurze Nachfrage zu unserem letzten Gespräch — gibt es Neuigkeiten?'),
  ('kalender', 'Ich schaue kurz in meinen Kalender und melde mich.'),
];

class _DemoEntry {
  const _DemoEntry({
    required this.id,
    required this.title,
    required this.content,
    required this.durationSec,
    required this.minutesAgo,
    required this.tags,
    required this.model,
    this.pinned = false,
  });

  final String id;
  final String title;
  final String content;
  final double durationSec;
  final int minutesAgo;
  final List<String> tags;
  final String model;
  final bool pinned;
}

// ---------------------------------------------------------------------------
// Mock providers — purely static values, no side effects
// ---------------------------------------------------------------------------

class _MockSettingsNotifier extends SettingsNotifier {
  _MockSettingsNotifier(this._settings);

  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;
}

class _MockModelDownloadNotifier extends ModelDownloadNotifier {
  @override
  ModelDownloadState build() => const ModelDownloadState(serverReady: true);
}

class _MockSttServiceNotifier extends SttServiceNotifier {
  @override
  SttStatus build() => const SttStatus(serverState: SttServerState.ready);
}

class _MockRecordingNotifier extends RecordingNotifier {
  @override
  RecordingState build() => const RecordingState();
}

const _sampleAnalytics = AnalyticsData(
  totalRecordings: 847,
  totalDurationMinutes: 423,
  totalWords: 52840,
  timeSavedMinutes: 846,
  weeklyActivity: [12.4, 18.2, 15.7, 22.1, 19.5, 8.3, 5.0],
  modelUsage: [
    AnalyticsModelUsage(model: 'Whisper Large v3', count: 612, fraction: 0.72),
    AnalyticsModelUsage(model: 'Whisper Medium', count: 183, fraction: 0.22),
    AnalyticsModelUsage(model: 'OpenAI API', count: 52, fraction: 0.06),
  ],
  durationBuckets: [234, 312, 189, 87, 25],
  localSavingsUsd: 127.05,
  cloudCostUsd: 3.12,
);
