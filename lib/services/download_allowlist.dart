/// Host allowlist for every network download the app performs itself.
///
/// [getWithAllowlistedRedirects] is the shared transport: it checks the
/// initial URL and every redirect target against [kDownloadHostAllowlist]
/// before a connection is opened. Anything else fails closed with a
/// [DownloadUrlRejectedException]. HTTPS only, default port only. A host
/// passes if it is an exact [kDownloadHostAllowlist] entry or a subdomain of a
/// [kDownloadDomainAllowlist] entry.
///
/// Store sandbox (AR-19): this adds no entitlement or capability. Downloads
/// still land only in the app-container paths they already used.
library;

import 'package:dio/dio.dart';

import '../core/logging/app_logger.dart';

final _log = AppLogger('DownloadAllowlist');

/// Hosts the app may download from, with the reason each one is reachable.
///
/// Redirect targets were observed with `curl -sI` against the real URLs on
/// 2026-10-17. HuggingFace answers `resolve/` with a 302 to its Xet CDN; GitHub
/// release assets answer with a 302 to `release-assets.githubusercontent.com`.
/// If a CDN host outside this list shows up in practice, the download fails
/// closed with the host name in the message, and the list is extended here.
const Map<String, String> kDownloadHostAllowlist = {
  'huggingface.co':
      'Model files: whisper GGML, Parakeet sherpa bundle and GGUF, and the '
      'Smart Mode Gemma GGUF. Answers resolve/ URLs with a 302 to the CDN.',
  'us.aws.cdn.hf.co':
      'HuggingFace Xet CDN, the 302 target of every huggingface.co resolve/ '
      'URL above. Signed, anonymous URLs.',
  'github.com':
      'CUDA pack archive (releases/download/cuda-*), which answers with a 302 '
      'to the release-asset CDN. Also the stable appcast URL that the native '
      'updater reads.',
  'release-assets.githubusercontent.com':
      'GitHub release-asset CDN, the 302 target of github.com release '
      'downloads (CUDA pack).',
  'objects.githubusercontent.com':
      'Older GitHub release-asset CDN host, still served for some assets.',
  'api.github.com':
      'Release metadata JSON for the in-app update check (UpdateService).',
  'raw.githubusercontent.com':
      'Beta appcast pointer read by the native updater (Sparkle/WinSparkle). '
      'Not fetched through this transport; listed so the feed host is '
      'covered by the same policy.',
};

/// Vendor-owned domains whose subdomains are all allowed.
///
/// HuggingFace picks the CDN host per region and storage backend
/// (`cdn-lfs-eu-1.hf.co`, `cas-bridge.xethub.hf.co`, ...), so an exact list
/// observed from one location would break downloads elsewhere. Both domains
/// belong to HuggingFace; the match requires a `.` boundary, so look-alikes
/// such as `evilhf.co` or `hf.co.example` do not pass.
const Map<String, String> kDownloadDomainAllowlist = {
  'hf.co': 'HuggingFace CDN hosts, the 302 targets of huggingface.co.',
  'huggingface.co': 'HuggingFace LFS CDN hosts (cdn-lfs.huggingface.co).',
};

bool _isAllowedHost(String host) =>
    kDownloadHostAllowlist.containsKey(host) ||
    kDownloadDomainAllowlist.keys.any((domain) => host.endsWith('.$domain'));

/// Thrown when a URL or redirect target is not allowed. Its [toString] is
/// the user-facing message, because the download notifiers show `'$e'`.
class DownloadUrlRejectedException implements Exception {
  const DownloadUrlRejectedException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Redirects followed before giving up. Matches Dio's default.
const int kMaxDownloadRedirects = 5;

const Set<int> _redirectStatuses = {301, 302, 303, 307, 308};

/// Throws [DownloadUrlRejectedException] unless [uri] is an HTTPS URL on the
/// default port whose host is allowed (see the library doc).
void assertAllowedDownloadUri(Uri uri) {
  if (uri.scheme != 'https') {
    throw DownloadUrlRejectedException(
      'Download blocked: only HTTPS is allowed (${uri.scheme}://${uri.host}).',
    );
  }
  final host = uri.host;
  if (host.isEmpty || (uri.hasPort && uri.port != 443)) {
    throw DownloadUrlRejectedException(
      'Download blocked: unexpected address "${uri.authority}".',
    );
  }
  if (!_isAllowedHost(host)) {
    throw DownloadUrlRejectedException(
      'Download blocked: host "$host" is not on the download allowlist.',
    );
  }
}

/// GET [url] with Dio, checking every hop against the allowlist.
///
/// Redirects are followed by hand (Dio's own following is switched off)
/// so each `Location` target is checked before it is requested. Request
/// headers, including a resume `Range`, are sent again on every hop.
/// Non-redirect error statuses still throw [DioException] as before.
Future<Response<T>> getWithAllowlistedRedirects<T>(
  Dio dio,
  String url, {
  Options? options,
  CancelToken? cancelToken,
}) async {
  var uri = Uri.parse(url);
  final base = options ?? Options();
  for (var hop = 0; ; hop++) {
    assertAllowedDownloadUri(uri);
    final response = await dio.get<T>(
      uri.toString(),
      cancelToken: cancelToken,
      options: base.copyWith(
        followRedirects: false,
        validateStatus: (status) =>
            status != null &&
            (status < 300 || _redirectStatuses.contains(status)),
      ),
    );
    final status = response.statusCode ?? 0;
    if (!_redirectStatuses.contains(status)) return response;

    await _discardBody(response.data);
    if (hop >= kMaxDownloadRedirects) {
      throw const DownloadUrlRejectedException(
        'Download blocked: more than $kMaxDownloadRedirects redirects.',
      );
    }
    final location = response.headers.value('location');
    if (location == null || location.isEmpty) {
      throw const DownloadUrlRejectedException(
        'Download failed: redirect without a Location header.',
      );
    }
    uri = uri.resolveUri(Uri.parse(location));
  }
}

/// Drops an unread redirect body so its connection can close.
Future<void> _discardBody(Object? data) async {
  if (data is ResponseBody) {
    try {
      await data.stream.drain<void>();
    } on Exception catch (e) {
      // The redirect body is unused, so a failed drain only costs the
      // connection's reuse; the redirect itself still proceeds.
      _log.warning('Could not drain redirect body: $e');
    }
  }
}
