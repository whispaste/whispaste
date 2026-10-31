/// Shared fixtures for the UX harness (`generators/ux/ux_screens_test.dart`
/// renders PNGs for the UX reviewer).
///
/// Realistic, deterministic data: 30 replacements, 50 history recordings,
/// 12 snippets and 15 notes, including long German compound names, so that
/// truncation and scroll behaviour show up the way a real, heavy user sees
/// them. Nothing here is a golden baseline.
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey, MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/platform/desktop_window_geometry.dart'
    show kOnboardingWindowSize;
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/core/theme/tokens.dart';
import 'package:whispaste/features/analytics/analytics_page.dart';
import 'package:whispaste/features/dictionary/dictionary_page.dart';
import 'package:whispaste/features/feedback/feedback_page.dart';
import 'package:whispaste/features/help/help_page.dart';
import 'package:whispaste/features/help/support_page.dart';
import 'package:whispaste/features/onboarding/onboarding_completion_gate.dart';
import 'package:whispaste/features/onboarding/onboarding_mic_gate.dart';
import 'package:whispaste/features/onboarding/onboarding_overlay.dart';
import 'package:whispaste/features/onboarding/steps/welcome_step.dart'
    show kWelcomeOtherModelLinkKey;
import 'package:whispaste/features/onboarding/stt_model_readiness.dart';
import 'package:whispaste/features/history/history_page.dart';
import 'package:whispaste/features/notes/notes_page.dart';
import 'package:whispaste/features/overview/overview_page.dart';
import 'package:whispaste/features/settings/settings_page.dart';
import 'package:whispaste/features/snippets/snippets_page.dart';
import 'package:whispaste/services/audio/import/audio_import_providers.dart'
    show AudioImportQueueNotifier, audioImportQueueProvider;
import 'package:whispaste/services/audio/import/audio_import_queue.dart';
import 'package:whispaste/services/audio/recovery/recording_journal.dart';
import 'package:whispaste/services/audio/recovery/recording_recovery.dart';
import 'package:whispaste/services/hotkey_service.dart';
import 'package:whispaste/widgets/toast.dart';

import '../features/settings/widgets/settings_golden_board.dart'
    show kSettingsGoldenSets;
import '../fixtures/onboarding_harness.dart';
import '../features/onboarding/onboarding_test_doubles.dart'
    show OnboardingFixedMicSpeech;
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

/// Realistic small work areas (width x height of the screen minus menu bar,
/// taskbar or dock), where the window is capped below its 716 px minimum
/// (UX-091). Used by the small-window guard and the screenshot harness.
const List<Size> kUxSmallWindowSizes = [
  Size(800, 640),
  Size(800, 688),
  Size(1024, 600),
  Size(1280, 680),
  Size(1366, 728),
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
    this.overrides = const <Object>[],
    this.openKeys = const <ValueKey<String>>[],
    this.scrollToKey,
  });

  /// File-name stem and guard-test name, e.g. `replacements-suggestions`.
  final String id;

  /// Sidebar entry that stays active (drives the page title).
  final String activePageId;
  final Widget Function() build;

  /// Optional tab tap after the first frame, e.g. the Dictionary tabs.
  final ValueKey<String>? selectTab;

  /// Provider overrides the screen needs beyond the shared ones.
  final List<Object> overrides;

  /// Taps after the first frame, in order, e.g. the summary rows that expand
  /// a section.
  final List<ValueKey<String>> openKeys;

  /// Optional key scrolled into view after the frame settles, for a screen
  /// whose subject sits below the fold (e.g. the overview community block).
  final ValueKey<String>? scrollToKey;
}

/// Three interrupted recordings, one with retained audio, and one journal
/// that could not be read: the recovery section shows every row and the
/// corrupt note.
RecordingJournalScan uxInterruptedScan() => RecordingJournalScan(
  recordings: [
    for (var i = 0; i < 3; i++)
      InterruptedRecording(
        id: 'interrupted-$i',
        startedAt: DateTime(2026, 10, 26, 10, i),
        wavPath: i == 0 ? '/nonexistent/interrupted-$i.wav' : null,
        journalPath: '/nonexistent/interrupted-$i.journal',
        entryId: 'entry-$i',
      ),
  ],
  skippedCorrupt: 1,
);

