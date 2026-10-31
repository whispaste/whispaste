/// Widget tests for [MicPermissionChip] (onboarding page 1).
///
/// The chip is a pure consumer of [MicPermissionNotifier] — covered here:
///  - fresh install never reads "action needed" before the first request;
///  - state mapping: unknown/requesting → pending, granted → ready,
///    denied → action needed;
///  - a tap always calls request() (the notifier decides between OS dialog
///    and Settings deep-link — no denied-handling in the widget);
///  - no chip on Linux (no Settings deep-link exists there);
///  - a grant applied outside the app is picked up by a side-effect-free
///    check() (the onWindowFocus recheck path) without restarting onboarding;
///  - the chip announces its status exactly once (MergeSemantics + the label
///    living only in the Text, not duplicated onto the Semantics wrapper).
///
/// Platform truth is faked through [MicPermissionChecker] — same pattern as
/// `test/services/paste/paste_capability_notifier_test.dart` and
/// `test/services/permissions/mic_permission_notifier_test.dart`.
library;

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/onboarding/steps/mic_permission_chip.dart';
import 'package:whispaste/services/permissions/mic_permission_notifier.dart';

import '../../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Scriptable platform truth behind the real [MicPermissionNotifier].
class _FakeMicPermissionChecker implements MicPermissionChecker {
  _FakeMicPermissionChecker({this.granted = false});

  /// Platform answer for the next check — mutable so a test can model a
  /// grant applied outside the app (System Settings) mid-flight.
  bool granted;

  /// Every `request` flag the notifier passed down — `false` entries are
  /// passive reads, `true` entries would have prompted the OS.
  final List<bool> calls = <bool>[];

  @override
  Future<bool> check({required bool request}) async {
    calls.add(request);
    return granted;
  }
}

/// Notifier stub pinned to one status — lets a test render each chip state
/// directly and record request() taps without platform involvement.
class _StubMicNotifier extends MicPermissionNotifier {
  _StubMicNotifier(this._status);

  final MicPermissionStatus _status;
  int requestCalls = 0;

  @override
  MicPermissionState build() => MicPermissionState(status: _status);

  @override
  Future<bool> check() async => _status == MicPermissionStatus.granted;

