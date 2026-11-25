/// "Modelle laden" for the user's own OpenAI-compatible endpoint (#1790).
///
/// Asks the server which models it offers, so the user can pick a name instead
/// of typing it. Runs only when the user presses the button, never in the
/// background. Sends `GET {base}/models` (OpenAI-compatible, carries no audio
/// and no text). When that path is missing, it also tries Ollama's own list,
/// `GET {root}/api/tags`, where `root` is the address without a trailing `/v1`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/custom_endpoint_rules.dart';
import 'custom_endpoint_probe.dart' show kCustomEndpointProbeTimeout;

/// How many model names the list keeps at most. A server with more is rare;
/// the field still takes any name typed by hand.
const int kCustomEndpointModelListMax = 200;

/// What the model list request found, each with one message at the field.
enum CustomEndpointModelListResult {
  /// The server listed at least one model.
  loaded,

  /// The server answered with an empty list (some servers list nothing until
  /// a model is loaded).
  empty,

  /// No answer: refused, unknown host, timeout.
  unreachable,

  /// 401 or 403: the key is missing or refused.
  unauthorized,

  /// The server answers, but offers no model list (`/models` missing or not
  /// in the OpenAI or Ollama format).
  noList,

  /// 5xx from the server.
  serverError,
}

class CustomEndpointModelList {
  const CustomEndpointModelList(
    this.result, {
    this.models = const [],
    this.needsV1 = false,
  });

  final CustomEndpointModelListResult result;

  /// The model names, sorted, without duplicates, at most
  /// [kCustomEndpointModelListMax]. Empty unless [result] is `loaded`.
  final List<String> models;

  /// True when only Ollama's own list answered and the address does not end
  /// in `/v1`: the names are right, but dictation needs the `/v1` address.
  final bool needsV1;
}

/// Loads the model list from [base] with the optional [apiKey].
///
/// [client] is injected by tests. Without one, a client is created and closed
/// here.
Future<CustomEndpointModelList> loadCustomEndpointModels({
  required Uri base,
  String? apiKey,
  http.Client? client,
  Duration timeout = kCustomEndpointProbeTimeout,
}) async {
  final own = client ?? http.Client();
  final headers = {
    if (apiKey != null && apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
  };
  try {
    final openAi = await _fetch(
      own,
      customEndpointUrl(base, '/models'),
      headers,
      timeout,
      _openAiIds,
    );
    if (openAi.result != CustomEndpointModelListResult.noList) return openAi;
    // No OpenAI-style list here. Ollama answers its own list at the root.
    final tags = await _fetch(
      own,
      customEndpointUrl(customEndpointOllamaRoot(base), '/api/tags'),
      headers,
      timeout,
      _ollamaNames,
    );
    if (tags.result != CustomEndpointModelListResult.loaded &&
        tags.result != CustomEndpointModelListResult.empty) {
      return openAi;
    }
    return CustomEndpointModelList(
      tags.result,
      models: tags.models,
      needsV1: !_endsInV1(base),
    );
  } finally {
    if (client == null) own.close();
  }
}

/// The address without a trailing `/v1`, where Ollama serves `/api/tags`.
Uri customEndpointOllamaRoot(Uri base) {
  final path = base.path.replaceAll(RegExp(r'/+$'), '');
  return base.replace(
    path: path.endsWith('/v1') ? path.substring(0, path.length - 3) : path,
  );
}

bool _endsInV1(Uri base) =>
    base.path.replaceAll(RegExp(r'/+$'), '').endsWith('/v1');

Future<CustomEndpointModelList> _fetch(
  http.Client client,
  Uri url,
  Map<String, String> headers,
  Duration timeout,
  List<String>? Function(Object? json) parse,
) async {
  final http.Response response;
  try {
    response = await client.get(url, headers: headers).timeout(timeout);
  } on TimeoutException {
    return const CustomEndpointModelList(
      CustomEndpointModelListResult.unreachable,
    );
  } on Exception {
    return const CustomEndpointModelList(
      CustomEndpointModelListResult.unreachable,
    );
  }
  final status = response.statusCode;
  if (status == 401 || status == 403) {
    return const CustomEndpointModelList(
      CustomEndpointModelListResult.unauthorized,
    );
  }
  if (status >= 500) {
    return const CustomEndpointModelList(
      CustomEndpointModelListResult.serverError,
    );
  }
  if (status != 200) {
    return const CustomEndpointModelList(CustomEndpointModelListResult.noList);
  }
  final Object? json;
  try {
    json = jsonDecode(response.body);
  } on FormatException {
    return const CustomEndpointModelList(CustomEndpointModelListResult.noList);
  }
  final ids = parse(json);
  if (ids == null) {
    return const CustomEndpointModelList(CustomEndpointModelListResult.noList);
  }
  final models = customEndpointModelNames(ids);
  return models.isEmpty
      ? const CustomEndpointModelList(CustomEndpointModelListResult.empty)
      : CustomEndpointModelList(
          CustomEndpointModelListResult.loaded,
          models: models,
        );
}

/// `{"data": [{"id": "…"}]}`, the OpenAI format. Null when it is not that.
List<String>? _openAiIds(Object? json) {
  if (json is! Map || json['data'] is! List) return null;
  return [
    for (final entry in json['data'] as List)
      if (entry is Map && entry['id'] is String) entry['id'] as String,
  ];
}

/// `{"models": [{"name": "…"}]}`, Ollama's `/api/tags`. Null when it is not
/// that.
List<String>? _ollamaNames(Object? json) {
  if (json is! Map || json['models'] is! List) return null;
  return [
    for (final entry in json['models'] as List)
      if (entry is Map && entry['name'] is String)
        entry['name'] as String
      else if (entry is Map && entry['model'] is String)
        entry['model'] as String,
  ];
}

/// Trimmed, non-empty, without duplicates, sorted case-insensitively and
/// capped at [kCustomEndpointModelListMax], so a long list stays findable.
List<String> customEndpointModelNames(Iterable<String> raw) {
  final names = <String>{
    for (final name in raw)
      if (name.trim().isNotEmpty) name.trim(),
  }.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return names.take(kCustomEndpointModelListMax).toList();
}
