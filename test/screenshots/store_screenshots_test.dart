/// Store screenshot tests for WhisPaste.
///
/// Generates high-quality PNGs for Microsoft Store and GitHub listings
/// using golden_screenshot — no app launch needed, runs headless in CI.
///
/// Usage:
///   flutter test --update-goldens test/screenshots/
///
/// Output: test/screenshots/goldens/ directory with PNG files.
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/core/data/analytics_provider.dart';
import 'package:whispaste/features/history/history_page.dart';
import 'package:whispaste/features/settings/settings_page.dart';
import 'package:whispaste/features/analytics/analytics_page.dart';
import 'package:whispaste/features/about/about_page.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/audio_service.dart';
import 'package:whispaste/services/hardware_info_service.dart' as hw;

import 'screenshot_devices.dart';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

/// Screenshots to generate. Each entry produces one golden per device.
final _screenshots = <_ScreenDef>[
  _ScreenDef(
    name: '01_history',
    builder: () => const HistoryPage(),
    needsDemoData: true,
  ),
  _ScreenDef(
    name: '02_settings',
    builder: () => const SettingsPage(),
  ),
  _ScreenDef(
    name: '03_analytics',
    builder: () => const AnalyticsPage(),
  ),
  _ScreenDef(
    name: '04_about',
    builder: () => const AboutPage(),
  ),
  _ScreenDef(
    name: '05_replacements',
    builder: () => const ReplacementsPage(),
    needsDemoData: true,
  ),
];

/// Devices to screenshot for. Only Windows Store for now.
const _devices = [WpScreenshotDevices.windowsStore];

// ---------------------------------------------------------------------------
// Test suite
// ---------------------------------------------------------------------------

void main() {
  ScreenshotDevice.screenshotsFolder = 'goldens/';

  group('Store screenshots:', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    for (final screen in _screenshots) {
      _screenshotTest(screen);
    }
  });
}

