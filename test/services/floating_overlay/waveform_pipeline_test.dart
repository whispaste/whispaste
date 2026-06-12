/// Tests for [WaveformPipeline] — the scrolling-history waveform model.
///
/// Verifies the canonical model (PRD §D4, ADR 0002): right→left scrolling
/// history, volume-faithful amplitude, silence decaying to the min-height floor
/// without jitter, compact-as-scaled (not reduced), spec-sourced parameters and
/// determinism.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/floating_overlay/waveform_pipeline.dart';

/// Anchor time used as t0 in every time-dependent test.
final DateTime _t0 = DateTime.utc(2026, 1, 1);

/// Canonical bar count / floor straight from the SSOT.
final int _barCount = OverlayDesignSpec.waveform.barCount;
final double _minLevel =
    OverlayDesignSpec.waveform.minBarHeightPx /
    OverlayDesignSpec.normalSize.waveformMaxHeight;

/// Drives [steps] ticks at 33 ms cadence, holding [level] as the input the
/// whole time, returning the final snapshot.
List<double> _runConstant(WaveformPipeline p, double level, int steps) {
  for (var i = 0; i < steps; i++) {
    p.pushSample(level, _t0.add(Duration(milliseconds: 33 * i)));
    p.tick(_t0.add(Duration(milliseconds: 33 * i)));
  }
  return p.snapshot();
}

