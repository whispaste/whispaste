// Merging a downloaded catalog into the bundled one (#1792): it only adds
// models, never changes a bundled pin, hides entries for newer app versions
// or other systems, and drops entries that would clash on disk.

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/models/active_model_catalog.dart';
import 'package:whispaste/core/models/bundled_model_catalog.dart';
import 'package:whispaste/core/models/model_catalog.dart';

Map<String, Object?> _entry(
  String id, {
  String minAppVersion = '1.5.2',
  String runtime = 'whisper.cpp',
  String? filename,
  List<String> platforms = const ['macos', 'windows', 'linux'],
}) => {
  'id': id,
  'kind': 'stt',
  'runtime': runtime,
  'label': id,
  'minAppVersion': minAppVersion,
  'languages': ['mul'],
  'speed': 'medium',
  'accuracy': 'high',
  'requirements': {'platforms': platforms},
  'license': 'MIT',
  'files': [
    {
      'filename': filename ?? 'ggml-$id.bin',
      'sizeBytes': 1000,
      'sha256': 'a' * 64,
      'sources': [
        'https://huggingface.co/org/repo/resolve/${'b' * 40}/ggml-$id.bin',
      ],
    },
  ],
};

ModelCatalog _catalog(List<Map<String, Object?>> models, {int revision = 1}) =>
    ModelCatalog.fromJson({
      'schemaVersion': 1,
      'revision': revision,
      'models': models,
    });

void main() {
  test('a new model is added after the bundled ones', () {
    final merged = mergeDownloadedCatalog(
      bundledModelCatalog,
      _catalog([_entry('whisper-new')]),
      appVersion: '1.5.5',
    );
    expect(merged.models.length, bundledModelCatalog.models.length + 1);
    expect(merged.models.last.id, 'whisper-new');
    expect(merged.revision, 1);
    expect(merged.validate(), isEmpty);
  });

  test('a downloaded entry cannot change a bundled model', () {
    final bundled = bundledModelCatalog.byId(CatalogIds.whisperSmall);
    final merged = mergeDownloadedCatalog(
      bundledModelCatalog,
      _catalog([_entry(CatalogIds.whisperSmall)]),
      appVersion: '1.5.5',
    );
    expect(merged.byId(CatalogIds.whisperSmall), same(bundled));
    expect(merged.models.length, bundledModelCatalog.models.length);
  });

  test('entries for a newer app or another system stay hidden', () {
    final merged = mergeDownloadedCatalog(
      bundledModelCatalog,
      _catalog([
        _entry('too-new', minAppVersion: '9.0.0'),
        _entry('mac-only', platforms: ['macos']),
        _entry('fits'),
      ]),
      appVersion: '1.5.5',
      platform: ModelPlatform.windows,
    );
    expect(merged.tryById('too-new'), isNull);
    expect(merged.tryById('mac-only'), isNull);
    expect(merged.tryById('fits'), isNotNull);
  });

  test('an entry reusing a bundled file name is dropped', () {
    final bundledName = bundledModelCatalog
        .byId(CatalogIds.whisperSmall)
        .filename;
    final merged = mergeDownloadedCatalog(
      bundledModelCatalog,
      _catalog([_entry('impostor', filename: bundledName)]),
      appVersion: '1.5.5',
    );
    expect(merged.tryById('impostor'), isNull);
  });

  test('fromJson skips entries above the app version before reading them', () {
    final json = {
      'schemaVersion': 1,
      'revision': 3,
      'models': [
        _entry('future', minAppVersion: '9.0.0', runtime: 'future-engine'),
        _entry('today'),
      ],
    };
    final catalog = ModelCatalog.fromJson(json, appVersion: '1.5.5');
    expect(catalog.revision, 3);
    expect(catalog.models.map((m) => m.id), ['today']);
    expect(
      () => ModelCatalog.fromJson(json),
      throwsA(isA<ModelCatalogFormatException>()),
    );
  });

  test('a negative revision is refused', () {
    expect(
      () => _catalog([], revision: -1),
      throwsA(isA<ModelCatalogFormatException>()),
    );
  });

  test('setActiveModelCatalog notifies and reset returns to bundled', () async {
    addTearDown(resetActiveModelCatalogForTesting);
    final merged = mergeDownloadedCatalog(
      bundledModelCatalog,
      _catalog([_entry('whisper-new')]),
      appVersion: '1.5.5',
    );
    final seen = <ModelCatalog>[];
    final sub = activeModelCatalogChanges.listen(seen.add);
    addTearDown(sub.cancel);
    setActiveModelCatalog(merged);
    expect(activeModelCatalog, same(merged));
    expect(seen, [merged]);
    resetActiveModelCatalogForTesting();
    expect(activeModelCatalog, same(bundledModelCatalog));
  });
}
