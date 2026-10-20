/// Every Hugging Face model URL is pinned to a commit (OW-P18). A re-upload
/// of `main` would otherwise break each download, which fails closed against
/// the fixed SHA-256.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/smart_mode/smart_mode_model_download_service.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_gguf_model.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_model_registry.dart';

final _pinned = RegExp(r'/resolve/[0-9a-f]{40}/');

void main() {
  final urls = <String>[
    for (final model in sttModels) model.url,
    smartModeModel.url,
    for (final file in parakeetModelFiles) file.url,
    for (final file in parakeetGgufFiles.values) file.url,
  ];

  test('the guard covers every model registry', () {
    // 3 Whisper models, 1 Smart Mode model, 4 Parakeet bundle files, 2 GGUF.
    expect(urls, hasLength(10));
  });

  for (final url in urls) {
    test('$url is pinned to a commit', () {
      expect(url, matches(_pinned), reason: 'expected /resolve/<40hex>/');
      expect(url, isNot(contains('/resolve/main/')));
    });
  }
}
