/// Shared fixtures for the UX harness (`ux_screens_test.dart` renders PNGs,
/// `ux_scroll_ownership_guard_test.dart` measures layout in the normal suite).
///
/// Realistic, deterministic data: 30 replacements, 50 history recordings,
/// 12 snippets and 15 notes, including long German compound names, so that
/// truncation and scroll behaviour show up the way a real, heavy user sees
/// them. Nothing here is a golden baseline.
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/platform/desktop_window_geometry.dart'
    show kOnboardingWindowSize;
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/features/analytics/analytics_page.dart';
import 'package:whispaste/features/dictionary/dictionary_page.dart';
import 'package:whispaste/features/feedback/feedback_page.dart';
import 'package:whispaste/features/help/help_page.dart';
import 'package:whispaste/features/help/support_page.dart';
import 'package:whispaste/features/onboarding/onboarding_overlay.dart';
import 'package:whispaste/features/history/history_page.dart';
import 'package:whispaste/features/notes/notes_page.dart';
import 'package:whispaste/features/settings/settings_page.dart';
import 'package:whispaste/features/snippets/snippets_page.dart';
import 'package:whispaste/services/hotkey_service.dart';
import 'package:whispaste/widgets/toast.dart';

import '../features/settings/widgets/settings_golden_board.dart'
    show kSettingsGoldenSets;
import '../fixtures/onboarding_harness.dart';
import '../fixtures/test_helpers.dart';
import '../screenshots/screenshot_shell.dart';

// ---------------------------------------------------------------------------
// Window sizes (logical px). 800x716 and 1100x720 are the guard sizes.
// ---------------------------------------------------------------------------

const Size kUxSizeMinimum = Size(800, 716);
const Size kUxSize1100 = Size(1100, 720);
const Size kUxSize1440 = Size(1440, 900);
const Size kUxSize1920 = Size(1920, 1080);

/// The sizes the guard test measures.
const List<Size> kUxGuardSizes = [kUxSizeMinimum, kUxSize1100];

/// Full sweep for the screenshot harness.
const List<Size> kUxSweepSizes = [
  kUxSizeMinimum,
  kUxSize1100,
  kUxSize1440,
  kUxSize1920,
];

/// Text scales (WCAG 1.4.4 asks for 200 %; 1.3 is the common large setting).
const List<double> kUxSweepScales = [1.0, 1.3, 2.0];

/// Themes in use. `light` is still in the code but CONTEXT.md §1 declares the
/// app dark-only since 2026-08-11, so it is not part of the default sweep.
const List<String> kUxSweepThemes = ['dark', 'navy'];

/// Locales of the sweep (de, en, he = RTL).
const List<String> kUxSweepLocales = ['de', 'en', 'he'];

/// The sidebar and page chrome of a finished screen.
const String kUxPaneKey = 'ux-pane';
const String kUxCaptureKey = 'ux-capture';

// ---------------------------------------------------------------------------
// Screens: every page, every tab, plus the sub-page Support.
// ---------------------------------------------------------------------------

class UxScreen {
  const UxScreen({
    required this.id,
    required this.activePageId,
    required this.build,
    this.selectTab,
  });

  /// File-name stem and guard-test name, e.g. `replacements-suggestions`.
  final String id;

  /// Sidebar entry that stays active (drives the page title).
  final String activePageId;
  final Widget Function() build;

  /// Optional tab tap after the first frame, e.g. the Dictionary tabs.
  final ValueKey<String>? selectTab;
}

final List<UxScreen> kUxScreens = [
  UxScreen(
    id: 'snippets',
    activePageId: 'snippets',
    build: () => const SnippetsPage(),
  ),
  UxScreen(id: 'notes', activePageId: 'notes', build: () => const NotesPage()),
  UxScreen(
    id: 'history',
    activePageId: 'history',
    build: () => const HistoryPage(),
  ),
  UxScreen(
    id: 'dictionary-terms',
    activePageId: 'replacements',
    build: () => const DictionaryPage(),
  ),
  UxScreen(
    id: 'dictionary-replacements',
    activePageId: 'replacements',
    build: () => const DictionaryPage(),
    selectTab: const ValueKey('dictionary-tab-replacements'),
  ),
  UxScreen(
    id: 'dictionary-suggestions',
    activePageId: 'replacements',
    build: () => const DictionaryPage(),
    selectTab: const ValueKey('dictionary-tab-suggestions'),
  ),
  UxScreen(
    id: 'analytics',
    activePageId: 'analytics',
    build: () => const AnalyticsPage(),
  ),
  UxScreen(id: 'help', activePageId: 'help', build: () => const HelpPage()),
  UxScreen(
    id: 'support',
    activePageId: 'help',
    build: () => const SupportPage(),
  ),
  UxScreen(
    id: 'feedback',
    activePageId: 'feedback',
    build: () => const FeedbackPage(),
  ),
  UxScreen(
    id: 'settings',
    activePageId: 'settings',
    build: () => const SettingsPage(),
  ),
];

