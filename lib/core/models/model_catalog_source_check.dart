/// Publish check for the downloadable catalog source
/// `tool/model-catalog.json` (#1792), shared by `tool/sign_model_catalog.dart`
/// and its test. Pure Dart.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'active_model_catalog.dart';
import 'bundled_model_catalog.dart';
import 'model_catalog.dart';

/// Everything that keeps [bytes] from being published; empty when fine.
///
/// The file must be a valid catalog ([ModelCatalog.fromJson]) with a
/// revision of at least 1. An entry with a bundled ID must equal the bundled
/// entry exactly (the app ignores it anyway, a difference is a mistake), and
/// every other entry must survive [mergeDownloadedCatalog] for an app that
/// is new enough, so no file name or ID clashes with the bundled models.
List<String> modelCatalogSourceProblems(
  Uint8List bytes, {
  ModelCatalog? bundled,
}) {
  final pins = bundled ?? bundledModelCatalog;
  final ModelCatalog catalog;
  try {
    final json = jsonDecode(utf8.decode(bytes));
    if (json is! Map) return ['not a JSON object'];
    catalog = ModelCatalog.fromJson(json.cast<String, Object?>());
  } on FormatException catch (e) {
    return ['$e'];
  }
  final problems = <String>[];
  if (catalog.revision < 1) {
    problems.add('revision must be at least 1, is ${catalog.revision}');
  }
  for (final model in catalog.models) {
    final pinned = pins.tryById(model.id);
    if (pinned != null &&
        jsonEncode(pinned.toJson()) != jsonEncode(model.toJson())) {
      problems.add('${model.id}: differs from the bundled entry');
    }
  }
  final merged = mergeDownloadedCatalog(
    pins,
    catalog,
    appVersion: '999999.0.0',
  );
  for (final model in catalog.models) {
    if (merged.tryById(model.id) == null) {
      problems.add('${model.id}: clashes with a bundled model');
    }
  }
  return problems;
}