/// Three import jobs in a busy session, one of them transcribing.
final List<ImportJob> uxBusyImportJobs = [
  const ImportJob(
    id: 'import-copy',
    fileName: 'Interview-Kopie-mit-langem-Dateinamen-2026.wav',
    status: ImportStatus.copying,
    progress: 0.6,
  ),
  ImportJob(
    id: 'import-whisper',
    fileName: 'Besprechung-Q4.mp3',
    status: ImportStatus.transcribing,
    progress: 0.42,
    transcribingSince: DateTime(2026, 10, 26, 10),
  ),
  const ImportJob(id: 'import-queued', fileName: 'Notiz.ogg'),
];

class UxBusyImportQueue extends AudioImportQueueNotifier {
  @override
  List<ImportJob> build() => uxBusyImportJobs;
}

/// Overrides for a history page with an import queue and interrupted
/// recordings waiting.
List<Object> uxQueueAndRecoveryOverrides() => [
  audioImportQueueProvider.overrideWith(UxBusyImportQueue.new),
  interruptedRecordingsProvider.overrideWith(
    (ref) async => uxInterruptedScan(),
  ),
];

/// Screens of the state the normal suite does not guard: a history page with
/// an import queue and interrupted recordings, both expanded. The screenshot
/// generator renders them (`generators/ux/ux_screens_test.dart`).
final List<UxScreen> kUxHistoryStateScreens = [
  UxScreen(
    id: 'history-queue-recovery',
    activePageId: 'history',
    build: () => const HistoryPage(),
    overrides: uxQueueAndRecoveryOverrides(),
    openKeys: const [
      ValueKey('history-recovery-summary'),
      ValueKey('history-import-summary'),
    ],
  ),
];

