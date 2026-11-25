/// Reads the address a user types or pastes for their own model (#1789).
///
/// Only HTTPS on the default port is accepted, without credentials in the
/// address. A Hugging Face address is recognised in all its usual forms
/// (repo page, `tree/`, `blob/`, `resolve/`, the short `hf.co` host) so the
/// download can be pinned to one commit. Pure: no network, no files.
library;

/// Why an address cannot be used. The UI says it in words.
enum UserModelAddressError {
  empty,
  notAUrl,
  notHttps,
  port,
  credentials,
  hostMissing,
}

/// A parsed address, or the reason it was refused.
sealed class UserModelAddress {
  const UserModelAddress();

  /// Parses [input]. Whitespace around it is ignored.
  static UserModelAddress parse(String input) {
    final text = input.trim();
    if (text.isEmpty) {
      return const RejectedAddress(UserModelAddressError.empty);
    }
    final Uri uri;
    try {
      uri = Uri.parse(text);
    } on FormatException {
      return const RejectedAddress(UserModelAddressError.notAUrl);
    }
    if (!uri.hasScheme) {
      return const RejectedAddress(UserModelAddressError.notAUrl);
    }
    if (uri.scheme.toLowerCase() != 'https') {
      return const RejectedAddress(UserModelAddressError.notHttps);
    }
    if (uri.userInfo.isNotEmpty) {
      return const RejectedAddress(UserModelAddressError.credentials);
    }
    if (uri.host.isEmpty) {
      return const RejectedAddress(UserModelAddressError.hostMissing);
    }
    if (uri.hasPort && uri.port != 443) {
      return const RejectedAddress(UserModelAddressError.port);
    }
    final hf = HuggingFaceAddress.tryFrom(uri);
    if (hf != null) return hf;
    return DirectFileAddress(uri.removeFragment());
  }
}

/// Refused address.
final class RejectedAddress extends UserModelAddress {
  const RejectedAddress(this.error);
  final UserModelAddressError error;
}

/// A Hugging Face model repo, optionally narrowed to a revision, a folder or
/// one file.
final class HuggingFaceAddress extends UserModelAddress {
  const HuggingFaceAddress({
    required this.owner,
    required this.repo,
    this.revision,
    this.path,
    this.pointsAtFile = false,
  });

  final String owner;
  final String repo;

  /// Branch, tag or commit named in the address; null means `main`.
  final String? revision;

  /// Folder (`tree/`) or file (`blob/`, `resolve/`) inside the repo.
  final String? path;

  /// Whether [path] names one file rather than a folder.
  final bool pointsAtFile;

  static const _hosts = {'huggingface.co', 'www.huggingface.co', 'hf.co'};

  /// Paths of the site that are not model repos.
  static const _reserved = {
    'api',
    'datasets',
    'spaces',
    'docs',
    'blog',
    'models',
    'settings',
    'login',
    'join',
    'organizations',
    'collections',
    'papers',
    'pricing',
    'tasks',
  };

  String get repoId => '$owner/$repo';

  /// Null when [uri] is not a model repo address on Hugging Face.
  static HuggingFaceAddress? tryFrom(Uri uri) {
    if (!_hosts.contains(uri.host.toLowerCase())) return null;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length < 2) return null;
    final owner = segments[0];
    final repo = segments[1];
    if (_reserved.contains(owner.toLowerCase()) ||
        !_validName(owner) ||
        !_validName(repo)) {
      return null;
    }
    if (segments.length == 2) {
      return HuggingFaceAddress(owner: owner, repo: repo);
    }
    final kind = segments[2];
    if (segments.length < 4) {
      return HuggingFaceAddress(owner: owner, repo: repo);
    }
    final revision = Uri.decodeComponent(segments[3]);
    final rest = segments.skip(4).map(Uri.decodeComponent).join('/');
    return switch (kind) {
      'tree' => HuggingFaceAddress(
        owner: owner,
        repo: repo,
        revision: revision,
        path: rest.isEmpty ? null : rest,
      ),
      'blob' || 'resolve' when rest.isNotEmpty => HuggingFaceAddress(
        owner: owner,
        repo: repo,
        revision: revision,
        path: rest,
        pointsAtFile: true,
      ),
      _ => HuggingFaceAddress(owner: owner, repo: repo),
    };
  }

  static final _namePattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');

  static bool _validName(String s) =>
      s.length <= 96 && _namePattern.hasMatch(s) && !s.contains('..');
}

/// Any other HTTPS address: taken as one file.
final class DirectFileAddress extends UserModelAddress {
  const DirectFileAddress(this.uri);
  final Uri uri;

  /// The host the user confirms before the first download.
  String get host => uri.host.toLowerCase();

  /// The last path segment, the file name the model gets on disk.
  String get fileName {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty);
    return segments.isEmpty ? '' : segments.last;
  }
}

/// The address a pinned Hugging Face file is downloaded from.
String huggingFaceResolveUrl({
  required String repoId,
  required String commit,
  required String path,
}) {
  final encoded = path.split('/').map(Uri.encodeComponent).join('/');
  return 'https://huggingface.co/$repoId/resolve/$commit/$encoded';
}

/// Whether [revision] is already a full commit hash (nothing to pin).
bool isCommitHash(String? revision) =>
    revision != null && RegExp(r'^[0-9a-f]{40}$').hasMatch(revision);
