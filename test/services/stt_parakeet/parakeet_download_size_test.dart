import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/stt_parakeet/parakeet_download_service.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_gpu_policy.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_gguf_model.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_model_registry.dart';

void main() {
  test('sherpa-only download is the sherpa bundle alone', () {
    expect(parakeetDownloadBytes(gpuWanted: false), parakeetModelTotalBytes);
    expect(parakeetDownloadSizeLabel(gpuWanted: false), '639 MB');
  });

  test('GPU download adds the GGUF model on top of the sherpa bundle', () {
    expect(
      parakeetDownloadBytes(gpuWanted: true),
      parakeetModelTotalBytes + parakeetGgufActive.sizeBytes,
    );
    expect(parakeetDownloadSizeLabel(gpuWanted: true), '1.2 GB');
  });

  test('gpuAcceleration setting maps to the GPU download decision', () {
    expect(parakeetGpuWantedForSetting('disabled'), isFalse);
    // Platform and GPU library also decide, so compare with the same policy
    // the download service uses instead of a fixed value.
    final expected = parakeetGpuWanted(gpuAccelerationAllowed: true);
    expect(parakeetGpuWantedForSetting('auto'), expected);
    expect(parakeetGpuWantedForSetting(null), expected);
  });
}
