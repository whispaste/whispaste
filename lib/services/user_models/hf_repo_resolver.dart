/// Asks Hugging Face which commit a repo address stands for and which files
/// it holds (#1789), so a user model is pinned to one fixed version.
///
/// One anonymous GET of the public model API on `huggingface.co` (on the
/// fixed download allowlist). Nothing about the user is sent.
library;

import 'package:dio/dio.dart';

import '../download_allowlist.dart';
import 'user_model_address.dart';
import 'user_model_detection.dart';

/// Why a repo could not be read.
enum HfResolveError {
  /// No such repo, or private.
  notFound,

  /// Needs a login and an accepted form on the site; WhisPaste downloads
  /// anonymously only.
  gated,

  /// The address names a file or folder the commit does not have.
  pathMissing,
  network,
  badResponse,
}

class HfResolveException implements Exception {
  const HfResolveException(this.error);
  final HfResolveError error;

  @override
  String toString() => 'HfResolveException(${error.name})';
}

/// A repo at one commit.
class HfRepoSnapshot {
  const HfRepoSnapshot({
    required this.repoId,
    required this.commit,
    required this.files,
    this.license,
  });

  final String repoId;

  /// The full commit hash every download URL is pinned to.
  final String commit;

  /// Files in the repo, narrowed to the folder or file of the address.
  final List<SourceFile> files;

  /// The license the model card names, as written there.
  final String? license;
}

/// Reads the API answer for [address]. Pure, for tests.
HfRepoSnapshot parseHfModelInfo(
  Object? json, {
  required HuggingFaceAddress address,
}) {
  if (json is! Map) throw const HfResolveException(HfResolveError.badResponse);
  final gated = json['gated'];
  if (gated == 'auto' || gated == 'manual' || gated == true) {
    throw const HfResolveException(HfResolveError.gated);
  }
  final sha = json['sha'];
  if (sha is! String || !isCommitHash(sha)) {
    throw const HfResolveException(HfResolveError.badResponse);
  }
  final siblings = json['siblings'];
  if (siblings is! List) {
    throw const HfResolveException(HfResolveError.badResponse);
  }
  final files = <SourceFile>[];
  for (final s in siblings) {
    if (s is! Map) continue;
    final name = s['rfilename'];
    if (name is! String || name.isEmpty || name.contains('..')) continue;
    final lfs = s['lfs'];
    var size = s['size'] is int ? s['size'] as int : 0;
    String? sha256;
    if (lfs is Map) {
      if (lfs['size'] is int) size = lfs['size'] as int;
      final h = lfs['sha256'];
      if (h is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(h)) sha256 = h;
    }
    files.add(SourceFile(path: name, sizeBytes: size, sha256: sha256));
  }
  final narrowed = _narrow(files, address);
  if (address.path != null && narrowed.isEmpty) {
    throw const HfResolveException(HfResolveError.pathMissing);
  }
  String? license;
  final card = json['cardData'];
  if (card is Map) {
    final l = card['license'];
    if (l is String && l.trim().isNotEmpty) {
      license = l.trim();
    } else if (l is List && l.isNotEmpty) {
      license = l.whereType<String>().join(', ');
    }
    final name = card['license_name'];
    if (license == 'other' && name is String && name.trim().isNotEmpty) {
      license = name.trim();
    }
  }
  return HfRepoSnapshot(
    repoId: address.repoId,
    commit: sha,
    files: narrowed,
    license: license,
  );
}

/// A file address keeps that file, plus — for sherpa-onnx — its folder's
/// other files and subfolders (the tokens or tokenizer), so detection still
/// sees the whole model. A
/// folder address keeps that folder.
List<SourceFile> _narrow(List<SourceFile> files, HuggingFaceAddress address) {
  final path = address.path;
  if (path == null) return files;
  if (address.pointsAtFile) {
    final hit = files.where((f) => f.path == path).toList();
    if (hit.isEmpty) return const [];
    final folder = hit.first.folder;
    final lower = hit.first.baseName.toLowerCase();
    if (lower.endsWith('.onnx')) {
      // The folder and what lies below it (a `tokenizer/` folder).
      return files
          .where(
            (f) =>
                f.folder == folder ||
                folder.isEmpty ||
                f.folder.startsWith('$folder/'),
          )
          .toList();
    }
    return hit;
  }
  final prefix = path.endsWith('/') ? path : '$path/';
  return files.where((f) => f.path.startsWith(prefix)).toList();
}

/// The model API URL for [address].
Uri hfModelApiUri(HuggingFaceAddress address) {
  final rev = Uri.encodeComponent(address.revision ?? 'main');
  return Uri.parse(
    'https://huggingface.co/api/models/${address.repoId}/revision/$rev?blobs=true',
  );
}

/// Fetches and reads the snapshot for [address].
Future<HfRepoSnapshot> resolveHfRepo(
  HuggingFaceAddress address, {
  Dio? dio,
}) async {
  final client =
      dio ??
      Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 30),
          headers: {'User-Agent': 'WhisPaste'},
        ),
      );
  try {
    final response = await getWithAllowlistedRedirects<Object?>(
      client,
      hfModelApiUri(address).toString(),
      options: Options(responseType: ResponseType.json),
    );
    return parseHfModelInfo(response.data, address: address);
  } on DioException catch (e) {
    final status = e.response?.statusCode;
    if (status == 401 || status == 404) {
      throw const HfResolveException(HfResolveError.notFound);
    }
    if (status == 403) throw const HfResolveException(HfResolveError.gated);
    throw const HfResolveException(HfResolveError.network);
  } on DownloadUrlRejectedException {
    throw const HfResolveException(HfResolveError.network);
  } finally {
    if (dio == null) client.close();
  }
}
