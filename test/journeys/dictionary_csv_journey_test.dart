/// Journey — dictionary CSV import with error rows, then dictation.
///
/// Import: the Dictionary page is opened from the sidebar, a CSV written by the
/// test is picked through the fake file dialog, the review page shows what
/// will be added, what is skipped as a duplicate and the lines that could not
/// be read. After the confirm, the Try-it field shows the replacement and a
/// hotkey dictation (exact and fuzzy trigger) pastes and stores the replaced
/// text. Export: the list is written through the fake save dialog and parses
/// back to the same rows.
///
/// Fakes sit only at the OS / model boundary: audio capture, STT, the Smart
/// Mode engine, native paste and clipboard, the attention service, and the
/// file dialogs (file_selector channel). Everything else is the production
/// code on an in-memory Drift database.
library;

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/app.dart'
    show wpHelpNavItem, wpNavItems, wpSettingsNavItem;
import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/features/dictionary/dictionary_page.dart';
import 'package:whispaste/features/history/data/providers.dart'
    show archivedEntriesProvider, historyEntriesProvider, trashEntriesProvider;
import 'package:whispaste/features/history/history_page.dart';
import 'package:whispaste/services/audio_service.dart';
import 'package:whispaste/services/dictionary/replacement_csv.dart';
import 'package:whispaste/services/desktop_paste/desktop_paste_controller.dart';
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/path_service.dart'
    show retainedAudioDirOverride, sttDir, sttDirOverride, sttModelPath;
import 'package:whispaste/services/recording_orchestrator.dart';
import 'package:whispaste/services/replacements/text_replacement_matcher.dart';
import 'package:whispaste/services/smart_mode/smart_mode_engine.dart';
import 'package:whispaste/services/smart_mode/smart_mode_ffi_engine.dart'
    show smartModeEngineProvider;
import 'package:whispaste/services/smart_mode/smart_mode_model_download_service.dart';
import 'package:whispaste/services/stt/stt_bundle.dart';
import 'package:whispaste/services/system_attention_service.dart';
import 'package:whispaste/widgets/sidebar.dart';
import 'package:whispaste/widgets/searchable_list_page.dart';
import 'package:whispaste/widgets/wp_button.dart';
import 'package:whispaste/widgets/wp_list_skeleton.dart';

import '../fixtures/test_helpers.dart';
import '../test_helpers/temp_dir_cleanup.dart';

const _fileSelectorChannel = MethodChannel('plugins.flutter.io/file_selector');
const _settleTimeout = Duration(seconds: 20);

/// Seven records: two valid rows, one row that duplicates the seeded trigger
/// `lg`, one that duplicates the valid row above it, and five broken rows
/// (too few columns, empty trigger, empty replacement, unknown match mode,
/// threshold out of range). Physical lines: 4, 5, 6, 7 and 8 are the errors.
const _csvText =
    'triggers,replacement,match_mode,threshold\r\n'
    'wisp paste,WhisPaste,exact,\r\n'
    'whisp paste,WhisPaste,fuzzy,standard\r\n'
    'lonely\r\n'
    ',Ersatz,exact,\r\n'
    'bitte,\r\n'
    'gruss,Grüße,regex,\r\n'
    'ciao,Hallo,fuzzy,1.7\r\n'
    'lg,Liebe Grüße,exact,\r\n'
    'wisp paste,WhisPaste doppelt,exact,\r\n';

late Directory _tmp;

/// Rows the History page shows. Set right before the page is opened; the
/// override reads it on first use, so the page sees the dictations.
List<HistoryEntry> _historySnapshot = const [];
late L10n _l10n;

/// What the simulated speaker said; read by the fake STT.
String _spokenText = '';

/// Clipboard contents, served through a mocked platform channel.
String? _clipboard;

/// Answers the next `openFile` call with [_queuedOpenFile].
String? _queuedOpenFile;

/// Answers the next `getSavePath` call with [_queuedSavePath].
String? _queuedSavePath;

AppSettings _settings() => const AppSettings(
  stt: SttSettings(model: 'whisper-small', language: 'English'),
  afterTranscriptionSection: AfterTranscriptionSettings(
    afterTranscription: 'paste',
  ),
  onboarding: OnboardingSettings(onboardingCompleted: true),
  behavior: BehaviorSettings(textReplacementsEnabled: true),
  smartMode: SmartModeSettings(standardPreset: 'off', provider: 'local'),
);

