/// ticket: overlay shape, waveform style, content and opacity policies.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/theme/generated/wp_tokens.g.dart';
import 'package:whispaste/core/theme/overlay_customization.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';

void main() {
  group('persisted names', () {
    test('form values match the native contract', () {
      expect(OverlayForm.values.map((f) => f.value), ['pill', 'rounded-rect']);
    });

    test('wave style values match the native contract', () {
      expect(OverlayWaveStyle.values.map((s) => s.value), [
        'bars',
        'line',
        'dots',
        'ribbon',
        'pulse',
      ]);
    });

    test('opacity steps are 100, 80 and 60 percent', () {
      expect(OverlayOpacity.values.map((o) => o.percent), [100, 80, 60]);
    });
  });

  group('fallbacks for unknown or missing values', () {
    test('unknown form falls back to pill', () {
      expect(OverlayForm.fromValue('hexagon'), OverlayForm.pill);
      expect(OverlayForm.fromValue(null), OverlayForm.pill);
      // Retired forms (removed 2026-10-30) parse to the pill.
      expect(OverlayForm.fromValue('compact-circle'), OverlayForm.pill);
      expect(OverlayForm.fromValue('edge-bar'), OverlayForm.pill);
    });

    test('unknown wave style falls back to bars', () {
      expect(OverlayWaveStyle.fromValue('spiral'), OverlayWaveStyle.bars);
      expect(OverlayWaveStyle.fromValue(null), OverlayWaveStyle.bars);
    });

    test('unknown or non-numeric opacity falls back to full', () {
      expect(OverlayOpacity.fromValue('42'), OverlayOpacity.full);
      expect(OverlayOpacity.fromValue('abc'), OverlayOpacity.full);
      expect(OverlayOpacity.fromValue(null), OverlayOpacity.full);
    });

    test('known values round-trip', () {
      for (final form in OverlayForm.values) {
        expect(OverlayForm.fromValue(form.value), form);
      }
      for (final style in OverlayWaveStyle.values) {
        expect(OverlayWaveStyle.fromValue(style.value), style);
      }
      for (final opacity in OverlayOpacity.values) {
        expect(OverlayOpacity.fromValue('${opacity.percent}'), opacity);
      }
    });
  });

  group('OverlayElementAvailability (#472)', () {
    test('normal and compact draw timer, cancel and live text', () {
      for (final v in [OverlaySizeVariant.normal, OverlaySizeVariant.compact]) {
        final a = OverlayElementAvailability.forSize(v);
        expect(a.timer, isTrue, reason: '$v');
        expect(a.cancel, isTrue, reason: '$v');
        expect(a.liveTranscript, isTrue, reason: '$v');
      }
    });

    test('mini draws no timer or cancel, but its transcribing label', () {
      // Mini paints the live transcript as the status label while transcribing
      // (overlay_painter.dart _drawMinimalContent -> _drawTranscribing).
      final a = OverlayElementAvailability.forSize(OverlaySizeVariant.mini);
      expect(a.timer, isFalse);
      expect(a.cancel, isFalse);
      expect(a.liveTranscript, isTrue);
    });

    test('nano draws none of them (spinner only, no label)', () {
      final a = OverlayElementAvailability.forSize(OverlaySizeVariant.nano);
      expect(a.timer, isFalse);
      expect(a.cancel, isFalse);
      expect(a.liveTranscript, isFalse);
    });
  });

  group('availability follows what each size draws (#534)', () {
    test('timer, cancel and live text per size, as the painter draws them', () {
      // Literal on purpose: a new variant or a changed spec must be decided
      // here, not mirrored by the formula under test.
      const expected = {
        OverlaySizeVariant.normal: (timer: true, cancel: true, live: true),
        OverlaySizeVariant.compact: (timer: true, cancel: true, live: true),
        OverlaySizeVariant.mini: (timer: false, cancel: false, live: true),
        OverlaySizeVariant.nano: (timer: false, cancel: false, live: false),
      };
      expect(expected.keys, unorderedEquals(OverlaySizeVariant.values));
      expected.forEach((v, e) {
        final a = OverlayElementAvailability.forSize(v);
        expect(a.timer, e.timer, reason: '$v timer');
        expect(a.cancel, e.cancel, reason: '$v cancel');
        expect(a.liveTranscript, e.live, reason: '$v live');
      });
    });

    AppSettings localWhisper(FloatingOverlaySize size) =>
        AppSettings.defaults.copyWith(
          sttProvider: SttProviderType.onDevice.value,
          sttEngine: OnDeviceEngine.whisper.value,
          overlayShowLiveTranscript: true,
          overlaySize: size.value,
        );

    test('the recording preview stream runs only where text is painted '
        'while recording (#749)', () {
      // Mini paints its label only while transcribing (from the engine's
      // partial transcript), nano has no label: neither needs the stream.
      for (final size in FloatingOverlaySize.values) {
        expect(
          localWhisper(size).wantsLivePreview,
          size != FloatingOverlaySize.nano && size != FloatingOverlaySize.mini,
          reason: '$size',
        );
      }
    });

    test(
      'mini still offers the live transcript for its transcribing label',
      () {
        final mini = OverlayElementAvailability.forSize(
          localWhisper(FloatingOverlaySize.mini).overlaySizeType.variant,
        );
        expect(mini.liveTranscript, isTrue);
        expect(mini.liveTranscriptWhileRecording, isFalse);
      },
    );

    test('opt-out and a non-whisper engine still stop the stream', () {
      final base = localWhisper(FloatingOverlaySize.normal);
      expect(base.wantsLivePreview, isTrue);
      expect(
        base.copyWith(overlayShowLiveTranscript: false).wantsLivePreview,
        isFalse,
      );
      expect(
        base
            .copyWith(sttEngine: OnDeviceEngine.parakeet.value)
            .wantsLivePreview,
        isFalse,
      );
    });
  });

  group('system speech live preview gate (#1078)', () {
    AppSettings system(FloatingOverlaySize size, {String language = 'de'}) =>
        AppSettings.defaults.copyWith(
          sttProvider: SttProviderType.onDevice.value,
          sttEngine: OnDeviceEngine.system.value,
          sttLanguage: language,
          overlayShowLiveTranscript: true,
          overlaySize: size.value,
        );

    test('streams only where text shows while recording, never with whisper '
        'alongside', () {
      for (final size in FloatingOverlaySize.values) {
        final wants =
            size != FloatingOverlaySize.nano &&
            size != FloatingOverlaySize.mini;
        expect(system(size).wantsSystemLivePreview, wants, reason: '$size');
        expect(system(size).wantsLivePreview, isFalse, reason: '$size');
      }
    });

    test('needs the setting, a fixed language and the system engine', () {
      final base = system(FloatingOverlaySize.normal);
      expect(base.wantsSystemLivePreview, isTrue);
      expect(
        base.copyWith(overlayShowLiveTranscript: false).wantsSystemLivePreview,
        isFalse,
      );
      expect(
        system(
          FloatingOverlaySize.normal,
          language: 'auto',
        ).wantsSystemLivePreview,
        isFalse,
      );
      expect(
        base
            .copyWith(sttEngine: OnDeviceEngine.whisper.value)
            .wantsSystemLivePreview,
        isFalse,
      );
    });
  });

  group('OverlayPolicy', () {
    test('reduce motion turns the fluid outline off', () {
      expect(
        OverlayPolicy.effectiveWaveFluid(setting: true, reduceMotion: true),
        isFalse,
      );
      expect(
        OverlayPolicy.effectiveWaveFluid(setting: true, reduceMotion: false),
        isTrue,
      );
      expect(
        OverlayPolicy.effectiveWaveFluid(setting: false, reduceMotion: false),
        isFalse,
      );
    });

    test('stop control is always visible', () {
      expect(OverlayPolicy.stopAlwaysVisible, isTrue);
    });
  });

  group('OverlayOpacityGate', () {
    test('every background and wave pairing keeps the opacity contract', () {
      for (final background in OverlayBackground.values) {
        for (final wave in OverlayWave.values) {
          // Disabled pairings are never resolved (the picker greys them out).
          if (!wave.isValidOn(background)) continue;
          final accent = OverlayThemeColors.resolve(
            background: background,
            wave: wave,
          ).accent;
          for (final requested in OverlayOpacity.values) {
            final result = OverlayOpacityGate.clamp(
              requested: requested,
              fill: background.surfaceStart,
              accent: accent,
            );

            // Never less opaque than asked for.
            expect(
              result.percent,
              greaterThanOrEqualTo(requested.percent),
              reason: '${background.value}/${wave.value}/${requested.percent}',
            );

            // Either the result keeps 3:1, or it is the full fill, the final
            // fallback that is guarded by the token tests.
            final contrast = OverlayOpacityGate.worstContrast(
              fill: background.surfaceStart,
              accent: accent,
              alpha: result.alpha,
            );
            expect(
              contrast >= OverlayOpacityGate.minimumContrast ||
                  result == OverlayOpacity.full,
              isTrue,
              reason:
                  '${background.value}/${wave.value}/${requested.percent} '
                  'gives ${contrast.toStringAsFixed(2)}:1 at ${result.percent}',
            );
          }
        }
      }
    });

    test('a request that already passes is not changed', () {
      final result = OverlayOpacityGate.clamp(
        requested: OverlayOpacity.full,
        fill: OverlayBackground.marine.surfaceStart,
        accent: WpOverlayTokens.overlayWaveCyanDark,
      );
      expect(result, OverlayOpacity.full);
    });

    test('marine with cyan steps 60 percent up to 80 (1.68:1 at 60)', () {
      // Over white the 60 percent marine fill lifts far enough that the dark
      // cyan falls to 1.68:1. The 80 percent step reaches 3.36:1.
      final result = OverlayOpacityGate.clamp(
        requested: OverlayOpacity.subtle,
        fill: OverlayBackground.marine.surfaceStart,
        accent: WpOverlayTokens.overlayWaveCyanDark,
      );
      expect(result, OverlayOpacity.reduced);
    });

    test(
      'gletscher with light cyan steps 80 percent up to full (2.76:1 at 80)',
      () {
        final result = OverlayOpacityGate.clamp(
          requested: OverlayOpacity.reduced,
          fill: OverlayBackground.gletscher.surfaceStart,
          accent: WpOverlayTokens.overlayWaveCyanLight,
        );
        expect(result, OverlayOpacity.full);
      },
    );
  });
}
