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
  return CustomEndpointUrlCheck.ok(customEndpointApiBase(uri));
}

/// Request paths that people copy from a server's help page together with the
/// address. They are dropped, so the base is what is left before them.
const List<String> _customEndpointRequestPaths = [
  '/chat/completions',
  '/completions',
  '/audio/transcriptions',
  '/models',
];

/// The API base of an entered address (#1957). Every server WhisPaste names
/// (Ollama, LM Studio, llama.cpp, Jan, LocalAI, vLLM, text-generation-webui,
/// KoboldCpp, GPT4All) serves its OpenAI-compatible API under `/v1`, and their
/// help pages show either the bare root (`http://localhost:11434`) or a full
/// request URL (`…/v1/chat/completions`). So trailing slashes and a trailing
/// request path are dropped, and an address without any path gets `/v1`. Any
/// other path is kept as entered, for a provider that serves elsewhere.
Uri customEndpointApiBase(Uri uri) {
  var path = uri.path.replaceAll(RegExp(r'/+$'), '');
  for (final suffix in _customEndpointRequestPaths) {
    if (path.toLowerCase().endsWith(suffix)) {
      path = path.substring(0, path.length - suffix.length);
      break;
    }
  }
  path = path.replaceAll(RegExp(r'/+$'), '');
  return uri.replace(path: path.isEmpty ? '/v1' : path);
}

/// A well-known local server and its usual address on this device (#1957).
typedef CustomEndpointServerPreset = ({String name, String url});

/// The servers people most often already run, each with the address it
/// listens on after a default install (checked against each project's own
/// docs, Ollama and llama.cpp also live, 2026-11-19). `127.0.0.1`, not
/// `localhost`: most of them listen on IPv4 only, and `localhost` can resolve
/// to IPv6 `::1` first. The settings offer them as a shortcut that fills in
/// the address; the handbook lists the same addresses.
const List<CustomEndpointServerPreset> kCustomEndpointServerPresets = [
  (name: 'Ollama', url: 'http://127.0.0.1:11434/v1'),
  (name: 'LM Studio', url: 'http://127.0.0.1:1234/v1'),
  // Port 9931 since llama.cpp PR #30159 (October 2026); older builds
  // listen on 8080, which the handbook mentions.
  (name: 'llama.cpp (llama-server)', url: 'http://127.0.0.1:9931/v1'),
  (name: 'Jan', url: 'http://127.0.0.1:1337/v1'),
  (name: 'LocalAI', url: 'http://127.0.0.1:8080/v1'),
  (name: 'vLLM', url: 'http://127.0.0.1:8000/v1'),
  (name: 'text-generation-webui', url: 'http://127.0.0.1:5000/v1'),
  (name: 'KoboldCpp', url: 'http://127.0.0.1:5001/v1'),
  (name: 'GPT4All', url: 'http://127.0.0.1:4891/v1'),
];

/// The preset whose address is entered in [raw], or null. Compares the API
/// bases, so `http://127.0.0.1:11434` and `…:11434/v1/` both name Ollama.
CustomEndpointServerPreset? customEndpointServerPresetFor(String raw) {
  final uri = checkCustomEndpointUrl(raw).uri;
  if (uri == null) return null;
  for (final preset in kCustomEndpointServerPresets) {
    if (checkCustomEndpointUrl(preset.url).uri == uri) return preset;
  }
  return null;
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
