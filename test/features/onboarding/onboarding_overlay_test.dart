/// Widget tests for the [OnboardingOverlay] shell.
///
/// The flow is seven steps on macOS/Windows and six on Linux — the Auto-Paste
/// page is omitted from the sequence where it cannot apply. Every test that
/// walks pages therefore pins [debugDefaultTargetPlatformOverride] explicitly
/// and derives the expected count from [buildOnboardingStepIds]; without that
/// the suite would silently depend on the host it runs on and the Linux path
/// would never actually be exercised. Covered here:
///  - the step counter reflects the per-platform total, and Linux never
///    mounts [AutoPasteStep] anywhere in the flow;
///  - the shell-owned navigation row carries exactly two actions (Back +
///    Next) and no skip affordance, and the disabled first-page Back button
///    is visibly disabled;
///  - overlay dispose stops both shared pollers (paste capability + mic
///    permission) — no zombie timer survives a window close;
///  - leaving page 1 auto-fires the mic request exactly when the user never
///    triggered it themselves (status still `unknown`) — and never otherwise;
///  - every page fits the fixed onboarding window (1100×720,
///    [kOnboardingWindowSize]) without scrolling, in every locale —
///    including the two tall branches (hotkey conflict, model download
///    error);
///  - the layout renders in every supported UI language (list read from
///    [L10n.supportedLocales], never hard-coded) and mirrors fully in RTL;
///  - the layout survives a window *below* the size the app enforces (800×550;
///    the real floor is `WpLayout.minWindowHeight`, 800×628) and an enlarged
///    system text scale without overflow errors.
library;

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderShiftedBox;
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:intl/intl.dart' show Bidi;
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/platform/desktop_window_geometry.dart'
    show kOnboardingWindowSize;
import 'package:whispaste/features/onboarding/onboarding_overlay.dart';
import 'package:whispaste/features/onboarding/steps/autostart_toggle.dart';
import 'package:whispaste/features/onboarding/steps/mic_permission_chip.dart';
import 'package:whispaste/features/onboarding/steps/model_step.dart';
import 'package:whispaste/features/onboarding/steps/onboarding_headings.dart';
import 'package:whispaste/features/onboarding/steps/onboarding_page_fill.dart';
import 'package:whispaste/features/onboarding/steps/test_recording_step.dart'
    show kTestRecordingStepMicBypassButtonKey;
import 'package:whispaste/features/onboarding/steps/trigger_step.dart';
import 'package:whispaste/features/settings/settings_widgets.dart'
    show SettingRow;
import 'package:whispaste/features/onboarding/steps/auto_paste_step.dart';
import 'package:whispaste/widgets/brand_wordmark.dart';
import 'package:whispaste/services/hotkey_service.dart';
import 'package:whispaste/services/keyboard_up_monitor.dart';
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/desktop_paste/desktop_paste_controller.dart';
import 'package:whispaste/services/paste/paste_capability_notifier.dart';
import 'package:whispaste/services/paste/paster.dart';
import 'package:whispaste/services/permissions/mic_permission_notifier.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_download_service.dart';
import 'package:whispaste/widgets/wp_button.dart';
import 'package:whispaste/widgets/wp_hero_button.dart';

import '../../fixtures/test_helpers.dart';

late L10n l10n;

/// Total number of steps for [platform] — read from the production sequence
/// builder, never hard-coded: the count is platform-dependent now, and a
/// literal here would go stale the next time the flow changes.
int _totalSteps(TargetPlatform platform) => buildOnboardingStepIds(
  platform: platform,
  // Matches `kAutoPasteSupported`, which is a compile-time const the tests
  // cannot override.
  autoPasteSupported: true,
).length;

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier([AppSettings? settings])
    : _settings = settings ?? AppSettings.defaults;

  AppSettings _settings;

  /// Read-back for tests that need to assert what the overlay persisted
  /// (e.g. that the legacy-flow migration did or didn't stamp a new value).
  AppSettings get current => _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    state = AsyncData(_settings);
  }
}

/// Minimal recording fake — counts [stopPolling] calls so the overlay
/// disposal test can verify the defensive cleanup fires.
class _RecordingPasteCapabilityNotifier extends PasteCapabilityNotifier {
  int stopPollingCalls = 0;

  @override
  PasteCapabilityState build() => const PasteCapabilityState();

  @override
  void stopPolling() {
    stopPollingCalls++;
  }
}

/// Seeds the Auto-Paste troubleshoot branch (needsRestart == true — missing
/// + sent-to-OS-grant-flow + poll timed out) and answers `repair()` with the
/// "nothing to clear" result. That combination renders the tallest
/// Auto-Paste state: Skip + Repair + the result banner's own extra Restart
/// button, all stacked at once — see [_RepairResultBanner]'s `nothingCleared`
/// branch.
///
/// `check()` re-asserts the seeded state (mirroring
/// `_FakePasteCapabilityNotifier` in auto_paste_step_test.dart): a
/// successful repair chains into `requestGrant()`, which calls
/// `check(prompt: true)` and would otherwise leave `pollingPhase` at
/// `awaitingGrant` — flipping the phase to `waiting` and hiding the very
/// banner this fake exists to keep on screen. `startPolling`/`stopPolling`
/// are no-ops so the chain never touches the real platform bridge.
class _TroubleshootPasteCapabilityNotifier extends PasteCapabilityNotifier {
  static const _troubleshootState = PasteCapabilityState(
    capability: PasteCapability(
      status: PasteCapabilityStatus.permissionMissing,
      canPrompt: true,
    ),
    sentToOsGrantFlow: true,
    pollingPhase: PollingPhase.timedOut,
  );

  @override
  PasteCapabilityState build() {
    // The troubleshoot branch this fake exists to hold on screen is
    // cached-probe (Mac App Store) only — on the live-probe Developer-ID
    // build `requiredAction` never resolves to `restart`, so the branch has
    // no restart button to measure. See [PasteCapabilityNotifier
    // .usesCachedPermissionProbe].
    usesCachedPermissionProbe = true;
    return _troubleshootState;
  }

  @override
  Future<void> check({bool prompt = false}) async {
    state = _troubleshootState;
  }

  @override
  void startPolling({
    Duration interval = const Duration(seconds: 1),
    Duration timeout = const Duration(seconds: 30),
  }) {}

  @override
  void stopPolling() {}

  @override
  Future<TccRepairResult> repair() async =>
      const TccRepairResult(accessibilityCleared: 0, appleEventsCleared: 0);
}

/// Seeds one Auto-Paste phase and holds it against the step's on-mount
/// `check()`. Exists because the fold matrix below pumps the overlay with no
/// capability seeded at all, which resolves to `checking` — so the two phases
/// that actually carry content (`intro`, the first-run state with the Grant
/// CTA, and `waiting`, which carries the multi-line "tick the box" hint) were
/// measured at no text scale whatsoever while the page's blocks were being
/// re-cut. That is the gap this fake closes; [PollingPhase.awaitingGrant]
/// keeps `needsRestart` false, so `waiting` cannot silently degrade into the
/// troubleshoot branch and measure the wrong thing.
class _PhasePasteCapabilityNotifier extends PasteCapabilityNotifier {
  _PhasePasteCapabilityNotifier({
    required this.pollingPhase,
    this.status = PasteCapabilityStatus.permissionMissing,
  });

  final PollingPhase pollingPhase;

  /// `_WindowsBody` keys only on this, so the same fake seeds both Windows
  /// branches: `permissionMissing` is the UIPI edge, `ready` the 99 % case.
  final PasteCapabilityStatus status;

  PasteCapabilityState get _seeded => PasteCapabilityState(
    capability: PasteCapability(status: status, canPrompt: true),
    sentToOsGrantFlow: pollingPhase == PollingPhase.awaitingGrant,
    pollingPhase: pollingPhase,
  );

  @override
  PasteCapabilityState build() => _seeded;

  @override
  Future<void> check({bool prompt = false}) async {
    state = _seeded;
  }

  @override
  void startPolling({
    Duration interval = const Duration(seconds: 1),
    Duration timeout = const Duration(seconds: 30),
  }) {}

  @override
  void stopPolling() {}
}

/// Same shape for the microphone permission poller — additionally pins the
/// status and records [request] calls so the leave-page-1 hook is provable
/// without any platform involvement.
class _RecordingMicPermissionNotifier extends MicPermissionNotifier {
  _RecordingMicPermissionNotifier([
    this.initialStatus = MicPermissionStatus.unknown,
  ]);

  final MicPermissionStatus initialStatus;
  int stopPollingCalls = 0;
  int requestCalls = 0;

