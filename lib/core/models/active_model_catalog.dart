/// The model catalog the app uses right now (#1792): the bundled catalog,
/// plus the models a signed catalog file added without an app release.
///
/// The bundled entries always win. A downloaded catalog only adds models
/// with new IDs; it can neither change nor remove a bundled model, so
/// installed models keep their pins and the code paths that name a
/// [CatalogIds] entry keep working. Loading, signature check and cache:
/// `lib/services/model_catalog/remote_model_catalog.dart`.
library;

import 'dart:async';

import 'bundled_model_catalog.dart';
import 'model_catalog.dart';

ModelCatalog _active = bundledModelCatalog;
final StreamController<ModelCatalog> _changes =
    StreamController<ModelCatalog>.broadcast(sync: true);

/// The catalog in use: [bundledModelCatalog] until a verified catalog file
/// was merged in with [setActiveModelCatalog].
ModelCatalog get activeModelCatalog => _active;

/// Every change of [activeModelCatalog].
Stream<ModelCatalog> get activeModelCatalogChanges => _changes.stream;

/// Makes [catalog] the catalog in use. Only call with the result of
/// [mergeDownloadedCatalog], never with a catalog read from outside.
void setActiveModelCatalog(ModelCatalog catalog) {
  if (identical(catalog, _active)) return;
  _active = catalog;
  _changes.add(catalog);
}

/// Back to the bundled catalog. For tests.
void resetActiveModelCatalogForTesting() =>
    setActiveModelCatalog(bundledModelCatalog);

/// [bundled] plus the models of [downloaded] that this app can use.
///
/// Kept from [downloaded]: entries with an ID [bundled] does not have, whose
/// `minAppVersion` is at most [appVersion], that run on [platform] (when
/// given) and whose file names do not clash with a file already in the
/// result. The result keeps [downloaded]'s revision and passes
/// [ModelCatalog.validate]; a downloaded entry that would break it is
/// dropped, never the bundled ones.
ModelCatalog mergeDownloadedCatalog(
  ModelCatalog bundled,
  ModelCatalog downloaded, {
  required String appVersion,
  ModelPlatform? platform,
}) {
  final models = [...bundled.models];
  for (final candidate in downloaded.models) {
    if (bundled.tryById(candidate.id) != null) continue;
    if (!candidate.supportsAppVersion(appVersion)) continue;
    if (platform != null &&
        !candidate.requirements.platforms.contains(platform)) {
      continue;
    }
    final next = ModelCatalog(
      schemaVersion: bundled.schemaVersion,
      models: [...models, candidate],
    );
    if (next.validate().isEmpty) models.add(candidate);
  }
  return ModelCatalog(
    schemaVersion: bundled.schemaVersion,
    revision: downloaded.revision,
    models: models,
  );
}
