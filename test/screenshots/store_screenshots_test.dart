/// Store screenshot tests for WhisPaste.
///
/// Generates high-quality PNGs for store listings and website galleries using
/// golden_screenshot. Each screenshot renders the FULL app window — title bar,
/// navigation sidebar, content panel and status bar — via [WpScreenshotShell].
///
/// Narrative flow:
///   01 workspace overview (dark/EN+DE)
///   02 workspace detail / open entry (light/EN+DE)
///   03 voice shortcuts (dark/EN+DE)
///   04 settings / hotkey section (light/EN+DE)
///   05 analytics (dark/EN+DE)
@Tags(<String>['golden'])
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/analytics_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/features/analytics/analytics_page.dart';
import 'package:whispaste/features/history/history_page.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';
import 'package:whispaste/features/settings/settings_page.dart';
import 'package:whispaste/services/audio_service.dart';
import 'package:whispaste/services/hardware_info_service.dart' as hw;
import 'package:whispaste/services/model_download_service.dart';

import 'screenshot_devices.dart';
import 'screenshot_shell.dart';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

const _locales = ['en', 'de'];

final _screenshots = <_ScreenDef>[
  _ScreenDef(
    name: '01_workspace_overview_dark',
    activePageId: 'history',
    themeMode: ThemeMode.dark,
    builder: () => const HistoryPage(),
    needsDemoData: true,
  ),
  _ScreenDef(
    name: '02_workspace_detail_light',
    activePageId: 'history',
    themeMode: ThemeMode.light,
    builder: () => const HistoryPage(),
    needsDemoData: true,
    arrange: _openFirstHistoryEntry,
  ),
  _ScreenDef(
    name: '03_voice_shortcuts_dark',
    activePageId: 'replacements',
    themeMode: ThemeMode.dark,
    builder: () => const ReplacementsPage(),
    needsDemoData: true,
    textReplacementsEnabled: true,
  ),
  _ScreenDef(
    name: '04_settings_light',
    activePageId: 'settings',
    themeMode: ThemeMode.light,
    builder: () => const SettingsPage(),
    arrange: _scrollToHotkeySection,
  ),
  _ScreenDef(
    name: '05_analytics_dark',
    activePageId: 'analytics',
    themeMode: ThemeMode.dark,
    builder: () => const AnalyticsPage(),
  ),
];

const _devices = [
  WpScreenshotDevices.windowsStore,
  WpScreenshotDevices.macStore,
];

// ---------------------------------------------------------------------------
// Test suite
// ---------------------------------------------------------------------------

void main() {
  ScreenshotDevice.screenshotsFolder = 'goldens/';

  group('Store screenshots:', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    for (final screen in _screenshots) {
      for (final locale in _locales) {
        _screenshotTest(screen, locale);
      }
    }
  });
}

void _screenshotTest(_ScreenDef screen, String locale) {
  group(screen.fileName(locale), () {
    for (final goldenDevice in _devices) {
      testGoldens(
        goldenDevice.name,
        (tester) async {
          final device = goldenDevice.device;
          final db = HistoryDatabase.forTesting(NativeDatabase.memory());
          final settings = AppSettings.defaults.copyWith(
            locale: locale,
            themeMode: screen.themeMode,
            textReplacementsEnabled: screen.textReplacementsEnabled,
            hotkeyEnabled: true,
            hotkeyKey: 'D',
            hotkeyModifiers: 'ctrl+shift',
          );

          if (screen.needsDemoData) {
            await _seedDemoData(db, locale: locale);
          }

          final app = _buildScreenshotApp(
            device: device,
            db: db,
            settings: settings,
            activePageId: screen.activePageId,
            child: screen.builder(),
          );

          await tester.pumpWidget(app);
          // Let providers resolve and build real content before scanning fonts.
          await tester.pumpFrames(app, const Duration(seconds: 1));
          // Load fonts after the widget tree is settled so icon fonts used by
          // the actual content (Lucide, FontAwesome) are found in the scan.
          // Explicitly include icon font families as safety net for cases where
          // icons are not yet in the visible tree portion.
          await tester.loadAssets(
            alsoLoadTheseFonts: const [
              'packages/lucide_icons_flutter/Lucide',
              'packages/font_awesome_flutter/FontAwesomeSolid',
              'packages/font_awesome_flutter/FontAwesomeRegular',
              'packages/font_awesome_flutter/FontAwesomeBrands',
              'MaterialIcons',
              'Segoe UI',
            ],
          );
          // One additional frame so widgets re-render with the loaded fonts.
          await tester.pump();

          if (screen.arrange != null) {
            await screen.arrange!(tester, locale);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 450));
          }

          await tester.expectScreenshot(device, screen.fileName(locale));
          await tester.pumpAndSettle(const Duration(seconds: 1));
          await db.close();
        },
      );
    }
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _buildScreenshotApp({
  required ScreenshotDevice device,
  required HistoryDatabase db,
  required AppSettings settings,
  required String activePageId,
  required Widget child,
}) {
  return ScreenshotApp(
    device: device,
    theme: wpLightTheme(),
    darkTheme: wpDarkTheme(),
    themeMode: settings.themeMode,
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: Locale(settings.locale),
    home: ProviderScope(
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
              const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'Test'),
        ),
      ],
      child: WpScreenshotShell(
        activePageId: activePageId,
        child: child,
      ),
    ),
  );
}

