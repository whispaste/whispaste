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

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/features/analytics/analytics_provider.dart';
import 'package:whispaste/features/history/history_page.dart';
import 'package:whispaste/features/settings/settings_page.dart';
import 'package:whispaste/features/analytics/analytics_page.dart';
import 'package:whispaste/features/about/about_page.dart';
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
    // HistoryPage's master-detail AnimationController ticker stays alive
    // after screenshot capture. golden_screenshot enforces !timersPending
    // internally, so this test must be skipped until a FakeAsync wrapper
    // is added. Use capture-store-screenshots.py for marketing screenshots.
    skip: true,
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
          final app =
              _buildScreenshotApp(device: device, child: screen.builder());

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
        historyDatabaseProvider.overrideWith((ref) {
          final db = HistoryDatabase.forTesting(NativeDatabase.memory());
          ref.onDispose(db.close);
          return db;
        }),
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
  });
  final String name;
  final Widget Function() builder;
  final bool skip;
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
