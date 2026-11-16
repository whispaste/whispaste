import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Result of [installMozillaRoots]. Counts only, nothing here throws.
class MozillaRootsResult {
  const MozillaRootsResult({required this.added, required this.rejected});

  /// Certificates the TLS stack accepted into the context.
  final int added;

  /// Certificates the TLS stack refused. Usually roots that are already
  /// trusted through the system store, which is harmless.
  final int rejected;
}

/// Adds every certificate in [pemBytes] to [context] one by one.
///
/// Certificates are added individually, so one refused entry (a duplicate of
/// a system root, or a damaged block) never hides the ones after it. Never
/// throws: the system store stays active whatever happens here.
///
/// Pure Dart on purpose (no Flutter import), so the same code runs in the app
/// and in the Windows lab probe.
MozillaRootsResult installMozillaRoots(
  SecurityContext context,
  Uint8List pemBytes,
) {
  final text = utf8.decode(pemBytes, allowMalformed: true);
  var added = 0;
  var rejected = 0;
  for (final block in _pemCertificateBlocks(text)) {
    try {
      context.setTrustedCertificatesBytes(utf8.encode(block));
      added++;
    } on Exception {
      rejected++;
    }
  }
  return MozillaRootsResult(added: added, rejected: rejected);
}

/// Yields each `BEGIN CERTIFICATE` … `END CERTIFICATE` block, including its
/// markers. Comment lines between blocks (subject names) are dropped.
Iterable<String> _pemCertificateBlocks(String text) sync* {
  const begin = '-----BEGIN CERTIFICATE-----';
  const end = '-----END CERTIFICATE-----';
  var from = 0;
  while (true) {
    final start = text.indexOf(begin, from);
    if (start < 0) return;
    final endAt = text.indexOf(end, start);
    if (endAt < 0) return;
    final stop = endAt + end.length;
    yield '${text.substring(start, stop)}\n';
    from = stop;
  }
}