// ---------------------------------------------------------------------------
// Seeding
// ---------------------------------------------------------------------------

/// Fixed clock for the seeded timestamps, so grouping ("Heute", "Gestern")
/// stays stable between runs.
final DateTime kUxSeedNow = DateTime(2026, 10, 18, 10, 30);

const List<(String, String)> _replacementPairs = [
  ('mfg', 'Mit freundlichen Grüßen'),
  ('lg', 'Liebe Grüße'),
  ('tel', '+49 30 1234567'),
  ('adr', 'Musterstraße 12, 10115 Berlin'),
  ('gh', 'github.com/whispaste/whispaste'),
  ('kw', 'Kalenderwoche'),
  ('dsgvo', 'Datenschutz-Grundverordnung'),
  ('ttl', 'Titel'),
  ('sw', 'Softwareentwicklung'),
  ('kd', 'Kundendienst Abteilung Reklamationsbearbeitung'),
  ('vg', 'Vielen Dank für Ihre Nachricht'),
  ('ab', 'Auf Wiedersehen'),
  ('bzgl', 'bezüglich'),
  ('ggf', 'gegebenenfalls'),
  ('zb', 'zum Beispiel'),
  ('usw', 'und so weiter'),
  ('ok', 'In Ordnung'),
  ('asap', 'so schnell wie möglich'),
  ('ftp', 'Dateiübertragungsprotokoll'),
  ('crm', 'Kundenbeziehungsmanagement'),
  ('ki', 'künstliche Intelligenz'),
  ('whisp', 'WhisPaste'),
  ('mtg', 'Besprechung am Donnerstag um 14 Uhr im Raum Nordlicht'),
  ('sig', 'Mit besten Grüßen aus Leipzig'),
  ('ttt', 'Tschüss bis morgen'),
  ('ps', 'Viele Grüße von unterwegs'),
  ('pr', 'Pull Request'),
  ('ci', 'Continuous Integration'),
  ('rb', 'Rückruf bitte'),
  ('ang', 'Anbei finden Sie die angeforderten Unterlagen'),
  ('ein', 'Eingangsrechnung Nummer'),
];

const List<String> _recordingTitles = [
  'Antwort an Maik zum Angebot',
  'Wöchentliche Standup-Notizen',
  'Entwurf E-Mail an den Vermieter wegen der Heizung im Erdgeschoss',
  'Code-Review Kommentar zu Pagination',
  'Kundenbeschwerde Lieferverzug',
  'Ideen für den Blogartikel',
  'Protokoll Projektsitzung Q4',
  'Chat-Antwort an das Support-Team',
  'Kurznotiz Einkaufsliste',
  'Ticket-Beschreibung Login-Fehler auf Windows 11',
];

const List<String> _snippetTitles = [
  'Signatur Geschäft',
  'Standardantwort Reklamation mit Verweis auf die Bestellnummer und Frist',
  'Bitte um Rückruf',
  'Terminvorschlag',
  'Danke für die Rückmeldung',
  'Bug-Report Vorlage',
  'Abwesenheitsnotiz',
  'Kurze Begrüßung',
  'Adresse Büro',
  'Zahlungserinnerung höflich',
  'Entschuldigung Verzögerung',
  'Meeting-Notiz Kopf',
];

