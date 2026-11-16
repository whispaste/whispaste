/// The storage block of the overview: the sizes of the three areas and the
/// rules for what "Aufräumen" may remove. Pure; the measuring lives in
/// `services/storage_usage_service.dart`.
library;

import '../text/byte_size.dart';

import 'package:path/path.dart' as p;

/// The sizes of the three areas. `null` means the area could not be read
/// completely (a permission error below it), so no number is shown for it.
class StorageSizes {
  const StorageSizes({this.models, this.recordings, this.cache});

  final int? models;
  final int? recordings;
  final int? cache;
}

/// Folders "Aufräumen" may empty: regenerated on demand, never user content.
/// `gpu-probe` is written by `gpu_probe_process.dart`, `app_icons` by
/// `app_identity_service.dart` (`appIconFolderName`).
/// Models and recordings are not in this list; recordings have their own
/// retention setting, models their own row in the speech settings.
List<String> storageCacheDirs(String appDataDir) => [
  p.join(appDataDir, 'gpu-probe'),
  p.join(appDataDir, 'app_icons'),
];

/// A byte count for the overview; the one shared formatter (#1152).
String formatStorageBytes(int bytes, String languageCode) =>
    formatByteSize(bytes, locale: languageCode);