  @override
  MicPermissionState build() => MicPermissionState(status: initialStatus);

  @override
  Future<bool> check() async => initialStatus == MicPermissionStatus.granted;

  @override
  Future<bool> request() async {
    requestCalls++;
    return false;
  }

  @override
  void stopPolling() {
    stopPollingCalls++;
  }
}

/// Inert platform truth for tests that run the *real* notifier — the mic
/// chip on the last page checks on mount, and leaving page 1 may request;
/// neither call may ever reach the real audio plugin in a widget test.
class _FakeMicPermissionChecker implements MicPermissionChecker {
  @override
  Future<bool> check({required bool request}) async => false;
}

/// Pins the hotkey registration status for the conflict-branch fit test.
class _FakeHotkeyStatusController extends HotkeyRegistrationStatusController {
  _FakeHotkeyStatusController(this._initial);

  final HotkeyRegistrationStatus _initial;

  @override
  HotkeyRegistrationStatus build() => _initial;
}

class _FakeRegistrar implements HotKeyRegistrar {
  const _FakeRegistrar();

  @override
  bool get supportsKeyUp => true;

  @override
  Future<void> register(
    HotKey hotKey, {
    HotKeyHandler? keyDownHandler,
    HotKeyHandler? keyUpHandler,
  }) async {}

  @override
  Future<void> unregister(HotKey hotKey) async {}
}

/// [HotkeyService] whose `build()` never runs the real startup registration —
/// that would asynchronously overwrite the status the conflict test seeds
/// (same fake as `trigger_step_test.dart`).
class _NoopHotkeyService extends HotkeyService {
  @override
  void build() {}
}

HotkeyService _noopHotkeyService() {
  final svc = _NoopHotkeyService();
  svc.injectRegistrar(const _FakeRegistrar());
  svc.injectMonitor(NoopKeyboardUpMonitor());
  return svc;
}

/// Both download providers pinned to a failed download, so whichever engine
/// the locale's recommendation selects renders the error branch.
class _StaticWhisperDownload extends ModelDownloadNotifier {
  _StaticWhisperDownload(this._initial);

  final ModelDownloadState _initial;

  @override
  ModelDownloadState build() => _initial;
}

class _StaticParakeetDownload extends ParakeetDownloadNotifier {
  _StaticParakeetDownload(this._initial);

  final ParakeetDownloadState _initial;

  @override
  ParakeetDownloadState build() => _initial;
}

Future<void> _tapNext(WidgetTester tester) async {
  await tester.tap(find.byKey(kOnboardingNextButtonKey));
  await tester.pumpAndSettle();
}

