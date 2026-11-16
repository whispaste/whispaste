/// Shared JSON response helper for the ticket route groups.
library;

import 'dart:convert';

import 'package:shelf/shelf.dart';

/// Wire version of the automation API. Bumped only for breaking changes.
const kAutomationApiVersion = 1;

Response jsonResponse(int statusCode, Map<String, Object?> body) => Response(
  statusCode,
  body: jsonEncode(body),
  headers: {'content-type': 'application/json'},
);

/// Decodes a request body that must be a JSON object. Returns `null` for
/// anything else, including malformed JSON.
Future<Map<String, dynamic>?> readJsonObject(Stream<List<int>> body) async {
  final text = await body.transform(utf8.decoder).join();
  try {
    final decoded = jsonDecode(text);
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  }
}