Future<void> _openFirstHistoryEntry(WidgetTester tester, String locale) async {
  final firstTitle = locale == 'de'
      ? 'Wöchentliche Standup-Notizen'
      : 'Weekly standup notes';
  await tester.tap(find.text(firstTitle).first);
}

Future<void> _scrollToHotkeySection(WidgetTester tester, String locale) async {
  final sectionTitle =
      locale == 'de' ? 'Tastenkürzel' : 'Keyboard Shortcut';
  await tester.dragUntilVisible(
    find.text(sectionTitle),
    find.byType(Scrollable).first,
    const Offset(0, -320),
  );
}

class _ScreenDef {
  const _ScreenDef({
    required this.name,
    required this.activePageId,
    required this.themeMode,
    required this.builder,
    this.needsDemoData = false,
    this.textReplacementsEnabled = false,
    this.arrange,
  });

  final String name;
  final String activePageId;
  final ThemeMode themeMode;
  final Widget Function() builder;
  final bool needsDemoData;
  final bool textReplacementsEnabled;
  final Future<void> Function(WidgetTester tester, String locale)? arrange;

  String fileName(String locale) => '${name}_$locale';
}

// ---------------------------------------------------------------------------
// Demo data — localized, realistic entries that make screenshots look populated
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
    final id = 'tag-${tag.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}';
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

const _demoEntriesEn = <_DemoEntry>[
  _DemoEntry(
    id: 'demo-1',
    title: 'Weekly standup notes',
    content:
        'The backend team shipped the new auth flow. Frontend is on track for '
        'the design review on Thursday. Mobile team needs one more day for the '
        'push notification integration. No blockers reported.',
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

const _demoEntriesDe = <_DemoEntry>[
  _DemoEntry(
    id: 'demo-1',
    title: 'Wöchentliche Standup-Notizen',
    content:
        'Das Backend-Team hat den neuen Login-Ablauf ausgeliefert. Das '
        'Frontend liegt für das Design-Review am Donnerstag im Plan. Mobile '
        'braucht noch einen Tag für die Push-Integration. Keine Blocker.',
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

const _replacementsEn = <(String, String)>[
  ('sign off', 'Best regards,\nAlex'),
  ('my email', 'alex@whispaste.dev'),
  ('meeting link', 'https://meet.example.com/team-sync'),
  ('brb', 'Be right back, give me just a moment.'),
];

const _replacementsDe = <(String, String)>[
  ('grußformel', 'Viele Grüße,\nAlex'),
  ('meine mail', 'alex@whispaste.dev'),
  ('meeting link', 'https://meet.example.com/team-sync'),
  ('bin gleich zurück', 'Bin gleich wieder da, gib mir bitte einen Moment.'),
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
// Mock providers
// ---------------------------------------------------------------------------

class _MockSettingsNotifier extends SettingsNotifier {
  _MockSettingsNotifier(this._settings);

  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;
}

class _MockModelDownloadNotifier extends ModelDownloadNotifier {
  @override
  ModelDownloadState build() => const ModelDownloadState();
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
