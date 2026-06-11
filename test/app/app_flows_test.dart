/// Regression backbone — cross-platform host-only widget + unit tests.
///
/// Covers:
///   1. Navigation smoke — all 6 pages render without exceptions via a
///      lightweight test shell that drives [activePageProvider].
///   2. Recording-pipeline → history — fake pipeline produces a DB entry and
///      sets the clipboard to the expected transcript.
///   3. Layout overflow guard — each page at 800 × 600 and 1920 × 1080
///      logical pixels; asserts no [RenderFlex] overflow fires.
///
/// History-page UI flows (search, filter, view mode) are intentionally NOT
/// duplicated here — they are already fully covered by
/// [test/features/history/history_page_test.dart].
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/app.dart'
    show activePageProvider, wpNavItems, wpPageWidgets;
import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/features/about/about_page.dart';
import 'package:whispaste/features/analytics/analytics_page.dart';
import 'package:whispaste/features/feedback/feedback_page.dart';
import 'package:whispaste/features/history/history_page.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';
import 'package:whispaste/features/settings/settings_page.dart';
import 'package:whispaste/services/audio_service.dart';
import 'package:whispaste/services/desktop_paste/desktop_paste_controller.dart';
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/path_service.dart' show sttDirOverride;
import 'package:whispaste/services/recording_orchestrator.dart';
import 'package:whispaste/services/stt/stt_bundle.dart';
import 'package:whispaste/features/history/data/providers.dart'
    show historyEntriesProvider, archivedEntriesProvider, trashEntriesProvider;
import 'package:whispaste/widgets/sidebar.dart';
import 'package:whispaste/widgets/sidebar_settings_button.dart';

import '../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Fakes (minimal inline copies — mirrors recording_orchestrator_test.dart)
// ---------------------------------------------------------------------------

class _FakeAudioService extends AudioServiceNotifier {
  String? wavPathToReturn;

  @override
  AudioStatus build() => const AudioStatus();

  @override
  Stream<double>? get amplitudeStream => null;

  @override
  Future<void> startRecording() async {
    if (state.isRecording) return;
    state = AudioStatus(
      captureState: AudioCaptureState.recording,
      filePath: wavPathToReturn,
    );
  }

  @override
  Future<String?> stopRecording() async {
    state = AudioStatus(filePath: wavPathToReturn);
    return wavPathToReturn;
  }

  @override
  Future<void> cleanupFile(String? path) async {}
}

class _FakeSttService extends SttServerStateNotifier {
  String transcriptToReturn = 'Fake transcript';

  @override
  SttStatus build() =>
      const SttStatus(serverState: SttServerState.ready, port: 9999);

  @override
  Future<void> ensureRunning() async {
    state = state.copyWith(serverState: SttServerState.ready);
  }

  @override
  Future<String> transcribeBytes(List<int> wavBytes, {String? language}) async {
    return transcriptToReturn;
  }

  @override
  Future<void> prewarm() async {}
}

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier([AppSettings? settings])
    : _settings = settings ?? _defaults;

  final AppSettings _settings;

  static const _defaults = AppSettings(
    afterTranscriptionSection: AfterTranscriptionSettings(
      afterTranscription: 'clipboard',
    ),
    onboarding: OnboardingSettings(onboardingCompleted: true),
    stt: SttSettings(model: 'whisper-small', language: 'English'),
  );

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

class _FakeModelDownloadNotifier extends ModelDownloadNotifier {
  @override
  ModelDownloadState build() => const ModelDownloadState(
    downloadedModels: {
      'whisper-small',
      'whisper-medium',
      'whisper-large-v3-turbo',
    },
    serverReady: true,
  );
}

class _FakeDesktopPasteController extends DesktopPasteController {
  int captureCalls = 0;
  int pasteCalls = 0;

  @override
  Future<bool> capturePasteTarget() async {
    captureCalls++;
    return true;
  }

