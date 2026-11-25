import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/models/bundled_model_catalog.dart';
import 'package:whispaste/core/models/model_catalog.dart';
import 'package:whispaste/services/model_install_check.dart';
import 'package:whispaste/services/download_fragment_guard.dart';

void main() {
  Map<String, Object?> encoded() =>
      jsonDecode(jsonEncode(bundledModelCatalog.toJson()))
          as Map<String, Object?>;

  test('bundled catalog validates and round trips without any host access', () {
    expect(bundledModelCatalog.validate(), isEmpty);
    expect(
      ModelCatalog.fromJson(encoded()).toJson(),
      bundledModelCatalog.toJson(),
    );
    expect(bundledModelCatalog.models, hasLength(7));
    expect(bundledModelCatalog.byId(CatalogIds.gemma4E2b).contextLength, 2048);
  });

  test('unsupported schema and missing integrity fields fail closed', () {
    final newer = encoded()..['schemaVersion'] = 2;
    expect(() => ModelCatalog.fromJson(newer), throwsFormatException);
    for (final field in ['sha256', 'sizeBytes', 'sources']) {
      final json = encoded();
      final model = (json['models'] as List).first as Map;
      ((model['files'] as List).first as Map).remove(field);
      expect(() => ModelCatalog.fromJson(json), throwsFormatException);
    }
  });

  test(
    'moving, credentialed and non-public addresses cannot enter catalog',
    () {
      for (final url in [
        'http://huggingface.co/org/repo/resolve/main/model',
        'https://huggingface.co/org/repo/resolve/main/model',
        'https://github.com/org/repo/releases/download/latest/model',
        'https://localhost/org/repo/releases/download/v1/model',
        'https://user:secret@github.com/org/repo/releases/download/v1/model',
      ]) {
        expect(pinnedSourceProblem(url), isNotNull, reason: url);
      }
      for (final file in bundledModelCatalog.allFiles) {
        for (final source in file.sources) {
          expect(pinnedSourceProblem(source), isNull);
        }
      }
    },
  );

  test('duplicate IDs, traversal and missing LLM context are refused', () {
    final duplicate = encoded();
    final models = duplicate['models'] as List;
    models.add(models.first);
    expect(() => ModelCatalog.fromJson(duplicate), throwsFormatException);
    final traversal = encoded();
    final model = (traversal['models'] as List).first as Map;
    ((model['files'] as List).first as Map)['filename'] = '../model.bin';
    expect(() => ModelCatalog.fromJson(traversal), throwsFormatException);
    final llm = encoded();
    ((llm['models'] as List).last as Map).remove('contextLength');
    expect(() => ModelCatalog.fromJson(llm), throwsFormatException);
  });

  test('minimum version comparison includes patch and major releases', () {
    final model = bundledModelCatalog.byId(CatalogIds.whisperSmall);
    expect(model.supportsAppVersion('1.5.1'), isFalse);
    expect(model.supportsAppVersion('1.5.2'), isTrue);
    expect(model.supportsAppVersion('2.0.0'), isTrue);
  });

  test(
    'only a complete regular file counts as installed, without replacing it',
    () async {
      final dir = await Directory.systemTemp.createTemp('catalog_install_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/model.bin');
      expect(await fileHasPinnedSize(file.path, 4), isFalse);
      await file.writeAsBytes([1, 2]);
      expect(await fileHasPinnedSize(file.path, 4), isFalse);
      await file.writeAsBytes([1, 2, 3, 4]);
      expect(await fileHasPinnedSize(file.path, 4), isTrue);
      expect(await file.readAsBytes(), [1, 2, 3, 4]);
      await prepareFragmentIdentity(
        destPath: file.path,
        sha256: 'a' * 64,
        sizeBytes: 4,
      );
      expect(
        await fileHasPinnedSize(file.path, 4),
        isFalse,
        reason:
            'a crash between rename and verification is not an installation',
      );
      expect(fileHasPinnedSizeSync(file.path, 4), isFalse);
      await clearFragmentIdentity(file.path);
      expect(await fileHasPinnedSize(file.path, 4), isTrue);
      expect(await fileHasPinnedSize(dir.path, 4), isFalse);
    },
  );
}
