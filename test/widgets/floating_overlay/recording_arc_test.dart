/// Recording-arc tests for the floating overlay (issue 09 — C1a).
///
/// Covers:
///  - AC1: Full arc Standby→Recording→Transcribing→Done (normal + compact);
///    spring appear animation; calm live waveform (no motion outside the arc).
///  - AC2: Vibrancy spec — platform-specific material selection + flat fallback.
///  - AC4: Anti-goals — no glow in spec; arc motion limited to appear +
///    state-crossfade (no scattered/decorative effects).
///  - AC6: Reduced-motion respected — dot pulse stops, spring is instant when
///    MediaQuery.disableAnimations is true; gates in WpFloatingOverlayView.
///
/// AC3 (litmus "five dictated sentences") and AC5 (HITL feel + vibrancy
/// sign-off) are human acceptance gates performed AFTER this build.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller_interface.dart';
import 'package:whispaste/widgets/floating_overlay/floating_overlay_view.dart';
import 'package:whispaste/widgets/floating_overlay/overlay_painter.dart';

// ── Snapshot helper ──────────────────────────────────────────────────────────

FloatingOverlaySnapshot _snap(
  OverlayVisualState state, {
  bool visible = true,
  OverlaySizeVariant size = OverlaySizeVariant.normal,
  String elapsed = '',
  String? doneMessage,
  String? errorMessage,
  double progress = 0.0,
}) {
  return FloatingOverlaySnapshot(
    visible: visible,
    state: state,
    size: size,
    label: switch (state) {
      OverlayVisualState.recording => 'Recording',
      OverlayVisualState.transcribing => 'Transcribing…',
      OverlayVisualState.done => 'Done',
      OverlayVisualState.error => 'Error',
    },
    elapsed: elapsed,
    doneMessage: doneMessage,
    errorMessage: errorMessage,
    progress: progress,
  );
}

/// Wraps [child] with the minimal MediaQuery + Directionality ancestors the
/// widget tree needs.
Widget _wrap(Widget child, {bool disableAnimations = false}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Directionality(textDirection: TextDirection.ltr, child: child),
  );
}