final List<UxScreen> kUxScreens = [
  UxScreen(
    id: 'overview',
    activePageId: 'overview',
    build: () => const OverviewPage(),
  ),
  UxScreen(
    id: 'overview-community',
    activePageId: 'overview',
    build: () => const OverviewPage(),
    scrollToKey: const ValueKey('overview-community-github'),
  ),
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

/// Frames a full-window [body] without the app shell, such as a start
/// screen that replaces the shell.
Future<void> pumpUxBody(
  WidgetTester tester, {
  required Widget body,
  required HistoryDatabase db,
  required Size size,
  required String theme,
  required String locale,
  double scale = 1.0,
}) => _pumpFramed(
  tester,
  body: body,
  db: db,
  size: size,
  scale: scale,
  theme: theme,
  locale: locale,
  overrides: const [],
);

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
  List<Object> extraOverrides = const <Object>[],
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
    overrides: [
      hotkeyServiceProvider.overrideWith(() => _NoopHotkeyService()),
      ...screen.overrides,
      ...extraOverrides,
    ],
  );

  await _settleUx(tester, const Duration(milliseconds: 250));

  final tab = screen.selectTab;
  if (tab != null) {
    await tester.tap(find.byKey(tab));
    await tester.pump(const Duration(milliseconds: 300));
  }
  for (final key in screen.openKeys) {
    await tester.tap(find.byKey(key));
    await tester.pump(const Duration(milliseconds: 300));
    // A short window opens the section as a dialog. Close it, so the next key
    // lands on the page.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 300));
  }
  final scrollTo = screen.scrollToKey;
  if (scrollTo != null) {
    await tester.ensureVisible(find.byKey(scrollTo));
    await tester.pump(const Duration(milliseconds: 100));
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

/// The onboarding window at the 800 px guard width (height unchanged). The
/// pages must reflow at this width, not clip (V11-25).
const Size kUxOnboardingWidthSize = Size(800, 800);

/// The onboarding window at the 800x600 compact size (screen 1 review, V12).
const Size kUxOnboardingCompactSize = Size(800, 600);

/// One onboarding page. [index] is its position in the six-page flow.
class UxOnboardingStep {
  const UxOnboardingStep(this.id, this.index);

  /// File-name stem, e.g. `onboarding-3-model`.
  final String id;
  final int index;
}

/// The six v6 pages in order. The speech model is no page of the sequence: it
/// opens from the start page ("Anderes Modell"), see `openModelFromStart`.
const List<UxOnboardingStep> kUxOnboardingSteps = [
  UxOnboardingStep('onboarding-1-welcome', 0),
  UxOnboardingStep('onboarding-2-access', 1),
  UxOnboardingStep('onboarding-3-mic', 2),
  UxOnboardingStep('onboarding-4-hotkey', 3),
  UxOnboardingStep('onboarding-5-tryout', 4),
  UxOnboardingStep('onboarding-6-privacy', 5),
];

/// Shell variants: the bare main window (title bar, sidebar, page header, dock),
/// and the same window with two stacked toasts. At large text only one toast
/// stays on screen, by design (UX-050), so the second variant checks that case.
const List<String> kUxShellIds = ['shell-window', 'shell-toasts'];

/// A finished practice dictation: opens the Next gate of the practice page for
/// targets behind it (see [pumpUxOnboarding]).
class _UxPracticeDone extends OnboardingTestRecordingSucceededNotifier {
  @override
  bool build() => true;
}

/// Pumps the onboarding overlay at [step], paging forward with the real Next
/// button. Returns the layout exceptions raised on the way, one per page.
/// [theme] is not used for the onboarding: its palette is the stage, see the
/// `theme:` argument below. It stays in the signature so the sweep callers
/// read the same.
Future<List<Object>> pumpUxOnboarding(
  WidgetTester tester, {
  required UxOnboardingStep step,
  required HistoryDatabase db,
  required Size size,
  required double scale,
  required String theme,
  required String locale,
  // Pins both model downloads to a failed download (UX-081: error page of
  // the model step). Only the model step shows it; other steps ignore it.
  bool downloadFailed = false,
  // Opens the speech page's Next gate (a finished model) so later pages are
  // reachable. Off by default: the model error page (UX-081) keeps the gate.
  bool passSpeechGate = false,
  // Opens the speech model from the start page ("Anderes Modell") after the
  // paging, so the model page can be captured; [step] must be the start page.
  bool openModelFromStart = false,
}) async {
  // The tryAndGo page starts window drags through window_manager; the test
  // host has no such plugin, so answer the channel with a no-op.
  const windowChannel = MethodChannel('window_manager');
  // The drag also asks isFullScreen on Windows; a null answer would fail it.
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    windowChannel,
    (call) async => call.method == 'isFullScreen' ? false : null,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      windowChannel,
      null,
    ),
  );
  // The tryout page creates a recorder for its level meter; the record plugin
  // has no implementation on the test host, so answer with an idle recorder.
  const recordChannel = MethodChannel('com.llfbandit.record/messages');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    recordChannel,
    (call) async => switch (call.method) {
      'listInputDevices' => <Object?>[],
      'hasPermission' || 'isRecording' || 'isPaused' => false,
      _ => null,
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      recordChannel,
      null,
    ),
  );
  await _pumpFramed(
    tester,
    // The "Anderes Modell" link is on the revision run's start page only.
    body: OnboardingOverlay(revisionRun: openModelFromStart),
    db: db,
    size: size,
    scale: scale,
    // The onboarding stage is always the navy stage (DESIGN.md, "Onboarding
    // stage"), whatever set the user runs. The app switches to it on the
    // same condition, so the harness renders the production palette.
    theme: 'dark',
    locale: locale,
    overrides: [
      ...onboardingOverrides(
        // The start page shows the app language of the settings: the render
        // must show the locale it is drawn in, not the default.
        settings: FakeSettingsNotifier(
          AppSettings.defaults.copyWith(locale: locale),
        ),
        hotkeyStatus: HotkeyRegistrationStatus.success,
        downloadFailed: downloadFailed,
      ),
      if (passSpeechGate)
        onboardingModelStepCanAdvanceProvider.overrideWithValue(true),
      // The mic and practice gates hold Next until the user has spoken and
      // dictated. Pages past them are reached by paging, so the gate is
      // passed here, and only for targets behind it: the gated page itself
      // keeps its real state.
      if (step.index > 2)
        onboardingMicSpeechHeardProvider.overrideWith(
          OnboardingFixedMicSpeech.new,
        ),
      if (step.index > 4)
        onboardingTestRecordingSucceededProvider.overrideWith(
          _UxPracticeDone.new,
        ),
    ],
  );
  await _settleUx(tester, const Duration(milliseconds: 250));

  final errors = <Object>[];
  if (openModelFromStart) {
    final link = find.byKey(kWelcomeOtherModelLinkKey);
    await tester.ensureVisible(link);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(link);
    await tester.pump(const Duration(milliseconds: 400));
  }
  for (var i = 0; i < step.index; i++) {
    await tester.tap(find.byKey(kOnboardingNextButtonKey));
    // Not pumpAndSettle: the mic chip and the model step animate for as long
    // as they are shown and would time out. Past the page cross-fade
    // (WpMotion.dramatic), so the outgoing page and its primary action are
    // gone before the next tap.
    await tester.pump(WpMotion.dramatic + const Duration(milliseconds: 100));
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