// ---------------------------------------------------------------------------
// Fakes at the OS / model boundary
// ---------------------------------------------------------------------------

class _FakeAudio extends AudioServiceNotifier {
  _FakeAudio(this.wavPath);

  final String wavPath;

  @override
  AudioStatus build() => const AudioStatus();

  @override
  Stream<double>? get amplitudeStream => null;

  @override
  Future<void> startRecording({bool streamRawPcm = false}) async {
    if (state.isRecording) return;
    state = AudioStatus(
      captureState: AudioCaptureState.recording,
      filePath: wavPath,
    );
  }

  @override
  Future<String?> stopRecording() async {
    state = AudioStatus(filePath: wavPath);
    return wavPath;
  }

  @override
  Future<void> cleanupFile(String? path) async {}
}

class _FakeStt extends SttServerStateNotifier {
  @override
  SttStatus build() =>
      const SttStatus(serverState: SttServerState.ready, port: 9999);

  @override
  Future<void> ensureRunning({bool warmup = true}) async {
    state = state.copyWith(serverState: SttServerState.ready);
  }

  @override
  Future<String> transcribeBytesWithProgress(
    List<int> wavBytes, {
    String? language,
    void Function(double fraction)? onProgress,
  }) async => _spokenText;

  @override
  Future<void> prewarm() async {}
}

/// Smart Mode is off in this journey, so the engine must never run.
class _NoLlm implements SmartModeEngine {
  @override
  Future<String> run({
    required String systemPrompt,
    required String userText,
  }) => throw StateError('Smart Mode engine must not run');

  @override
  Future<void> cancel() async {}
}

class _FakeSettings extends SettingsNotifier {
  _FakeSettings(this._settings);

  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;
}

class _FakeSecureKeyStore extends SecureKeyStore {
  _FakeSecureKeyStore() : super(null);

  final _store = <String, String>{};

  @override
  Future<String?> readKey(String key) async => _store[key];

  @override
  Future<void> writeKey(String key, String value) async => _store[key] = value;

  @override
  Future<void> deleteKey(String key) async => _store.remove(key);

  @override
  Future<Map<String, String>> readAllApiKeys() async => {};
}

class _FakeModelDownload extends ModelDownloadNotifier {
  @override
  ModelDownloadState build() =>
      const ModelDownloadState(downloadedModels: {'whisper-small'});
}

class _FakeSmartModeDownload extends SmartModeDownloadNotifier {
  @override
  SmartModeDownloadState build() =>
      const SmartModeDownloadState(modelDownloaded: true);
}

class _FakeSystemAttention extends SystemAttentionService {
  _FakeSystemAttention(super.ref);

  final List<AttentionKind> kinds = [];

  @override
  Future<void> requestAttention({
    required AttentionKind kind,
    required String title,
    required String body,
    void Function()? onClick,
  }) async {
    kinds.add(kind);
  }

  @override
  Future<void> clearAttention() async {}
}

/// Native paste bridge stand-in. [pastedTexts] collects the clipboard content
/// at the moment the native paste shortcut fires.
class _FakePaste extends DesktopPasteController {
  final List<String?> pastedTexts = [];

  @override
  Future<bool> capturePasteTarget() async => true;

  @override
  Future<NativePasteResult> pasteClipboard({required Duration delay}) async {
    pastedTexts.add(_clipboard);
    return const NativePasteResult(status: NativePasteStatus.success);
  }

  @override
  Future<NativePasteResult> copySelection({required Duration delay}) async =>
      const NativePasteResult(status: NativePasteStatus.unknown);

  @override
  Future<NativePasteResult> typeText(
    String text, {
    required Duration delay,
  }) async => const NativePasteResult(status: NativePasteStatus.postFailed);

  @override
  Future<bool> writeClipboardTextExcludingHistory(String text) async => false;

  @override
  Future<NativeCapabilityResult> checkCapability({
    bool promptIfMissing = false,
  }) async =>
      const NativeCapabilityResult(status: NativeCapabilityStatus.ready);

  @override
  Future<TccRepairResult> repairTccEntries() async =>
      TccRepairResult.unsupported();

