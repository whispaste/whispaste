/// `whispaste --download-cuda-pack`: the CLI refuses to download without
/// `--accept-nvidia-eula`, and the flag and refusal are documented in the help.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/headless/headless_cli.dart';
import 'package:whispaste/services/headless/headless_transcription.dart';

void main() {
  test('the download command is recognised by its flag', () {
    expect(isCudaPackDownloadRequested(['--download-cuda-pack']), isTrue);
    expect(
      isCudaPackDownloadRequested(['--transcribe-file', 'a.wav']),
      isFalse,
    );
  });

  test(
    'without --accept-nvidia-eula the download is refused, with the reason',
    () {
      final refusal = cudaPackDownloadRefusal(['--download-cuda-pack']);

      expect(refusal, isNotNull);
      expect(refusal, contains('NVIDIA CUDA EULA'));
      expect(refusal, contains('https://docs.nvidia.com/cuda/eula/index.html'));
      expect(refusal, contains('--accept-nvidia-eula'));
    },
  );

  test('--accept-nvidia-eula lets the download run', () {
    expect(
      cudaPackDownloadRefusal(['--download-cuda-pack', '--accept-nvidia-eula']),
      isNull,
    );
  });

  test(
    'the transcription help documents the download command and its flag',
    () {
      expect(headlessUsage, contains('--download-cuda-pack'));
      expect(headlessUsage, contains('--accept-nvidia-eula'));
      expect(cudaPackDownloadUsage, contains('--accept-nvidia-eula'));
    },
  );
}
