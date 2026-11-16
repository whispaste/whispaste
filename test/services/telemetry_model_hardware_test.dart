import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:whispaste/core/config/quality_tier.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart'
    show BehaviorSettings;
import 'package:whispaste/core/telemetry/onboarding_telemetry_buffer.dart';
import 'package:whispaste/services/engine_recommendation.dart';
import 'package:whispaste/services/hardware_info_service.dart';
import 'package:whispaste/services/model_hardware_telemetry.dart';
import 'package:whispaste/services/speech_recommendation.dart';
import 'package:whispaste/services/telemetry_model_buckets.dart';
import 'package:whispaste/services/telemetry_service.dart';

AppSettings _settings({
  String provider = 'On Device',
  String engine = 'whisper',
  String model = 'whisper-medium',
}) {
  return AppSettings.defaults.copyWith(
    sttProvider: provider,
    sttEngine: engine,
    sttModel: model,
  );
}

TelemetryService _service({
  required http.Client client,
  bool consentGranted = true,
}) {
  return TelemetryService(
    client: client,
    endpointUrl: 'https://example.matomo.cloud',
    siteId: 1,
    consentGranted: consentGranted,
    sessionVisitorId: 'abcd',
  );
}

void main() {
  group('usage-sharing gate for model events (consent)', () {
    test('no request without consent', () async {
      var sent = 0;
      final client = MockClient((_) async {
        sent++;
        return http.Response('', 204);
      });
      final service = _service(client: client, consentGranted: false);

      service.trackEvent(
        category: 'model',
        action: 'switch',
        name: 'small>medium|lt1d',
      );
      await service.flush();

      expect(sent, 0);
    });

    test('one request with consent', () async {
      final bodies = <String>[];
      final client = MockClient((request) async {
        bodies.add(request.body);
        return http.Response('', 204);
      });
      final service = _service(client: client);

      service.trackEvent(
        category: 'model',
        action: 'switch',
        name: 'small>medium|lt1d',
      );
      await service.flush();

      expect(bodies, hasLength(1));
      expect(bodies.single, contains('e_c=model'));
      expect(bodies.single, contains('e_a=switch'));
    });
  });

  group('settings whitelist', () {
    test('stt_engine is reported as a changed key', () {
      expect(kTrackableSettingKeys, contains('stt_engine'));
    });
  });

  group('model catalog ids', () {
    test('Whisper ids map to catalog names, anything else is other', () {
      expect(whisperCatalogId('whisper-small'), 'small');
      expect(whisperCatalogId('whisper-medium'), 'medium');
      expect(whisperCatalogId('whisper-large-v3-turbo'), 'large-v3-turbo');
      expect(whisperCatalogId('/models/secret.bin'), 'other');
    });

    test('cloud provider is cloud, Parakeet engine is parakeet', () {
      expect(telemetryModelId(_settings(provider: 'OpenAI')), 'cloud');
      expect(telemetryModelId(_settings(engine: 'parakeet')), 'parakeet');
      expect(telemetryModelId(_settings(model: 'whisper-small')), 'small');
    });
  });

  group('model_chosen waits for the privacy choice of a first run', () {
    (ProviderContainer, List<String>, OnboardingTelemetryBuffer) setUpRun() {
      final sent = <String>[];
      final buffer = OnboardingTelemetryBuffer(
        send: (e) => sent.add('${e.category}/${e.action}'),
      );
      final container = ProviderContainer(
        overrides: [
          onboardingTelemetryBufferProvider.overrideWithValue(buffer),
          speechRecommendationProvider.overrideWith(
            (ref) => Future.error('no hardware in tests'),
          ),
        ],
      );
      addTearDown(container.dispose);
      return (container, sent, buffer);
    }

    test('held during the first run, sent after a yes', () {
      final (container, sent, buffer) = setUpRun();
      buffer.begin();
      container
          .read(modelHardwareTelemetryProvider)
          .modelChosen(engine: OnDeviceEngine.parakeet);
      expect(sent, isEmpty);

      buffer.decide(shareUsageStats: true);
      expect(sent, ['onboarding/model_chosen']);
    });

    test('dropped after a no', () {
      final (container, sent, buffer) = setUpRun();
      buffer.begin();
      container
          .read(modelHardwareTelemetryProvider)
          .modelChosen(engine: OnDeviceEngine.parakeet);
      buffer.decide(shareUsageStats: false);
      expect(sent, isEmpty);
    });
  });

  group('model_chosen: comparison against recommendEngine', () {
    test('Parakeet recommended for German, choosing Whisper overrides it', () {
      final rec = recommendEngine(dictationLanguageCodes: const ['de']);
      expect(rec.engine, OnDeviceEngine.parakeet);

      final recommended = recommendedModelId(rec);
      expect(recommended, 'parakeet');
      expect(
        modelChoiceOutcome(chosen: 'medium', recommended: recommended),
        'overridden',
      );
      expect(
        modelChoiceOutcome(chosen: 'parakeet', recommended: recommended),
        'accepted',
      );
    });

    test(
      'a Whisper recommendation is compared by tier, not by engine name',
      () {
        final rec = recommendEngine(
          dictationLanguageCodes: const ['zz'],
          vendor: GpuVendor.nvidia,
          vramMB: 8192,
          cudaUsable: true,
        );
        final recommended = recommendedModelId(rec);
        expect(recommended, isNot('parakeet'));
        expect(recommended, isNot('unknown'));

        expect(
          modelChoiceOutcome(chosen: recommended, recommended: recommended),
          'accepted',
        );
        final other = recommended == 'small' ? 'large-v3-turbo' : 'small';
        expect(
          modelChoiceOutcome(chosen: other, recommended: recommended),
          'overridden',
        );
      },
    );

    test(
      'no recommendation to compare against gives unknown, not overridden',
      () {
        expect(
          modelChoiceOutcome(chosen: 'medium', recommended: 'unknown'),
          'unknown',
        );
      },
    );

    test('tier pickers map to the same catalog ids', () {
      expect(tierCatalogId(QualityTier.compact), 'small');
      expect(tierCatalogId(QualityTier.premium), isNot('other'));
    });
  });

  group('real-time-factor bucket', () {
    test('classes by transcribe time over audio length', () {
      expect(rtfBucket(transcribeMs: 490, audioMs: 1000), 'lt0_5');
      expect(rtfBucket(transcribeMs: 500, audioMs: 1000), '0_5_1_5');
      expect(rtfBucket(transcribeMs: 1499, audioMs: 1000), '0_5_1_5');
      expect(rtfBucket(transcribeMs: 1500, audioMs: 1000), '1_5_3');
      expect(rtfBucket(transcribeMs: 2999, audioMs: 1000), '1_5_3');
      expect(rtfBucket(transcribeMs: 3000, audioMs: 1000), 'gt3');
    });

    test('no bucket without a usable length', () {
      expect(rtfBucket(transcribeMs: null, audioMs: 1000), isNull);
      expect(rtfBucket(transcribeMs: 0, audioMs: 1000), isNull);
      expect(rtfBucket(transcribeMs: 500, audioMs: 0), isNull);
    });
  });

  group('backend dimension', () {
    test('cloud has no backend', () {
      expect(
        telemetryBackend(
          settings: _settings(provider: 'Deepgram'),
          optimalBackend: 'cuda',
        ),
        'none',
      );
    });

    test(
      'Whisper reports the detected backend, unknown values count as cpu',
      () {
        expect(
          telemetryBackend(settings: _settings(), optimalBackend: 'cuda'),
          'cuda',
        );
        expect(
          telemetryBackend(settings: _settings(), optimalBackend: 'metal'),
          'metal',
        );
        expect(
          telemetryBackend(settings: _settings(), optimalBackend: null),
          'cpu',
        );
      },
    );

    test('Parakeet stays on cpu when the GPU setting is disabled', () {
      expect(
        telemetryBackend(
          settings: _settings(engine: 'parakeet').copyWithSections(
            behavior: const BehaviorSettings(gpuAcceleration: 'disabled'),
          ),
          optimalBackend: 'cuda',
        ),
        'cpu',
      );
    });
  });

  group('hardware classes', () {
    test('RAM class edges, with the reported-below-nominal allowance', () {
      expect(ramBucket(null), 'unknown');
      expect(ramBucket(4096), 'lt8');
      expect(ramBucket(7880), '8_16');
      expect(ramBucket(15872), '8_16');
      expect(ramBucket(32768), 'gt16');
    });

    test('Mac chip family: M1 to M4, intel, other, n/a off Mac', () {
      expect(
        macChipDimension(
          isMacOS: false,
          vendor: GpuVendor.nvidia,
          gpuName: 'x',
        ),
        'n/a',
      );
      expect(
        macChipDimension(isMacOS: true, vendor: null, gpuName: null),
        'unknown',
      );
      expect(
        macChipDimension(
          isMacOS: true,
          vendor: GpuVendor.apple,
          gpuName: 'Apple M2 Pro',
        ),
        'm2',
      );
      expect(
        macChipDimension(
          isMacOS: true,
          vendor: GpuVendor.apple,
          gpuName: 'Apple M9',
        ),
        'other',
      );
      expect(
        macChipDimension(
          isMacOS: true,
          vendor: GpuVendor.amd,
          gpuName: 'Radeon Pro',
        ),
        'intel',
      );
    });

    test('GPU vendor class is the enum name, unknown without GPU info', () {
      expect(gpuVendorDimension(GpuVendor.nvidia), 'nvidia');
      expect(gpuVendorDimension(GpuVendor.none), 'none');
      expect(gpuVendorDimension(null), 'unknown');
    });

    test('visit dimensions 8 to 12 are all present and categorical', () {
      final dims = modelHardwareDimensions(
        settings: _settings(),
        gpu: null,
        ramMB: 16384,
        isMacOS: false,
      );
      expect(
        dims.keys,
        unorderedEquals([
          'dimension8',
          'dimension9',
          'dimension10',
          'dimension11',
          'dimension12',
        ]),
      );
      expect(dims['dimension8'], 'medium');
      expect(dims['dimension10'], '8_16');
      expect(dims['dimension12'], 'n/a');
    });
  });

  group('days since onboarding (injected clock)', () {
    final done = DateTime(2026, 10, 1, 12);

    test('unknown when no completion date is stored', () {
      expect(
        daysSinceOnboardingBucket(completedOn: null, now: done),
        'unknown',
      );
    });

    test('bucket edges at 1, 7 and 30 days', () {
      String at(int days) => daysSinceOnboardingBucket(
        completedOn: done,
        now: done.add(Duration(days: days)),
      );
      expect(at(0), 'lt1d');
      expect(at(1), '1_7d');
      expect(at(6), '1_7d');
      expect(at(7), '7_30d');
      expect(at(29), '7_30d');
      expect(at(30), 'gt30d');
    });

    test('a completion date in the future counts as lt1d, not negative', () {
      expect(
        daysSinceOnboardingBucket(
          completedOn: done.add(const Duration(days: 2)),
          now: done,
        ),
        'lt1d',
      );
    });

    test('reads the stored local date back', () async {
      SharedPreferences.setMockInitialValues({
        'telemetry_onboarding_completed_on': '2026-10-01',
      });
      final prefs = await SharedPreferences.getInstance();
      expect(readOnboardingCompletedOn(prefs), DateTime(2026, 10, 1));
    });
  });
}
