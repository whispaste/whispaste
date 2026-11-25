import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/services/feedback_diagnostics.dart';

void main() {
  // #2116: a report from a cloud-transcription setup named the unused
  // on-device engine ("Engine parakeet · Backend cpu").
  test(
    'a cloud transcription service is named instead of the local engine',
    () {
      expect(feedbackCloudEngineName(SttProviderType.onDevice), isNull);
      expect(feedbackCloudEngineName(SttProviderType.openAI), 'openai');
      expect(feedbackCloudEngineName(SttProviderType.deepgram), 'deepgram');
      expect(
        feedbackCloudEngineName(SttProviderType.customEndpoint),
        'custom-endpoint',
      );
    },
  );
}