void _screenshotTest(_ScreenDef screen) {
  group(screen.name, () {
    for (final goldenDevice in _devices) {
      testGoldens(
        goldenDevice.name,
        skip: screen.skip,
        (tester) async {
          final device = goldenDevice.device;
          final db = HistoryDatabase.forTesting(NativeDatabase.memory());

          if (screen.needsDemoData) {
            await _seedDemoData(db);
          }

          final app = _buildScreenshotApp(
            device: device,
            db: db,
            child: screen.builder(),
          );

          // 1. Pump the widget tree first.
          await tester.pumpWidget(app);

          // 2. Load fonts (discovers 'Segoe UI' in tree -> replaces with Inter)
          //    and precache images.
          await tester.loadAssets();

          // 3. Re-pump with loaded fonts so text renders correctly.
          await tester.pumpFrames(app, const Duration(seconds: 1));

          // 4. Capture the screenshot.
          await tester.expectScreenshot(device, screen.name);

          // 5. Drain pending timers.
          await tester.pumpAndSettle(const Duration(seconds: 2));

          await db.close();
        },
      );
    }
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds the full screenshot widget tree with provider overrides and theme.
Widget _buildScreenshotApp({
  required ScreenshotDevice device,
  required HistoryDatabase db,
  required Widget child,
}) {
  return ScreenshotApp(
    device: device,
    theme: wpDarkTheme(),
    darkTheme: wpDarkTheme(),
    themeMode: ThemeMode.dark,
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: const Locale('en'),
    home: ProviderScope(
      overrides: [
        historyDatabaseProvider.overrideWithValue(db),
        settingsProvider.overrideWith(() => _MockSettingsNotifier()),
        analyticsProvider.overrideWith(
          (ref) async => _sampleAnalytics,
        ),
        modelDownloadProvider.overrideWith(() => _MockModelDownloadNotifier()),
        audioInputDevicesProvider.overrideWith(
          (ref) async => <String>['Default Microphone', 'Headset'],
        ),
        hw.gpuInfoProvider.overrideWith(
          (ref) async =>
              const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'Test'),
        ),
      ],
      child: Scaffold(body: child),
    ),
  );
}

class _ScreenDef {
  const _ScreenDef({
    required this.name,
    required this.builder,
    this.skip = false,
    this.needsDemoData = false,
  });
  final String name;
  final Widget Function() builder;
  final bool skip;
  final bool needsDemoData;
}

// ---------------------------------------------------------------------------
// Demo data — realistic entries that make screenshots look populated
// ---------------------------------------------------------------------------

Future<void> _seedDemoData(HistoryDatabase db) async {
  final now = DateTime.now();

  // Tags
  final tagIds = <String, String>{};
  for (final tag in ['Work', 'Personal', 'Meeting', 'Idea', 'Email']) {
    final id = 'tag-${tag.toLowerCase()}';
    tagIds[tag] = id;
    await db.into(db.tags).insert(TagsCompanion(
          id: Value(id),
          name: Value(tag),
          createdAt: Value(now),
        ));
  }

  // History entries — diverse, realistic dictations
  const entries = <_DemoEntry>[
    _DemoEntry(
      id: 'demo-1',
      title: 'Weekly standup notes',
      content:
          'The backend team shipped the new auth flow. Frontend is on track '
          'for the design review on Thursday. Mobile team needs an extra day '
          'for the push notification integration. No blockers reported.',
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
          'Hi Sarah, just a quick update on the project. We\'re ahead of '
          'schedule on the dashboard redesign and the new analytics features '
          'should be ready for testing by next Monday. I\'ll send you the '
          'staging link as soon as it\'s deployed. Best regards.',
      durationSec: 28.7,
      minutesAgo: 45,
      tags: ['Work', 'Email'],
      model: 'Whisper Large v3',
    ),
    _DemoEntry(
      id: 'demo-3',
      title: 'Product idea — voice shortcuts',
      content:
          'What if we add customizable voice shortcuts that expand into full '
          'text snippets? Like saying "sign off" automatically types out your '
          'email signature. Could save a ton of time for repetitive phrases.',
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
          'olive oil, pasta, chicken breast, garlic, onions, and dark chocolate '
          'for dessert.',
      durationSec: 12.1,
      minutesAgo: 180,
      tags: ['Personal'],
      model: 'Whisper Medium',
    ),
    _DemoEntry(
      id: 'demo-5',
      title: 'Meeting recap — Q2 planning',
      content:
          'Key takeaways: Revenue target is 15% growth. Three new hires '
          'approved for the engineering team. Launch date for v2.0 confirmed '
          'for September. Marketing budget increased by 20% for the product '
          'launch campaign. Follow up with design team on brand refresh.',
      durationSec: 55.8,
      minutesAgo: 360,
      tags: ['Work', 'Meeting'],
      model: 'Whisper Large v3',
    ),
    _DemoEntry(
      id: 'demo-6',
      title: 'Quick thought — app onboarding',
      content:
          'The first-run experience needs to feel magical. Show the user one '
          'successful dictation within 30 seconds of opening the app. Skip '
          'the tutorial, just let them press the button and see the result.',
      durationSec: 15.2,
      minutesAgo: 1440,
      tags: ['Idea', 'Work'],
      model: 'Whisper Medium',
    ),
    _DemoEntry(
      id: 'demo-7',
      title: 'Thank you note for the team',
      content:
          'Hey everyone, I just wanted to say a huge thank you for the '
          'incredible work on the release. The late nights and weekend pushes '
          'really paid off. Let\'s celebrate with lunch on Friday — my treat!',
      durationSec: 20.4,
      minutesAgo: 2880,
      tags: ['Work', 'Personal'],
      model: 'Whisper Large v3',
    ),
  ];

  for (final entry in entries) {
    final ts = now.subtract(Duration(minutes: entry.minutesAgo));
    await db.into(db.historyEntries).insert(HistoryEntriesCompanion(
          id: Value(entry.id),
          title: Value(entry.title),
          content: Value(entry.content),
          timestamp: Value(ts),
          durationSec: Value(entry.durationSec),
          processingDurationSec: const Value(0.8),
          language: const Value('en'),
          model: Value(entry.model),
          isLocal: const Value(true),
          pinned: Value(entry.pinned),
          source: const Value('dictation'),
        ));

    // Link tags
    for (final tagName in entry.tags) {
      final tagId = tagIds[tagName]!;
      await db.into(db.entryTags).insert(EntryTagsCompanion(
            entryId: Value(entry.id),
            tagId: Value(tagId),
          ));
    }
  }

  // Text replacements (voice shortcuts)
  final replacements = <(String, String)>[
    ('sign off', 'Best regards,\nAlex'),
    ('my email', 'alex@whispaste.dev'),
    ('meeting link', 'https://meet.example.com/team-sync'),
    ('brb', 'Be right back, give me just a moment.'),
  ];

  for (var i = 0; i < replacements.length; i++) {
    final (trigger, replacement) = replacements[i];
    await db.into(db.textReplacements).insert(TextReplacementsCompanion(
          id: Value('repl-$i'),
          trigger: Value(trigger),
          replacement: Value(replacement),
          createdAt: Value(now),
        ));
  }
}

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
  @override
  Future<AppSettings> build() async => AppSettings.defaults;
}

class _MockModelDownloadNotifier extends ModelDownloadNotifier {
  @override
  ModelDownloadState build() => const ModelDownloadState();
}

/// Sample analytics data that makes the dashboard look populated.
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
