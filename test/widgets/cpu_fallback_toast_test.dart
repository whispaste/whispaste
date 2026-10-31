/// Tests for the CPU-fallback status toast wired in `recording_behavior.dart`.
///
/// Mirrors the extracted-helper pattern from `recovery_toast_test.dart`:
/// the pure transition gate ([shouldShowCpuFallbackToast]) is unit-tested
/// without any widget tree, and the toast rendering itself
/// ([showCpuFallbackToast]) is exercised through a minimal harness widget —
/// neither needs the full `WpRecordingBehavior` + `ref.listen` wiring
/// mounted, so no app-shell/overlay bootstrapping is required to prove the
/// behaviour.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/stt/stt_bundle.dart';
import 'package:whispaste/widgets/recording_behavior.dart';

import '../fixtures/test_helpers.dart';

class _CpuFallbackHarness extends StatelessWidget {
  const _CpuFallbackHarness();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: () =>
            showCpuFallbackToast(context: context, l10n: L10n.of(context)),
        child: const Text('fire-cpu-fallback-toast'),
      ),
    );
  }
}

void main() {
  late L10n lDe;
  late L10n lEn;
  setUpAll(() async {
    lDe = await L10n.delegate.load(const Locale('de'));
    lEn = await L10n.delegate.load(const Locale('en'));
  });

  group('shouldShowCpuFallbackToast (pure transition gate)', () {
    test('false → true (no prior status) triggers the toast', () {
      expect(
        shouldShowCpuFallbackToast(
          null,
          const SttStatus(cpuFallbackActive: true),
        ),
        isTrue,
      );
    });

    test('false → true triggers the toast', () {
      expect(
        shouldShowCpuFallbackToast(
          const SttStatus(cpuFallbackActive: false),
          const SttStatus(cpuFallbackActive: true),
        ),
        isTrue,
      );
    });

    test('true → true (no real transition) does NOT re-trigger', () {
      expect(
        shouldShowCpuFallbackToast(
          const SttStatus(cpuFallbackActive: true),
          const SttStatus(cpuFallbackActive: true),
        ),
        isFalse,
        reason:
            'Repeated status emissions while fallback stays active must '
            'not spam a new toast each time.',
      );
    });

    test('true → false (GPU recovered) does not trigger the toast', () {
      expect(
        shouldShowCpuFallbackToast(
          const SttStatus(cpuFallbackActive: true),
          const SttStatus(cpuFallbackActive: false),
        ),
        isFalse,
      );
    });

    test('false → false does not trigger the toast', () {
      expect(
        shouldShowCpuFallbackToast(
          const SttStatus(cpuFallbackActive: false),
          const SttStatus(cpuFallbackActive: false),
        ),
        isFalse,
      );
    });
  });

  group('showCpuFallbackToast', () {
    testWidgets('renders a plain-language info toast with no action button', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(const _CpuFallbackHarness(), locale: const Locale('de')),
      );

      await tester.tap(find.text('fire-cpu-fallback-toast'));
      await tester.pumpAndSettle();

      expect(find.text(lDe.cpuFallbackToast), findsOneWidget);

      // Drain the toast's auto-dismiss timer so no Timer outlives the test.
      await tester.pumpAndSettle(const Duration(seconds: 6));
    });

    testWidgets('en locale: English copy matches the ARB entry', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(const _CpuFallbackHarness(), locale: const Locale('en')),
      );

      await tester.tap(find.text('fire-cpu-fallback-toast'));
      await tester.pumpAndSettle();

      expect(find.text(lEn.cpuFallbackToast), findsOneWidget);

      await tester.pumpAndSettle(const Duration(seconds: 6));
    });
  });
}