Future<void> _pumpOverlay(
  WidgetTester tester, {
  PasteCapabilityNotifier? paste,
  _RecordingMicPermissionNotifier? mic,
  _FakeSettingsNotifier? settings,
  Size size = const Size(1280, 980),
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
  HotkeyRegistrationStatus? hotkeyStatus,
  bool downloadFailed = false,
  // `false` for states that animate forever (the mic chip's `requesting`
  // spinner) — pumpAndSettle would time out on those.
  bool settle = true,
}) async {
  const downloadError = 'Verbindung unterbrochen (HTTP 503)';
  await tester.pumpWidget(
    makeTestable(
      MediaQuery(
        data: MediaQueryData(size: size, textScaler: textScaler),
        child: const OnboardingOverlay(),
      ),
      size: size,
      locale: locale,
      overrides: [
        settingsProvider.overrideWith(
          () => settings ?? _FakeSettingsNotifier(),
        ),
        micPermissionCheckerProvider.overrideWithValue(
          _FakeMicPermissionChecker(),
        ),
        if (paste != null)
          pasteCapabilityNotifierProvider.overrideWith(() => paste),
        if (mic != null) micPermissionNotifierProvider.overrideWith(() => mic),
        if (hotkeyStatus != null) ...[
          hotkeyRegistrationStatusProvider.overrideWith(
            () => _FakeHotkeyStatusController(hotkeyStatus),
          ),
          hotkeyServiceProvider.overrideWith(_noopHotkeyService),
        ],
        // Always statically overridden — never the real notifier. Its
        // initial disk scan hits real `Directory`/`File` calls, which
        // `ModelStep._detectHardware()` now awaits before its first
        // `setState` (see `awaitInitialScan()`); those real calls never
        // resolve under `testWidgets`, hanging every test that reaches
        // ModelStep until `pumpAndSettle` times out.
        modelDownloadProvider.overrideWith(
          () => _StaticWhisperDownload(
            downloadFailed
                ? const ModelDownloadState(
                    phase: DownloadPhase.error,
                    errorMessage: downloadError,
                  )
                : const ModelDownloadState(),
          ),
        ),
        parakeetDownloadProvider.overrideWith(
          () => _StaticParakeetDownload(
            downloadFailed
                ? const ParakeetDownloadState(
                    phase: ParakeetDownloadPhase.error,
                    errorMessage: downloadError,
                  )
                : const ParakeetDownloadState(),
          ),
        ),
      ],
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
    // Load the real bundled UI font (Inter) instead of the Ahem test font.
    // The fixed-window fit assertions below measure whether a page fits
    // 1100×720 without scrolling — with Ahem every glyph is a full em
    // square, roughly doubling text width vs. Inter, which makes captions
    // wrap to lines that never occur in the real app. Real metrics keep the
    // gate meaningful.
    final fontLoader = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Inter-Medium.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Inter-SemiBold.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Inter-Bold.ttf'));
    await fontLoader.load();
  });

  // ── Step sequence: seven steps, six on Linux ────────────────────────────

  group('OnboardingOverlay step sequence', () {
    for (final platform in [
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      final total = _totalSteps(platform);
      testWidgets(
        'on $platform: the counter reflects $total total, and the first page '
        'never mounts AutoPasteStep',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          try {
            await _pumpOverlay(tester);

            expect(find.text(l10n.onboardingStepOf(1, total)), findsOneWidget);
            expect(find.byType(AutoPasteStep), findsNothing);
          } finally {
            // Reset before the framework's foundation-vars-unset assertion.
            debugDefaultTargetPlatformOverride = null;
          }
        },
      );
    }

    testWidgets(
      'on Linux the Auto-Paste page is absent from the whole flow — walking '
      'every page never mounts it, and the flow is one page shorter',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        try {
          await _pumpOverlay(tester);
          final total = _totalSteps(TargetPlatform.linux);
          expect(total, 6);

          for (var page = 2; page <= total; page++) {
            await _tapNext(tester);
            expect(
              find.byType(AutoPasteStep),
              findsNothing,
              reason: 'AutoPasteStep must never mount on Linux (page $page)',
            );
          }
          // The last page is Try & Go, i.e. the Next button became the
          // completion CTA — proof the flow really ended one page earlier
          // rather than just hiding the page's content.
          expect(
            find.text(l10n.onboardingStepOf(total, total)),
            findsOneWidget,
          );
          final next = tester.widget<WpHeroButton>(
            find.byKey(kOnboardingNextButtonKey),
          );
          expect(next.label, l10n.onboardingStartUsing);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'on macOS the Auto-Paste page is a page of its own, between Appearance '
      'and Try & Go',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          await _pumpOverlay(tester);
          for (var page = 2; page <= 5; page++) {
            await _tapNext(tester); // → 5: Appearance
          }
          expect(find.byKey(kOnboardingAutostartToggleKey), findsOneWidget);
          expect(find.byType(AutoPasteStep), findsNothing);

          await _tapNext(tester); // → 6: Auto-Paste
          expect(find.byType(AutoPasteStep), findsOneWidget);
          expect(
            find.byKey(kOnboardingAutostartToggleKey),
            findsNothing,
            reason: 'the autostart toggle stayed on the Appearance page',
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  });

  // ── Page composition after the split ────────────────────────────────────

  group('OnboardingOverlay — page composition', () {
    testWidgets(
      'Model and Hotkey are separate pages, and the Appearance page carries '
      'the autostart toggle',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          await _pumpOverlay(tester);
          await _tapNext(tester); // → 2: Privacy
          await _tapNext(tester); // → 3: Model

          expect(find.byKey(kModelStepEngineParakeetCardKey), findsOneWidget);
          expect(
            find.byKey(kTriggerStepChangeHotkeyKey),
            findsNothing,
            reason: 'the hotkey block has its own page now',
          );
          // The page heading took over the block titles, so the model page's
          // title is on screen exactly once — not twice at two sizes.
          expect(find.text(l10n.onboardingModelTitle), findsOneWidget);

          await _tapNext(tester); // → 4: Hotkey
          expect(find.byKey(kTriggerStepChangeHotkeyKey), findsOneWidget);
          expect(find.byKey(kModelStepEngineParakeetCardKey), findsNothing);
          expect(find.text(l10n.onboardingTriggerTitle), findsOneWidget);

          await _tapNext(tester); // → 5: Appearance
          expect(
            find.byKey(kOnboardingAutostartToggleKey),
            findsOneWidget,
            reason: 'the autostart toggle moved onto the Appearance page',
          );
          expect(find.text(l10n.onboardingAppearancePageTitle), findsOneWidget);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'the Auto-Paste page shows its title exactly once — the macOS and '
      'Windows bodies both handed the heading to the page',
      (tester) async {
        for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
          debugDefaultTargetPlatformOverride = platform;
          try {
            await _pumpOverlay(tester);
            for (var page = 2; page <= 6; page++) {
              await _tapNext(tester);
            }
            expect(
              find.byType(AutoPasteStep),
              findsOneWidget,
              reason: '$platform',
            );
            expect(
              find.text(l10n.onboardingPasteTitle),
              findsOneWidget,
              reason: 'title rendered twice (or not at all) on $platform',
            );
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        }
      },
    );
  });

  // ── Shell-owned navigation: exactly two actions, no skip ────────────────
  //
  // The generic "Skip this step" button was removed with the merged flow
  // (it did the same as Next on every page). The nav row must carry exactly
  // two navigation actions; the full walkthrough proof lives in
  // onboarding_flow_test.dart, this one pins the shape.

  group('OnboardingOverlay — navigation row', () {
    testWidgets(
      'first page: nav row carries exactly two actions (Back disabled + '
      'Next), and the generic skip button is gone (AutoPasteStep keeps its '
      'own intentional Skip — a mode choice, not navigation)',
      (tester) async {
        await _pumpOverlay(tester);

        final navRow = find.byKey(kOnboardingNavRowKey);
        expect(navRow, findsOneWidget);

        // Exactly two tappable navigation actions inside the row.
        final backButtons = find.descendant(
          of: navRow,
          matching: find.byType(WpButton),
        );
        final accentButtons = find.descendant(
          of: navRow,
          matching: find.byType(WpHeroButton),
        );
        expect(
          tester.widgetList(backButtons).length +
              tester.widgetList(accentButtons).length,
          2,
          reason: 'The nav row must carry exactly two navigation actions.',
        );

        // Back exists but is disabled on the first page.
        final back = tester.widget<WpButton>(
          find.byKey(kOnboardingBackButtonKey),
        );
        expect(back.onPressed, isNull);

        // Next is enabled.
        final next = tester.widget<WpHeroButton>(
          find.byKey(kOnboardingNextButtonKey),
        );
        expect(next.onPressed, isNotNull);
      },
    );

    testWidgets(
      'the disabled first-page Back button is visibly disabled: its label '
      'renders in a different colour than on page 2, where it works. It used '
      'to carry an explicit TextStyle(color:) that beat Material\'s '
      'disabledForegroundColor, so "off" looked exactly like "on"',
      (tester) async {
        await _pumpOverlay(tester);

        Color labelColour() {
          final text = tester.widget<Text>(
            find.descendant(
              of: find.byKey(kOnboardingBackButtonKey),
              matching: find.byType(Text),
            ),
          );
          final style = text.style;
          // WpButton resolves disabled as a token swap inside build(), not
          // as a WidgetState-driven overlay — the ghost variant's inner
          // TextButton already carries the right foregroundColor regardless
          // of state, so resolve({}) here is a no-op that still reads back
          // the value the button actually paints with.
          final button = tester.widget<TextButton>(
            find.descendant(
              of: find.byKey(kOnboardingBackButtonKey),
              matching: find.byType(TextButton),
            ),
          );
          return style?.color ??
              button.style!.foregroundColor!.resolve(<WidgetState>{})!;
        }

        final disabledColour = labelColour();
        await _tapNext(tester);
        expect(
          tester
              .widget<WpButton>(find.byKey(kOnboardingBackButtonKey))
              .onPressed,
          isNotNull,
          reason: 'page 2 Back must be enabled — otherwise this proves nothing',
        );
        final enabledColour = labelColour();

        expect(
          disabledColour,
          isNot(enabledColour),
          reason:
              'A disabled Back button that paints in the enabled colour reads '
              'as tappable and silently does nothing.',
        );
      },
    );

    testWidgets(
      'pages 2–4 each carry exactly two navigation actions too — the shell '
      'row is the only navigation surface, not just on page 1',
      (tester) async {
        await _pumpOverlay(tester);
        for (var page = 0; page < 3; page++) {
          await _tapNext(tester);
          final navRow = find.byKey(kOnboardingNavRowKey);
          final backButtons = find.descendant(
            of: navRow,
            matching: find.byType(WpButton),
          );
          final accentButtons = find.descendant(
            of: navRow,
            matching: find.byType(WpHeroButton),
          );
          expect(
            tester.widgetList(backButtons).length +
                tester.widgetList(accentButtons).length,
            2,
            reason: 'page ${page + 2} nav row must carry exactly two actions',
          );
        }
      },
    );
  });

  // ── Supported languages + RTL mirroring ─────────────────────────────────
  //
  // The language list is read from L10n.supportedLocales — never hard-coded
  // — so a newly added locale is automatically covered.

  group('OnboardingOverlay — all supported locales incl. RTL', () {
    testWidgets(
      'renders the first page in every supported locale without errors; '
      'RTL locales fully mirror the shell-owned nav row',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          final total = _totalSteps(TargetPlatform.macOS);
          for (final locale in L10n.supportedLocales) {
            final localized = await L10n.delegate.load(locale);
            await _pumpOverlay(tester, locale: locale);

            expect(
              find.text(localized.onboardingStepOf(1, total)),
              findsOneWidget,
              reason: 'Step counter must render in ${locale.languageCode}',
            );

            final backCenter = tester.getCenter(
              find.byKey(kOnboardingBackButtonKey),
            );
            final nextCenter = tester.getCenter(
              find.byKey(kOnboardingNextButtonKey),
            );
            final isRtl = Bidi.isRtlLanguage(locale.languageCode);
            if (isRtl) {
              expect(
                backCenter.dx,
                greaterThan(nextCenter.dx),
                reason:
                    'In RTL (${locale.languageCode}) the Back action must sit '
                    'on the right of Next — the edge-to-edge layout has to '
                    'mirror, it no longer mirrors for free like the old '
                    'centered card',
              );
            } else {
              expect(
                backCenter.dx,
                lessThan(nextCenter.dx),
                reason:
                    'In LTR (${locale.languageCode}) Back must sit left of '
                    'Next',
              );
            }

            expect(
              tester.takeException(),
              isNull,
              reason: 'No layout exception in ${locale.languageCode}',
            );

            // The nav row mirrors "for free" via ambient Directionality on any
            // plain Row — proving nothing about *our* layout. The real risk
            // the ticket calls out ("nebeneinander liegende Blöcke und
            // Status-Chips") lives on the pages with side-by-side blocks: the
            // engine cards and the Auto-Paste status chip. Walk the whole flow
            // and confirm no overflow/exception under long Hebrew/German
            // strings.
            for (var page = 2; page <= total; page++) {
              await _tapNext(tester);
              expect(
                tester.takeException(),
                isNull,
                reason:
                    'No layout exception on page $page in '
                    '${locale.languageCode}',
              );
            }

            // Clean teardown between locales.
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
          }
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  });

  // ── Minimum window size + enlarged system text ──────────────────────────

  group('OnboardingOverlay — small window & accessibility text scale', () {
    // `_pumpOverlay`'s `size` only feeds an inner MediaQuery — it never
    // constrains the actual render surface, so `makeTestable`'s default
    // (1280×800) stays the real layout constraint underneath it. Setting
    // `tester.view.physicalSize` is what genuinely shrinks the surface —
    // same pattern as `test/core/design/responsive_overflow_test.dart`.
    //
    // 800×550 is one notch *below* the window minimum the app enforces
    // (`WpLayout.minWindowHeight`, 800×628) — kept there on purpose after the
    // minimum was raised: a floor that is harsher than reality stays a valid
    // floor, and the onboarding overlay covers the whole window anyway, so
    // none of the chrome that sets that minimum is on screen here.
    void shrinkToMinimumWindow(WidgetTester tester) {
      tester.view.physicalSize = const Size(800, 550);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets(
      'every page lays out at the window minimum size (800×550) without '
      'overflow — content stacks/scrolls instead of clipping',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          final total = _totalSteps(TargetPlatform.macOS);
          shrinkToMinimumWindow(tester);
          await _pumpOverlay(tester, size: const Size(800, 550));
          expect(find.text(l10n.onboardingStepOf(1, total)), findsOneWidget);
          expect(tester.takeException(), isNull);
          for (var page = 2; page <= total; page++) {
            await _tapNext(tester);
            expect(
              tester.takeException(),
              isNull,
              reason: 'No overflow on page $page at 800×550',
            );
          }
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets('every page lays out at minimum size with enlarged system text '
        '(textScaler 1.5, matching sidebar_large_text_test.dart) without '
        'overflow', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final total = _totalSteps(TargetPlatform.macOS);
        shrinkToMinimumWindow(tester);
        await _pumpOverlay(
          tester,
          size: const Size(800, 550),
          textScaler: const TextScaler.linear(1.5),
        );
        expect(tester.takeException(), isNull);
        for (var page = 2; page <= total; page++) {
          await _tapNext(tester);
          expect(
            tester.takeException(),
            isNull,
            reason: 'No overflow on page $page at 800×550, textScaler 1.5',
          );
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  // ── Leaving page 1 — automatic microphone request ───────────────────────
  //
  // PRD: the OS permission dialog fires when *leaving* page 1 (never on
  // appear), and only when the user hasn't triggered it themselves. `unknown`
  // is the proof of that — request() has never run this process, so the
  // one-time dialog budget is guaranteed unspent.

  group('OnboardingOverlay — mic request on leaving page 1', () {
    testWidgets(
      'status unknown: tapping Next on page 1 fires request() exactly once',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          final mic = _RecordingMicPermissionNotifier();
          await _pumpOverlay(tester, mic: mic);

          await _tapNext(tester);

          expect(
            find.text(
              l10n.onboardingStepOf(2, _totalSteps(TargetPlatform.macOS)),
            ),
            findsOneWidget,
          );
          expect(mic.requestCalls, 1);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    for (final status in [
      MicPermissionStatus.requesting,
      MicPermissionStatus.granted,
      MicPermissionStatus.denied,
    ]) {
      testWidgets(
        'status $status: leaving page 1 fires nothing — something already '
        'resolved the permission (the startup gate, or the chip on the last '
        'page during an earlier pass), so a second call is pointless',
        (tester) async {
          final mic = _RecordingMicPermissionNotifier(status);
          await _pumpOverlay(tester, mic: mic);

          await _tapNext(tester);

          expect(mic.requestCalls, 0);
        },
      );
    }

    testWidgets(
      'page 1 shows no microphone affordance at all — the request is silent '
      'and the visible status lives on the last page, next to the recording '
      'that needs it',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          final total = _totalSteps(TargetPlatform.macOS);
          await _pumpOverlay(tester, mic: _RecordingMicPermissionNotifier());

          expect(find.byType(MicPermissionChip), findsNothing);

          for (var page = 2; page <= total; page++) {
            await _tapNext(tester);
            expect(
              find.byType(MicPermissionChip),
              page == total ? findsOneWidget : findsNothing,
              reason: 'unexpected chip presence on page $page',
            );
          }
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets('leaving any later page never fires request()', (tester) async {
      final mic = _RecordingMicPermissionNotifier();
      await _pumpOverlay(tester, mic: mic);

      await _tapNext(tester); // page 1 → 2 (fires, budget spent conceptually)
      await _tapNext(tester); // page 2 → 3
      await _tapNext(tester); // page 3 → 4

      expect(
        mic.requestCalls,
        1,
        reason: 'Only the page-1 exit may auto-request.',
      );
    });
  });

  // ── Fixed onboarding window size — no page may scroll ───────────────────
  //
  // The onboarding window is pinned to 1100×720 (kOnboardingWindowSize). At
  // the system text scale that leaves a 579-px scroll viewport and a 539-px
  // content area for the page itself (the viewport minus the scroll view's
  // 2 × `lg` vertical padding). Neither number is constant across text
  // scales, because the footer grows with the text:
  //
  //   viewport   579 px @ 1.0    573 px @ 1.15    567 px @ 1.3
  //
  // and the page's own area is 40 px less in each case. Every page has to fit
  // inside it: there is no way for the user to make the window bigger, so a
  // page that scrolls is a page whose bottom half is easy to miss entirely.
  //
  // It was a flat 551 px until the footer stack put the dots and the "step X
  // of Y" counter on one line and `_kOnboardingBottomGap` went `xxl` → `lg`.
  // That is where the +28 px came from, and it is why every number below is
  // larger than the set this table used to carry while the pages themselves
  // grew *less* crowded, not more — the viewport moved under them.
  //
  // Measured with real Inter metrics (see setUpAll — with the square-glyph
  // test font the numbers are meaningless), macOS unless noted, the dictation
  // language seeded to the UI locale, and the GPU-fallback notice asserted
  // present on the model page, i.e. the worst case. Natural content height
  // against the viewport, German / English / Hebrew.
  //
  // These are *natural* heights: what the page's blocks come to with every
  // gap at its minimum. The leftover height trails below the body rather than
  // being split around it ([OnboardingPageBody] is unconditionally top-
  // aligned now; it used to be centred, with sparse pages opting out per call
  // site), so a page shorter than the viewport still occupies the full
  // viewport whatever these numbers say — they are still the ones that decide
  // whether a page fits at all, and the ones to re-measure before adding to a
  // page.
  //
  // ── Re-measured wholesale on 2026-08-10 (ticket 20, phase 6) ────────────
  //
  // One harness run, one day, the whole set — the rule the 2026-08-09
  // re-measurement wrote down, and the reason the density pass left this
  // table standing with a stale marker rather than patching the rows it
  // happened to touch. Everything moved: the footer lost a line (above), the
  // body is top-aligned, the reading measure dropped to 640 px, and pages 1,
  // 2, 4, 5 and 6 rebuilt their rows or their content. Treat the numbers as a
  // set; when you re-measure, re-measure all of them.
  //
  // Scale 1.0, macOS, against the 579-px viewport:
  //
  //   page 1  Welcome       517 / 517 / 517
  //   page 2  Privacy       307 / 307 / 307
  //   page 3  Model         434 / 413 / 438
  //   page 4  Hotkey        278 / 278 / 278   (still the sparsest page in the
  //                                            flow: two setting rows, and
  //                                            the ~60 % of trailing empty
  //                                            space under them is the
  //                                            documented correct outcome,
  //                                            see OnboardingPageBody)
  //   page 5  Appearance    390 / 390 / 390   (theme tiles + autostart row)
  //   page 6  Auto-Paste    301 / 301 / 301   (macOS/Windows only; one status
  //                                            card + why + skip, the shape
  //                                            every phase of the page now
  //                                            shares)
  //   page 7  Try & Go      483 / 467 / 467   (the flow's tallest nominal
  //                                            page, and the one the mic-
  //                                            bypass guard below watches)
  //
  // Linux runs the same pages 1–5 — identical page for page to the numbers
  // above — and ends on Try & Go as page 6, measured 443 / 427 / 427 there.
  //
  // ── The binding cases (scale 1.3, 567-px viewport) ─────────────────────
  //
  // 1.0 is not where this flow is decided any more. These are the rows a
  // change breaks first, and the only 1.3 numbers worth carrying here:
  //
  //   page 1  Welcome,  de        567 of 567    0 px — an exact fit
  //   page 7  Try & Go, de        563 of 567    4 px
  //   page 3  Model,    he        550 of 567   17 px
  //   page 1  Welcome,  en / he   543 of 567   24 px
  //   page 7  Try & Go, en / he   536 of 567   31 px
  //
  // Everything else keeps ≥ 46 px at 1.3. Page 1 in German is the tightest
  // case in the flow and it is a deliberate landing, not an accident: the one
  // post that separates German from the other two is beat 1's caption
  // wrapping to a third line. Anyone who needs slack there has 24 px in the
  // other locales to spend first.
  //
  // ── The three branch cases ─────────────────────────────────────────────
  //
  // German / Hebrew, the two locales the tests cover. This is the one part of
  // the table where the higher scales are not derivable from the 1.0 row,
  // because two of the three branches stop fitting:
  //
  //   page 4, confirmed hotkey conflict (warn box + full inline recorder).
  //   The branch the page split was for — on the merged Model & Hotkey page
  //   it came to 914 px against a 551-px viewport. It pays for the fit three
  //   ways: the heading drops its subtitle while a conflict is up, the gap
  //   under that heading is `sm` rather than [kOnboardingHeaderGap] (the
  //   flow's one deliberate deviation, declared at the call site), and the
  //   warn box is vertically tighter than it is wide.
  //     1.0    579 / 562     fits (German on exactly 0 px of slack)
  //     1.15   585 / 585     12 px past the fold, RenderFlex overflow in both
  //     1.3    636 / 615     69 / 48 px past it, overflow in Hebrew (German
  //                          scrolls instead of throwing at that scale)
  //   page 3, failed model download (error banner + retry button)
  //     1.0    491 / 495     fits
  //     1.15   542 / 527     fits
  //     1.3    576 / 605     9 / 38 px past the fold
  //   page 6, Auto-Paste troubleshoot (missing + sent-to-OS-grant-flow + poll
  //   timed out, Repair tapped and resolved to "nothing cleared" — skip +
  //   repair + the result banner's own restart button, the tallest state the
  //   page has)
  //     1.0    504 / 504     fits
  //     1.15   521 / 521     fits
  //     1.3    563 / 541     fits
  //
  // ⚠ OPEN FINDING — reported, not fixed (ticket 20, phase 6). The conflict
  // and download branches run past the fold above scale 1.0. No test is red:
  // both are covered at 1.0 only, because the fold matrix walks the nominal
  // flow and never enters either branch, and the troubleshoot branch is the
  // one that was extended to all three scales (and fixed there). What can be
  // said precisely, and what cannot:
  //
  //   * At 1.0 the conflict branch went from 17 px of slack (534 px against
  //     the old 551-px viewport) to 0 px in German. That tightening is this
  //     ticket's doing — the setting rows on that page grew, and the density
  //     pass records paying 3 px back in Hebrew for exactly that reason.
  //   * At 1.15 and 1.3 the origin is UNDETERMINED. No commit ever measured
  //     either branch above 1.0, so there is no baseline to have regressed
  //     from. These numbers are neither "newly broken" nor "pre-existing";
  //     they are newly *known*.
  //
  // Fixing it is layout work on two branch states and belongs in its own
  // ticket with its own visual sign-off. Adding a `foldRatchet` row instead
  // would be precisely the misuse that table forbids.
  //
  // Hebrew is the tightest on the model page for a reason worth keeping in
  // mind when re-measuring: the loop seeds the *dictation* language, and
  // Hebrew is not one of the languages the Parakeet engine covers, so its
  // card renders an extra "unsupported language" line that IntrinsicHeight
  // applies to both engine cards. Measuring with the default dictation
  // language would miss 24 px on that page.

  group('OnboardingOverlay — fixed window size (1100×720)', () {
    /// Height the page is given, the height it occupies, and the height it
    /// would occupy with every gap at its minimum. The page content
    /// shrink-wraps inside an [Align], so `maxScrollExtent` alone is always 0
    /// and proves nothing — the incoming constraint is what the content has
    /// to fit into.
    ///
    /// [natural] is what the table above lists, and on a page that fills the
    /// viewport ([OnboardingPageFill]) it is the only informative number:
    /// [content] is then the viewport height by construction. Subtracting the
    /// height the [OnboardingPageBody] left trailing under itself recovers it
    /// — that trailing space is the only height on the page that comes from
    /// leftover room rather than from content.
    ///
    /// NOTE: on a fill page these numbers alone cannot see an overflow —
    /// [IntrinsicHeight] pins the column to the offered height and the
    /// excess surfaces as a RenderFlex overflow *exception* instead. Every
    /// assertion below therefore checks `takeException()` too; that check is
    /// the load-bearing one, not the arithmetic.
    ({double available, double content, double natural}) measure(
      WidgetTester tester,
    ) {
      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      final available = tester
          .renderObject<RenderBox>(find.byType(SingleChildScrollView).first)
          .constraints
          .maxHeight;
      final content =
          scrollable.position.viewportDimension +
          scrollable.position.maxScrollExtent;
      // The leftover height trailing under the body — the only height on the
      // page that comes from spare room rather than from content.
      final distributed = tester
          .renderObjectList<RenderBox>(find.byType(OnboardingPageBody))
          .whereType<RenderShiftedBox>()
          .fold<double>(
            0,
            (sum, box) => sum + box.size.height - box.child!.size.height,
          );
      return (
        available: available,
        content: content,
        natural: content - distributed,
      );
    }

    void useFixedWindow(WidgetTester tester) {
      tester.view.physicalSize = kOnboardingWindowSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    void expectFits(
      WidgetTester tester,
      ({double available, double content, double natural}) m, {
      required String what,
      double allowed = 0,
    }) {
      expect(
        tester.takeException(),
        isNull,
        reason:
            '$what overflowed its page column. Its blocks (every gap at its '
            'minimum) come to ${m.natural} px against the ${m.available} px '
            'the fixed 1100x720 window offers.',
      );
      final over = m.content - m.available;
      expect(
        over,
        lessThanOrEqualTo(allowed),
        reason: allowed == 0
            ? '$what needs ${m.content} px of the ${m.available} px the fixed '
                  '1100x720 window offers — it would scroll. Its blocks alone '
                  'come to ${m.natural} px.'
            : '$what is a known-open case (see _foldRatchet) allowed to run '
                  '$allowed px past the fold, and it runs $over px past it. '
                  'If $over is the smaller number, lower the entry — that is '
                  'what the ratchet is for. If it is the larger one, this is '
                  'a regression.',
      );
    }

    // ── Text scale: 1.0 is not the interesting case ──────────────────────
    //
    // This guard ran at 1.0 only, and that is the gap the flow's one P0
    // finding fell through: on Try & Go the microphone-bypass button — the
    // only way past that page without a working microphone — was clipped at
    // scale 1.15 and entirely below the fold at 1.3, while every test here
    // stayed green. The page did not overflow, it *scrolled*, and a page
    // whose bottom is reachable only by scrolling a window the user cannot
    // resize is exactly the failure this group exists to catch.
    //
    // 1.3 is the top of the band, not an arbitrary maximum: it is where the
    // footer stack's own growth had squeezed the viewport from 551 to 539 px,
    // i.e. where the chrome was taking height from the page precisely when
    // the page needed it most.
    const foldTextScales = [1.0, 1.15, 1.3];

    // Cases that still run past the fold, keyed by (platform, page, locale,
    // scale) and carrying the deficit measured the day the entry was written.
    //
    // This is a ratchet, not a tolerance. Everything NOT listed must fit
    // outright, at every scale in [foldTextScales]. An entry may only ever be
    // lowered, and it is deleted the moment its case fits. Adding an entry is
    // a finding to be reported, never a way to make a red test green — the
    // whole point of the table is that each row has to name the open decision
    // that owns it.
    //
    // Empty, and that is the point: every page in every locale at every scale
    // in [foldTextScales] now fits the fixed window outright.
    //
    // The table's last two rows were page 1 (Welcome) in German at scale 1.3,
    // 22 px over, owned by ticket 20 Phase 5 / question a. They are gone
    // because that page was re-cut on purpose rather than left to the media
    // panel: the beat tiles' vertical padding dropped from 12 to 8 (which is
    // also W3's staggering fix), the showcase→language gap from 24 to 16, and
    // the brand lockup's inner gap from 12 to 8. German at 1.3 now lands on
    // 567 px of the 567 px offered — the tightest case in the flow, and a fit.
    // The panel itself is unchanged at 460×288; question a was answered with a
    // designed placeholder, not with a smaller surface.
    final foldRatchet = <(TargetPlatform, int, String, double), double>{};

    for (final platform in [TargetPlatform.macOS, TargetPlatform.linux]) {
      for (final locale in L10n.supportedLocales) {
        for (final scale in foldTextScales) {
          testWidgets('every page fits the fixed window on $platform in '
              '${locale.languageCode}, at text scale '
              '$scale', (tester) async {
            useFixedWindow(tester);
            debugDefaultTargetPlatformOverride = platform;
            try {
              await _pumpOverlay(
                tester,
                size: kOnboardingWindowSize,
                locale: locale,
                textScaler: TextScaler.linear(scale),
                // Seed the *dictation* language too, not just the UI one.
                // The model page reads it (`recommendEngine`) and disables
                // the Parakeet card for a language it cannot do, which adds
                // a reason line that IntrinsicHeight applies to BOTH engine
                // cards. Leaving it at the default measured the cheap
                // branch for every locale and missed exactly the case where
                // the page is at its tallest.
                settings: _FakeSettingsNotifier(
                  AppSettings.defaults.copyWith(locale: locale.languageCode),
                ),
              );

              final total = _totalSteps(platform);
              for (var page = 1; page <= total; page++) {
                if (page > 1) await _tapNext(tester);
                expectFits(
                  tester,
                  measure(tester),
                  what:
                      'page $page ($platform, ${locale.languageCode}, '
                      'scale $scale)',
                  allowed:
                      foldRatchet[(
                        platform,
                        page,
                        locale.languageCode,
                        scale,
                      )] ??
                      0,
                );
              }
            } finally {
              debugDefaultTargetPlatformOverride = null;
            }
          });
        }
      }
    }

    // ── The escape hatch specifically ────────────────────────────────────
    //
    // The measurements above prove the *page* fits. This proves the one
    // control that must never be unreachable actually sits above the fold,
    // which is the P0 finding stated in its own terms rather than inferred
    // from a page height: "Ohne Mikrofon fortfahren" is the only way past
    // Try & Go for a user whose microphone does not work, and Try & Go is
    // the last page of the flow.
    //
    // Worth asserting separately because the two can come apart: a page can
    // fit while a *later* change re-orders its column and pushes this button
    // under the fold anyway, and nothing in the height arithmetic would say
    // so.

    for (final scale in foldTextScales) {
      testWidgets('the microphone-bypass escape hatch stays above the fold at '
          'text scale $scale (de, the tallest locale)', (tester) async {
        useFixedWindow(tester);
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          await _pumpOverlay(
            tester,
            size: kOnboardingWindowSize,
            locale: const Locale('de'),
            textScaler: TextScaler.linear(scale),
            settings: _FakeSettingsNotifier(
              AppSettings.defaults.copyWith(locale: 'de'),
            ),
          );

          final total = _totalSteps(TargetPlatform.macOS);
          for (var page = 2; page <= total; page++) {
            await _tapNext(tester);
          }

          final button = find.byKey(kTestRecordingStepMicBypassButtonKey);
          expect(
            button,
            findsOneWidget,
            reason:
                'Without a granted microphone the bypass button is the page '
                'and the flow — if it is not rendered, this test is measuring '
                'the wrong state.',
          );

          final fold = tester
              .getRect(find.byType(SingleChildScrollView).first)
              .bottom;
          expect(
            tester.getRect(button).bottom,
            lessThanOrEqualTo(fold),
            reason:
                'The microphone-bypass button ends '
                '${tester.getRect(button).bottom - fold} px below the fold at '
                'text scale $scale. The onboarding window cannot be resized, '
                'so a user without a working microphone has no way to reach '
                'it. Relieve the page (see the 6:3 column split and the '
                'footer stack) — do not add a scroll affordance.',
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }

    // ── One header gap for the whole flow ────────────────────────────────
    //
    // The companion to the reading-start guard below: that one pins where a
    // page's header *starts*, this one pins where its body starts relative to
    // it. Both were true only by accident before.
    //
    // The distance from the header's bottom edge to the first thing under it
    // used to run from 20 px on Try & Go to 117.5 px on Appearance — a factor
    // of six off a single shared constant. The spread did not come from the
    // constant but from what sat underneath it: the body was centred in the
    // leftover height, so half of every page's slack was inserted into
    // precisely this gap, and the emptier the page the further its heading
    // drifted from the content it introduces. The body is top-aligned now
    // (see [OnboardingPageBody]) and the gap is the constant again.
    //
    // Asserted through [kOnboardingPageHeaderKey] rather than by widget type
    // because page 1's header is a brand lockup and every other page's is an
    // [OnboardingPageHeading] — the guard is about the composition, not about
    // what a page chose to put in the slot.

    for (final locale in L10n.supportedLocales) {
      testWidgets('every fill page puts exactly kOnboardingHeaderGap between '
          'its header and its body, in ${locale.languageCode}', (tester) async {
        useFixedWindow(tester);
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          await _pumpOverlay(
            tester,
            size: kOnboardingWindowSize,
            locale: locale,
            settings: _FakeSettingsNotifier(
              AppSettings.defaults.copyWith(locale: locale.languageCode),
            ),
          );

          final total = _totalSteps(TargetPlatform.macOS);
          for (var page = 1; page <= total; page++) {
            if (page > 1) await _tapNext(tester);

            final header = find.byKey(kOnboardingPageHeaderKey);
            if (header.evaluate().isEmpty) {
              // Try & Go is two side-by-side columns rather than a header over
              // a body, so it has no header slot to measure. It is the one
              // page `_fillsViewport` excludes, and skipping it here is that
              // same exclusion rather than a gap in coverage.
              expect(
                page,
                total,
                reason:
                    'Only the last page (Try & Go) may render without an '
                    'OnboardingPage header slot.',
              );
              continue;
            }

            expect(
              tester.getRect(find.byType(OnboardingPageBody).first).top -
                  tester.getRect(header).bottom,
              kOnboardingHeaderGap,
              reason:
                  'page $page (${locale.languageCode}) puts a different gap '
                  'under its header than every other page does. If a page '
                  'genuinely cannot afford the canonical gap, it says so '
                  'through OnboardingPage.headerGap at its call site — there '
                  'is exactly one such page (the hotkey page in its '
                  'confirmed-conflict branch) and it is covered separately.',
            );
          }
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }

    // ── A control stays with the label it belongs to ─────────────────────
    //
    // `SettingRow` pins its trailing control to the far end of the row. In the
    // settings column, where the row is barely wider than its own text, that
    // is the same thing as putting the control next to the label. On an
    // onboarding page the identical row is handed a 640-px frame, and the two
    // came apart: 153–349 px of empty run between text and switch on the
    // privacy page, 425 px on the hotkey page — a label separated from its own
    // control by more than the label is wide, which reads as two unrelated
    // columns rather than one row.
    //
    // The rows that opt into `trailingHugsLabel` are asserted here rather than
    // eyeballed, because the failure mode is a single word (`Expanded`) that
    // reintroduces itself easily and looks perfectly reasonable in a diff.
    // Directional arithmetic, so Hebrew is covered by the same assertion
    // rather than by a second one that could drift from it.
    //
    // The second expectation is the other half of the same criterion: hugging
    // the label must not shorten the row's own painted surface, which is what
    // carries the flush trailing edge the page's blocks share.

    const maxLabelToControl = 48.0;

    for (final locale in L10n.supportedLocales) {
      testWidgets('every onboarding setting row keeps its control within '
          '$maxLabelToControl px of its label, in ${locale.languageCode}', (
        tester,
      ) async {
        useFixedWindow(tester);
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          await _pumpOverlay(
            tester,
            size: kOnboardingWindowSize,
            locale: locale,
            settings: _FakeSettingsNotifier(
              AppSettings.defaults.copyWith(locale: locale.languageCode),
            ),
          );

          final rtl = Bidi.isRtlLanguage(locale.languageCode);
          final total = _totalSteps(TargetPlatform.macOS);
          var checked = 0;

          for (var page = 1; page <= total; page++) {
            if (page > 1) await _tapNext(tester);

            for (final element in find.byType(SettingRow).evaluate().toList()) {
              final row = element.widget as SettingRow;
              if (!row.trailingHugsLabel) continue;

              final rowFinder = find.byWidget(row);
              // The rendered strings, not the column that holds them: `Icon`
              // brings its own `ExcludeSemantics` and a structural finder
              // silently measures that instead. This is also the criterion in
              // its own terms — where the *text* ends, not where its box does.
              final textRects = [
                tester.getRect(
                  find.descendant(
                    of: rowFinder,
                    matching: find.text(row.label),
                  ),
                ),
                if (row.subtitle != null)
                  tester.getRect(
                    find.descendant(
                      of: rowFinder,
                      matching: find.text(row.subtitle!),
                    ),
                  ),
              ];
              final labelRect = textRects.reduce(
                (a, b) => a.expandToInclude(b),
              );
              final trailingRect = tester.getRect(
                find.descendant(
                  of: rowFinder,
                  matching: find.byWidget(row.trailing),
                ),
              );

              final gap = rtl
                  ? labelRect.left - trailingRect.right
                  : trailingRect.left - labelRect.right;

              expect(
                gap,
                lessThanOrEqualTo(maxLabelToControl),
                reason:
                    'page $page (${locale.languageCode}): "${row.label}" and '
                    'the control that operates it are $gap px apart. A row '
                    'whose label column claims the full frame puts them at '
                    'opposite ends of the page; pass trailingHugsLabel on the '
                    'row rather than widening the gap allowed here.',
              );

              expect(
                tester.getRect(rowFinder).width,
                tester.getRect(find.byType(OnboardingPageBody).first).width,
                reason:
                    'page $page (${locale.languageCode}): the row\'s own '
                    'surface no longer spans the body. Pulling the control '
                    'towards the label must not shorten the row itself — the '
                    'surface is what carries the trailing edge this page\'s '
                    'blocks line up on, in LTR and RTL alike.',
              );
              checked++;
            }
          }

          expect(
            checked,
            greaterThanOrEqualTo(5),
            reason:
                'The flow is expected to carry at least five hugging setting '
                'rows (two on the privacy page, two on the hotkey page, the '
                'autostart row on the ready page) — the three pages the '
                'criterion names. '
                'Finding fewer means the opt-in was dropped somewhere and the '
                'assertion above silently stopped covering it.',
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }

    // ── One reading start for the whole flow ─────────────────────────────
    //
    // The regression this guards: page 1 used to be centred as a single unit
    // (brand lockup + showcase + language selector), so its wordmark sat
    // wherever the rest of the page left it — visibly *below* page 2's
    // heading. Every page now carries a fixed header and centres only its
    // body underneath it ([OnboardingPageBody]), which is a property worth
    // asserting rather than eyeballing: it is invisible in a screenshot of
    // any single page and only shows up when paging through.

    for (final locale in L10n.supportedLocales) {
      testWidgets('every page starts its header on the same line — page 1 '
          "'s wordmark included, in ${locale.languageCode}", (tester) async {
        useFixedWindow(tester);
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          await _pumpOverlay(
            tester,
            size: kOnboardingWindowSize,
            locale: locale,
            settings: _FakeSettingsNotifier(
              AppSettings.defaults.copyWith(locale: locale.languageCode),
            ),
          );

          // Page 1's header is the brand lockup, and the wordmark is its
          // first line — the same role the page title plays everywhere else.
          final headerTop = tester.getTopLeft(find.byType(WpBrandWordmark)).dy;

          final total = _totalSteps(TargetPlatform.macOS);
          for (var page = 2; page <= total; page++) {
            await _tapNext(tester);
            expect(
              tester.getTopLeft(find.byType(OnboardingPageHeading)).dy,
              headerTop,
              reason:
                  "page $page's heading starts at a different height than "
                  "page 1's wordmark — the flow's reading start moves as the "
                  'user pages through it',
            );
          }
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }

    // ── The two tall branches ────────────────────────────────────────────
    //
    // Both were previously uncovered, and the hotkey one was a documented
    // dead end: on the merged Model & Hotkey page the conflict branch came to
    // 914 px (de) against a 551-px viewport. Splitting the page is what made
    // it fit, so it is worth a test that says so.

    for (final locale in [const Locale('de'), const Locale('he')]) {
      testWidgets(
        'the hotkey page fits the fixed window in the confirmed-conflict '
        'branch (warn box + full inline recorder) in ${locale.languageCode}',
        (tester) async {
          useFixedWindow(tester);
          debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          try {
            await _pumpOverlay(
              tester,
              size: kOnboardingWindowSize,
              locale: locale,
              settings: _FakeSettingsNotifier(
                AppSettings.defaults.copyWith(locale: locale.languageCode),
              ),
              hotkeyStatus: HotkeyRegistrationStatus.conflict,
            );
            for (var page = 2; page <= 4; page++) {
              await _tapNext(tester);
            }

            // Prove the branch is actually on screen — otherwise this would
            // happily measure the nominal page and pass for the wrong reason.
            expect(find.byKey(kTriggerStepConflictWarnBoxKey), findsOneWidget);
            expect(find.byKey(kTriggerStepInlineRecorderKey), findsOneWidget);

            expectFits(
              tester,
              measure(tester),
              what: 'hotkey page, conflict branch (${locale.languageCode})',
            );
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        },
      );

      testWidgets(
        'the model page fits the fixed window in the download-error branch '
        '(error banner + retry button) in ${locale.languageCode}',
        (tester) async {
          useFixedWindow(tester);
          debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          try {
            await _pumpOverlay(
              tester,
              size: kOnboardingWindowSize,
              locale: locale,
              settings: _FakeSettingsNotifier(
                AppSettings.defaults.copyWith(locale: locale.languageCode),
              ),
              downloadFailed: true,
            );
            await _tapNext(tester); // → 2: Privacy
            await _tapNext(tester); // → 3: Model

            final localized = await L10n.delegate.load(locale);
            expect(
              find.text(localized.overlayRetry),
              findsOneWidget,
              reason: 'the download-error branch must actually be rendered',
            );

            expectFits(
              tester,
              measure(tester),
              what:
                  'model page, download-error branch (${locale.languageCode})',
            );
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        },
      );

      // The Auto-Paste phases the default matrix cannot reach: it seeds no
      // capability, so it only ever measures `checking`. `intro` is the
      // first-run state every macOS user meets (status card + full-width
      // Grant CTA + why + skip) and `waiting` is the tallest non-troubleshoot
      // one — its card carries a four-line hint with a blank line in it.
      for (final (name, phase) in [
        ('intro', PollingPhase.idle),
        ('waiting', PollingPhase.awaitingGrant),
      ]) {
        for (final scale in foldTextScales) {
          testWidgets(
            'the Auto-Paste page fits the fixed window in the $name branch '
            'in ${locale.languageCode} at text scale $scale',
            (tester) async {
              useFixedWindow(tester);
              debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
              try {
                await _pumpOverlay(
                  tester,
                  size: kOnboardingWindowSize,
                  locale: locale,
                  textScaler: TextScaler.linear(scale),
                  settings: _FakeSettingsNotifier(
                    AppSettings.defaults.copyWith(locale: locale.languageCode),
                  ),
                  paste: _PhasePasteCapabilityNotifier(pollingPhase: phase),
                );
                for (var page = 2; page <= 6; page++) {
                  await _tapNext(tester);
                }

                final localized = await L10n.delegate.load(locale);
                expect(
                  find.text(
                    phase == PollingPhase.awaitingGrant
                        ? localized.onboardingPasteWaitingForGrantTitle
                        : localized.onboardingPasteGrantCta,
                  ),
                  findsOneWidget,
                  reason: 'the $name branch must actually be rendered',
                );

                expectFits(
                  tester,
                  measure(tester),
                  what:
                      'Auto-Paste page, $name branch '
                      '(${locale.languageCode}, scale $scale)',
                );
              } finally {
                debugDefaultTargetPlatformOverride = null;
              }
            },
          );
        }
      }

      // Troubleshoot used to be measured at scale 1.0 only, which is the one
      // scale where its slack is comfortable. It carries the Skip button —
      // the escape control — so it is measured across the same scales as
      // everything else.
      for (final scale in foldTextScales) {
        testWidgets(
          'the Auto-Paste page fits the fixed window in the troubleshoot '
          'branch (skip + repair + result banner + its own restart button) '
          'in ${locale.languageCode} at text scale $scale',
          (tester) async {
            useFixedWindow(tester);
            debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
            try {
              await _pumpOverlay(
                tester,
                size: kOnboardingWindowSize,
                locale: locale,
                textScaler: TextScaler.linear(scale),
                settings: _FakeSettingsNotifier(
                  AppSettings.defaults.copyWith(locale: locale.languageCode),
                ),
                paste: _TroubleshootPasteCapabilityNotifier(),
              );
              for (var page = 2; page <= 6; page++) {
                await _tapNext(tester);
              }

              final localized = await L10n.delegate.load(locale);
              expect(
                find.text(localized.pasteCapabilityRestartTitle),
                findsOneWidget,
                reason: 'the troubleshoot branch must actually be rendered',
              );

              await tester.tap(
                find.text(localized.pasteCapabilityRepairButton),
              );
              // Sequential pump() — the success path chains into the grant
              // flow, same as auto_paste_step_test.dart's nothingCleared
              // case; pumpAndSettle would deadlock on the polling spinner.
              await tester.pump();
              await tester.pump();
              await tester.pump();

              expect(
                find.text(localized.pasteCapabilityRepairNothingToClear),
                findsOneWidget,
                reason:
                    'the result banner (and its own Restart button) must '
                    'actually be rendered — otherwise this measures the '
                    'nominal troubleshoot state and passes for the wrong '
                    'reason',
              );

              expectFits(
                tester,
                measure(tester),
                what:
                    'Auto-Paste page, troubleshoot branch '
                    '(${locale.languageCode}, scale $scale)',
              );
            } finally {
              debugDefaultTargetPlatformOverride = null;
            }
          },
        );
      }
    }

    // ── Windows: the two branches of _WindowsBody ────────────────────────
    //
    // Deliberately narrow rather than a second 36-case matrix: Windows shares
    // the whole flow with macOS except this one page body, and it is the one
    // platform with neither a golden nor a row in the matrix above — so a
    // wrap on its cards would surface nowhere. `de` and `he` only, being the
    // long and the RTL case; `en` is strictly shorter than both here.
    for (final locale in [const Locale('de'), const Locale('he')]) {
      for (final (name, status) in [
        ('UIPI edge', PasteCapabilityStatus.permissionMissing),
        ('ready', PasteCapabilityStatus.ready),
      ]) {
        for (final scale in foldTextScales) {
          testWidgets(
            'the Auto-Paste page fits the fixed window on Windows in the '
            '$name branch in ${locale.languageCode} at text scale $scale',
            (tester) async {
              useFixedWindow(tester);
              debugDefaultTargetPlatformOverride = TargetPlatform.windows;
              try {
                await _pumpOverlay(
                  tester,
                  size: kOnboardingWindowSize,
                  locale: locale,
                  textScaler: TextScaler.linear(scale),
                  settings: _FakeSettingsNotifier(
                    AppSettings.defaults.copyWith(locale: locale.languageCode),
                  ),
                  paste: _PhasePasteCapabilityNotifier(
                    pollingPhase: PollingPhase.idle,
                    status: status,
                  ),
                );
                for (var page = 2; page <= 6; page++) {
                  await _tapNext(tester);
                }

                final localized = await L10n.delegate.load(locale);
                expect(
                  find.text(
                    status == PasteCapabilityStatus.ready
                        ? localized.onboardingPasteWhyWin
                        : localized.onboardingPasteWhyWinUipi,
                  ),
                  findsOneWidget,
                  reason:
                      'the Windows $name branch must actually be rendered — '
                      'otherwise this measures the wrong card and passes for '
                      'the wrong reason',
                );

                expectFits(
                  tester,
                  measure(tester),
                  what:
                      'Auto-Paste page on Windows, $name branch '
                      '(${locale.languageCode}, scale $scale)',
                );
              } finally {
                debugDefaultTargetPlatformOverride = null;
              }
            },
          );
        }
      }
    }
  });

  // ── Disposal — no poll timer survives the window closing ────────────────

  group('OnboardingOverlay disposal', () {
    testWidgets(
      'dispose explicitly stops Auto-Paste AND mic-permission polling — '
      'defends against zombie timers when the overlay tears down '
      '(window close, app quit, re-mount)',
      (tester) async {
        final paste = _RecordingPasteCapabilityNotifier();
        final mic = _RecordingMicPermissionNotifier();

        await _pumpOverlay(tester, paste: paste, mic: mic);
        // Replace the overlay with an empty widget to trigger dispose.
        await tester.pumpWidget(
          makeTestable(
            const SizedBox.shrink(),
            size: const Size(1280, 980),
            // Same override shape as _pumpOverlay — the ProviderScope element
            // is reused across pumps and Riverpod forbids changing the
            // number of overrides.
            overrides: [
              settingsProvider.overrideWith(() => _FakeSettingsNotifier()),
              micPermissionCheckerProvider.overrideWithValue(
                _FakeMicPermissionChecker(),
              ),
              pasteCapabilityNotifierProvider.overrideWith(() => paste),
              micPermissionNotifierProvider.overrideWith(() => mic),
              modelDownloadProvider.overrideWith(
                () => _StaticWhisperDownload(const ModelDownloadState()),
              ),
              parakeetDownloadProvider.overrideWith(
                () => _StaticParakeetDownload(const ParakeetDownloadState()),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(
          paste.stopPollingCalls,
          greaterThanOrEqualTo(1),
          reason: 'Overlay dispose must stop the paste-capability poller',
        );
        expect(
          mic.stopPollingCalls,
          greaterThanOrEqualTo(1),
          reason: 'Overlay dispose must stop the mic-permission poller',
        );
      },
    );
  });

  // ── The One-Loud-Action Rule, applied to the flow ───────────────────────
  //
  // *The shared gate for this rule lives in
  // `test/core/design/one_loud_action_test.dart`. This half sits here because
  // it needs `_pumpOverlay`'s fixtures, and the shared file says so.*
  //
  // **The chrome/content boundary, once, for all seven pages.** The shell's
  // Next button is a `WpHeroButton` and it is *not* the page's loud action —
  // it is navigation, the same on every page, and it lives in
  // `kOnboardingNavRowKey` outside the scrolling content. So the count runs
  // over everything except that row.
  //
  // **Hero and `primary` are counted together.** Counting only `primary`
  // WpButtons would let a step re-introduce a gradient hero and still pass —
  // which is exactly the shape the violation had before Ticket 15
  // (`auto_paste_step.dart` and `model_step.dart` each carried one, eight
  // pixels above the shell's).
  group('OnboardingOverlay — one loud action per page (Ticket 15)', () {
    /// Loud things in the page body: `primary` WpButtons plus every
    /// WpHeroButton, with the shell's navigation row excluded by scope.
    int loudActionsInContent(WidgetTester tester) {
      final navRow = find.byKey(kOnboardingNavRowKey);
      bool inNavRow(Finder of) =>
          find.ancestor(of: of, matching: navRow).evaluate().isNotEmpty;

      final loudButtons = tester
          .elementList(find.byType(WpButton))
          .where(
            (e) =>
                (e.widget as WpButton).variant == WpButtonVariant.primary &&
                !inNavRow(find.byWidget(e.widget)),
          )
          .length;
      final heroes = tester
          .elementList(find.byType(WpHeroButton))
          .where((e) => !inNavRow(find.byWidget(e.widget)))
          .length;
      return loudButtons + heroes;
    }

    testWidgets('no page of the flow carries a second loud action', (
      tester,
    ) async {
      await _pumpOverlay(tester);
      final total = _totalSteps(defaultTargetPlatform);
      var pagesWithALoudAction = 0;

      for (var page = 1; page <= total; page++) {
        final loud = loudActionsInContent(tester);
        if (loud == 1) pagesWithALoudAction++;
        expect(
          loud,
          lessThanOrEqualTo(1),
          reason:
              '*The One-Loud-Action Rule* — onboarding page $page of $total.\n'
              'The page body carries more than one loud action while the '
              'shell\'s hero Next button is already on screen. Demote the one '
              'the page is not pointing at: gradient hero for the flow CTA in '
              'the chrome, `primary` WpButton for the page\'s own action, '
              'ghost for the escape hatch.',
        );
        if (page < total) await _tapNext(tester);
      }

      // Non-vacuity: `lessThanOrEqualTo(1)` passes trivially on a flow where
      // no page has an action at all, which is a different bug with the same
      // symptom.
      //
      // Exactly one page clears it under these fixtures, and that is a
      // property of the fixtures rather than of the flow: flutter_test runs
      // as Android unless told otherwise, so the sequence is the six-step
      // one (no Auto-Paste page), and the model page defaults to a state
      // with no engine picked and therefore no Download CTA. Try & Go's
      // record button is the one that always renders. The *source*-level half
      // of this rule — no step body may build a hero at all — is what pins
      // the two demoted CTAs, and it lives in
      // `test/core/design/one_loud_action_test.dart`.
      expect(
        pagesWithALoudAction,
        greaterThanOrEqualTo(1),
        reason:
            'The walk found $pagesWithALoudAction pages with a loud action. '
            'Either the fixtures stopped reaching the states that have one, '
            'or the pages lost theirs — both make the bound above vacuous.',
      );
    });

    testWidgets('the hero is the shell\'s alone — no step body builds one', (
      tester,
    ) async {
      await _pumpOverlay(tester);
      final total = _totalSteps(defaultTargetPlatform);

      for (var page = 1; page <= total; page++) {
        final navRow = find.byKey(kOnboardingNavRowKey);
        final heroesOutsideNav = tester
            .elementList(find.byType(WpHeroButton))
            .where(
              (e) => find
                  .ancestor(of: find.byWidget(e.widget), matching: navRow)
                  .evaluate()
                  .isEmpty,
            )
            .length;

        expect(
          heroesOutsideNav,
          0,
          reason:
              'Page $page builds a WpHeroButton of its own. The hero is one '
              'step *above* the button ladder and the flow spends it exactly '
              'once, on the shell\'s Next/completion CTA — a second one '
              'wearing the identical `accentWarmGradient` a few pixels away '
              'makes the page\'s own action outshout the one that ends the '
              'flow.',
        );
        if (page < total) await _tapNext(tester);
      }
    });
  });
}