  @override
  Future<NativePasteResult> pasteClipboard({required Duration delay}) async {
    pasteCalls++;
    return const NativePasteResult(status: NativePasteStatus.success);
  }

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
// Test navigation shell — lightweight substitute for the private _AppShell.
//
// Renders just sidebar + active page content, no title bar / FAB / tray.
// Driven by activePageProvider so tests can navigate without platform calls.
// ---------------------------------------------------------------------------

class _TestNavShell extends ConsumerWidget {
  // Intentionally no key parameter — test-only widget never keyed.
  // ignore: use_super_parameters
  const _TestNavShell() : super();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activePage = ref.watch(activePageProvider);
    final l10n = L10n.of(context);
    final navItems = wpNavItems(l10n);

    return Row(
      children: [
        WpSidebar(
          items: navItems,
          activeId: activePage,
          onItemTap: (id) => ref.read(activePageProvider.notifier).setPage(id),
          bottomItems: [
            WpSidebarSettingsButton(
              isActive: activePage == 'settings',
              onTap: () =>
                  ref.read(activePageProvider.notifier).setPage('settings'),
            ),
          ],
        ),
        Expanded(child: wpPageWidgets[activePage] ?? const SizedBox.shrink()),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Provider overrides that replace live Drift streams with static one-shot
/// streams.  Prevents Drift's [StreamQueryStore] from leaving pending timers
/// behind when the ProviderScope is disposed after a test — the same technique
/// used by [test/features/history/history_page_test.dart].
List<Object> _emptyHistoryStreamOverrides() => [
  historyEntriesProvider.overrideWith((ref) => Stream.value([])),
  archivedEntriesProvider.overrideWith((ref) => Stream.value([])),
  trashEntriesProvider.overrideWith((ref) => Stream.value([])),
];

/// Scratch dir for fake WAV files used in pipeline tests.
final _scratchDir = Directory('test${Platform.pathSeparator}.scratch_flows');

/// Creates a minimal valid RIFF/WAV file so the orchestrator has bytes to read.
File _createFakeWav(String name) {
  final bytes = List<int>.filled(364, 0);
  bytes[0] = 0x52; // R
  bytes[1] = 0x49; // I
  bytes[2] = 0x46; // F
  bytes[3] = 0x46; // F
  final file = File('${_scratchDir.path}${Platform.pathSeparator}$name');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes);
  return file;
}

/// Intercepts [FlutterError] during [action], collecting any overflow
/// messages without failing the test immediately.  Other errors are
/// re-dispatched to the original handler (they still fail the test).
Future<List<String>> _collectOverflowErrors(
  Future<void> Function() action,
) async {
  final overflowMessages = <String>[];
  final original = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    final msg = details.exception.toString();
    if (msg.contains('overflowed')) {
      overflowMessages.add(msg);
    } else {
      original?.call(details);
    }
  };
  try {
    await action();
  } finally {
    FlutterError.onError = original;
  }
  return overflowMessages;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // =========================================================================
  // 1. Navigation Smoke
  // =========================================================================

  group('Navigation smoke — all 6 pages render', () {
    late L10n l10n;

    setUpAll(() async {
      l10n = await L10n.delegate.load(const Locale('en'));
    });

    // Pages navigated via sidebar tooltip taps (5 main items + settings gear).
    // Each subtest navigates to the page, settles, then asserts no exception.
    //
    // All tests pass [_emptyHistoryStreamOverrides()] to replace live Drift
    // streams with one-shot [Stream.value([])] — prevents Drift's
    // StreamQueryStore from leaving pending timers after widget disposal.

    testWidgets('history page renders without exception', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const _TestNavShell(),
          locale: const Locale('en'),
          overrides: _emptyHistoryStreamOverrides(),
        ),
      );
      // history is the default page — just settle
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Characteristic widget: search field
      expect(find.byType(TextField), findsWidgets);
    });

