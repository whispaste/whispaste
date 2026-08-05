/// Widget tests for the [OnboardingOverlay] shell.
///
/// The six-step flow is identical on every platform (the platform variance
/// lives inside the Autostart & Auto-Paste page). Covered here:
///  - step counter shows "1 of 6" on macOS, Windows and Linux alike;
///  - the shell-owned navigation row carries exactly two actions (Back +
///    Next) and no skip affordance;
///  - overlay dispose stops both shared pollers (paste capability + mic
///    permission) — no zombie timer survives a window close;
///  - leaving page 1 auto-fires the mic request exactly when the user never
///    triggered it themselves (status still `unknown`) — and never otherwise;
///  - page 1 fits the fixed onboarding window size (1100×720,
///    [kOnboardingWindowSize]) without scrolling;
///  - the layout renders in every supported UI language (list read from
///    [L10n.supportedLocales], never hard-coded) and mirrors fully in RTL;
///  - the layout survives the window minimum size (800×550, `lib/main.dart`)
///    and an enlarged system text scale without overflow errors.
library;

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show Bidi;
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/platform/desktop_window_geometry.dart'
    show kOnboardingWindowSize;
import 'package:whispaste/features/onboarding/onboarding_overlay.dart';
import 'package:whispaste/features/onboarding/steps/appearance_step.dart';
import 'package:whispaste/features/onboarding/steps/mic_permission_chip.dart';
import 'package:whispaste/features/onboarding/steps/model_step.dart';
import 'package:whispaste/features/onboarding/steps/trigger_step.dart';
import 'package:whispaste/features/onboarding/steps/auto_paste_step.dart';
import 'package:whispaste/services/paste/paste_capability_notifier.dart';
import 'package:whispaste/services/permissions/mic_permission_notifier.dart';
import 'package:whispaste/widgets/wp_accent_button.dart';

import '../../fixtures/test_helpers.dart';

late L10n l10n;

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
/// chip on page 1 checks on mount, and leaving page 1 may request; neither
/// call may ever reach the real audio plugin in a widget test.
class _FakeMicPermissionChecker implements MicPermissionChecker {
  @override
  Future<bool> check({required bool request}) async => false;
}

Future<void> _tapNext(WidgetTester tester) async {
  await tester.tap(find.byKey(kOnboardingNextButtonKey));
  await tester.pumpAndSettle();
}

