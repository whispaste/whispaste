import 'dart:convert';

import 'package:http/http.dart' as http;

/// The Matomo hits carried by one telemetry request: a single form POST or a
/// bulk request (`{"requests": ["?idsite=…", …]}`, #1994).
List<Map<String, String>> telemetryHits(http.Request request) {
  final type = request.headers['content-type'] ?? '';
  if (type.startsWith('application/json')) {
    final requests = (jsonDecode(request.body) as Map)['requests'] as List;
    return [
      for (final r in requests.cast<String>())
        Uri.splitQueryString(r.substring(1)),
    ];
  }
  return [Uri.splitQueryString(request.body)];
}