    testWidgets('replacements page renders without exception', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const _TestNavShell(),
          locale: const Locale('en'),
          overrides: _emptyHistoryStreamOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(l10n.navReplacements));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('analytics page renders without exception', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const _TestNavShell(),
          locale: const Locale('en'),
          overrides: _emptyHistoryStreamOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(l10n.navAnalytics));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('about page renders without exception', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const _TestNavShell(),
          locale: const Locale('en'),
          overrides: _emptyHistoryStreamOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(l10n.navAbout));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('feedback page renders without exception', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const _TestNavShell(),
          locale: const Locale('en'),
          overrides: _emptyHistoryStreamOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(l10n.navFeedback));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('settings page renders without exception', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const _TestNavShell(),
          locale: const Locale('en'),
          overrides: _emptyHistoryStreamOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(l10n.navSettings));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('back-navigation: settings → history → analytics', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const _TestNavShell(),
          locale: const Locale('en'),
          overrides: _emptyHistoryStreamOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to settings
      await tester.tap(find.byTooltip(l10n.navSettings));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Back to history
      await tester.tap(find.byTooltip(l10n.navHistory));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Then to analytics
      await tester.tap(find.byTooltip(l10n.navAnalytics));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  // =========================================================================
  // 2. Recording pipeline → history entry
  // =========================================================================

  group('Recording pipeline → history entry', () {
    late ProviderContainer container;
    late _FakeAudioService fakeAudio;
    late _FakeSttService fakeStt;
    late _FakeDesktopPasteController fakeDesktopPaste;
    late HistoryDatabase db;
    late File wavFile;
    String? clipboardText;

    setUp(() async {
      sttDirOverride = _scratchDir.path;

      wavFile = _createFakeWav(
        'flow_test_${DateTime.now().millisecondsSinceEpoch}.wav',
      );

      fakeAudio = _FakeAudioService()..wavPathToReturn = wavFile.absolute.path;
      fakeStt = _FakeSttService();
      fakeDesktopPaste = _FakeDesktopPasteController();
      db = HistoryDatabase.forTesting(NativeDatabase.memory());
      clipboardText = null;

      // Mock the platform clipboard channel.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            switch (call.method) {
              case 'Clipboard.setData':
                final args = Map<String, dynamic>.from(call.arguments as Map);
                clipboardText = args['text'] as String?;
                return null;
              case 'Clipboard.getData':
                if (clipboardText == null) return null;
                return <String, dynamic>{'text': clipboardText};
              default:
                return null;
            }
          });

      container = ProviderContainer(
        overrides: [
          historyDatabaseProvider.overrideWith((ref) {
            ref.onDispose(db.close);
            return db;
          }),
          audioServiceProvider.overrideWith(() => fakeAudio),
          localSttBundleProvider.overrideWith(() => fakeStt),
          settingsProvider.overrideWith(() => _FakeSettingsNotifier()),
          secureKeyStoreProvider.overrideWith((ref) => _FakeSecureKeyStore()),
          desktopPasteControllerProvider.overrideWith(
            (ref) => fakeDesktopPaste,
          ),
          modelDownloadProvider.overrideWith(_FakeModelDownloadNotifier.new),
        ],
      );

      await container.read(settingsProvider.future);
    });

    tearDown(() {
      sttDirOverride = null;
      container.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
      if (wavFile.existsSync()) {
        try {
          wavFile.deleteSync();
        } catch (_) {}
      }
    });

