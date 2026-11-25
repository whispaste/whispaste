import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_gpu_policy.dart';
import 'package:whispaste/services/stt_sherpa/sherpa_provider_policy.dart';

void main() {
  test('only measured families on eligible platforms use the GPU', () {
    for (final platform in ['macos', 'windows', 'linux']) {
      for (final allowed in [true, false]) {
        expect(
          selectSherpaProvider(
            platform: platform,
            gpuAllowed: allowed,
            measuredFasterProviders: {},
          ),
          SherpaProvider.cpu,
        );
        expect(
          selectSherpaProvider(
            platform: platform,
            gpuAllowed: allowed,
            measuredFasterProviders: SherpaProvider.values.toSet(),
          ),
          !allowed || platform == 'linux'
              ? SherpaProvider.cpu
              : platform == 'macos'
              ? SherpaProvider.coreml
              : SherpaProvider.directml,
        );
      }
    }
  });

  late Directory dir;
  late ParakeetGpuCrashMarker marker;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('sherpa-provider-test-');
    marker = ParakeetGpuCrashMarker(dir: dir.path);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('load failure retries CPU once and preserves CPU errors', () {
    final attempts = <SherpaProvider>[];
    expect(
      () => SherpaProviderSession<String>(
        requested: SherpaProvider.directml,
        marker: marker,
        create: (provider) {
          attempts.add(provider);
          throw StateError(provider.name);
        },
        dispose: (_) {},
        warmUp: (_) {},
      ),
      throwsStateError,
    );
    expect(attempts, [SherpaProvider.directml, SherpaProvider.cpu]);
    expect(marker.recoverFromPreviousLaunch(), isFalse);
  });

  test('warm-up failure disposes GPU before CPU creation', () {
    final events = <String>[];
    final session = SherpaProviderSession<String>(
      requested: SherpaProvider.coreml,
      marker: marker,
      create: (p) {
        events.add('create ${p.name}');
        return p.name;
      },
      dispose: (value) => events.add('dispose $value'),
      warmUp: (_) => throw StateError('unsupported operator'),
    );
    expect(events, ['create coreml', 'dispose coreml', 'create cpu']);
    expect(session.provider, SherpaProvider.cpu);
    session.close();
  });

  test('decode failure retries audio on CPU and remains on CPU', () {
    final session = SherpaProviderSession<String>(
      requested: SherpaProvider.coreml,
      marker: marker,
      create: (p) => p.name,
      dispose: (_) {},
      warmUp: (_) {},
    );
    final attempts = <String>[];
    String decode(String backend) {
      attempts.add(backend);
      if (backend == 'coreml') throw StateError('device lost');
      return 'transcript';
    }

    expect(session.run(decode), 'transcript');
    expect(session.run(decode), 'transcript');
    expect(attempts, ['coreml', 'cpu', 'cpu']);
    expect(marker.recoverFromPreviousLaunch(), isFalse);
    session.close();
  });

  test('cancellation clears the attempt without replacing the recognizer', () {
    var creates = 0;
    final session = SherpaProviderSession<String>(
      requested: SherpaProvider.coreml,
      marker: marker,
      create: (p) {
        creates++;
        return p.name;
      },
      dispose: (_) {},
      warmUp: (_) {},
      shouldRetry: (_) => false,
    );
    expect(
      () => session.run((_) => throw StateError('cancelled')),
      throwsStateError,
    );
    expect(creates, 1);
    expect(session.provider, SherpaProvider.coreml);
    expect(marker.recoverFromPreviousLaunch(), isFalse);
    session.close();
  });

  test('native crash marker forces CPU on the next launch', () {
    marker.markAttempt();
    final session = SherpaProviderSession<String>(
      requested: SherpaProvider.directml,
      marker: marker,
      create: (p) => p.name,
      dispose: (_) {},
      warmUp: (_) => fail('CPU must not GPU-warm-up'),
    );
    expect(session.provider, SherpaProvider.cpu);
    expect(marker.readStrikes(), 1);
    session.close();
  });
}