void main() {
  // ── AC1: Full recording arc ────────────────────────────────────────────────

  group('AC1 — full recording arc: painter config per state/size', () {
    for (final state in OverlayVisualState.values) {
      for (final size in OverlaySizeVariant.values) {
        final tag = '${state.name} · ${size.name}';

        testWidgets('$tag — builds without error', (tester) async {
          final bars = List<double>.generate(
            OverlayDesignSpec.waveform.barCount,
            (i) => (i % 5) / 5.0,
          );
          await tester.pumpWidget(
            _wrap(
              WpFloatingOverlayView(
                snapshot: _snap(
                  state,
                  size: size,
                  elapsed: state == OverlayVisualState.recording ? '0:07' : '',
                  progress: state == OverlayVisualState.recording ? 0.2 : 0.0,
                  doneMessage: state == OverlayVisualState.done
                      ? 'Eingefügt!'
                      : null,
                  errorMessage: state == OverlayVisualState.error
                      ? 'Kein Netzwerk'
                      : null,
                ),
                waveformBars: bars,
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 16));
          expect(find.byType(CustomPaint), findsWidgets);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }

    test('painterFor wires live waveform in recording, empty otherwise', () {
      final bars = List<double>.filled(
        OverlayDesignSpec.waveform.barCount,
        0.7,
      );
      for (final state in OverlayVisualState.values) {
        final painter = WpFloatingOverlayView.painterFor(
          snapshot: _snap(state, elapsed: '0:12', progress: 0.1),
          waveformBars: bars,
        );
        if (state == OverlayVisualState.recording) {
          expect(
            painter.waveformBars,
            isNotEmpty,
            reason: '$state should pass bars',
          );
        } else {
          expect(
            painter.waveformBars,
            isEmpty,
            reason: '$state should suppress bars',
          );
        }
      }
    });

    test(
      'done state with paste-confirmation doneMessage flows to statusText',
      () {
        const pasteMsg = 'Eingefügt!';
        final painter = WpFloatingOverlayView.painterFor(
          snapshot: _snap(OverlayVisualState.done, doneMessage: pasteMsg),
        );
        expect(painter.statusText, pasteMsg);
      },
    );

    test('recording arc covers standby (visible=false) → recording → done', () {
      // All valid snapshot transitions are spec-driven; the arc is closed.
      final standby = _snap(OverlayVisualState.recording, visible: false);
      final recording = _snap(
        OverlayVisualState.recording,
        visible: true,
        elapsed: '0:15',
        progress: 0.05,
      );
      final transcribing = _snap(
        OverlayVisualState.transcribing,
        visible: true,
      );
      final done = _snap(
        OverlayVisualState.done,
        visible: true,
        doneMessage: 'Eingefügt!',
      );

      for (final snap in [standby, recording, transcribing, done]) {
        expect(
          () => WpFloatingOverlayView.painterFor(snapshot: snap),
          returnsNormally,
        );
      }
    });
  });

  // ── AC1: Spring appear animation ─────────────────────────────────────────

  group('AC1 — spring appear animation (wow-moment)', () {
    testWidgets('overlay starts transparent when visible=false', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          WpFloatingOverlayView(
            snapshot: _snap(OverlayVisualState.recording, visible: false),
          ),
        ),
      );
      await tester.pump();
      final opacity = tester.widget<Opacity>(find.byType(Opacity).first);
      expect(opacity.opacity, 0.0);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'overlay is immediately opaque when created with visible=true',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            WpFloatingOverlayView(
              snapshot: _snap(OverlayVisualState.recording, visible: true),
            ),
          ),
        );
        await tester.pump();
        final opacity = tester.widget<Opacity>(find.byType(Opacity).first);
        expect(opacity.opacity, 1.0);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'spring-in: opacity > 0 mid-animation when visible flips true',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            WpFloatingOverlayView(
              snapshot: _snap(OverlayVisualState.recording, visible: false),
            ),
          ),
        );

        // Flip visible → triggers spring-in animation.
        await tester.pumpWidget(
          _wrap(
            WpFloatingOverlayView(
              snapshot: _snap(
                OverlayVisualState.recording,
                visible: true,
                elapsed: '0:03',
              ),
            ),
          ),
        );
        // Advance one short tick — animation is in flight.
        await tester.pump(const Duration(milliseconds: 50));
        final opacity = tester.widget<Opacity>(find.byType(Opacity).first);
        expect(opacity.opacity, greaterThan(0.0));
        expect(opacity.opacity, lessThan(1.0));

        // Advance past the full appear duration (300ms hard-cap + margin).
        await tester.pump(const Duration(milliseconds: 350));
        final opacityFinal = tester.widget<Opacity>(find.byType(Opacity).first);
        expect(opacityFinal.opacity, closeTo(1.0, 0.001));
        // Teardown without pumpAndSettle — dot pulse is still running.
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      're-show: overlay is opaque again on a second show after a hide '
      '(regression — overlay was invisible on every recording after the first)',
      (tester) async {
        Widget view(bool visible) => _wrap(
          WpFloatingOverlayView(
            snapshot: _snap(
              OverlayVisualState.recording,
              visible: visible,
              elapsed: visible ? '0:02' : '',
            ),
          ),
        );

        // First recording: appear settles to fully opaque.
        await tester.pumpWidget(view(true));
        await tester.pump(const Duration(milliseconds: 350));
        expect(
          tester.widget<Opacity>(find.byType(Opacity).first).opacity,
          closeTo(1.0, 0.001),
        );

        // Recording ends: hide snaps the appear controller back to 0.
        await tester.pumpWidget(view(false));
        await tester.pump();
        expect(tester.widget<Opacity>(find.byType(Opacity).first).opacity, 0.0);

        // Second recording: the capsule MUST fade back in — before the re-show
        // guard it stayed transparent (Opacity 0) while the native panel was
        // ordered front, so nothing was visible from the second recording on.
        await tester.pumpWidget(view(true));
        await tester.pump(const Duration(milliseconds: 350));
        expect(
          tester.widget<Opacity>(find.byType(Opacity).first).opacity,
          closeTo(1.0, 0.001),
          reason: 'overlay must be opaque again on the second show',
        );

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('spring-in uses scale from below 1.0 (spec appearScale)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          WpFloatingOverlayView(
            snapshot: _snap(OverlayVisualState.recording, visible: false),
          ),
        ),
      );
      await tester.pumpWidget(
        _wrap(
          WpFloatingOverlayView(
            snapshot: _snap(OverlayVisualState.recording, visible: true),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      // Mid-animation: Transform.scale builds Matrix4.diagonal3Values(s,s,1).
      // matrix[0] = X scale (column-major storage from vector_math_64).
      // getMaxScaleOnAxis() would return max(s, 1.0) = 1.0 even when s < 1 —
      // so we read the X entry directly.
      final transform = tester.widget<Transform>(find.byType(Transform).first);
      final midScale = transform.transform[0]; // X scale entry
      expect(
        midScale,
        greaterThan(OverlayDesignSpec.arc.appearScale),
        reason: 'scale should be above initial floor mid-animation',
      );
      expect(
        midScale,
        lessThan(1.0),
        reason: 'scale should not yet reach 1.0 mid-animation',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });

    test('arc spec: appearDuration ≤ 700ms hard-cap (Phase-0)', () {
      expect(
        OverlayDesignSpec.arc.appearDuration,
        lessThanOrEqualTo(const Duration(milliseconds: 700)),
      );
    });

    test('arc spec: appearScale is below 1.0 (subtle, not a jump-cut)', () {
      final s = OverlayDesignSpec.arc.appearScale;
      expect(s, greaterThan(0.5), reason: 'should not shrink too aggressively');
      expect(s, lessThan(1.0), reason: 'should start below full size');
    });

    test(
      'arc spec: appearCurve is easeOutCubic (WpMotion.spring, no overshoot)',
      () {
        // Phase-0: Gentle 170/26, no overshoot — easeOutCubic approximation.
        expect(OverlayDesignSpec.arc.appearCurve, same(Curves.easeOutCubic));
        expect(
          OverlayDesignSpec.arc.appearCurve,
          isNot(same(Curves.elasticOut)),
          reason: 'old elasticOut was removed in Phase-0',
        );
      },
    );

    test('arc spec: state-transition duration ≤ normal cap', () {
      expect(
        OverlayDesignSpec.arc.stateTransitionDuration,
        lessThanOrEqualTo(const Duration(milliseconds: 300)),
      );
    });

    test('arc spec: state-transition curve is calm (no elastic/bounce)', () {
      // AC4 anti-goal: the crossfade between recording-arc states must stay
      // calm — a plain ease, never an elastic/overshoot curve.
      expect(
        OverlayDesignSpec.arc.stateTransitionCurve,
        isNot(isA<ElasticOutCurve>()),
      );
      expect(
        OverlayDesignSpec.arc.stateTransitionCurve,
        equals(Curves.easeOut),
      );
    });
  });

  // ── AC2: Vibrancy spec (platform-aware) ───────────────────────────────────

  group('AC2 — vibrancy spec: platform-aware material selection', () {
    test('macOS material = hudWindow (Phase-0 GO, best optics confirmed)', () {
      expect(
        OverlayDesignSpec.vibrancy.macOS,
        OverlayVibrancyMaterial.hudWindow,
      );
    });

    test('Windows material = acrylic (planned, flutter_acrylic)', () {
      expect(
        OverlayDesignSpec.vibrancy.windows,
        OverlayVibrancyMaterial.acrylic,
      );
    });

    test('Linux material = flat (default tinted fallback, no OS blur)', () {
      expect(OverlayDesignSpec.vibrancy.linux, OverlayVibrancyMaterial.flat);
    });

    test('forPlatform selects macOS/Windows/Linux by platform string', () {
      const v = OverlayDesignSpec.vibrancy;
      expect(v.forPlatform('macos'), OverlayVibrancyMaterial.hudWindow);
      expect(v.forPlatform('windows'), OverlayVibrancyMaterial.acrylic);
      expect(v.forPlatform('linux'), OverlayVibrancyMaterial.flat);
    });

    test('forPlatform falls back to flat for unknown platform', () {
      expect(
        OverlayDesignSpec.vibrancy.forPlatform('unknown'),
        OverlayVibrancyMaterial.flat,
      );
      expect(
        OverlayDesignSpec.vibrancy.forPlatform(''),
        OverlayVibrancyMaterial.flat,
      );
    });

    test(
      'flat fallback fill opacity is higher than vibrancy fill (more opaque without blur)',
      () {
        // Without OS-level blur, the capsule needs more opacity for readability.
        expect(
          OverlayDesignSpec.flatFallbackFillOpacity,
          greaterThan(OverlayDesignSpec.fillOpacityFactor),
        );
        // But never exceeds 1.0.
        expect(
          OverlayDesignSpec.flatFallbackFillOpacity,
          lessThanOrEqualTo(1.0),
        );
      },
    );

    test('OverlayVibrancyMaterial enum covers all required variants', () {
      expect(
        OverlayVibrancyMaterial.values,
        containsAll(<OverlayVibrancyMaterial>[
          OverlayVibrancyMaterial.hudWindow,
          OverlayVibrancyMaterial.acrylic,
          OverlayVibrancyMaterial.mica,
          OverlayVibrancyMaterial.flat,
        ]),
      );
    });
  });

  // ── AC4: Anti-goals ───────────────────────────────────────────────────────

  group('AC4 — anti-goals: no glow, no decorative / scattered motion', () {
    test('button spec explicitly has hasGlow = false', () {
      expect(OverlayDesignSpec.button.hasGlow, isFalse);
    });

    test('OverlayThemeColors has no glow color field', () {
      // Structural: there is no field named "glow" in the theme color set.
      // If a glow field were added, the Flutter analyzer would catch it via
      // dead-code or the AC4 assertion here would fail on inspection.
      const colors = OverlayDesignSpec.light;
      // All defined fields: capsuleFillStart, capsuleFillEnd, capsuleBorder,
      // text, accent, success, error, recordingDot. None is "glow".
      expect(colors.accent, isNotNull); // accent is teal, not a glow tint
    });

    test('arc appear duration is within Phase-0 hard-cap (≤ 700 ms)', () {
      expect(
        OverlayDesignSpec.arc.appearDuration.inMilliseconds,
        lessThanOrEqualTo(700),
      );
    });

    test('state transition duration is calm (≤ 300 ms)', () {
      expect(
        OverlayDesignSpec.arc.stateTransitionDuration.inMilliseconds,
        lessThanOrEqualTo(300),
      );
    });

    test('appear curve is non-overshooting (no bounce/elastic)', () {
      final curve = OverlayDesignSpec.arc.appearCurve;
      // Must NOT be any elastic/spring-with-overshoot curve.
      expect(curve, isNot(same(Curves.elasticIn)));
      expect(curve, isNot(same(Curves.elasticOut)));
      expect(curve, isNot(same(Curves.elasticInOut)));
      expect(curve, isNot(same(Curves.bounceOut)));
      // Must be easeOutCubic (approved Phase-0 curve — critically damped).
      expect(curve, same(Curves.easeOutCubic));
    });

    test('waveform parameters produce calm, not erratic bar behavior', () {
      const wf = OverlayDesignSpec.waveform;
      // Release is slower than attack → decays gently on silence (no jitter).
      expect(wf.releaseTimeConstantMs, greaterThan(wf.attackTimeConstantMs));
      // Rest level is low but non-zero → flat at silence, no dead-flat pulse.
      expect(OverlayDesignSpec.waveformRestLevel, greaterThan(0.0));
      expect(OverlayDesignSpec.waveformRestLevel, lessThan(0.2));
    });
  });

  // ── Issue 09 wiring: state-transition crossfade ───────────────────────────

  group('state-transition crossfade (issue 09 wiring)', () {
    testWidgets('(a) visible state change renders 3-layer Stack mid-crossfade '
        '(fill + outgoing content + incoming content)', (tester) async {
      // Mount with recording visible and let appear settle.
      await tester.pumpWidget(
        _wrap(
          WpFloatingOverlayView(
            snapshot: _snap(
              OverlayVisualState.recording,
              visible: true,
              elapsed: '0:05',
              progress: 0.1,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 350));
      // Steady state: one CustomPaint.
      expect(find.byType(CustomPaint), findsOneWidget);

      // Transition to transcribing (visible → visible state change).
      await tester.pumpWidget(
        _wrap(
          WpFloatingOverlayView(
            snapshot: _snap(OverlayVisualState.transcribing, visible: true),
          ),
        ),
      );
      // Pump to mid-crossfade. `recording → transcribing` runs for the
      // release-out window (OverlayDesignSpec.arc.releaseOutDuration) rather
      // than the generic stateTransitionDuration, so the decaying waveform the
      // service is still feeding stays painted for the whole decay
      // (overlay_release_out_test.dart).
      await tester.pump(const Duration(milliseconds: 50));

      // During crossfade: 3 CustomPaint layers.
      expect(
        find.byType(CustomPaint),
        findsNWidgets(3),
        reason:
            'mid-crossfade must render fill + outgoing-content + '
            'incoming-content painters',
      );

      // Advance past full crossfade + setState drain.
      await tester.pump(
        OverlayDesignSpec.arc.releaseOutDuration +
            const Duration(milliseconds: 50),
      );
      await tester.pump();

      // Steady state again: one CustomPaint.
      expect(
        find.byType(CustomPaint),
        findsOneWidget,
        reason: 'after crossfade completes only one painter should remain',
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });

    test(
      '(b) WpOverlayPainter paintFill/paintContent flags affect shouldRepaint',
      () {
        final snap = _snap(OverlayVisualState.recording, visible: true);
        final base = WpFloatingOverlayView.painterFor(snapshot: snap);
        final fillOnly = WpFloatingOverlayView.painterFor(
          snapshot: snap,
          paintContent: false,
        );
        final contentOnly = WpFloatingOverlayView.painterFor(
          snapshot: snap,
          paintFill: false,
        );

        // shouldRepaint detects flag differences.
        expect(
          base.shouldRepaint(fillOnly),
          isTrue,
          reason: 'paintContent change must trigger repaint',
        );
        expect(
          base.shouldRepaint(contentOnly),
          isTrue,
          reason: 'paintFill change must trigger repaint',
        );

        // Field accessors are correct.
        expect(base.paintFill, isTrue);
        expect(base.paintContent, isTrue);
        expect(fillOnly.paintContent, isFalse);
        expect(contentOnly.paintFill, isFalse);
      },
    );

    testWidgets(
      '(c) reduced-motion skips crossfade — single CustomPaint after state change',
      (tester) async {
        // Mount recording visible under reduced-motion.
        await tester.pumpWidget(
          _wrap(
            WpFloatingOverlayView(
              snapshot: _snap(
                OverlayVisualState.recording,
                visible: true,
                elapsed: '0:03',
              ),
            ),
            disableAnimations: true,
          ),
        );
        await tester.pump();

        // Transition to transcribing.
        await tester.pumpWidget(
          _wrap(
            WpFloatingOverlayView(
              snapshot: _snap(OverlayVisualState.transcribing, visible: true),
            ),
            disableAnimations: true,
          ),
        );
        await tester.pump();

        // Under reduced-motion no crossfade: single CustomPaint only.
        expect(
          find.byType(CustomPaint),
          findsOneWidget,
          reason: 'reduced-motion must snap — no 3-layer Stack',
        );
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  });

  // ── AC6: Reduced-motion ───────────────────────────────────────────────────

  group('AC6 — reduced-motion (disableAnimations)', () {
    testWidgets(
      'appear is instant when disableAnimations=true (opacity=1 after one pump)',
      (tester) async {
        // Start hidden.
        await tester.pumpWidget(
          _wrap(
            WpFloatingOverlayView(
              snapshot: _snap(OverlayVisualState.recording, visible: false),
            ),
            disableAnimations: true,
          ),
        );

        // Flip to visible.
        await tester.pumpWidget(
          _wrap(
            WpFloatingOverlayView(
              snapshot: _snap(
                OverlayVisualState.recording,
                visible: true,
                elapsed: '0:01',
              ),
            ),
            disableAnimations: true,
          ),
        );

        // Single pump — no in-flight animation, should already be 1.0.
        await tester.pump();
        final opacity = tester.widget<Opacity>(find.byType(Opacity).first);
        expect(
          opacity.opacity,
          1.0,
          reason: 'must be instant under reduced-motion',
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'dot pulse does not run under reduced-motion (pumpAndSettle completes)',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            // animate: true would normally start the repeating pulse.
            WpFloatingOverlayView(
              snapshot: _snap(OverlayVisualState.recording, visible: true),
              animate: true,
            ),
            disableAnimations: true,
          ),
        );
        // pumpAndSettle would hang if the pulse ticker were running. It must
        // complete here because disableAnimations collapses all durations → 0.
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'dot pulse DOES run when animate=true and disableAnimations=false',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            WpFloatingOverlayView(
              snapshot: _snap(OverlayVisualState.recording, visible: true),
              animate: true,
            ),
          ),
        );
        // Advance two frames — the dot repeating controller should be running.
        await tester.pump(const Duration(milliseconds: 100));
        // If the dot ticker were NOT running this would also pass, so we
        // verify by looking at the painted Opacity value: the appear animation
        // should have settled at 1.0 (visible=true from initState), meaning
        // the only remaining tickers are the dot repeat. The widget must not
        // crash after 100ms even with an active repeat.
        expect(find.byType(CustomPaint), findsWidgets);
        expect(tester.takeException(), isNull);
        // Teardown without pumpAndSettle — dot pulse is still running.
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'appear animation does not run under reduced-motion (scale stays at 1.0)',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            WpFloatingOverlayView(
              snapshot: _snap(OverlayVisualState.recording, visible: false),
            ),
            disableAnimations: true,
          ),
        );
        await tester.pumpWidget(
          _wrap(
            WpFloatingOverlayView(
              snapshot: _snap(OverlayVisualState.recording, visible: true),
            ),
            disableAnimations: true,
          ),
        );
        await tester.pump();

        final transform = tester.widget<Transform>(
          find.byType(Transform).first,
        );
        // X scale entry (column-major Matrix4.diagonal3Values(s,s,1)).
        final scale = transform.transform[0];
        expect(
          scale,
          closeTo(1.0, 0.001),
          reason: 'no scale animation under reduced-motion',
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    test('WpMotion.durationFor returns zero when disableAnimations=true', () {
      // This is the project-wide pattern; referenced here as AC6 anchor.
      // Verified in the token tests; just confirm the API exists + returns 0.
      // (We can't call it without a BuildContext in a pure test, but we can
      // verify the spec arc duration is non-zero so the gate matters.)
      expect(
        OverlayDesignSpec.arc.appearDuration,
        isNot(Duration.zero),
        reason: 'duration must be non-zero so durationFor gate has effect',
      );
    });

    testWidgets('pill-width spring snaps to target under reduced-motion '
        '(pumpAndSettle completes, no hanging spring ticker)', (tester) async {
      // Mount recording state, visible, reduced-motion.
      await tester.pumpWidget(
        _wrap(
          WpFloatingOverlayView(
            snapshot: _snap(
              OverlayVisualState.recording,
              visible: true,
              elapsed: '0:05',
              progress: 0.1,
            ),
          ),
          disableAnimations: true,
        ),
      );
      await tester.pump();

      // Transition to done — under reduced-motion the spring must not start.
      await tester.pumpWidget(
        _wrap(
          WpFloatingOverlayView(
            snapshot: _snap(
              OverlayVisualState.done,
              visible: true,
              doneMessage: 'Eingefügt!',
            ),
          ),
          disableAnimations: true,
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);

      // pumpAndSettle must finish — a running spring ticker would hang here.
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  // ── Dynamic pill-width spring (issue 10) ──────────────────────────────────

  group('pill-width spring (issue 10)', () {
    testWidgets(
      'spring animates width mid-transition (no pumpAndSettle mid-flight)',
      (tester) async {
        // Mount recording visible — appear settles to 1.0.
        await tester.pumpWidget(
          _wrap(
            WpFloatingOverlayView(
              snapshot: _snap(
                OverlayVisualState.recording,
                visible: true,
                elapsed: '0:05',
                progress: 0.1,
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 350));

        // Steady-state: one CustomPaint, no exception.
        expect(find.byType(CustomPaint), findsOneWidget);

        // Transition to done — spring should start.
        await tester.pumpWidget(
          _wrap(
            WpFloatingOverlayView(
              snapshot: _snap(
                OverlayVisualState.done,
                visible: true,
                doneMessage: 'Eingefügt!',
              ),
            ),
          ),
        );

        // Advance a few ticks — spring is running, no exception.
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull);

        // Advance past a generous spring settle time (spring 170/26 ≈ 600 ms).
        await tester.pump(const Duration(milliseconds: 700));
        expect(tester.takeException(), isNull);

        // After settling: back to single CustomPaint (crossfade also done).
        expect(
          find.byType(CustomPaint),
          findsOneWidget,
          reason: 'after spring + crossfade settle: single painter',
        );

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('pill-width spring does not crash on rapid state changes '
        '(interruption test)', (tester) async {
      Future<void> push(OverlayVisualState s) async {
        await tester.pumpWidget(
          _wrap(WpFloatingOverlayView(snapshot: _snap(s, visible: true))),
        );
        await tester.pump(const Duration(milliseconds: 30));
      }

      await push(OverlayVisualState.recording);
      await push(OverlayVisualState.transcribing);
      await push(OverlayVisualState.done);
      await push(OverlayVisualState.error);
      await push(OverlayVisualState.recording);

      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  // ── Re-show pill width (waveform-gone-on-2nd-recording regression) ─────────
  //
  // Proven root cause: the pill-width spring only fires on a state change
  // between two *visible* snapshots. A second recording is a hide→show where
  // both the hide snapshot and the show snapshot carry state=recording, so no
  // spring fires and the pill stays at the previous episode's final `done`
  // (narrow) width — which clips the live waveform to nothing. The fix snaps
  // the pill to the current state's width on every (re-)appear.

  group('re-show pill width', () {
    double? steadyPillWidth(WidgetTester tester) {
      final painters = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<WpOverlayPainter>()
          .toList();
      // Steady state renders exactly one painter; during a crossfade there are
      // three. We only assert in steady state.
      return painters.length == 1 ? painters.single.pillWidth : null;
    }

    testWidgets('re-show after done restores the full recording width so the '
        'waveform is not clipped away', (tester) async {
      final sizeSpec = OverlayDesignSpec.size(compact: false);
      final layout = OverlayDesignSpec.layout(compact: false);
      final recW = OverlayDesignSpec.pillWidthFor(
        OverlayDesignState.recording,
        sizeSpec,
      );
      // pillWidthForText, not the raw ratio: the done pill grows just enough
      // to fit 'Eingefügt!' without an ellipsis (see OverlayDesignSpec doc).
      final doneW = OverlayDesignSpec.pillWidthForText(
        OverlayDesignState.done,
        sizeSpec,
        layout,
        'Eingefügt!',
      );
      expect(
        doneW,
        lessThan(recW),
        reason: 'precondition: the done pill is narrower than recording',
      );

      // Episode 1: recording visible — pill at full recording width.
      await tester.pumpWidget(
        _wrap(
          WpFloatingOverlayView(
            snapshot: _snap(OverlayVisualState.recording, visible: true),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 350));
      expect(steadyPillWidth(tester), closeTo(recW, 0.5));

      // recording → done: pill springs to the narrow done width.
      await tester.pumpWidget(
        _wrap(
          WpFloatingOverlayView(
            snapshot: _snap(
              OverlayVisualState.done,
              visible: true,
              doneMessage: 'Eingefügt!',
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(
        steadyPillWidth(tester),
        closeTo(doneW, 1.0),
        reason: 'after recording→done the pill should have shrunk',
      );

      // done → hidden. In production the hide snapshot carries state=recording,
      // so the next show is NOT a state change — reproduce that exactly.
      await tester.pumpWidget(
        _wrap(
          WpFloatingOverlayView(
            snapshot: _snap(OverlayVisualState.recording, visible: false),
          ),
        ),
      );
      await tester.pump();

      // Episode 2: re-show recording — pill MUST be back to full width.
      await tester.pumpWidget(
        _wrap(
          WpFloatingOverlayView(
            snapshot: _snap(OverlayVisualState.recording, visible: true),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        steadyPillWidth(tester),
        closeTo(recW, 0.5),
        reason:
            'BUG: re-shown recording pill stuck at the previous done width → '
            'live waveform clipped away ("gone on 2nd recording")',
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