/// Seeds the database. Call inside `tester.runAsync`, because drift's native
/// executor needs real async time.
Future<void> seedUxDatabase(HistoryDatabase db) async {
  final now = kUxSeedNow;

  for (var i = 0; i < _replacementPairs.length; i++) {
    final (trigger, replacement) = _replacementPairs[i];
    final id = 'ux-repl-$i';
    await db
        .into(db.textReplacements)
        .insert(
          TextReplacementsCompanion(
            id: Value(id),
            trigger: Value(trigger),
            replacement: Value(replacement),
            createdAt: Value(now),
          ),
        );
    await db
        .into(db.textReplacementTriggers)
        .insert(
          TextReplacementTriggersCompanion(
            id: Value('${id}_t0'),
            replacementId: Value(id),
            trigger: Value(trigger),
          ),
        );
  }

  for (var i = 0; i < 50; i++) {
    final ts = now.subtract(Duration(minutes: 17 * (i + 1)));
    final title = _recordingTitles[i % _recordingTitles.length];
    await db
        .into(db.historyEntries)
        .insert(
          HistoryEntriesCompanion(
            id: Value('ux-hist-$i'),
            title: Value('$title ${i + 1}'),
            content: Value(
              'Hallo zusammen, kurz zu $title. Das ist Aufnahme Nummer ${i + 1} '
              'mit etwas mehr Text, damit die Zeile realistisch lang wird.',
            ),
            timestamp: Value(ts),
            durationSec: Value(4.0 + (i % 9) * 3.5),
            processingDurationSec: const Value(0.8),
            language: const Value('de'),
            model: const Value('whisper-small'),
            isLocal: const Value(true),
            pinned: Value(i == 0),
            source: const Value('dictation'),
            colorSlot: Value(i % 5),
          ),
        );
  }

  for (var i = 0; i < _snippetTitles.length; i++) {
    await db.upsertSnippet(
      id: 'ux-snip-$i',
      title: _snippetTitles[i],
      body:
          'Sehr geehrte Damen und Herren, vielen Dank für Ihre Nachricht. '
          'Wir melden uns bis Freitag mit einer Rückmeldung zu Punkt ${i + 1}.',
      createdAt: now,
    );
  }

  for (var i = 0; i < 15; i++) {
    final updatedAt = now.subtract(Duration(minutes: 9 * (i + 1)));
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: 'ux-note-$i',
            content: Value(
              'Notiz ${i + 1}: Einkaufsliste, Ideen für den Termin am Montag '
              'und offene Punkte aus dem Gespräch mit dem Team.',
            ),
            pinned: Value(i == 1),
            createdAt: updatedAt.subtract(const Duration(hours: 2)),
            updatedAt: updatedAt,
          ),
        );
  }
}

// ---------------------------------------------------------------------------
// Pumping
// ---------------------------------------------------------------------------

class _NoopHotkeyService extends HotkeyService {
  @override
  void build() {}
}

/// Frames [body] for capture: theme, text scale, locale, the capture boundary
/// and the seeded database. It pumps but does not settle; callers settle.
Future<void> _pumpFramed(
  WidgetTester tester, {
  required Widget body,
  required HistoryDatabase db,
  required Size size,
  required double scale,
  required String theme,
  required String locale,
  required List<Object> overrides,
}) async {
  // The feedback page reads its rate limit from SharedPreferences in
  // initState; without a mock every feedback variant fails (UIA-VIS-04).
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final set = kSettingsGoldenSets[theme]!;
  WpColors.activate(set);
  addTearDown(() => WpColors.activate(kSettingsGoldenSets['dark']!));

  await tester.pumpWidget(
    makeTestable(
      Theme(
        data: wpThemeFor(set),
        child: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: RepaintBoundary(
              key: const ValueKey(kUxCaptureKey),
              child: ColoredBox(
                color: set.background,
                child: SizedBox.expand(child: body),
              ),
            ),
          ),
        ),
      ),
      size: size,
      locale: Locale(locale),
      db: db,
      overrides: overrides,
    ),
  );
}

/// Lets drift queries and timers resolve in real time, then builds a frame.
Future<void> _settleUx(WidgetTester tester, Duration realTime) async {
  await tester.runAsync(() => Future<void>.delayed(realTime));
  await tester.pump(const Duration(milliseconds: 300));
}

/// Builds one screen in the real screenshot shell (title band, sidebar, page
/// header, page body) with the given size, text scale, theme and locale.
///
/// The page body is wrapped in a [SizedBox.expand] keyed [kUxPaneKey], so a
/// caller can measure the content pane. The whole frame is keyed
/// [kUxCaptureKey] for PNG capture.
Future<void> pumpUxScreen(
  WidgetTester tester, {
  required UxScreen screen,
  required HistoryDatabase db,
  required Size size,
  required double scale,
  required String theme,
  required String locale,
}) async {
  await _pumpFramed(
    tester,
    body: WpScreenshotShell(
      activePageId: screen.activePageId,
      child: SizedBox.expand(
        key: const ValueKey(kUxPaneKey),
        child: screen.build(),
      ),
    ),
    db: db,
    size: size,
    scale: scale,
    theme: theme,
    locale: locale,
    overrides: [hotkeyServiceProvider.overrideWith(() => _NoopHotkeyService())],
  );

  await _settleUx(tester, const Duration(milliseconds: 250));

  final tab = screen.selectTab;
  if (tab != null) {
    await tester.tap(find.byKey(tab));
    await tester.pump(const Duration(milliseconds: 300));
  }
  await _settleUx(tester, const Duration(milliseconds: 150));
}

// ---------------------------------------------------------------------------
// Onboarding and shell variants. They are not in [kUxScreens]: the scroll
// guard measures a list inside the pane, and neither variant has one.
// ---------------------------------------------------------------------------

