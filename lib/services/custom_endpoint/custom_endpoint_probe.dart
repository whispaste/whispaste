/// "Verbindung testen" for the user's own OpenAI-compatible endpoint (W-M3).
///
/// Sends one `GET {base}/models`, which every OpenAI-compatible server answers
/// and which carries no audio and no text. It proves that the server is
/// reachable, that the key (if any) is accepted, and whether the model name is
/// among the models the server lists. It cannot prove that the server accepts
/// audio uploads; that shows up on the first real request.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/custom_endpoint_rules.dart';

/// Time the probe waits for an answer before it reports the endpoint as
/// unreachable.
const Duration kCustomEndpointProbeTimeout = Duration(seconds: 8);

/// How many listed model names the result shows at most.
const int kCustomEndpointProbeListedModels = 8;

/// What the probe found, each with one next step in the settings text.
enum CustomEndpointProbeResult {
  /// Reachable and accepted. [CustomEndpointProbe.modelVerified] says whether
  /// the model name was found in the list.
  connected,

  /// Reachable, but the model is not among the listed models.
  modelMissing,

  /// No answer: refused, unknown host, timeout.
  unreachable,

  /// 401 or 403: the key is missing or refused.
  unauthorized,

  /// The address answers, but not as an OpenAI-compatible service would
  /// (e.g. a 404 for `/models`, or a body without a model list).
  badFormat,

  /// 5xx from the server.
  serverError,
}

class CustomEndpointProbe {
  const CustomEndpointProbe(
    this.result, {
    this.modelVerified = false,
    this.availableModels = const [],
  });

  final CustomEndpointProbeResult result;

  /// True when [CustomEndpointProbeResult.connected] also confirmed the model.
  /// False when the server lists no models at all, so the name is checked on
  /// the first request instead.
  final bool modelVerified;

  /// Model names the server listed, at most [kCustomEndpointProbeListedModels].
  final List<String> availableModels;
}

/// Runs the probe against [base] with the optional [apiKey] and [model].
///
/// [client] is injected by tests. Without one, a client is created and closed
/// here.
Future<CustomEndpointProbe> probeCustomEndpoint({
  required Uri base,
  required String model,
  String? apiKey,
  http.Client? client,
  Duration timeout = kCustomEndpointProbeTimeout,
}) async {
  final own = client ?? http.Client();
  try {
    final response = await own
        .get(
          customEndpointUrl(base, '/models'),
          headers: {
            if (apiKey != null && apiKey.isNotEmpty)
              'Authorization': 'Bearer $apiKey',
          },
        )
        .timeout(timeout);
    return _classify(response, model);
  } on TimeoutException {
    return const CustomEndpointProbe(CustomEndpointProbeResult.unreachable);
  } on Exception {
    return const CustomEndpointProbe(CustomEndpointProbeResult.unreachable);
  } finally {
    if (client == null) own.close();
  }
}

CustomEndpointProbe _classify(http.Response response, String model) {
  final status = response.statusCode;
  if (status == 200) return _classifyModelList(response.body, model);
  if (status == 401 || status == 403) {
    return const CustomEndpointProbe(CustomEndpointProbeResult.unauthorized);
  }
  // A 404 on /models means the address does not end where an OpenAI-compatible
  // service lives (usually `/v1`), whatever the body says.
  if (status == 404) {
    return const CustomEndpointProbe(CustomEndpointProbeResult.badFormat);
  }
  return switch (customEndpointHttpClass(status, response.body)) {
    CustomEndpointHttpClass.serverError => const CustomEndpointProbe(
      CustomEndpointProbeResult.serverError,
    ),
    _ => const CustomEndpointProbe(CustomEndpointProbeResult.badFormat),
  };
}

CustomEndpointProbe _classifyModelList(String body, String model) {
  final Object? json;
  try {
    json = jsonDecode(body);
  } on FormatException {
    return const CustomEndpointProbe(CustomEndpointProbeResult.badFormat);
  }
  if (json is! Map || json['data'] is! List) {
    return const CustomEndpointProbe(CustomEndpointProbeResult.badFormat);
  }
  final ids = [
    for (final entry in json['data'] as List)
      if (entry is Map && entry['id'] is String) entry['id'] as String,
  ];
  if (ids.isEmpty) {
    // Some servers list nothing until a model is loaded. The name is then
    // checked on the first request.
    return const CustomEndpointProbe(CustomEndpointProbeResult.connected);
  }
  if (ids.contains(model)) {
    return CustomEndpointProbe(
      CustomEndpointProbeResult.connected,
      modelVerified: true,
      availableModels: ids.take(kCustomEndpointProbeListedModels).toList(),
    );
  }
  return CustomEndpointProbe(
    CustomEndpointProbeResult.modelMissing,
    availableModels: ids.take(kCustomEndpointProbeListedModels).toList(),
  );
}