    tearDownAll(() {
      if (_scratchDir.existsSync()) {
        try {
          _scratchDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test(
      'stopRecording: transcript → DB entry + clipboard contains transcript',
      () async {
        const expectedTranscript = 'Hello WhisPaste pipeline test';
        fakeStt.transcriptToReturn = expectedTranscript;

        // Bypass preflight checks (filesystem lookups) by directly driving the
        // state machine to "recording", as done in recording_orchestrator_test.
        final orch = container.read(recordingOrchestratorProvider.notifier);
        await Future<void>.delayed(Duration.zero);

        container.read(recordingProvider.notifier).startRecording();
        expect(
          container.read(recordingProvider).phase,
          RecordingPhase.recording,
        );

        await orch.stopRecording();

        // State machine reached "done"
        final recState = container.read(recordingProvider);
        expect(recState.phase, RecordingPhase.done);
        expect(recState.transcript, expectedTranscript);

        // A history entry was persisted
        final entries = await db.allEntries();
        expect(entries, hasLength(1));
        expect(entries.first.content, expectedTranscript);
        expect(entries.first.isLocal, isTrue);
        expect(entries.first.source, 'dictation');

        // Clipboard action: transcript was written to clipboard
        expect(clipboardText, expectedTranscript);

        // Paste bridge was NOT called (action = clipboard only)
        expect(fakeDesktopPaste.pasteCalls, 0);
      },
    );

    test(
      'toggleRecording from idle: preflight mock → recording → done via toggle',
      () async {
        const expectedTranscript = 'Toggle flow result';
        fakeStt.transcriptToReturn = expectedTranscript;

        final orch = container.read(recordingOrchestratorProvider.notifier);
        await Future<void>.delayed(Duration.zero);

        // Drive to recording manually (skips filesystem preflight).
        container.read(recordingProvider.notifier).startRecording();
        expect(
          container.read(recordingProvider).phase,
          RecordingPhase.recording,
        );

        // toggleRecording while recording → calls stopRecording internally.
        await orch.toggleRecording();

        expect(container.read(recordingProvider).phase, RecordingPhase.done);
        expect(
          container.read(recordingProvider).transcript,
          expectedTranscript,
        );

        final entries = await db.allEntries();
        expect(entries, hasLength(1));
        expect(entries.first.content, expectedTranscript);
      },
    );
  });

  // =========================================================================
  // 3. Layout overflow guard
  // =========================================================================

  group('Layout overflow guard', () {
    // Two representative viewport sizes:
    //   • 800 × 600 — "narrow desktop" / small laptop
    //   • 1920 × 1080 — maximised desktop
    const narrowSize = Size(800, 600);
    const wideSize = Size(1920, 1080);

    final pages = <String, Widget>{
      'history': const HistoryPage(),
      'replacements': const ReplacementsPage(),
      'analytics': const AnalyticsPage(),
      'about': const AboutPage(),
      'feedback': const FeedbackPage(),
      'settings': const SettingsPage(),
    };

    // Parameterised helper: renders [page] at [size] and returns any
    // overflow messages that fired during layout.
    Future<List<String>> renderAndCollectOverflows(
      WidgetTester tester,
      Widget page,
      Size size,
    ) async {
      // Set the viewport to match so both RenderBox constraints and MediaQuery
      // agree on the available space.
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      late List<String> overflows;
      overflows = await _collectOverflowErrors(() async {
        await tester.pumpWidget(
          makeTestable(
            page,
            size: size,
            locale: const Locale('en'),
            overrides: _emptyHistoryStreamOverrides(),
          ),
        );
        await tester.pumpAndSettle();
      });

      return overflows;
    }

    for (final entry in pages.entries) {
      final pageId = entry.key;
      final pageWidget = entry.value;

      testWidgets('$pageId — no overflow at 800×600', (tester) async {
        final overflows = await renderAndCollectOverflows(
          tester,
          pageWidget,
          narrowSize,
        );
        expect(
          overflows,
          isEmpty,
          reason:
              '$pageId overflowed at ${narrowSize.width}×${narrowSize.height}',
        );
      });

      testWidgets('$pageId — no overflow at 1920×1080', (tester) async {
        final overflows = await renderAndCollectOverflows(
          tester,
          pageWidget,
          wideSize,
        );
        expect(
          overflows,
          isEmpty,
          reason: '$pageId overflowed at ${wideSize.width}×${wideSize.height}',
        );
      });
    }
  });
}
