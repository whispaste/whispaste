/// Store screenshot tests for WhisPaste.
///
/// Store screenshot GENERATOR, not a regression test. It is tagged `store` and
/// excluded from every normal run. Regenerate the committed PNGs under
/// test/screenshots/goldens/ before a store release:
///   `wp-test.sh run <worktree> --tags=store --update-goldens`
/// Without --update-goldens it only compares against those PNGs.
///
/// Generates high-quality PNGs for store listings and website galleries using
/// golden_screenshot. Each screenshot renders the FULL app window — title bar,
/// navigation sidebar, content panel and status bar — via [WpScreenshotShell].
///
/// Narrative flow:
///   01 workspace overview (EN+DE)
///   03 replacements (EN+DE)
///   05 analytics (EN+DE)
@Tags(<String>['store'])
library;

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:whispaste/core/app_info.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/data/analytics_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/colors.dart'
    show WpColors, wpLightColors, wpNavyColors;
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/features/analytics/analytics_page.dart';
import 'package:whispaste/features/history/history_page.dart';
import 'package:whispaste/features/notes/notes_page.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';
import 'package:whispaste/features/settings/settings_page.dart';
import 'package:whispaste/services/audio_service.dart';
import 'package:whispaste/services/hardware_info_service.dart' as hw;
import 'package:whispaste/services/hotkey_service.dart';
import 'package:whispaste/services/model_download_service.dart';

import '../../test/screenshots/screenshot_devices.dart';
import '../../test/screenshots/screenshot_shell.dart';
import '../../test/screenshots/store_demo_data.dart';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

const _locales = ['en', 'de', 'ru'];

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
  // Website gallery only (10 has no store-listing slot): the Notizen area with
  // the quick-note mark, opened on that note.
  _ScreenDef(
    name: '10_notes_dark',
    activePageId: 'notes',
    builder: () => const NotesPage(),
    needsNotesData: true,
    arrange: _openQuickNote,
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
  ScreenshotDevice.screenshotsFolder = '../../test/screenshots/goldens/';

  // The navigation footer shows the version; without a mocked package info it
  // falls back to "unknown" and the store shot shows that instead.
  setUpAll(() async {
    PackageInfo.setMockInitialValues(
      appName: 'WhisPaste',
      packageName: 'com.whispaste.app',
      version: '1.4.2',
      buildNumber: '51',
      buildSignature: '',
    );
    await initAppInfo();
  });

  group('Store screenshots:', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    // The store set is Marine (navy frame around light content, the default
    // look); the light journal set is only the fallback for other tests.
    setUp(() => WpColors.activate(wpNavyColors));
    tearDown(() => WpColors.activate(wpLightColors));

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
        // Pinned clock: the seeded timestamps and the Today/Yesterday
        // grouping render as text, so wall-clock time would move pixels.
        (tester) => withClock(Clock.fixed(_screenshotNow), () async {
          final device = goldenDevice.device;
          final db = await _pumpStoreShot(tester, screen, locale, device);
          await tester.expectScreenshot(device, screen.fileName(locale));
          await tester.pumpAndSettle(const Duration(seconds: 1));
          await db.close();
        }),
        // golden_screenshot's default (0.1) is compared against a pixel
        // *fraction*, i.e. 10 %. 0 keeps the comparison exact.
        allowedDiffPercent: 0,
      );
    }
  });
}

/// Families the store shell paints with. They are registered before the
/// first frame of every shot, not after it: the recording dock measures its
/// labels to plan its row, so a label measured before its family is loaded
/// lays out differently. Without this, a shot rendered after another device
/// in the same test process came out a little different from a cold one.
const _storeFontFamilies = [
  kWpUiFont,
  kWpDisplayFont,
  'Inter',
  'packages/lucide_icons_flutter/Lucide',
  'packages/font_awesome_flutter/FontAwesomeSolid',
  'packages/font_awesome_flutter/FontAwesomeRegular',
  'packages/font_awesome_flutter/FontAwesomeBrands',
  'MaterialIcons',
];