  @override
  Future<TestPasteOutcome> diagnosticPaste(String demoText) async =>
      const TestPasteOutcomeUnsupported();

  @override
  Future<String?> getTargetBundleId() async => null;

  @override
  Future<void> dispose() async {}
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

/// Stand-in for the app shell: sidebar plus the page for the active id. The
/// History and Dictionary pages have content; the rest stay empty.
class _DictionaryShell extends StatefulWidget {
  const _DictionaryShell();

  @override
  State<_DictionaryShell> createState() => _DictionaryShellState();
}

class _DictionaryShellState extends State<_DictionaryShell> {
  String _active = 'help';

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Row(
      children: [
        WpSidebar(
          items: wpNavItems(l10n),
          activeId: _active,
          onItemTap: (id) => setState(() => _active = id),
          bottomItems: [wpHelpNavItem(l10n), wpSettingsNavItem(l10n)],
        ),
        Expanded(
          child: switch (_active) {
            'history' => const HistoryPage(),
            'replacements' => const DictionaryPage(),
            _ => const SizedBox.shrink(),
          },
        ),
      ],
    );
  }
}

/// Answers `openFile` and `getSavePath` on the file_selector channel.
void _mockFileDialogs() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_fileSelectorChannel, (call) async {
        switch (call.method) {
          case 'openFile':
            final path = _queuedOpenFile;
            _queuedOpenFile = null;
            return path == null ? null : <String>[path];
          case 'getSavePath':
            final path = _queuedSavePath;
            _queuedSavePath = null;
            return path;
          default:
            return null;
        }
      });
}

/// Pipeline container for the hotkey path. Runs without a mounted page, the
/// same way the dictation journey does.
ProviderContainer _pipeline(
  HistoryDatabase db, {
  required AppSettings settings,
  required String wavPath,
  required _FakePaste paste,
}) {
  final container = ProviderContainer(
    overrides: [
      historyDatabaseProvider.overrideWith((ref) => db),
      audioServiceProvider.overrideWith(() => _FakeAudio(wavPath)),
      localSttBundleProvider.overrideWith(_FakeStt.new),
      settingsProvider.overrideWith(() => _FakeSettings(settings)),
      secureKeyStoreProvider.overrideWith((ref) => _FakeSecureKeyStore()),
      desktopPasteControllerProvider.overrideWith((ref) => paste),
      modelDownloadProvider.overrideWith(_FakeModelDownload.new),
      smartModeDownloadProvider.overrideWith(_FakeSmartModeDownload.new),
      smartModeEngineProvider.overrideWith((ref) => _NoLlm()),
      systemAttentionServiceProvider.overrideWith(_FakeSystemAttention.new),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Hotkey press starts, second press stops and runs the whole pipeline.
Future<void> _dictate(WidgetTester tester, ProviderContainer container) async {
  final orchestrator = container.read(recordingOrchestratorProvider.notifier);
  await tester.runAsync(orchestrator.toggleRecording);
  expect(
    container.read(recordingProvider).phase,
    RecordingPhase.recording,
    reason: 'first hotkey press must start the recording',
  );
  await tester.runAsync(orchestrator.toggleRecording);
}

/// Steps the fake clock in small pumps until the toast has gone (its
/// auto-dismiss timer and exit animation), then disposes the tree, so no
/// timer or ticker outlives the test. One large pump does not run it.
Future<void> _teardown(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    if (!_present(const ValueKey('toast-message'))) break;
    await tester.pump(const Duration(milliseconds: 250));
  }
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

/// Pumps (with real yields) until [done] holds. Real file IO and Drift
/// queries only progress inside `runAsync`, so the bound is wall-clock time.
Future<void> _settle(
  WidgetTester tester,
  bool Function() done, {
  required String what,
}) async {
  final clock = Stopwatch()..start();
  while (clock.elapsed < _settleTimeout) {
    if (done()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  if (!done()) fail('timed out waiting for: $what');
}

/// Same as [_settle] for a condition that needs real async work (a database
/// read), evaluated inside `runAsync`.
Future<void> _settleAsync(
  WidgetTester tester,
  Future<bool> Function() done, {
  required String what,
}) async {
  final clock = Stopwatch()..start();
  while (clock.elapsed < _settleTimeout) {
    if (await tester.runAsync(done) ?? false) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
  fail('timed out waiting for: $what');
}

bool _present(Key key) => find.byKey(key).evaluate().isNotEmpty;

/// True when the button with [key] is present and has a press handler.
String _labelOf(WidgetTester tester, Key key) =>
    tester.widget<Text>(find.byKey(key)).data ?? '';

/// Mounts the shell with the real history database and opens the Dictionary
/// page through its sidebar key. Waits until the replacement list has loaded
/// (the export button is only enabled once it has rows).
Future<void> _openDictionary(
  WidgetTester tester,
  HistoryDatabase db,
  AppSettings settings,
) async {
  await tester.pumpWidget(
    makeTestable(
      const _DictionaryShell(),
      locale: const Locale('en'),
      db: db,
      overrides: [
        settingsProvider.overrideWith(() => _FakeSettings(settings)),
        // Static one-shot streams, as in the dictation journey: live Drift
        // streams under FakeAsync would keep pending timers.
        historyEntriesProvider.overrideWith(
          (ref) => Stream.value(_historySnapshot),
        ),
        archivedEntriesProvider.overrideWith(
          (ref) => Stream.value(const <HistoryEntry>[]),
        ),
        trashEntriesProvider.overrideWith(
          (ref) => Stream.value(const <HistoryEntry>[]),
        ),
      ],
    ),
  );
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('sidebar-nav-replacements')));
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('dictionary-tab-replacements')));
  await tester.pump();
  await _settle(
    tester,
    () =>
        _present(const ValueKey('replacements-more')) &&
        find.byType(WpListSkeleton).evaluate().isEmpty,
    what: 'dictionary page open',
  );
}

/// Opens the replacements toolbar's ⋯ menu. CSV import and export live there
/// (WP-81), so the journey reaches them the way a user does.
Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('replacements-more')));
  await tester.pumpAndSettle();
}

