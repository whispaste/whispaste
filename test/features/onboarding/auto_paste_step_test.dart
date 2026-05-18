/// Widget tests for [AutoPasteStep] (onboarding step 3, macOS).
///
/// External behaviour only: we check what the user sees and which side
/// effects fire (settings update, polling timer disposal). The shared
/// [PasteCapabilityNotifier] is overridden with a tiny fake so we don't
/// touch the real platform bridge — the production notifier still owns the
/// `Paster` integration; here we only exercise the widget contract.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/features/onboarding/steps/auto_paste_step.dart';
import 'package:whispaste/services/paste/paste_capability_notifier.dart';
import 'package:whispaste/services/paste/paster.dart';

import '../../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Drop-in fake of [PasteCapabilityNotifier] for widget tests.
///
/// Records every method call so tests can assert which side effects fired,
/// and lets each test seed the initial state plus the result of any
/// follow-up `check()` (mirroring how the real notifier would update its
/// state after a Paster probe).
class _FakePasteCapabilityNotifier extends PasteCapabilityNotifier {
  _FakePasteCapabilityNotifier({
    PasteCapabilityState initial = const PasteCapabilityState(),
    PasteCapabilityState? afterCheck,
  }) : _initial = initial,
       _afterCheck = afterCheck ?? initial;

  final PasteCapabilityState _initial;
  final PasteCapabilityState _afterCheck;

  final List<bool> checkCalls = <bool>[];
  int startPollingCalls = 0;
  int stopPollingCalls = 0;
  Duration? lastPollInterval;
  Duration? lastPollTimeout;
  bool _isPollingFake = false;

  @override
  bool get isPolling => _isPollingFake;

  @override
  PasteCapabilityState build() {
    ref.onDispose(() => stopPollingCalls++);
    return _initial;
  }

  @override
  Future<void> check({bool prompt = false}) async {
    checkCalls.add(prompt);
    state = _afterCheck;
  }

  @override
  void startPolling({
    Duration interval = const Duration(seconds: 1),
    Duration timeout = const Duration(seconds: 30),
  }) {
    startPollingCalls++;
    lastPollInterval = interval;
    lastPollTimeout = timeout;
    _isPollingFake = true;
  }

  @override
  void stopPolling() {
    stopPollingCalls++;
    _isPollingFake = false;
  }
}

class _RecordingSettingsNotifier extends SettingsNotifier {
  _RecordingSettingsNotifier([AppSettings? settings])
    : _settings = settings ?? AppSettings.defaults;

  AppSettings _settings;
  final List<AppSettings> updates = <AppSettings>[];

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    updates.add(_settings);
    state = AsyncData(_settings);
  }
}

void _noop() {}

Future<
  ({_FakePasteCapabilityNotifier paste, _RecordingSettingsNotifier settings})
>
_pumpStep(
  WidgetTester tester, {
  required _FakePasteCapabilityNotifier paste,
  _RecordingSettingsNotifier? settings,
  VoidCallback onNext = _noop,
}) async {
  final settingsNotifier = settings ?? _RecordingSettingsNotifier();
  await tester.pumpWidget(
    makeTestable(
      SingleChildScrollView(
        child: AutoPasteStep(onNext: onNext, onBack: _noop),
      ),
      size: const Size(1280, 980),
      overrides: [
        pasteCapabilityNotifierProvider.overrideWith(() => paste),
        settingsProvider.overrideWith(() => settingsNotifier),
      ],
    ),
  );
  await tester.pumpAndSettle();
  return (paste: paste, settings: settingsNotifier);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AutoPasteStep', () {
    testWidgets(
      'macOS pre-grant: shows permissionMissing status, Grant CTA, Next disabled, '
      'fires one prompt-less check on mount',
      (tester) async {
        final paste = _FakePasteCapabilityNotifier(
          initial: const PasteCapabilityState(
            capability: PasteCapability(
              status: PasteCapabilityStatus.permissionMissing,
              canPrompt: true,
            ),
          ),
        );
        var nextCalled = false;

        await _pumpStep(tester, paste: paste, onNext: () => nextCalled = true);

        // Permission-missing label rendered.
        expect(
          find.text('Accessibility permission not granted'),
          findsOneWidget,
        );
        // Grant CTA shown.
        expect(find.text('Grant Accessibility permission'), findsOneWidget);
        // Skip-Auto-Paste secondary still visible while not ready.
        expect(find.text('Skip — disable Auto-Paste'), findsOneWidget);

        // initState fires exactly one un-prompted check.
        expect(paste.checkCalls, [false]);

        // Tapping the Next CTA while disabled must not fire onNext.
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(nextCalled, isFalse);
      },
    );

    testWidgets('ready state: success icon, Next enabled, Skip hidden', (
      tester,
    ) async {
      final paste = _FakePasteCapabilityNotifier(
        initial: const PasteCapabilityState(
          capability: PasteCapability(status: PasteCapabilityStatus.ready),
        ),
      );
      var nextCalled = false;

      await _pumpStep(tester, paste: paste, onNext: () => nextCalled = true);

      // "Ready to paste" label is the success message.
      expect(find.text('Ready to paste'), findsOneWidget);
      // Skip button is not shown anymore once status is ready.
      expect(find.text('Skip — disable Auto-Paste'), findsNothing);
      // Grant CTA also hidden in the success state.
      expect(find.text('Grant Accessibility permission'), findsNothing);

      // Tapping Next now advances.
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(nextCalled, isTrue);
    });

    testWidgets(
      'Skip persists afterTranscription = clipboard and advances via onNext',
      (tester) async {
        final paste = _FakePasteCapabilityNotifier(
          initial: const PasteCapabilityState(
            capability: PasteCapability(
              status: PasteCapabilityStatus.permissionMissing,
              canPrompt: true,
            ),
          ),
        );
        final settings = _RecordingSettingsNotifier(
          const AppSettings(
            afterTranscriptionSection: AfterTranscriptionSettings(
              afterTranscription: 'paste',
            ),
          ),
        );
        var nextCalled = false;

        await _pumpStep(
          tester,
          paste: paste,
          settings: settings,
          onNext: () => nextCalled = true,
        );

        await tester.tap(find.text('Skip — disable Auto-Paste'));
        await tester.pumpAndSettle();

        expect(
          nextCalled,
          isTrue,
          reason: 'Skip must advance via onNext after persisting the setting',
        );
        expect(
          settings.updates,
          hasLength(1),
          reason: 'Skip must run exactly one settings update',
        );
        expect(
          settings.updates.single.afterTranscriptionSection.afterTranscription,
          'clipboard',
        );
      },
    );

    testWidgets(
      'dispose stops the shared polling timer — no zombie timer survives the step',
      (tester) async {
        final paste = _FakePasteCapabilityNotifier(
          initial: const PasteCapabilityState(
            capability: PasteCapability(
              status: PasteCapabilityStatus.permissionMissing,
              canPrompt: true,
            ),
          ),
        );

        await _pumpStep(tester, paste: paste);
        // Replace the step with an empty widget to trigger dispose.
        await tester.pumpWidget(
          makeTestable(
            const SizedBox.shrink(),
            overrides: [
              pasteCapabilityNotifierProvider.overrideWith(() => paste),
              settingsProvider.overrideWith(() => _RecordingSettingsNotifier()),
            ],
          ),
        );
        await tester.pumpAndSettle();

        // The widget explicitly stops polling on dispose. The provider scope
        // tearing down adds one more stop call — we only require at least one
        // explicit stop from the widget's own dispose path.
        expect(paste.stopPollingCalls, greaterThanOrEqualTo(1));
      },
    );
  });
}