  @override
  Future<bool> request() async {
    requestCalls++;
    return false;
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

late L10n l10n;

Future<void> _pumpChip(
  WidgetTester tester, {
  _FakeMicPermissionChecker? checker,
  MicPermissionNotifier Function()? notifier,
}) async {
  await tester.pumpWidget(
    makeTestable(
      const MicPermissionChip(),
      locale: const Locale('en'),
      overrides: [
        if (checker != null)
          micPermissionCheckerProvider.overrideWithValue(checker),
        if (notifier != null)
          micPermissionNotifierProvider.overrideWith(notifier),
      ],
    ),
  );
  // Bounded pumps instead of pumpAndSettle: the `requesting` state renders an
  // indeterminate spinner that never settles. Two pumps run the post-frame
  // check() plus its state propagation; the timed pump finishes the entry
  // animations.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('MicPermissionChip — fresh install', () {
    testWidgets(
      'shows "pending", never "action needed", before the first request — '
      'and only ever performs the passive check on mount (no OS prompt)',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          final checker = _FakeMicPermissionChecker();
          await _pumpChip(tester, checker: checker);

          expect(find.text(l10n.onboardingMicChipPending), findsOneWidget);
          expect(find.text(l10n.onboardingMicChipAction), findsNothing);
          expect(find.text(l10n.onboardingMicChipReady), findsNothing);
          expect(
            checker.calls,
            [false],
            reason:
                'Mount must trigger exactly one side-effect-free check — a '
                'request:true call here would fire the OS dialog on appear.',
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets('a permission granted before launch reads "ready" right away', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        final checker = _FakeMicPermissionChecker(granted: true);
        await _pumpChip(tester, checker: checker);

        expect(find.text(l10n.onboardingMicChipReady), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('MicPermissionChip — state mapping', () {
    final expectations = <MicPermissionStatus, String Function()>{
      MicPermissionStatus.unknown: () => l10n.onboardingMicChipPending,
      MicPermissionStatus.requesting: () => l10n.onboardingMicChipPending,
      MicPermissionStatus.granted: () => l10n.onboardingMicChipReady,
      MicPermissionStatus.denied: () => l10n.onboardingMicChipAction,
    };

    for (final entry in expectations.entries) {
      testWidgets('${entry.key} renders the correct label', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          await _pumpChip(tester, notifier: () => _StubMicNotifier(entry.key));

          expect(find.text(entry.value()), findsOneWidget);
          // The spinner accompanies only the in-flight request.
          expect(
            find.byType(CircularProgressIndicator),
            entry.key == MicPermissionStatus.requesting
                ? findsOneWidget
                : findsNothing,
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  });

  group('MicPermissionChip — tap', () {
    for (final status in MicPermissionStatus.values) {
      testWidgets('tap in $status always calls request()', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          final stub = _StubMicNotifier(status);
          await _pumpChip(tester, notifier: () => stub);

          await tester.tap(find.byType(MicPermissionChip));
          // Single pump — pumpAndSettle would never settle on the
          // `requesting` spinner.
          await tester.pump();

          expect(
            stub.requestCalls,
            1,
            reason:
                'The widget must not second-guess the notifier — request() '
                'itself decides between OS dialog and deep-link recovery.',
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  });

  group('MicPermissionChip — Linux', () {
    testWidgets(
      'renders nothing and never touches the platform — the chip must not '
      'promise an action (Settings deep-link) that Linux does not have',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        try {
          final checker = _FakeMicPermissionChecker();
          await _pumpChip(tester, checker: checker);

          expect(find.text(l10n.onboardingMicChipPending), findsNothing);
          expect(find.text(l10n.onboardingMicChipReady), findsNothing);
          expect(find.text(l10n.onboardingMicChipAction), findsNothing);
          expect(tester.getSize(find.byType(MicPermissionChip)), Size.zero);
          expect(checker.calls, isEmpty);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  });

  group('MicPermissionChip — external grant', () {
    testWidgets('a grant applied in System Settings is picked up by a later '
        'side-effect-free check() (onWindowFocus path) without a restart', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final checker = _FakeMicPermissionChecker();
        await _pumpChip(tester, checker: checker);
        expect(find.text(l10n.onboardingMicChipPending), findsOneWidget);

        // The user flips the toggle in System Settings…
        checker.granted = true;
        // …and returns to the app: app.dart's onWindowFocus re-checks.
        final container = ProviderScope.containerOf(
          tester.element(find.byType(MicPermissionChip)),
        );
        await container.read(micPermissionNotifierProvider.notifier).check();
        await tester.pumpAndSettle();

        expect(find.text(l10n.onboardingMicChipReady), findsOneWidget);
        expect(find.text(l10n.onboardingMicChipPending), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('MicPermissionChip \u2014 semantics', () {
    testWidgets('announces its status exactly once, as a button', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final handle = tester.ensureSemantics();
      try {
        final checker = _FakeMicPermissionChecker(granted: true);
        await _pumpChip(tester, checker: checker);

        // Regression guard: the wrapper used to carry `label:` *and* wrap a
        // Text of the same string, so a screen reader read the status twice
        // ("Microphone ready, Microphone ready"). The label must come from
        // the Text alone, folded in by MergeSemantics — and the button role
        // plus the tap action have to survive that folding, or the chip is
        // announced as something a screen reader cannot activate.
        expect(
          tester.getSemantics(find.byType(MicPermissionChip)),
          matchesSemantics(
            label: l10n.onboardingMicChipReady,
            isButton: true,
            hasTapAction: true,
            hasFocusAction: true,
            isFocusable: true,
          ),
        );
      } finally {
        handle.dispose();
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
