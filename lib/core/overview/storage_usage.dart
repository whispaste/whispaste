/// The storage block of the overview: the sizes of the three areas and the
/// rules for what "Aufräumen" may remove. Pure; the measuring lives in
/// `services/storage_usage_service.dart`.
library;

import 'package:intl/intl.dart' show NumberFormat;
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

/// A byte count in KB, MB or GB with one decimal from 1 MB on, in the given
/// language's number format. The units are the same in every language.
String formatStorageBytes(int bytes, String languageCode) {
  final numbers = NumberFormat.decimalPattern(languageCode);
  String fixed(double v) => NumberFormat('0.0', languageCode).format(v);
  if (bytes < 1024) return '${numbers.format(bytes)} B';
  const kb = 1024.0;
  const mb = kb * 1024;
  const gb = mb * 1024;
  if (bytes < mb) return '${numbers.format((bytes / kb).round())} KB';
  if (bytes < gb) return '${fixed(bytes / mb)} MB';
  return '${fixed(bytes / gb)} GB';
}
