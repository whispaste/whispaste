/// Rules for the user's own OpenAI-compatible endpoint (W-M3): address checks,
/// the network notice, the URL of each request and the error class of an HTTP
/// status. Pure functions, no I/O, so the rules are tested without a network.
library;

/// Why a configured endpoint address is refused.
enum CustomEndpointUrlProblem {
  /// Nothing entered.
  empty,

  /// Not an absolute http(s) address with a host.
  invalid,

  /// Carries credentials, a query or a fragment. Credentials belong in the
  /// key field, where they are stored in secure storage.
  credentialsOrQuery,

  /// Plain http to a public host. The key and the audio or text would travel
  /// unencrypted over the internet, so the address is refused. Plain http on
  /// this device or in the local network is allowed with a warning.
  httpToRemoteHost,
}

/// Result of [checkCustomEndpointUrl]: the parsed address when it is usable,
/// otherwise the [problem].
class CustomEndpointUrlCheck {
  const CustomEndpointUrlCheck._(this.uri, this.problem);

  const CustomEndpointUrlCheck.ok(Uri uri) : this._(uri, null);

  const CustomEndpointUrlCheck.refused(CustomEndpointUrlProblem problem)
    : this._(null, problem);

  final Uri? uri;
  final CustomEndpointUrlProblem? problem;

  bool get isValid => uri != null;
}

/// How far the data travels for a host, from nearest to farthest.
enum CustomEndpointNetwork {
  /// Loopback: `localhost`, `127.0.0.0/8`, `::1`. Stays on this device.
  device,

  /// Private addresses (10/8, 172.16/12, 192.168/16, 169.254/16, fc00::/7,
  /// fe80::/10) and `.local` names. Stays in the local network, but other
  /// devices on that network can read plain traffic.
  lan,

  /// Any other host. The data leaves the local network; the host is named.
  remote,
}

/// Classifies [host] by how far data sent to it travels.
CustomEndpointNetwork customEndpointNetworkOf(String host) {
  final h = host.toLowerCase();
  if (h == 'localhost' || h == '::1') return CustomEndpointNetwork.device;
  if (h.endsWith('.local')) return CustomEndpointNetwork.lan;
  if (h.contains(':')) {
    return _isPrivateIpv6(h)
        ? CustomEndpointNetwork.lan
        : CustomEndpointNetwork.remote;
  }
  final v4 = RegExp(
    r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$',
  ).firstMatch(h);
  if (v4 == null) return CustomEndpointNetwork.remote;
  // A leading zero makes the system resolver read the octet as octal (glibc:
  // 010.0.0.1 is 8.0.0.1, a public address), while Dart reads it as decimal.
  // Such a literal cannot be classed reliably, so it counts as remote.
  if (h.split('.').any((octet) => octet.length > 1 && octet.startsWith('0'))) {
    return CustomEndpointNetwork.remote;
  }
  final a = int.parse(v4.group(1)!);
  final b = int.parse(v4.group(2)!);
  if (a == 127) return CustomEndpointNetwork.device;
  if (a == 10) return CustomEndpointNetwork.lan;
  if (a == 172 && b >= 16 && b <= 31) return CustomEndpointNetwork.lan;
  if (a == 192 && b == 168) return CustomEndpointNetwork.lan;
  if (a == 169 && b == 254) return CustomEndpointNetwork.lan;
  return CustomEndpointNetwork.remote;
}

/// fc00::/7 (unique local) and fe80::/10 (link local), for an IPv6 literal.
bool _isPrivateIpv6(String h) {
  final first = h.split(':').first;
  if (first.startsWith('fc') || first.startsWith('fd')) return true;
  final value = int.tryParse(first.padLeft(4, '0'), radix: 16);
  return value != null && value >= 0xfe80 && value <= 0xfebf;
}

/// Checks an address entered in the settings. Trims it, then accepts an
/// absolute `https` address for any host, and `http` only for a device or a
/// local-network host.
CustomEndpointUrlCheck checkCustomEndpointUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return const CustomEndpointUrlCheck.refused(CustomEndpointUrlProblem.empty);
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      (uri.scheme != 'http' && uri.scheme != 'https')) {
    return const CustomEndpointUrlCheck.refused(
      CustomEndpointUrlProblem.invalid,
    );
  }
  if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
    return const CustomEndpointUrlCheck.refused(
      CustomEndpointUrlProblem.credentialsOrQuery,
    );
  }
  if (uri.scheme == 'http' &&
      customEndpointNetworkOf(uri.host) == CustomEndpointNetwork.remote) {
    return const CustomEndpointUrlCheck.refused(
      CustomEndpointUrlProblem.httpToRemoteHost,
    );
  }
  return CustomEndpointUrlCheck.ok(uri);
}

/// Whether the endpoint can run a function now: a usable address and a model
/// name. The key is optional, since many local servers need none.
bool customEndpointReady({required String url, required String model}) =>
    checkCustomEndpointUrl(url).isValid && model.trim().isNotEmpty;

/// Whether a valid [uri] sends plain http into the local network. The settings
/// show a warning then, because other devices on the network can read it.
bool customEndpointPlainHttpOnLan(Uri uri) =>
    uri.scheme == 'http' &&
    customEndpointNetworkOf(uri.host) == CustomEndpointNetwork.lan;

/// Network notice for a valid [uri]: how far the data travels, and for a
/// remote host the name that receives it. [host] is set only for `remote`.
({CustomEndpointNetwork network, String? host}) customEndpointNetworkNotice(
  Uri uri,
) {
  final network = customEndpointNetworkOf(uri.host);
  return (
    network: network,
    host: network == CustomEndpointNetwork.remote ? uri.host : null,
  );
}

/// The endpoint address with [suffix] appended to its path, for example
/// `/chat/completions`. A trailing slash of the base path is dropped first, so
/// `http://localhost:1234/v1/` and `…/v1` give the same request URL.
Uri customEndpointUrl(Uri base, String suffix) {
  final basePath = base.path.replaceAll(RegExp(r'/+$'), '');
  return base.replace(path: '$basePath$suffix');
}

/// The error class of an HTTP [status] other than 200 and 429 from an
/// OpenAI-compatible server. The rate-limit (429) and server (5xx) cases keep
/// their own retry rules in the transcriber, so this only names the class.
enum CustomEndpointHttpClass {
  /// 401 or 403: the key is missing or refused.
  unauthorized,

  /// The server does not know the model (404 or 400 that names the model).
  modelMissing,

  /// The server answered, but not as an OpenAI-compatible service would
  /// (wrong path or unsupported request).
  badFormat,

  /// 5xx.
  serverError,
}

/// Class of a non-200 response (except 429, which the caller handles).
CustomEndpointHttpClass customEndpointHttpClass(int status, String body) {
  if (status == 401 || status == 403) {
    return CustomEndpointHttpClass.unauthorized;
  }
  if (status >= 500) return CustomEndpointHttpClass.serverError;
  if (status == 404 || status == 400 || status == 422) {
    return body.toLowerCase().contains('model')
        ? CustomEndpointHttpClass.modelMissing
        : CustomEndpointHttpClass.badFormat;
  }
  return CustomEndpointHttpClass.badFormat;
}
