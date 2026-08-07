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
///    [kOnboardingWindowSize]) without scrolling, in every locale and both
///    brightnesses — including the two tall branches (hotkey conflict,
///    model download error);
///  - the layout renders in every supported UI language (list read from
///    [L10n.supportedLocales], never hard-coded) and mirrors fully in RTL;
///  - the layout survives the window minimum size (800×550, `lib/main.dart`)
///    and an enlarged system text scale without overflow errors.
library;

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
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
import 'package:whispaste/features/onboarding/steps/appearance_step.dart';
import 'package:whispaste/features/onboarding/steps/autostart_toggle.dart';
import 'package:whispaste/features/onboarding/steps/mic_permission_chip.dart';
import 'package:whispaste/features/onboarding/steps/model_step.dart';
import 'package:whispaste/features/onboarding/steps/onboarding_headings.dart';
import 'package:whispaste/features/onboarding/steps/onboarding_page_fill.dart';
import 'package:whispaste/features/onboarding/steps/trigger_step.dart';
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
  PasteCapabilityState build() => _troubleshootState;

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
  Brightness brightness = Brightness.dark,
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
      brightness: brightness,
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
        if (downloadFailed) ...[
          modelDownloadProvider.overrideWith(
            () => _StaticWhisperDownload(
              const ModelDownloadState(
                phase: DownloadPhase.error,
                errorMessage: downloadError,
              ),
            ),
          ),
          parakeetDownloadProvider.overrideWith(
            () => _StaticParakeetDownload(
              const ParakeetDownloadState(
                phase: ParakeetDownloadPhase.error,
                errorMessage: downloadError,
              ),
            ),
          ),
        ],
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
          expect(find.byKey(kAppearanceThemeSelectorKey), findsOneWidget);
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
      'the theme choice together with the autostart toggle',
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
          expect(find.byKey(kAppearanceThemeSelectorKey), findsOneWidget);
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
  // The onboarding window is pinned to 1100×720 (kOnboardingWindowSize), which
  // leaves a 551-px scroll viewport and a 511-px content area for the page
  // itself (the viewport minus the scroll view's padding). Every page has to
  // fit inside it: there is no way for the user to make the window bigger, so
  // a page that scrolls is a page whose bottom half is easy to miss entirely.
  //
  // Measured with real Inter metrics (see setUpAll — with the square-glyph
  // test font the numbers are meaningless), macOS unless noted, GPU-fallback
  // notice visible, i.e. the worst case. Natural content height against the
  // 551-px viewport, German / English / Hebrew.
  //
  // These are *natural* heights: what the page's blocks come to with every
  // gap at its minimum. Every page except Try & Go hands its leftover height
  // to the centring of its body block ([OnboardingPageFill] plus the page's
  // [OnboardingPageBody]) and therefore occupies the full 551 px whatever
  // these numbers say — the numbers are still the ones that decide whether a
  // page fits at all, and the ones to re-measure before adding to a page.
  //
  // Re-measured after the header-top/body-centred unification: every number
  // came out identical to the flex-gap layout it replaced, page 1 included.
  // That is the point — the change moved where the spare height goes, not how
  // much of it there is.
  //
  // Re-measured again after [OnboardingPage] gave the whole flow ONE header
  // gap ([kOnboardingHeaderGap] = `xxl`) in place of the per-page `lg`/`xl`/
  // `xxl` mix. Pages 1, 2 and 7 were already on `xxl` and did not move; the
  // pages that were tighter grew by exactly the token step (+12 from `lg`,
  // +8 from `xl`), which comes out of centring slack and is invisible.
  //
  // The 551 px itself is unchanged by the same-day chrome rebalance (top-bar
  // strip 48 → 32 px, bottom gap 16 → 32 px): the two moves are equal and
  // opposite by construction, see `_kOnboardingBottomGap`.
  //
  //   page 1  Welcome       529 / 529 / 529   (22 px slack)
  //   page 2  Privacy       303 / 303 / 303   (248 px distributed)
  //   page 3  Model         390 / 390 / 377
  //   page 4  Hotkey        222 / 222 / 222   (the sparsest page in the flow)
  //   page 5  Appearance    380 / 401 / 380   (theme tiles + autostart row)
  //   page 6  Auto-Paste    190 / 190 / 190   (macOS/Windows only)
  //   page 7  Try & Go      545 / 508 / 508   (6 px slack — the mic-bypass
  //                                            escape hatch moved from a raw
  //                                            TextButton to WpButton
  //                                            standard, +16 px; it kept
  //                                            `standard` because its label
  //                                            was always body-weight text,
  //                                            unlike the dense settings-row
  //                                            case in trigger_step.dart.
  //                                            This is now the binding
  //                                            constraint in the flow — see
  //                                            the full-transcript case in
  //                                            onboarding_flow_test)
  //
  // Linux runs the same pages 1–5 and ends on Try & Go as page 6, measured
  // 499 / 462 / 462 there.
  //
  // The three branch cases, which are what the split was for (German / Hebrew,
  // the two locales the tests cover):
  //   page 4 with a confirmed hotkey conflict   534 / 534
  //     Warn box + full inline recorder. On the old merged Model & Hotkey
  //     page this came to 914 / 921 px, i.e. ~370 px of forced scrolling that
  //     was documented as unreachable without a flow change. This is that
  //     flow change. Both keep 17 px of slack and pay for it three ways — the
  //     page heading drops its subtitle while a conflict is up, the gap
  //     under that heading is `sm` instead of [kOnboardingHeaderGap] (the
  //     flow's one deliberate deviation: the canonical 32 px would cost this
  //     branch 20 px it does not have), and the warn box is vertically
  //     tighter than it is wide. German pays a fourth way, which is what
  //     brings it level with Hebrew: its conflict body is worded to stay on
  //     one line. It used to wrap to two, and those 17 px are what put this
  //     branch 4 px over once WpButton gave the recorder's action row 48 px
  //     instead of 32 — that was 13 px of slack; the trailing "Ändern" button
  //     in the same row later moved to `WpButtonSize.dense` (32 px, down from
  //     its old 36), which is what brought the branch back to 17 px. Both
  //     numbers were binding constraints in their moment; re-measure before
  //     adding anything to this branch.
  //   page 3 with a failed model download      447 / 434
  //     Was 431 / 418 before the Retry button (`OutlinedButton.icon` in a
  //     `SizedBox(width: infinity)`) moved to `WpButton(secondary/neutral,
  //     expanded: true)` — the same +16 px a standard-size button costs
  //     everywhere else in this migration.
  //   page 6 with the troubleshoot branch        492 / 492
  //     (missing + sent-to-OS-grant-flow + poll timed out, Repair tapped and
  //     resolved to "nothing cleared") — Skip + Repair + the result banner's
  //     own extra Restart button, all stacked at once. This is the tallest
  //     Auto-Paste state and was entirely uncovered before this migration;
  //     the nominal (intro-phase) row above stayed at 190 px because Skip is
  //     the only button that phase renders, and re-measuring confirmed it did
  //     not move. 59 px of headroom against the 551 px viewport — re-measure
  //     before adding anything to this branch.
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
    /// height the [OnboardingPageBody]'s centring gave away recovers it —
    /// that gap is the only height on the page that comes from leftover space
    /// rather than from content.
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
      // The leftover height the body's centring gave away — the only height
      // on the page that comes from spare space rather than from content.
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
    }) {
      expect(
        tester.takeException(),
        isNull,
        reason:
            '$what overflowed its page column. Its blocks (every gap at its '
            'minimum) come to ${m.natural} px against the ${m.available} px '
            'the fixed 1100x720 window offers.',
      );
      expect(
        m.content,
        lessThanOrEqualTo(m.available),
        reason:
            '$what needs ${m.content} px of the ${m.available} px the fixed '
            '1100x720 window offers — it would scroll. Its blocks alone come '
            'to ${m.natural} px.',
      );
    }

    for (final platform in [TargetPlatform.macOS, TargetPlatform.linux]) {
      for (final locale in L10n.supportedLocales) {
        for (final brightness in [Brightness.dark, Brightness.light]) {
          testWidgets('every page fits the fixed window on $platform in '
              '${locale.languageCode}, ${brightness.name}', (tester) async {
            useFixedWindow(tester);
            debugDefaultTargetPlatformOverride = platform;
            try {
              await _pumpOverlay(
                tester,
                size: kOnboardingWindowSize,
                locale: locale,
                brightness: brightness,
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
                      '${brightness.name})',
                );
              }
            } finally {
              debugDefaultTargetPlatformOverride = null;
            }
          });
        }
      }
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

      testWidgets(
        'the Auto-Paste page fits the fixed window in the troubleshoot '
        'branch (skip + repair + result banner + its own restart button) '
        'in ${locale.languageCode}',
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
              paste: _TroubleshootPasteCapabilityNotifier(),
            );
            for (var page = 2; page <= 5; page++) {
              await _tapNext(tester);
            }
            await _tapNext(tester); // → 6: Auto-Paste

            final localized = await L10n.delegate.load(locale);
            expect(
              find.text(localized.pasteCapabilityRestartTitle),
              findsOneWidget,
              reason: 'the troubleshoot branch must actually be rendered',
            );

            await tester.tap(find.text(localized.pasteCapabilityRepairButton));
            // Sequential pump() — the success path chains into the grant
            // flow, same as auto_paste_step_test.dart's nothingCleared case;
            // pumpAndSettle would deadlock on the polling spinner.
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
                  '(${locale.languageCode})',
            );
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        },
      );
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
}
