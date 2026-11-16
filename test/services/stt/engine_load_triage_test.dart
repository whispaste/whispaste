// Sorting a failed whisper load into "file damaged" or "hardware
// incompatible" (#561). The answer decides between a hash check plus
// re-download and a move to the CPU, so both directions are pinned here.
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/stt/engine_load_triage.dart';
import 'package:whispaste/services/stt/whisper/whisper_ffi_engine.dart'
    show whisperInitErrorWithNativeLines, whisperInitReturnedNullError;

void main() {
  group('classifyWhisperLoadFailure', () {
    test('backend and driver errors are hardware, on any device', () {
      for (final error in [
        'vk::DeviceLostError: vk::Queue::submit',
        'ggml_backend_cuda_init: CUDA error: no kernel image',
        'failed to load model on Vulkan',
        'ErrorOutOfDeviceMemory',
        'whisper_isolate_load_failed: TimeoutException after 0:01:00',
      ]) {
        expect(
          classifyWhisperLoadFailure(error, onGpu: true),
          EngineLoadCause.hardwareIncompatible,
          reason: error,
        );
      }
    });

    test('file errors are the file, on any device', () {
      for (final error in [
        'whisper_init_failed: invalid model data (bad magic)',
        'failed to read model tensor',
        'unexpected end of file',
        'gguf_init_from_file: truncated',
      ]) {
        for (final onGpu in [true, false]) {
          expect(
            classifyWhisperLoadFailure(error, onGpu: onGpu),
            EngineLoadCause.fileDefect,
            reason: '$error (gpu: $onGpu)',
          );
        }
      }
    });

    test('without a sign the device decides', () {
      expect(
        classifyWhisperLoadFailure(StateError('boom'), onGpu: true),
        EngineLoadCause.hardwareIncompatible,
      );
      expect(
        classifyWhisperLoadFailure(StateError('boom'), onGpu: false),
        EngineLoadCause.fileDefect,
      );
    });
  });
  test('a timeout or busy video memory passes by itself; a lost device '
      'does not', () {
    expect(
      isTransientWhisperLoadFailure(
        'whisper_isolate_load_failed: TimeoutException after 0:01:00',
      ),
      isTrue,
    );
    expect(isTransientWhisperLoadFailure('ErrorOutOfDeviceMemory'), isTrue);
    expect(isTransientWhisperLoadFailure('vk::DeviceLostError'), isFalse);
  });

  group('whisper_init returned NULL (#1669)', () {
    // The lines whisper.cpp logs when video memory held by other programs
    // leaves no room for the weights (patch 0002), per backend.
    const vulkanLines = [
      'ggml_vulkan: Device memory allocation of size 1617000000 failed.',
      'whisper_model_load: failed to allocate Vulkan0 buffer for the model '
          'weights (out of memory)',
      'whisper_init_with_params_no_state: failed to load model',
    ];
    const cudaLines = [
      'ggml_backend_cuda_buffer_type_alloc_buffer: allocating 1617.00 MiB on '
          'device 0: cudaMalloc failed: out of memory',
      'whisper_model_load: failed to allocate CUDA0 buffer for the model '
          'weights (out of memory)',
      'whisper_init_with_params_no_state: failed to load model',
    ];

    test('full video memory on the GPU is hardware and passes by itself, '
        'so the CPU takes over for this session only', () {
      for (final lines in [vulkanLines, cudaLines]) {
        final error = StateError(whisperInitReturnedNullError(lines));
        expect(
          classifyWhisperLoadFailure(error, onGpu: true),
          EngineLoadCause.hardwareIncompatible,
          reason: lines.first,
        );
        expect(isTransientWhisperLoadFailure(error), isTrue);
      }
    });

    test('a KV cache or compute buffer that does not fit passes too', () {
      for (final line in [
        'whisper_kv_cache_init: failed to allocate memory for the kv cache',
        'whisper_sched_graph_init: failed to allocate the compute buffer',
      ]) {
        expect(
          isTransientWhisperLoadFailure(whisperInitReturnedNullError([line])),
          isTrue,
          reason: line,
        );
      }
    });

    test('system memory running out during the GPU load passes too', () {
      // Windows moves video memory other programs hold into system memory;
      // then a ggml context (patch 0003) or a C++ allocation fails instead.
      for (final error in [
        whisperInitReturnedNullError(const [
          'ggml_init: failed to allocate 1048576 bytes for the context '
              '(out of memory)',
          'whisper_model_load: failed to allocate the tensor context '
              '(out of memory)',
        ]),
        whisperInitErrorWithNativeLines(
          'whisper_init_failed: failed to create ggml context',
          const [
            'ggml_init: failed to allocate 512 bytes for the context '
                '(out of memory)',
          ],
        ),
        'whisper_init_failed: bad allocation',
        'whisper_init_failed: std::bad_alloc',
      ]) {
        expect(
          classifyWhisperLoadFailure(StateError(error), onGpu: true),
          EngineLoadCause.hardwareIncompatible,
          reason: error,
        );
        expect(isTransientWhisperLoadFailure(error), isTrue, reason: error);
      }
    });

    test('a native exception without native lines keeps its message', () {
      expect(
        whisperInitErrorWithNativeLines(
          'whisper_init_failed: vk::SystemError',
          const [],
        ),
        'whisper_init_failed: vk::SystemError',
      );
    });

    test('without native lines the error stays as before and is not '
        'transient', () {
      final message = whisperInitReturnedNullError(const []);
      expect(message, 'whisper_init_from_file_with_params returned null');
      expect(isTransientWhisperLoadFailure(message), isFalse);
    });

    test('carries only the last four native lines', () {
      final message = whisperInitReturnedNullError([
        for (var i = 0; i < 6; i++) 'line $i',
      ]);
      expect(message, isNot(contains('line 1')));
      expect(message, endsWith('line 2 | line 3 | line 4 | line 5'));
    });
  });
}