Future<void> _pumpOverlay(
  WidgetTester tester, {
  _RecordingPasteCapabilityNotifier? paste,
  _RecordingMicPermissionNotifier? mic,
  _FakeSettingsNotifier? settings,
  Size size = const Size(1280, 980),
  Locale locale = const Locale('en'),
  Brightness brightness = Brightness.dark,
  TextScaler textScaler = TextScaler.noScaling,
  // `false` for states that animate forever (the mic chip's `requesting`
  // spinner) — pumpAndSettle would time out on those.
  bool settle = true,
}) async {
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
    // The fixed-window fit assertion below measures whether page 1 fits
    // 1100×720 without scrolling — with Ahem every glyph is a full em
    // square, roughly doubling text width vs. Inter, which makes the
    // asymmetric beat layout's caption column wrap to 4–5 lines that never
    // occur in the real app. Real metrics keep the gate meaningful.
    final fontLoader = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Inter-Medium.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Inter-SemiBold.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Inter-Bold.ttf'));
    await fontLoader.load();
  });

  group('OnboardingOverlay step sequence — six steps on every platform', () {
    for (final platform in [
      TargetPlatform.linux,
      TargetPlatform.macOS,
      TargetPlatform.windows,
    ]) {
      testWidgets(
        'on $platform: counter reflects 6 total and the first page never '
        'mounts AutoPasteStep',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          try {
            await _pumpOverlay(tester);

            expect(find.text(l10n.onboardingStepOf(1, 6)), findsOneWidget);
            // Auto-Paste content lives on page 5 only.
            expect(find.byType(AutoPasteStep), findsNothing);
          } finally {
            // Reset before the framework's foundation-vars-unset assertion.
            debugDefaultTargetPlatformOverride = null;
          }
        },
      );
    }
  });

  // ── Shell-owned navigation: exactly two actions, no skip ────────────────
  //
  // The generic "Skip this step" button was removed with the merged flow
  // (it did the same as Next on every page). The nav row must carry exactly
  // two navigation actions; the full walkthrough proof over pages 1–4 lives
  // in onboarding_flow_test.dart, this one pins the shape on the first page.

  group('OnboardingOverlay — navigation row', () {
    testWidgets(
      'first page: nav row carries exactly two actions (Back disabled + '
      'Next), and the generic skip button is gone (AutoPasteStep keeps its '
      'own intentional Skip on page 4 — a mode choice, not navigation)',
      (tester) async {
        await _pumpOverlay(tester);

        final navRow = find.byKey(kOnboardingNavRowKey);
        expect(navRow, findsOneWidget);

        // Exactly two tappable navigation actions inside the row.
        final textButtons = find.descendant(
          of: navRow,
          matching: find.byType(TextButton),
        );
        final accentButtons = find.descendant(
          of: navRow,
          matching: find.byType(WpAccentButton),
        );
        expect(
          tester.widgetList(textButtons).length +
              tester.widgetList(accentButtons).length,
          2,
          reason: 'The nav row must carry exactly two navigation actions.',
        );

        // Back exists but is disabled on the first page.
        final back = tester.widget<TextButton>(
          find.byKey(kOnboardingBackButtonKey),
        );
        expect(back.onPressed, isNull);

        // Next is enabled.
        final next = tester.widget<WpAccentButton>(
          find.byKey(kOnboardingNextButtonKey),
        );
        expect(next.onPressed, isNotNull);
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
          final textButtons = find.descendant(
            of: navRow,
            matching: find.byType(TextButton),
          );
          final accentButtons = find.descendant(
            of: navRow,
            matching: find.byType(WpAccentButton),
          );
          expect(
            tester.widgetList(textButtons).length +
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
        for (final locale in L10n.supportedLocales) {
          final localized = await L10n.delegate.load(locale);
          await _pumpOverlay(tester, locale: locale);

          expect(
            find.text(localized.onboardingStepOf(1, 6)),
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
                  'In LTR (${locale.languageCode}) Back must sit left of Next',
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
          // Status-Chips") lives on pages 3–4: side-by-side engine cards and
          // the Auto-Paste status chip. Walk there too and confirm no
          // overflow/exception under long Hebrew/German strings.
          await _tapNext(tester); // → page 3: Model & Hotkey
          expect(
            tester.takeException(),
            isNull,
            reason: 'No layout exception on page 3 in ${locale.languageCode}',
          );
          await _tapNext(tester); // → page 4: Autostart & Auto-Paste
          expect(
            tester.takeException(),
            isNull,
            reason: 'No layout exception on page 4 in ${locale.languageCode}',
          );

          // Clean teardown between locales.
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }
      },
    );

    testWidgets(
      'pages 3–4 render without layout errors in every supported locale on '
      'macOS, where the Auto-Paste status chip actually mounts alongside '
      'the engine cards and Autostart toggle',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          for (final locale in L10n.supportedLocales) {
            await _pumpOverlay(tester, locale: locale);
            await _tapNext(tester); // → page 3
            await _tapNext(tester); // → page 4 (Auto-Paste chip mounts here)
            expect(
              tester.takeException(),
              isNull,
              reason:
                  'No layout exception on page 4 (macOS) in '
                  '${locale.languageCode}',
            );
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
          }
        } finally {
          // Reset before the framework's foundation-vars-unset assertion.
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
        shrinkToMinimumWindow(tester);
        await _pumpOverlay(tester, size: const Size(800, 550));
        expect(find.text(l10n.onboardingStepOf(1, 6)), findsOneWidget);
        expect(tester.takeException(), isNull);
        for (var page = 2; page <= 6; page++) {
          await _tapNext(tester);
          expect(
            tester.takeException(),
            isNull,
            reason: 'No overflow on page $page at 800×550',
          );
        }
      },
    );

    testWidgets('every page lays out at minimum size with enlarged system text '
        '(textScaler 1.5, matching sidebar_large_text_test.dart) without '
        'overflow', (tester) async {
      shrinkToMinimumWindow(tester);
      await _pumpOverlay(
        tester,
        size: const Size(800, 550),
        textScaler: const TextScaler.linear(1.5),
      );
      expect(tester.takeException(), isNull);
      for (var page = 2; page <= 6; page++) {
        await _tapNext(tester);
        expect(
          tester.takeException(),
          isNull,
          reason: 'No overflow on page $page at 800×550, textScaler 1.5',
        );
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
        final mic = _RecordingMicPermissionNotifier();
        await _pumpOverlay(tester, mic: mic);

        await _tapNext(tester);

        expect(find.text(l10n.onboardingStepOf(2, 6)), findsOneWidget);
        expect(mic.requestCalls, 1);
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

          expect(find.text(l10n.onboardingStepOf(2, 6)), findsOneWidget);
          expect(mic.requestCalls, 0);
        },
      );
    }

    testWidgets(
      'page 1 shows no microphone affordance at all — the request is silent '
      'and the visible status lives on the last page, next to the recording '
      'that needs it',
      (tester) async {
        await _pumpOverlay(tester, mic: _RecordingMicPermissionNotifier());

        expect(find.byType(MicPermissionChip), findsNothing);

        for (var page = 2; page <= 6; page++) {
          await _tapNext(tester);
          expect(
            find.byType(MicPermissionChip),
            page == 6 ? findsOneWidget : findsNothing,
            reason: 'unexpected chip presence on page $page',
          );
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
  // leaves a 551-px content viewport. Every page has to fit inside it: there
  // is no way for the user to make the window bigger, so a page that scrolls
  // is a page whose bottom half is easy to miss entirely.
  //
  // Measured with real Inter metrics (see setUpAll — with the square-glyph
  // test font the numbers are meaningless), macOS, GPU-fallback notice
  // visible, i.e. the worst case. Content height against the 551-px viewport,
  // German / Hebrew / English:
  //
  //   page 1  Welcome                529 / 529 / 529   (22 px slack)
  //   page 2  Privacy                345 / 345 / 324
  //   page 3  Model & Hotkey         500 / 524 / 500   (27 px slack in
  //                                                     Hebrew, the tightest)
  //   page 4  Appearance             292 / 292 / 292
  //   page 5  Autostart & Auto-Paste 247 / 247 / 247
  //   page 6  Try & Go               521 / 484 / 484   (30 px slack — and
  //                                                     see the full-
  //                                                     transcript case in
  //                                                     onboarding_flow_test)
  //
  // Hebrew is the tightest on page 3 for a reason worth keeping in mind when
  // re-measuring: the loop seeds the *dictation* language, and Hebrew is not
  // one of the languages the Parakeet engine covers, so its card renders an
  // extra "unsupported language" line that IntrinsicHeight applies to both
  // engine cards. Measuring with the default dictation language would miss
  // 24 px on this page.
  //
  // Known exception, pre-existing and out of scope here: page 3 in the
  // confirmed-hotkey-conflict branch mounts a full inline recorder and does
  // scroll (documented in trigger_step.dart).

  group('OnboardingOverlay — fixed window size (1100×720)', () {
    /// Height the page is given, and the height it actually wants. The page
    /// content shrink-wraps inside an [Align], so `maxScrollExtent` alone is
    /// always 0 and proves nothing — the incoming constraint is what the
    /// content has to fit into.
    ({double available, double content}) measure(WidgetTester tester) {
      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      final available = tester
          .renderObject<RenderBox>(find.byType(SingleChildScrollView).first)
          .constraints
          .maxHeight;
      return (
        available: available,
        content:
            scrollable.position.viewportDimension +
            scrollable.position.maxScrollExtent,
      );
    }

    for (final locale in L10n.supportedLocales) {
      for (final brightness in [Brightness.dark, Brightness.light]) {
        testWidgets(
          'every page fits the fixed window in ${locale.languageCode}, '
          '${brightness.name}',
          (tester) async {
            tester.view.physicalSize = kOnboardingWindowSize;
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
            try {
              await _pumpOverlay(
                tester,
                size: kOnboardingWindowSize,
                locale: locale,
                brightness: brightness,
                // Seed the *dictation* language too, not just the UI one.
                // Page 3 reads it (`recommendEngine`) and disables the
                // Parakeet card for a language it cannot do, which adds a
                // reason line that IntrinsicHeight applies to BOTH engine
                // cards. Leaving it at the default measured the cheap branch
                // for every locale and missed exactly the case where the
                // tightest page in the flow is at its tallest.
                settings: _FakeSettingsNotifier(
                  AppSettings.defaults.copyWith(locale: locale.languageCode),
                ),
              );

              for (var page = 1; page <= 6; page++) {
                if (page > 1) await _tapNext(tester);
                final m = measure(tester);
                expect(tester.takeException(), isNull);
                expect(
                  m.content,
                  lessThanOrEqualTo(m.available),
                  reason:
                      'page $page (${locale.languageCode}, '
                      '${brightness.name}) needs ${m.content} px of the '
                      '${m.available} px the fixed 1100x720 window offers — '
                      'it would scroll.',
                );
              }
            } finally {
              debugDefaultTargetPlatformOverride = null;
            }
          },
        );
      }
    }

    testWidgets('page 3 carries the model choice and the hotkey block, page 4 '
        'the theme choice — the split that bought page 3 its heading', (
      tester,
    ) async {
      tester.view.physicalSize = kOnboardingWindowSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await _pumpOverlay(tester, size: kOnboardingWindowSize);
        await _tapNext(tester); // → page 2
        await _tapNext(tester); // → page 3: Model & Hotkey

        expect(find.byKey(kModelStepEngineParakeetCardKey), findsOneWidget);
        expect(find.byKey(kTriggerStepChangeHotkeyKey), findsOneWidget);
        expect(
          find.byKey(kAppearanceThemeSelectorKey),
          findsNothing,
          reason: 'The theme choice must have left this page.',
        );

        await _tapNext(tester); // → page 4: Appearance
        expect(find.byKey(kAppearanceThemeSelectorKey), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
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
