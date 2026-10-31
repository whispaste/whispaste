/// Central free-space check before any model download starts (RE2-20,
/// OW-P19). Every download service (settings, Smart Mode, Parakeet) asks here
/// before it fetches, so a full disk fails before the first byte is written.
library;

import 'free_disk_space.dart';

/// Free space a download needs: 1.2 x its size, for the temporary file, the
/// final file and the verification pass.
const double downloadDiskSpaceFactor = 1.2;

const _errorPrefix = 'disk_space_short:';

/// A download was refused because the volume holds less than it needs.
final class DiskSpaceShortage {
  const DiskSpaceShortage({required this.neededBytes, required this.freeBytes});

  /// The free space the download needs (1.2 x its size).
  final int neededBytes;

  /// The free space the volume has.
  final int freeBytes;

  /// The value stored in a download state's `errorMessage`. The UI turns it
  /// into the localized message (see `localizedDownloadError`).
  String get errorCode => '$_errorPrefix$neededBytes:$freeBytes';

  /// The shortage encoded in [message], or `null` for any other message.
  static DiskSpaceShortage? fromErrorCode(String? message) {
    if (message == null || !message.startsWith(_errorPrefix)) return null;
    final parts = message.substring(_errorPrefix.length).split(':');
    if (parts.length != 2) return null;
    final needed = int.tryParse(parts[0]);
    final free = int.tryParse(parts[1]);
    if (needed == null || free == null) return null;
    return DiskSpaceShortage(neededBytes: needed, freeBytes: free);
  }
}

/// Returns the shortage when the volume of [dir] holds less than
/// [downloadDiskSpaceFactor] x [downloadBytes], otherwise `null`.
///
/// Fail-open: when the probe cannot tell how much space is free, the download
/// is allowed. A probe error must never block a download.
Future<DiskSpaceShortage?> checkDownloadDiskSpace({
  required String dir,
  required int downloadBytes,
  required FreeDiskSpaceProbe probe,
}) async {
  if (downloadBytes <= 0) return null;
  final free = await probe(dir);
  if (free == null) return null;
  final needed = (downloadBytes * downloadDiskSpaceFactor).ceil();
  if (free >= needed) return null;
  return DiskSpaceShortage(neededBytes: needed, freeBytes: free);
}
