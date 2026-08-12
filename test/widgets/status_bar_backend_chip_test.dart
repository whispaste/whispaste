/// Widget tests for the `WpStatusBar` far-right CPU/GPU backend chip.
///
/// The chip is deliberately separate from the main STT mode/state chip (see
/// `app.dart`'s `_sttBackendKind` doc comment): it shows only the coarse
/// device kind — never the specific architecture (Metal/CUDA/Vulkan) — plus
/// a utilization percentage, and is entirely absent when the host passes no
/// [WpStatusBar.backendKind] (no model loaded yet, Parakeet engine, or the
/// user turned the Settings toggle off — see `app.dart`'s gating of
/// `sttBackendKind` on `interface_.showBackendUtilization`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/widgets/status_bar.dart';

import '../fixtures/test_helpers.dart';

void main() {
  Widget buildStatusBar({
    String? backendKind,
    double? backendUtilizationPercent,
  }) {
    return makeTestable(
      Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          WpStatusBar(
            sttModeLabel: 'On device',
            sttState: SttServerState.ready,
            backendKind: backendKind,
            backendUtilizationPercent: backendUtilizationPercent,
          ),
        ],
      ),
    );
  }

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.devicePixelRatio = 1.0;
    view.physicalSize = const Size(1280, 800);
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetDevicePixelRatio();
    view.resetPhysicalSize();
  });

  testWidgets('hidden when the host passes no backend kind (e.g. toggle off)', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildStatusBar(backendKind: null, backendUtilizationPercent: 42),
    );
    await tester.pump();

    expect(find.byIcon(LucideIcons.cpu), findsNothing);
    expect(find.byIcon(LucideIcons.zap), findsNothing);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets(
    'shows "CPU" with the cpu icon and no percent before a reading exists',
    (tester) async {
      await tester.pumpWidget(
        buildStatusBar(backendKind: 'CPU', backendUtilizationPercent: null),
      );
      await tester.pump();

      expect(find.byIcon(LucideIcons.cpu), findsOneWidget);
      expect(find.text('CPU'), findsOneWidget);
    },
  );

  testWidgets('shows "CPU · N%" once a utilization reading exists', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildStatusBar(backendKind: 'CPU', backendUtilizationPercent: 37.6),
    );
    await tester.pump();

    expect(find.byIcon(LucideIcons.cpu), findsOneWidget);
    expect(find.text('CPU · 38%'), findsOneWidget);
  });

  testWidgets('shows "GPU · N%" with the zap icon — the percent is still a '
      'CPU reading (see tooltip), never the raw architecture name', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildStatusBar(backendKind: 'GPU', backendUtilizationPercent: 12.4),
    );
    await tester.pump();

    expect(find.byIcon(LucideIcons.zap), findsOneWidget);
    expect(find.byIcon(LucideIcons.cpu), findsNothing);
    expect(find.text('GPU · 12%'), findsOneWidget);
    expect(find.textContaining('Metal'), findsNothing);
  });
}
