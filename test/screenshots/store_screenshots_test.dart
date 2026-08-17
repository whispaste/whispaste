/// Store screenshot tests for WhisPaste.
///
/// Generates high-quality PNGs for store listings and website galleries using
/// golden_screenshot. Each screenshot renders the FULL app window — title bar,
/// navigation sidebar, content panel and status bar — via [WpScreenshotShell].
///
/// Narrative flow:
///   01 workspace overview (EN+DE)
///   03 replacements (EN+DE)
///   05 analytics (EN+DE)
@Tags(<String>['golden'])
library;

import 'dart:io';

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
import 'package:whispaste/core/theme/colors.dart' show WpCategorySlot;
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/features/analytics/analytics_page.dart';
import 'package:whispaste/features/history/history_page.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';
import 'package:whispaste/features/settings/settings_page.dart';
import 'package:whispaste/services/audio_service.dart';
import 'package:whispaste/services/hardware_info_service.dart' as hw;
import 'package:whispaste/services/hotkey_service.dart';
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
    builder: () => const HistoryPage(),
    needsDemoData: true,
  ),
  // 02 and 04 were the store set's only *light* captures, and each is the
  // only shot of its screen. When the light theme went (2026-08-11) they came
  // back as dark rather than out: the set is five screens of the product, and
  // dropping the theme is not a reason to stop showing the detail view and
  // the settings page at all.
  _ScreenDef(
    name: '02_workspace_detail_dark',
    activePageId: 'history',
    builder: () => const HistoryPage(),
    needsDemoData: true,
    arrange: _openFirstHistoryEntry,
  ),
  _ScreenDef(
    name: '03_voice_shortcuts_dark',
    activePageId: 'replacements',
    builder: () => const ReplacementsPage(),
    needsDemoData: true,
    textReplacementsEnabled: true,
  ),
  _ScreenDef(
    name: '04_settings_dark',
    activePageId: 'settings',
    builder: () => const SettingsPage(),
    arrange: _scrollToHotkeySection,
  ),
  _ScreenDef(
    name: '05_analytics_dark',
    activePageId: 'analytics',
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

  // ---------------------------------------------------------------------------
  // Ticket 32, B1 — the color rotation never reached this fixture: every demo
  // entry landed on the `color_slot` column default (0, `iris`) because
  // neither `_DemoEntry` nor `_seedDemoData` carried the field. The rotation
  // itself is exercised at runtime by `HistoryDatabase._drawColorSlot`
  // (`lib/core/data/database.dart`), which guarantees a slot never repeats on
  // two consecutive inserts — these tests hold the *fixture* to the same
  // "visibly varied, never twice in a row" bar without re-testing the random
  // draw.
  // ---------------------------------------------------------------------------
  group('Demo data color-slot rotation (Ticket 32, B1)', () {
    const categorySlotCount = 8; // WpCategorySlot.categories.length

    test('WpCategorySlot.categories has not drifted from 8', () {
      expect(
        WpCategorySlot.categories.length,
        categorySlotCount,
        reason:
            'this fixture assumes 8 rotation-eligible slots — if that moved, '
            'the coverage assertions below need to move with it',
      );
    });

    for (final (localeName, entries) in [
      ('en', _demoEntriesEn),
      ('de', _demoEntriesDe),
    ]) {
      test(
        '$localeName: at least 6 of 8 categorical slots are represented',
        () {
          final distinctSlots = entries.map((e) => e.colorSlot).toSet();
          expect(
            distinctSlots.length,
            greaterThanOrEqualTo(6),
            reason:
                '$localeName demo entries cover only $distinctSlots '
                '(${distinctSlots.length}/$categorySlotCount) — the store '
                'screenshots would show a near-identical column of avatars '
                'again',
          );
        },
      );

      test('$localeName: no two consecutive entries share a color slot', () {
        for (var i = 1; i < entries.length; i++) {
          expect(
            entries[i].colorSlot,
            isNot(entries[i - 1].colorSlot),
            reason:
                '$localeName entries ${entries[i - 1].id} and ${entries[i].id} '
                'both draw slot ${entries[i].colorSlot} — '
                'HistoryDatabase._drawColorSlot never repeats a slot on '
                'consecutive inserts, and the fixture should not either',
          );
        }
      });
    }

    test('no demo entry insert relies on the color_slot column default', () {
      final source = File(
        'test/screenshots/store_screenshots_test.dart',
      ).readAsStringSync();

      final companionMatch = RegExp(
        r'HistoryEntriesCompanion\(([\s\S]*?)\),\s*\);',
      ).firstMatch(source);
      expect(
        companionMatch,
        isNotNull,
        reason:
            'the HistoryEntriesCompanion insert this test targets was not '
            'found — the sweep below would pass vacuously',
      );

      expect(
        companionMatch!.group(1),
        contains('colorSlot: Value(entry.colorSlot)'),
        reason:
            'the demo-entry Companion insert no longer names colorSlot '
            'explicitly — every entry would silently fall back to the '
            'column default (0, iris) again',
      );
    });
  });
}

