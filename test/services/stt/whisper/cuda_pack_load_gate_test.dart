/// The CUDA load gate (Maintainer decision 3a, 2026-10-18): an installed pack
/// is loaded only with a current NVIDIA EULA consent for its label and text
/// hash. Without it the Whisper engine stays on Vulkan/CPU.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/services/stt/whisper/cuda_pack.dart';

const _pack = CudaPackInfo(
  id: 'ggml-test-r1',
  url: 'https://example.invalid/pack.zip',
  archiveSizeBytes: 1024,
  archiveSha256: '',
  files: [],
);

const _installed = CudaPackState(pack: _pack, installed: true);

String? _dirFor({
  CudaPackState state = _installed,
  String accepted = '',
  bool enabled = true,
  bool offered = true,
}) => activeCudaPackDirFor(
  offered: offered,
  downloadAllowed: true,
  enabled: enabled,
  state: state,
  accepted: accepted,
  rootDir: '/root',
);

void main() {
  test('an installed pack without any consent is not loaded', () {
    expect(_dirFor(), isNull);
  });

  test('consent for an older licence label does not count', () {
    final stale =
        '${_pack.id}+eula-1999-01-01+${kCudaEulaSha256.substring(0, 12)}'
        '@2026-01-01T00:00:00.000Z';

    expect(_dirFor(accepted: stale), isNull);
  });

  test('consent for a changed licence text does not count', () {
    final changed =
        '${_pack.id}+eula-$kCudaEulaVersion+000000000000'
        '@2026-01-01T00:00:00.000Z';

    expect(_dirFor(accepted: changed), isNull);
  });

  test('consent for another pack id does not count', () {
    expect(_dirFor(accepted: cudaEulaConsentValue('ggml-other-r1')), isNull);
  });

  test('current consent loads the installed pack folder', () {
    expect(
      _dirFor(accepted: cudaEulaConsentValue(_pack.id)),
      '/root/${_pack.id}',
    );
  });

  test(
    'a switched-off CUDA or a missing pack loads nothing, even with consent',
    () {
      final accepted = cudaEulaConsentValue(_pack.id);

      expect(_dirFor(accepted: accepted, enabled: false), isNull);
      expect(
        _dirFor(
          accepted: accepted,
          state: const CudaPackState(pack: _pack),
        ),
        isNull,
      );
    },
  );

  test('a headless download stores its consent under the settings key', () {
    final stored = cudaEulaConsentStorageMap(_pack.id);

    expect(stored.keys.single, kCudaEulaSettingsKey);
    expect(AppSettings.defaults.toStorageMap(), contains(kCudaEulaSettingsKey));
    expect(
      isCudaEulaAcceptedFor(
        accepted: stored[kCudaEulaSettingsKey]!,
        packId: _pack.id,
      ),
      isTrue,
    );
  });
}
