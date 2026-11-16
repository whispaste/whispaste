import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/transcription/transcriber_exception.dart';

void main() {
  group('transcriptionErrorCode', () {
    test('maps the classified transcriber reasons to their codes', () {
      expect(
        transcriptionErrorCode(
          const TranscriberException(
            'x',
            reason: TranscriberFailureReason.authError,
          ),
        ),
        'cloud_auth_error',
      );
      expect(
        transcriptionErrorCode(
          const TranscriberException(
            'x',
            reason: TranscriberFailureReason.quotaExceeded,
          ),
        ),
        'cloud_quota_exceeded',
      );
      expect(
        transcriptionErrorCode(
          const TranscriberException(
            'x',
            reason: TranscriberFailureReason.networkError,
          ),
        ),
        'cloud_network_error',
      );
      expect(
        transcriptionErrorCode(
          const TranscriberException(
            'x',
            reason: TranscriberFailureReason.timeout,
          ),
        ),
        'cloud_timeout',
      );
    });

    test('an unclassified transcriber error keeps its message as the code', () {
      expect(
        transcriptionErrorCode(const TranscriberException('stt_cuda_oom')),
        'stt_cuda_oom',
      );
    });

    test('any other error counts as a server failure, like the pipeline', () {
      expect(transcriptionErrorCode(StateError('boom')), 'stt_server_failed');
    });
  });
}