void main() {
  group('WaveformPipeline — interface + spec sourcing', () {
    test('exposes the pushSample/tick/snapshot/reset surface', () {
      final p = WaveformPipeline();
      p.pushSample(0.0, _t0);
      p.tick(_t0);
      expect(p.snapshot(), isA<List<double>>());
      p.reset();
    });

    test('bar count and floor come from the SSOT, not local constants', () {
      final p = WaveformPipeline();
      expect(p.barCount, OverlayDesignSpec.waveform.barCount);
      expect(p.snapshot(), hasLength(OverlayDesignSpec.waveform.barCount));
      expect(p.minBarLevel, closeTo(_minLevel, 1e-12));
    });
  });

  group('WaveformPipeline — initial state', () {
    test('fresh snapshot is length barCount, every bar at the floor', () {
      final p = WaveformPipeline();
      final s = p.snapshot();
      expect(s, hasLength(_barCount));
      for (final v in s) {
        expect(v, closeTo(_minLevel, 1e-12));
      }
    });
  });

  group('WaveformPipeline — AC: scrolling history (right→left)', () {
    test(
      'newest sample sits at the right edge; samples scroll left each tick',
      () {
        final p = WaveformPipeline();
        // Saturate attack to make a pushed level reach the bar almost fully in
        // one tick is unrealistic; instead feed the same value for several
        // ticks so the right-edge bar tracks it closely, then read positions.
        // Use three distinct sustained plateaus and confirm ordering.
        final marker = <double>[0.9, 0.6, 0.3];
        // Feed each plateau for 6 ticks (≈ 5τ at 33 ms cadence) so the display
        // level settles, leaving a recognisable trail in the history.
        var t = 0;
        for (final level in marker) {
          for (var k = 0; k < 6; k++) {
            p.pushSample(level, _t0.add(Duration(milliseconds: 33 * t)));
            p.tick(_t0.add(Duration(milliseconds: 33 * t)));
            t++;
          }
        }
        final s = p.snapshot();
        // The right edge is the freshest plateau (0.3 ≈ low), and walking left
        // we cross into the older, taller plateaus (0.6 then 0.9). The maximum
        // of the right-most third is below the maximum of the left two-thirds.
        final third = _barCount ~/ 3;
        final rightMax = s
            .sublist(_barCount - third)
            .reduce((a, b) => a > b ? a : b);
        final leftMax = s
            .sublist(0, _barCount - third)
            .reduce((a, b) => a > b ? a : b);
        expect(
          rightMax,
          lessThan(leftMax),
          reason:
              'Newest (low) plateau must sit at the right; older (loud) '
              'plateaus scrolled left. Got $s',
        );
      },
    );

    test('a single pushed level advances one bar per tick (deterministic)', () {
      final p = WaveformPipeline();
      // One loud tick, then silence: the loud moment must march left by exactly
      // one bar per subsequent tick.
      p.pushSample(1.0, _t0);
      p.tick(_t0); // baseline tick: no smoothing yet, scrolls rest in.
      p.pushSample(1.0, _t0.add(const Duration(milliseconds: 33)));
      p.tick(_t0.add(const Duration(milliseconds: 33)));
      final afterLoud = p.snapshot();
      final loudIndex = _argMax(afterLoud);
      expect(
        loudIndex,
        _barCount - 1,
        reason: 'Loud moment enters at the right edge.',
      );

      // Now feed silence; the loud peak should slide one index left per tick.
      p.pushSample(0.0, _t0.add(const Duration(milliseconds: 66)));
      p.tick(_t0.add(const Duration(milliseconds: 66)));
      final s1 = p.snapshot();
      expect(_argMax(s1), _barCount - 2);

      p.pushSample(0.0, _t0.add(const Duration(milliseconds: 99)));
      p.tick(_t0.add(const Duration(milliseconds: 99)));
      final s2 = p.snapshot();
      expect(_argMax(s2), _barCount - 3);
    });
  });

  group('WaveformPipeline — AC: volume-faithful amplitude', () {
    test('a louder sustained level yields a taller right-edge bar', () {
      final quiet = WaveformPipeline();
      final loud = WaveformPipeline();
      // Settle each at a constant level for plenty of ticks.
      final sQuiet = _runConstant(quiet, 0.3, 12);
      final sLoud = _runConstant(loud, 0.9, 12);
      // Right edge = the freshest, fully-settled moment.
      expect(
        sLoud.last,
        greaterThan(sQuiet.last),
        reason: 'Higher input volume must drive a taller bar.',
      );
      // Sanity: the loud bar tracks its input reasonably (≥ 0.7 after settling).
      expect(sLoud.last, greaterThan(0.7));
    });

    test('monotonic mapping: rising input never lowers the right-edge bar', () {
      final p = WaveformPipeline();
      double? prev;
      for (var i = 0; i <= 10; i++) {
        final level = i / 10.0;
        // Hold each rung for a few ticks so the smoother can climb.
        for (var k = 0; k < 4; k++) {
          final t = _t0.add(Duration(milliseconds: 33 * (i * 4 + k)));
          p.pushSample(level, t);
          p.tick(t);
        }
        final edge = p.snapshot().last;
        if (prev != null) {
          expect(
            edge,
            greaterThanOrEqualTo(prev - 1e-9),
            reason: 'Right-edge bar dropped while input rose ($level).',
          );
        }
        prev = edge;
      }
    });
  });

  group('WaveformPipeline — AC: silence decays to a flat floor', () {
    test(
      'after a loud burst, sustained silence settles every bar at the floor',
      () {
        final p = WaveformPipeline();
        // Loud for a while.
        _runConstant(p, 1.0, 12);
        final loud = p.snapshot();
        expect(loud.last, greaterThan(0.7));

        // Then a long silence: more than barCount ticks so the loud history fully
        // scrolls out, plus release decay to the floor.
        final settled = _runConstant(p, 0.0, _barCount + 30);
        for (var i = 0; i < settled.length; i++) {
          expect(
            settled[i],
            closeTo(_minLevel, 1e-9),
            reason:
                'Held silence must flatten bar $i to the floor. Got $settled',
          );
        }
      },
    );

    test(
      'a held pause does not jitter the floor (consecutive frames equal)',
      () {
        final p = WaveformPipeline();
        _runConstant(p, 1.0, 8);
        // Let silence fully settle.
        _runConstant(p, 0.0, _barCount + 40);
        // Now capture several consecutive frames of continued silence; with no
        // synthetic modulation they must be identical (no floor "wabern").
        final frames = <List<double>>[];
        for (var i = 0; i < 5; i++) {
          p.pushSample(0.0, _t0.add(Duration(milliseconds: 33 * (200 + i))));
          p.tick(_t0.add(Duration(milliseconds: 33 * (200 + i))));
          frames.add(p.snapshot());
        }
        for (var f = 1; f < frames.length; f++) {
          for (var i = 0; i < _barCount; i++) {
            expect(
              frames[f][i],
              closeTo(frames[0][i], 1e-12),
              reason: 'Floor jittered at bar $i between silent frames.',
            );
          }
        }
      },
    );

    test('the floor is the hard lower bound under prolonged zero input', () {
      final p = WaveformPipeline();
      for (var i = 0; i < 300; i++) {
        p.pushSample(0.0, _t0.add(Duration(milliseconds: 33 * i)));
        p.tick(_t0.add(Duration(milliseconds: 33 * i)));
        for (final v in p.snapshot()) {
          expect(v, greaterThanOrEqualTo(_minLevel - 1e-12));
        }
      }
    });
  });

  group('WaveformPipeline — AC: compact is scaled, not reduced', () {
    test('barHeights keeps the same count for both sizes', () {
      final p = WaveformPipeline();
      _runConstant(p, 0.7, 10);
      final normal = p.barHeights(compact: false);
      final compact = p.barHeights(compact: true);
      expect(normal, hasLength(_barCount));
      expect(compact, hasLength(_barCount));
      expect(
        compact.length,
        normal.length,
        reason: 'No 8-vs-30 split: compact must not reduce the bar count.',
      );
    });

    test('compact heights equal normal × compactScale, bar for bar', () {
      final p = WaveformPipeline();
      // Mix of levels so heights vary across bars.
      for (var i = 0; i < 14; i++) {
        final level = (i.isEven) ? 0.8 : 0.2;
        p.pushSample(level, _t0.add(Duration(milliseconds: 33 * i)));
        p.tick(_t0.add(Duration(milliseconds: 33 * i)));
      }
      final normal = p.barHeights(compact: false);
      final compact = p.barHeights(compact: true);
      for (var i = 0; i < _barCount; i++) {
        expect(
          compact[i],
          closeTo(normal[i] * OverlayDesignSpec.compactScale, 1e-9),
          reason: 'Compact bar $i is not a clean scaling of the normal bar.',
        );
      }
    });

    test('snapshot data is identical regardless of size (one data source)', () {
      final p = WaveformPipeline();
      _runConstant(p, 0.55, 9);
      final snap = p.snapshot();
      final normal = p.barHeights(compact: false);
      final maxNormal = OverlayDesignSpec.normalSize.waveformMaxHeight;
      for (var i = 0; i < _barCount; i++) {
        expect(normal[i], closeTo(snap[i] * maxNormal, 1e-9));
      }
    });
  });

  group('WaveformPipeline — determinism + reset', () {
    test('same inputs produce identical snapshots across two pipelines', () {
      final a = WaveformPipeline();
      final b = WaveformPipeline();
      final samples = <double>[0.0, 0.2, 0.5, 0.8, 1.0, 0.7, 0.3, 0.1, 0.9];
      for (var i = 0; i < samples.length; i++) {
        final now = _t0.add(Duration(milliseconds: 33 * i));
        a.pushSample(samples[i], now);
        b.pushSample(samples[i], now);
        a.tick(now);
        b.tick(now);
        final sa = a.snapshot();
        final sb = b.snapshot();
        expect(sa.length, sb.length);
        for (var k = 0; k < sa.length; k++) {
          expect(sa[k], sb[k], reason: 'mismatch at step $i bar $k');
        }
      }
    });

    test('reset restores the fresh-floor state', () {
      final p = WaveformPipeline();
      for (var i = 0; i < 20; i++) {
        p.pushSample(0.05 * (i + 1), _t0.add(Duration(milliseconds: 33 * i)));
        p.tick(_t0.add(Duration(milliseconds: 33 * i)));
      }
      p.reset();
      final s = p.snapshot();
      expect(s, hasLength(_barCount));
      for (final v in s) {
        expect(v, closeTo(_minLevel, 1e-12));
      }
    });
  });
}

/// Index of the maximum value in [xs].
int _argMax(List<double> xs) {
  var best = 0;
  for (var i = 1; i < xs.length; i++) {
    if (xs[i] > xs[best]) best = i;
  }
  return best;
}
