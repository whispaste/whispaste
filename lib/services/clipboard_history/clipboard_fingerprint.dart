import 'dart:convert';

/// A cheap, deterministic content fingerprint for clipboard text, used to
/// recognize "this clipboard content is something WhisPaste itself just
/// wrote" by matching against the *actual* content later observed on the
/// clipboard -- not by predicting a native change-sequence number.
///
/// A sequence-based approach ("skip changeCount N+1") breaks whenever a
/// single logical write produces more than one native change notification
/// (e.g. macOS `clearContents()` followed by `setString()` on the same
/// pasteboard) or when dispatch order between two different platform
/// channels isn't guaranteed. Content matching sidesteps both: whichever
/// change notification the native monitor ends up polling, it only needs to
/// compare the pasteboard's current content against pending fingerprints.
class ClipboardFingerprint {
  const ClipboardFingerprint({required this.length, required this.hash});

  factory ClipboardFingerprint.ofText(String text) {
    final bytes = utf8.encode(text);
    return ClipboardFingerprint(length: bytes.length, hash: _fnv1a64(bytes));
  }

  final int length;
  final int hash;

  @override
  bool operator ==(Object other) =>
      other is ClipboardFingerprint &&
      other.length == length &&
      other.hash == hash;

  @override
  int get hashCode => Object.hash(length, hash);
}

/// FNV-1a, 64-bit. Not cryptographic -- only needs to be cheap, stable
/// across the process, and trivially reimplementable identically on the
/// native side (Swift/C++/GTK) for issues 04-06.
int _fnv1a64(List<int> bytes) {
  const offsetBasis = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  const mask = 0xFFFFFFFFFFFFFFFF;
  var hash = offsetBasis;
  for (final byte in bytes) {
    hash = (hash ^ byte) & mask;
    hash = (hash * prime) & mask;
  }
  return hash;
}
