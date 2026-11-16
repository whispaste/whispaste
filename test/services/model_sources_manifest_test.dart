/// `tool/model_sources.json` is what the source guard
/// (`tool/check_model_sources.dart`) checks against the live servers. It must
/// list exactly the files, sources, sizes and hashes of the registries, or the
/// guard would test something other than what the app downloads.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/download_allowlist.dart';
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/smart_mode/smart_mode_model_download_service.dart';
import 'package:whispaste/services/stt/whisper/cuda_pack.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_gguf_model.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_model_registry.dart';

typedef _Entry = ({List<String> sources, int size, String sha256});

void main() {
  final registry = <_Entry>[
    for (final m in sttModels)
      (sources: m.sources, size: m.sizeBytes, sha256: m.sha256),
    for (final f in parakeetModelFiles)
      (sources: f.sources, size: f.sizeBytes, sha256: f.sha256),
    for (final f in parakeetGgufFiles.values)
      (sources: f.sources, size: f.sizeBytes, sha256: f.sha256),
    (
      sources: smartModeModel.sources,
      size: smartModeModel.sizeBytes,
      sha256: smartModeModel.sha256,
    ),
    for (final pack in allCudaPacks)
      (
        sources: [pack.url],
        size: pack.archiveSizeBytes,
        sha256: pack.archiveSha256,
      ),
  ];

  final json =
      jsonDecode(File('tool/model_sources.json').readAsStringSync())
          as Map<String, Object?>;
  final manifest = <_Entry>[
    for (final f in (json['files']! as List).cast<Map<String, Object?>>())
      (
        sources: (f['sources']! as List).cast<String>(),
        size: f['size']! as int,
        sha256: f['sha256']! as String,
      ),
  ];

  String key(_Entry e) => '${e.sources.join(' ')} ${e.size} ${e.sha256}';

  test('tool/model_sources.json matches every registry', () {
    expect(
      manifest.map(key).toSet(),
      registry.map(key).toSet(),
      reason: 'update tool/model_sources.json together with the registries',
    );
    expect(manifest, hasLength(registry.length));
  });

  test('every source is https, on the allowlist and pinned', () {
    final pinnedHf = RegExp(r'/resolve/[0-9a-f]{40}/');
    for (final e in registry) {
      expect(e.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      for (final url in e.sources) {
        final uri = Uri.parse(url);
        expect(uri.scheme, 'https', reason: url);
        expect(
          () => assertAllowedDownloadUri(uri),
          returnsNormally,
          reason: url,
        );
        if (uri.path.contains('/resolve/')) {
          expect(url, matches(pinnedHf), reason: url);
        } else {
          // GitHub release assets: a fixed tag, never `latest`.
          expect(url, contains('/releases/download/'), reason: url);
          expect(url, isNot(contains('/latest/')), reason: url);
        }
      }
    }
  });
}
