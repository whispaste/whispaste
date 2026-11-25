// The catalog source tool/model-catalog.json must always be publishable
// (#1792): valid, revision >= 1, no clash with or change of bundled models.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/models/bundled_model_catalog.dart';
import 'package:whispaste/core/models/model_catalog_source_check.dart';

Uint8List _bytes(Object json) =>
    Uint8List.fromList(utf8.encode(jsonEncode(json)));

void main() {
  test('tool/model-catalog.json is publishable', () {
    final bytes = File('tool/model-catalog.json').readAsBytesSync();
    expect(modelCatalogSourceProblems(Uint8List.fromList(bytes)), isEmpty);
  });

  test('a changed bundled entry or revision 0 is reported', () {
    final small = bundledModelCatalog.byId(CatalogIds.whisperSmall).toJson();
    final changed = {...small, 'label': 'changed'};
    final problems = modelCatalogSourceProblems(
      _bytes({
        'schemaVersion': 1,
        'models': [changed],
      }),
    );
    expect(problems, hasLength(2));
    expect(problems.join(), contains('revision'));
    expect(problems.join(), contains('differs from the bundled entry'));
  });

  test('an unchanged bundled entry is fine', () {
    final small = bundledModelCatalog.byId(CatalogIds.whisperSmall).toJson();
    expect(
      modelCatalogSourceProblems(
        _bytes({
          'schemaVersion': 1,
          'revision': 2,
          'models': [small],
        }),
      ),
      isEmpty,
    );
  });
}