void _screenshotTest(_ScreenDef screen, String locale) {
  group(screen.fileName(locale), () {
    for (final goldenDevice in _devices) {
      testGoldens(goldenDevice.name, (tester) async {
        final device = goldenDevice.device;
        final db = HistoryDatabase.forTesting(NativeDatabase.memory());
        final settings = AppSettings.defaults.copyWith(
          locale: locale,
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
            'Inter',
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
      });
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
    theme: wpDarkTheme(),
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
        // Skip platform-channel calls to the `hotkey_manager` plugin — the
        // settings screenshot renders the hotkey section, which would
        // otherwise trigger MissingPluginException during EventChannel
        // setup in the test environment.
        hotkeyServiceProvider.overrideWith(_FakeHotkeyService.new),
      ],
      child: WpScreenshotShell(activePageId: activePageId, child: child),
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
  final sectionTitle = locale == 'de' ? 'Tastenkürzel' : 'Keyboard Shortcut';
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
    required this.builder,
    this.needsDemoData = false,
    this.textReplacementsEnabled = false,
    this.arrange,
  });

  final String name;
  final String activePageId;
  final Widget Function() builder;
  final bool needsDemoData;
  final bool textReplacementsEnabled;
  final Future<void> Function(WidgetTester tester, String locale)? arrange;

  String fileName(String locale) => '${name}_$locale';
}

// ---------------------------------------------------------------------------
// Demo data — localized, realistic entries that make screenshots look populated
// ---------------------------------------------------------------------------

Future<void> _seedDemoData(HistoryDatabase db, {required String locale}) async {
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
    await db
        .into(db.tags)
        .insert(
          TagsCompanion(id: Value(id), name: Value(tag), createdAt: Value(now)),
        );
  }

  final entries = isGerman ? _demoEntriesDe : _demoEntriesEn;
  for (final entry in entries) {
    final ts = now.subtract(Duration(minutes: entry.minutesAgo));
    await db
        .into(db.historyEntries)
        .insert(
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
            colorSlot: Value(entry.colorSlot),
          ),
        );

    for (final tagName in entry.tags) {
      final tagId = tagIds[tagName]!;
      await db
          .into(db.entryTags)
          .insert(
            EntryTagsCompanion(entryId: Value(entry.id), tagId: Value(tagId)),
          );
    }
  }

  final replacements = isGerman ? _replacementsDe : _replacementsEn;
  for (var i = 0; i < replacements.length; i++) {
    final (trigger, replacement) = replacements[i];
    final replacementId = 'repl-$locale-$i';
    await db
        .into(db.textReplacements)
        .insert(
          TextReplacementsCompanion(
            id: Value(replacementId),
            trigger: Value(trigger),
            replacement: Value(replacement),
            createdAt: Value(now),
          ),
        );
    await db
        .into(db.textReplacementTriggers)
        .insert(
          TextReplacementTriggersCompanion(
            id: Value('${replacementId}_t0'),
            replacementId: Value(replacementId),
            trigger: Value(trigger),
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
    colorSlot: 5,
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
    colorSlot: 6,
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
    colorSlot: 0,
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
    colorSlot: 1,
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
    colorSlot: 3,
  ),
  _DemoEntry(
    id: 'demo-6',
    title: 'Quick reminder — dentist appointment',
    content:
        'Dentist appointment moved to Friday at nine. Ask reception whether '
        'the parking garage validation still works for early visits.',
    durationSec: 8.2,
    minutesAgo: 25,
    tags: ['Personal'],
    model: 'Whisper Medium',
    colorSlot: 7,
  ),
  _DemoEntry(
    id: 'demo-7',
    title: 'Interview debrief — backend candidate',
    content:
        'Strong on distributed systems, thinner on frontend collaboration. '
        'Leaning yes, but loop in the frontend lead before the offer call.',
    durationSec: 61.4,
    minutesAgo: 300,
    tags: ['Work', 'Meeting'],
    model: 'Whisper Large v3',
    colorSlot: 2,
  ),
  _DemoEntry(
    id: 'demo-8',
    title: 'Travel note — conference next month',
    content:
        'Book the flight before prices climb, and check whether the hotel '
        'block for the conference is still open for early registration.',
    durationSec: 15.0,
    minutesAgo: 500,
    tags: ['Idea'],
    model: 'Whisper Medium',
    colorSlot: 4,
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
    colorSlot: 5,
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
    colorSlot: 6,
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
    colorSlot: 0,
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
    colorSlot: 1,
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
    colorSlot: 3,
  ),
  _DemoEntry(
    id: 'demo-6',
    title: 'Kurze Erinnerung — Zahnarzttermin',
    content:
        'Zahnarzttermin auf Freitag neun Uhr verschoben. An der Rezeption '
        'fragen, ob die Parkhaus-Validierung auch für frühe Termine gilt.',
    durationSec: 8.2,
    minutesAgo: 25,
    tags: ['Privat'],
    model: 'Whisper Medium',
    colorSlot: 7,
  ),
  _DemoEntry(
    id: 'demo-7',
    title: 'Interview-Nachbesprechung — Backend-Kandidat',
    content:
        'Stark bei verteilten Systemen, dünner bei Frontend-Zusammenarbeit. '
        'Tendenz ja, aber vor dem Angebot noch die Frontend-Leitung einbeziehen.',
    durationSec: 61.4,
    minutesAgo: 300,
    tags: ['Arbeit', 'Meeting'],
    model: 'Whisper Large v3',
    colorSlot: 2,
  ),
  _DemoEntry(
    id: 'demo-8',
    title: 'Reisenotiz — Konferenz nächsten Monat',
    content:
        'Flug buchen, bevor die Preise steigen, und prüfen, ob das '
        'Hotelkontingent für die Konferenz noch für Frühbucher offen ist.',
    durationSec: 15.0,
    minutesAgo: 500,
    tags: ['Idee'],
    model: 'Whisper Medium',
    colorSlot: 4,
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
    required this.colorSlot,
    this.pinned = false,
  });

  final String id;
  final String title;
  final String content;
  final double durationSec;
  final int minutesAgo;
  final List<String> tags;
  final String model;
  final int colorSlot;
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

/// No-op [HotkeyService] for screenshot tests — skips the real platform
/// registration path that would otherwise call into the `hotkey_manager`
/// EventChannel (`dev.leanflutter.plugins/hotkey_manager_event`) and fail
/// with MissingPluginException when no native plugin is registered.
class _FakeHotkeyService extends HotkeyService {
  @override
  void build() {}
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