/// Opens the ⋯ menu and taps the item [key].
Future<void> _menuAction(WidgetTester tester, Key key) async {
  await _openMenu(tester);
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

/// Whether the menu item [key] is enabled. Opens the menu, reads it and
/// closes it again by tapping the modal barrier.
Future<bool> _menuItemEnabled(WidgetTester tester, Key key) async {
  await _openMenu(tester);
  final enabled = tester
      .widget<PopupMenuItem<WpListMenuAction>>(find.byKey(key))
      .enabled;
  await tester.tapAt(const Offset(2, 2));
  await tester.pumpAndSettle();
  return enabled;
}

Future<List<ReplacementWithTriggers>> _rows(
  WidgetTester tester,
  HistoryDatabase db,
) async => await tester.runAsync(db.readAllReplacements) ?? const [];

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Each test opens its own in-memory database; Drift only warns about it.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  setUpAll(() async {
    _l10n = await L10n.delegate.load(const Locale('en'));
  });

  setUp(() {
    // The pipeline's fire-and-forget review/support prompt checks read
    // SharedPreferences; without a backend getInstance fails and the error
    // can escape into the test zone, depending on timing.
    SharedPreferences.setMockInitialValues({});
    _tmp = Directory.systemTemp.createTempSync('wp40-dictionary-csv-');
    sttDirOverride = _tmp.path;
    retainedAudioDirOverride = '${_tmp.path}/retained-audio';
    // Preflight only checks that the model file exists; STT is faked.
    Directory(sttDir()).createSync(recursive: true);
    final modelPath = sttModelPath('whisper-small');
    if (modelPath != null && !File(modelPath).existsSync()) {
      File(modelPath).writeAsStringSync('fake-model');
    }
    _spokenText = '';
    _clipboard = null;
    _queuedOpenFile = null;
    _queuedSavePath = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              final args = Map<String, dynamic>.from(call.arguments as Map);
              _clipboard = args['text'] as String?;
              return null;
            case 'Clipboard.getData':
              if (_clipboard == null) return null;
              return <String, dynamic>{'text': _clipboard};
            default:
              return null;
          }
        });
    _mockFileDialogs();
  });

  tearDown(() {
    sttDirOverride = null;
    retainedAudioDirOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_fileSelectorChannel, null);
    deleteTempDir(_tmp);
  });

  testWidgets(
    'CSV import with error rows, then exact and fuzzy replacements apply to '
    'dictation',
    (tester) async {
      // Taller than the default 800x600 surface, so the review page's import
      // button is on screen without scrolling.
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      final settings = _settings();
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      // One existing row, so the list is not seeded with the sample entries
      // and the duplicate rows in the CSV have something to collide with.
      await tester.runAsync(
        () => db.upsertReplacementWithTriggers(
          id: 'seed-lg',
          triggers: const ['lg'],
          replacement: 'Liebe Grüße',
          createdAt: DateTime(2026, 10, 1),
        ),
      );
      final wav = File('${_tmp.path}/dictation.wav')
        ..writeAsBytesSync(List<int>.filled(364, 0));
      final paste = _FakePaste();
      final container = _pipeline(
        db,
        settings: settings,
        wavPath: wav.absolute.path,
        paste: paste,
      );
      await tester.runAsync(() => container.read(settingsProvider.future));
      final attention =
          container.read(systemAttentionServiceProvider)
              as _FakeSystemAttention;

      await _openDictionary(tester, db, settings);

      // -- Import: pick the file, review the preview -----------------------
      final csv = File('${_tmp.path}/woerterbuch.csv')
        ..writeAsStringSync(_csvText);
      _queuedOpenFile = csv.path;
      await _menuAction(tester, const ValueKey('dictionary-csv-import'));
      await _settle(
        tester,
        () => _present(const ValueKey('dictionary-csv-preview-import')),
        what: 'review page opened',
      );

      expect(
        find.byKey(const ValueKey('dictionary-csv-preview-errors')),
        findsOneWidget,
        reason: 'error summary must be shown',
      );
      expect(
        find.text(_l10n.dictionaryCsvErrorSummary(5)),
        findsOneWidget,
        reason: 'five broken lines are summarised',
      );
      for (final line in [4, 5, 6, 7, 8]) {
        expect(
          find.byKey(ValueKey('dictionary-csv-preview-error-$line')),
          findsOneWidget,
          reason: 'line $line is listed with its error',
        );
      }
      expect(
        find.byKey(const ValueKey('dictionary-csv-preview-summary')),
        findsOneWidget,
        reason: 'the counts line is shown',
      );

      // Rows that pass validation, in file order: two new triggers, the seeded
      // `lg` (duplicate), and a second `wisp paste` with another replacement,
      // which conflicts with the first row and is skipped by default.
      expect(
        _labelOf(tester, const ValueKey('dictionary-csv-preview-row-status-0')),
        _l10n.dictionaryCsvStatusAdded,
      );
      expect(
        _labelOf(tester, const ValueKey('dictionary-csv-preview-row-status-1')),
        _l10n.dictionaryCsvStatusAdded,
      );
      expect(
        _labelOf(tester, const ValueKey('dictionary-csv-preview-row-status-2')),
        _l10n.dictionaryCsvStatusDuplicate,
      );
      expect(
        _labelOf(tester, const ValueKey('dictionary-csv-preview-row-status-3')),
        _l10n.dictionaryCsvStatusConflictSkipped,
      );
      expect(
        find.byKey(const ValueKey('dictionary-csv-preview-row-status-4')),
        findsNothing,
      );

      // -- Confirm: two rows are written, the seeded one is untouched -------
      await tester.tap(
        find.byKey(const ValueKey('dictionary-csv-preview-import')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await _settleAsync(
        tester,
        () async => (await db.readAllReplacements()).length == 3,
        what: 'imported rows written',
      );
      await tester.pump(const Duration(milliseconds: 300));

      final rows = await _rows(tester, db);
      final byTrigger = {
        for (final r in rows)
          for (final t in r.triggers) t: r.row,
      };
      expect(byTrigger.keys, containsAll(['lg', 'wisp paste', 'whisp paste']));
      expect(byTrigger['lg']!.replacement, 'Liebe Grüße');
      expect(byTrigger['wisp paste']!.matchMode, 'exact');
      expect(byTrigger['whisp paste']!.matchMode, 'fuzzy');
      expect(byTrigger['whisp paste']!.fuzzyThreshold, 0.85);

      // -- Try-it dialog (⋯ menu) shows the replacement ---------------------
      await _menuAction(tester, const ValueKey('dictionary-test-open'));
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('dictionary-test-input')),
          matching: find.byType(EditableText),
        ),
        'ich teste wisp paste heute',
      );
      await tester.pump();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('dictionary-test-result')))
            .data,
        contains('ich teste WhisPaste heute'),
      );
      final close = find.widgetWithText(WpButton, _l10n.actionClose);
      await tester.ensureVisible(close);
      await tester.pumpAndSettle();
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dictionary-test-input')), findsNothing);

      // -- Dictation, exact trigger ----------------------------------------
      _spokenText = 'ich teste wisp paste heute';
      await _dictate(tester, container);
      expect(container.read(recordingProvider).phase, RecordingPhase.done);
      expect(paste.pastedTexts, ['ich teste WhisPaste heute']);

      // -- Dictation, fuzzy trigger (one letter off) -----------------------
      _spokenText = 'ich teste whispe paste heute';
      await _dictate(tester, container);
      expect(container.read(recordingProvider).phase, RecordingPhase.done);
      expect(paste.pastedTexts, [
        'ich teste WhisPaste heute',
        'ich teste WhisPaste heute',
      ]);

      final entries = await tester.runAsync(db.allEntries) ?? const [];
      expect(entries, hasLength(2));
      for (final entry in entries) {
        expect(entry.content, 'ich teste WhisPaste heute');
      }
      expect(
        entries.map((e) => e.originalTranscript),
        unorderedEquals([
          'ich teste wisp paste heute',
          'ich teste whispe paste heute',
        ]),
      );
      expect(attention.kinds, isEmpty);

      // -- History shows both entries with the replacement -----------------
      _historySnapshot = entries;
      await tester.tap(find.byKey(const ValueKey('sidebar-nav-history')));
      await tester.pump();
      await _settle(
        tester,
        () => entries.every((e) => _present(ValueKey(e.id))),
        what: 'history rows for both dictations',
      );

      await _settle(
        tester,
        () => _present(const ValueKey('toast-message')),
        what: 'confirmation toast',
      );
      await _teardown(tester);
    },
  );

  testWidgets('CSV export writes the list and parses back to the same rows', (
    tester,
  ) async {
    final settings = _settings();
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    await tester.runAsync(() async {
      await db.upsertReplacementWithTriggers(
        id: 'r-exact',
        triggers: const ['wisp paste'],
        replacement: 'WhisPaste',
        createdAt: DateTime(2026, 10, 1),
      );
      await db.upsertReplacementWithTriggers(
        id: 'r-fuzzy',
        triggers: const ['whisp paste', 'wisp pase'],
        replacement: 'WhisPaste',
        createdAt: DateTime(2026, 10, 2),
        matchMode: 'fuzzy',
        fuzzyThreshold: fuzzyThresholdStandard,
      );
    });

    // The selection page's confirm button sits below the default surface.
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final exportPath = '${_tmp.path}/whispaste-woerterbuch.csv';
    _queuedSavePath = exportPath;
    await _openDictionary(tester, db, settings);
    expect(
      await _menuItemEnabled(tester, const ValueKey('dictionary-csv-export')),
      isTrue,
    );
    await _menuAction(tester, const ValueKey('dictionary-csv-export'));
    await _settle(
      tester,
      () => _present(const ValueKey('vocabulary-import-confirm')),
      what: 'export selection page open',
    );
    _pressConfirm(tester);

    await _settle(tester, () {
      final file = File(exportPath);
      if (!file.existsSync()) return false;
      return parseReplacementsCsv(file.readAsStringSync()).rows.length == 2;
    }, what: 'export file written');

    final parsed = parseReplacementsCsv(File(exportPath).readAsStringSync());
    expect(parsed.errors, isEmpty);
    expect(parsed.rows, hasLength(2));
    final exact = parsed.rows.singleWhere(
      (r) => r.matchMode == TextReplacementMatchMode.exact,
    );
    expect(exact.triggers, ['wisp paste']);
    expect(exact.replacement, 'WhisPaste');
    expect(exact.fuzzyThreshold, isNull);

    final fuzzy = parsed.rows.singleWhere(
      (r) => r.matchMode == TextReplacementMatchMode.fuzzy,
    );
    expect(fuzzy.triggers, unorderedEquals(['whisp paste', 'wisp pase']));
    expect(fuzzy.replacement, 'WhisPaste');
    expect(fuzzy.fuzzyThreshold, fuzzyThresholdStandard);

    await _settle(
      tester,
      () => _present(const ValueKey('toast-message')),
      what: 'confirmation toast',
    );
    await _teardown(tester);
  });

  testWidgets('CSV export neutralises cells starting with = + - @ (formula '
      'injection)', (tester) async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    await tester.runAsync(
      () => db.upsertReplacementWithTriggers(
        id: 'r-formula',
        triggers: const ['=formel'],
        replacement: '=SUMME(A1:A2)',
        createdAt: DateTime(2026, 10, 1),
      ),
    );
    // The selection page's confirm button sits below the default surface.
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final exportPath = '${_tmp.path}/formula.csv';
    _queuedSavePath = exportPath;
    await _openDictionary(tester, db, _settings());
    expect(
      await _menuItemEnabled(tester, const ValueKey('dictionary-csv-export')),
      isTrue,
    );
    await _menuAction(tester, const ValueKey('dictionary-csv-export'));
    await _settle(
      tester,
      () => _present(const ValueKey('vocabulary-import-confirm')),
      what: 'export selection page open',
    );
    _pressConfirm(tester);
    await _settle(
      tester,
      () => File(exportPath).existsSync() && File(exportPath).lengthSync() > 0,
      what: 'export file written',
    );

    final dataLine = File(
      exportPath,
    ).readAsStringSync().split('\r\n').firstWhere((l) => l.contains('formel'));
    expect(
      dataLine.replaceFirst('﻿', '').startsWith('='),
      isFalse,
      reason: 'a spreadsheet must not evaluate the exported trigger',
    );

    // The toast follows the closed write: Windows cannot delete a file that
    // is still open, so tearDown would fail without this wait.
    await _settle(
      tester,
      () => _present(const ValueKey('toast-message')),
      what: 'confirmation toast',
    );
    await _teardown(tester);
  });

  testWidgets('CSV export writes only the entries left selected, with package '
      'metadata', (tester) async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    await tester.runAsync(() async {
      await db.upsertReplacementWithTriggers(
        id: 'r-keep',
        triggers: const ['wisp paste'],
        replacement: 'WhisPaste',
        createdAt: DateTime(2026, 10, 1),
      );
      await db.upsertReplacementWithTriggers(
        id: 'r-skip',
        triggers: const ['lg'],
        replacement: 'Liebe Grüße',
        createdAt: DateTime(2026, 10, 2),
      );
    });

    // The selection page's confirm button sits below the default surface.
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final exportPath = '${_tmp.path}/whispaste-woerterbuch.csv';
    _queuedSavePath = exportPath;
    await _openDictionary(tester, db, _settings());
    expect(
      await _menuItemEnabled(tester, const ValueKey('dictionary-csv-export')),
      isTrue,
    );
    await _menuAction(tester, const ValueKey('dictionary-csv-export'));
    await _settle(
      tester,
      () => _present(const ValueKey('vocabulary-import-confirm')),
      what: 'export selection page open',
    );

    // Both entries start selected; take the second one out.
    await tester.tap(find.text('lg → Liebe Grüße'));
    await tester.pump();
    expect(
      find.text(_l10n.dictionaryCsvExportConfirm(1)),
      findsOneWidget,
      reason: 'the button counts the entries that stay selected',
    );
    _pressConfirm(tester);

    await _settle(tester, () {
      final file = File(exportPath);
      return file.existsSync() && file.lengthSync() > 0;
    }, what: 'export file written');

    final parsed = parseReplacementsCsv(File(exportPath).readAsStringSync());
    expect(parsed.rows, hasLength(1));
    expect(parsed.rows.single.triggers, ['wisp paste']);
    expect(parsed.meta?.name, 'whispaste-woerterbuch');
    expect(parsed.meta?.created, isNotNull);
    await _teardown(tester);
  });
}

/// Presses the selection page's confirm button. Its centre lies outside the
/// test surface, so a pointer event cannot reach it; the button callback is
/// invoked directly instead.
void _pressConfirm(WidgetTester tester) {
  tester
      .widget<WpButton>(find.byKey(const ValueKey('vocabulary-import-confirm')))
      .onPressed!();
}
