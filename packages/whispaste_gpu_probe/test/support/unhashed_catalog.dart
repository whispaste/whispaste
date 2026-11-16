import 'package:whispaste_gpu_probe/whispaste_gpu_probe.dart';

/// The default catalogue without SHA-256 values, for tests whose fake
/// downloader writes placeholder bytes instead of the real model file.
List<CatalogModel> unhashedCatalog() => [
  for (final m in defaultModelCatalog())
    CatalogModel(
      id: m.id,
      label: m.label,
      family: m.family,
      entry: m.entry == null
          ? null
          : ModelEntry(
              name: m.entry!.name,
              downloadUrl: m.entry!.downloadUrl,
              sha256: '',
              targetFilename: m.entry!.targetFilename,
              sizeBytes: m.entry!.sizeBytes,
            ),
      files: m.files == null
          ? null
          : [
              for (final f in m.files!)
                BundleFile(
                  url: f.url,
                  filename: f.filename,
                  sizeBytes: f.sizeBytes,
                ),
            ],
    ),
];