/// Builds the shot for [screen] on [device] and pumps it to the captured
/// frame. Returns the database, which the caller closes.
Future<HistoryDatabase> _pumpStoreShot(
  WidgetTester tester,
  _ScreenDef screen,
  String locale,
  ScreenshotDevice device, {
  Widget Function(Widget app)? wrap,
}) async {
  // Show each platform's default hotkey: Cmd on macOS, Ctrl elsewhere.
  final modifiers = device.platform == TargetPlatform.macOS
      ? 'meta+shift'
      : 'ctrl+shift';
  final db = HistoryDatabase.forTesting(NativeDatabase.memory());
  final settings = AppSettings.defaults
      .copyWith(
        locale: locale,
        textReplacementsEnabled: screen.textReplacementsEnabled,
        hotkeyEnabled: true,
        hotkeyKey: 'D',
        hotkeyModifiers: modifiers,
      )
      // The quick-note hotkey is off by default. The Notizen shot shows
      // it active, the way a user who set it up sees the page.
      .copyWithSections(
        quickNoteHotkey: screen.needsNotesData
            ? QuickNoteHotkeySettings(
                quickNoteHotkeyEnabled: true,
                quickNoteHotkeyKey: 'N',
                quickNoteHotkeyKeyDisplay: 'N',
                quickNoteHotkeyModifiers: modifiers,
              )
            : null,
      );

  if (screen.needsDemoData) {
    await _seedDemoData(db, locale: locale);
  }
  if (screen.needsNotesData) {
    await _seedNotesDemo(db, locale: locale);
  }

  final app = _buildScreenshotApp(
    device: device,
    db: db,
    settings: settings,
    activePageId: screen.activePageId,
    child: screen.builder(),
  );
  final root = wrap?.call(app) ?? app;

  await tester.loadAssets(alsoLoadTheseFonts: _storeFontFamilies);
  await tester.pumpWidget(root);
  // Let providers resolve and build real content before scanning images.
  await tester.pumpFrames(root, const Duration(seconds: 1));
  // Icon fonts used by the actual content are found by the tree scan; the
  // explicit list above already covers the families the shell itself uses.
  await tester.loadAssets(alsoLoadTheseFonts: _storeFontFamilies);
  // One additional frame so widgets re-render with the loaded fonts.
  await tester.pump();

  if (screen.arrange != null) {
    await screen.arrange!(tester, locale);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
  }
  return db;
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
  final firstTitle = switch (locale) {
    'de' => 'Wöchentliche Standup-Notizen',
    'ru' => 'Еженедельные заметки по стендапу',
    _ => 'Weekly standup notes',
  };
  await tester.tap(find.text(firstTitle).first);
}

/// Opens the quick note (see [_seedNotesDemo]; it is listed below the pinned
/// note, so it is selected by its title rather than by position).
Future<void> _openQuickNote(WidgetTester tester, String locale) async {
  await tester.tap(find.text(_quickNoteTitle(locale)).first);
}

Future<void> _scrollToHotkeySection(WidgetTester tester, String locale) async {
  // The dictation card heading replaced the former "Hotkey" section label.
  final sectionTitle = lookupL10n(Locale(locale)).shortcutsGroupDictate;
  // The hotkey rows live in the Keyboard shortcuts area, not in General.
  await tester.tap(find.byKey(const ValueKey('settings-nav-shortcuts')));
  await tester.pumpAndSettle();
  // Scoped to the scroll content: the section picker sits in the sticky header
  // above the scrollable and can show this exact section label, so a bare
  // `find.text` may match both.
  await tester.dragUntilVisible(
    find.descendant(
      of: find.byType(SingleChildScrollView),
      matching: find.text(sectionTitle),
    ),
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
    this.needsNotesData = false,
    this.textReplacementsEnabled = false,
    this.arrange,
  });

  final String name;
  final String activePageId;
  final Widget Function() builder;
  final bool needsDemoData;
  final bool needsNotesData;
  final bool textReplacementsEnabled;
  final Future<void> Function(WidgetTester tester, String locale)? arrange;

  String fileName(String locale) => '${name}_$locale';
}

// ---------------------------------------------------------------------------
// Demo data — localized, realistic entries that make screenshots look populated
// ---------------------------------------------------------------------------

/// The moment the committed baselines were rendered at.
final _screenshotNow = DateTime(2026, 9, 30, 14, 54);