/// The onboarding window is fixed (see [kOnboardingWindowSize]), so its
/// variants render at this size only.
const Size kUxOnboardingSize = kOnboardingWindowSize;

/// One onboarding page. [index] is its position in the seven-step flow.
class UxOnboardingStep {
  const UxOnboardingStep(this.id, this.index);

  /// File-name stem, e.g. `onboarding-3-model`.
  final String id;
  final int index;
}

const List<UxOnboardingStep> kUxOnboardingSteps = [
  UxOnboardingStep('onboarding-1-welcome', 0),
  UxOnboardingStep('onboarding-2-privacy', 1),
  UxOnboardingStep('onboarding-3-model', 2),
  UxOnboardingStep('onboarding-4-hotkey', 3),
  UxOnboardingStep('onboarding-5-appearance', 4),
  UxOnboardingStep('onboarding-6-autopaste', 5),
  UxOnboardingStep('onboarding-7-tryandgo', 6),
];

/// Shell variants: the bare main window (title bar, sidebar, page header, dock),
/// and the same window with two stacked toasts. At large text only one toast
/// stays on screen, by design (UX-050), so the second variant checks that case.
const List<String> kUxShellIds = ['shell-window', 'shell-toasts'];

/// Pumps the onboarding overlay at [step], paging forward with the real Next
/// button. Returns the layout exceptions raised on the way, one per page.
Future<List<Object>> pumpUxOnboarding(
  WidgetTester tester, {
  required UxOnboardingStep step,
  required HistoryDatabase db,
  required Size size,
  required double scale,
  required String theme,
  required String locale,
}) async {
  // The tryAndGo page starts window drags through window_manager; the test
  // host has no such plugin, so answer the channel with a no-op.
  const windowChannel = MethodChannel('window_manager');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    windowChannel,
    (_) async => null,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      windowChannel,
      null,
    ),
  );
  await _pumpFramed(
    tester,
    body: const OnboardingOverlay(),
    db: db,
    size: size,
    scale: scale,
    theme: theme,
    locale: locale,
    overrides: onboardingOverrides(
      hotkeyStatus: HotkeyRegistrationStatus.success,
    ),
  );
  await _settleUx(tester, const Duration(milliseconds: 250));

  final errors = <Object>[];
  for (var i = 0; i < step.index; i++) {
    await tester.tap(find.byKey(kOnboardingNextButtonKey));
    // Not pumpAndSettle: the mic chip and the model step animate for as long
    // as they are shown and would time out.
    await tester.pump(const Duration(milliseconds: 400));
    final error = tester.takeException();
    if (error != null) errors.add('page ${i + 2}: $error');
  }
  await tester.pump(const Duration(milliseconds: 300));
  return errors;
}

/// Pumps the shell variant [id] (one of [kUxShellIds]).
Future<void> pumpUxShell(
  WidgetTester tester, {
  required String id,
  required HistoryDatabase db,
  required Size size,
  required double scale,
  required String theme,
  required String locale,
}) async {
  await _pumpFramed(
    tester,
    body: WpScreenshotShell(
      activePageId: 'history',
      child: SizedBox.expand(
        key: const ValueKey(kUxPaneKey),
        child: id == 'shell-toasts'
            ? const _UxToastSeeder()
            : const SizedBox.shrink(),
      ),
    ),
    db: db,
    size: size,
    scale: scale,
    theme: theme,
    locale: locale,
    overrides: [hotkeyServiceProvider.overrideWith(() => _NoopHotkeyService())],
  );
  await _settleUx(tester, const Duration(milliseconds: 250));
  // A toast slides in from below the window: let the entrance finish.
  await tester.pump(const Duration(seconds: 1));
}

/// Shows two toasts once the window is built. Long durations keep them up
/// until the capture; the test's teardown pump lets their timers finish.
class _UxToastSeeder extends StatefulWidget {
  const _UxToastSeeder();

  @override
  State<_UxToastSeeder> createState() => _UxToastSeederState();
}

class _UxToastSeederState extends State<_UxToastSeeder> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final l10n = L10n.of(context);
      WpToast.show(
        context,
        message: l10n.historyCopiedToClipboard,
        type: WpToastType.success,
        duration: const Duration(seconds: 4),
      );
      WpToast.show(
        context,
        message: l10n.historyTitleSaved,
        type: WpToastType.info,
        duration: const Duration(seconds: 4),
      );
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Opens a fresh in-memory database and seeds it.
Future<HistoryDatabase> openSeededUxDatabase(WidgetTester tester) async {
  final db = HistoryDatabase.forTesting(NativeDatabase.memory());
  await tester.runAsync(() => seedUxDatabase(db));
  return db;
}