/// Demo notes for the Notizen screen. Each note's content is Markdown; the
/// list title is its first non-blank line (no title column). Index 0 is the
/// quick note; index 1 is pinned and therefore listed first.
List<String> _notesFor(String locale) => switch (locale) {
  'de' => const [
    'Schnellnotiz: Ideen für den Newsletter\n- Release-Text für Version 1.4\n- Screenshot der Notizen-Ansicht\n- Feedback aus der Community sammeln',
    'Lesenotizen Kapitel 3\n\nDer Abschnitt zu Gedächtnisprozessen fasst die Kernthesen gut zusammen. Quellen für die Hausarbeit noch prüfen.',
    'Wochenplan Team\n\nMontag: Designreview. Mittwoch: Release-Check mit dem Backend-Team. Freitag: Retro.',
    'Ideen für den Urlaub\n\nZugverbindungen nach Wien vergleichen und eine Unterkunft mit Küche suchen.',
  ],
  'ru' => const [
    'Быстрая заметка: идеи для рассылки\n- Текст релиза для версии 1.4\n- Скриншот экрана заметок\n- Собрать отзывы сообщества',
    'Конспект, глава 3\n\nРаздел о консолидации памяти хорошо суммирует основные аргументы. Проверить источники для реферата.',
    'План команды на неделю\n\nПонедельник: ревью дизайна. Среда: проверка релиза с командой бэкенда. Пятница: ретро.',
    'Идеи для поездки\n\nСравнить поезда до Вены и найти жильё с кухней.',
  ],
  _ => const [
    'Quick note: newsletter ideas\n- Release text for version 1.4\n- Screenshot of the notes view\n- Collect community feedback',
    'Reading notes, chapter 3\n\nThe section on memory consolidation sums up the core arguments well. Check the sources for the essay.',
    'Team plan for the week\n\nMonday: design review. Wednesday: release check with the backend team. Friday: retro.',
    'Ideas for the trip\n\nCompare train connections to Vienna and look for accommodation with a kitchen.',
  ],
};

String _quickNoteTitle(String locale) =>
    _notesFor(locale).first.split('\n').first;

Future<void> _seedNotesDemo(
  HistoryDatabase db, {
  required String locale,
}) async {
  final now = clock.now();
  final notes = _notesFor(locale);
  for (var i = 0; i < notes.length; i++) {
    final updatedAt = now.subtract(Duration(minutes: 5 * (i + 1)));
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: 'note-$locale-$i',
            content: Value(notes[i]),
            pinned: Value(i == 1),
            createdAt: updatedAt.subtract(const Duration(hours: 2)),
            updatedAt: updatedAt,
          ),
        );
  }
  await db.setQuickNote('note-$locale-0');
}

Future<void> _seedDemoData(HistoryDatabase db, {required String locale}) async {
  final now = clock.now();

  final tagLabels = switch (locale) {
    'de' => ['Arbeit', 'Privat', 'Meeting', 'Idee', 'E-Mail'],
    'ru' => ['Работа', 'Личное', 'Встреча', 'Идея', 'Почта'],
    _ => ['Work', 'Personal', 'Meeting', 'Idea', 'Email'],
  };

  final tagIds = <String, String>{};
  for (var i = 0; i < tagLabels.length; i++) {
    final tag = tagLabels[i];
    // Index-based id: the ASCII-slug formula collapses every Cyrillic tag
    // name to the same id ('tag--'), which breaks the primary key.
    final id = 'tag-$locale-$i';
    tagIds[tag] = id;
    await db
        .into(db.tags)
        .insert(
          TagsCompanion(id: Value(id), name: Value(tag), createdAt: Value(now)),
        );
  }

  final entries = switch (locale) {
    'de' => demoEntriesDe,
    'ru' => demoEntriesRu,
    _ => demoEntriesEn,
  };
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

  final replacements = switch (locale) {
    'de' => replacementsDe,
    'ru' => replacementsRu,
    _ => replacementsEn,
  };
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
    AnalyticsModelUsage(
      model: 'Whisper Large v3 Turbo',
      count: 612,
      fraction: 0.72,
    ),
    AnalyticsModelUsage(model: 'Whisper Medium', count: 183, fraction: 0.22),
    AnalyticsModelUsage(model: 'OpenAI API', count: 52, fraction: 0.06),
  ],
  durationBuckets: [234, 312, 189, 87, 25],
  localSavingsUsd: 127.05,
  cloudCostUsd: 3.12,
);
