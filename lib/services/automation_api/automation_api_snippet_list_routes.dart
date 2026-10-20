/// Route group: list snippets and render one with field values (WP-38 / 8.1).
///
/// Rendering returns text only. Insertion (paste) stays on
/// `POST /v1/snippets/insert`, which is the one path that is gated by the
/// multiline preview.
library;

import 'package:shelf/shelf.dart';

import '../../core/logging/app_logger.dart';
import 'automation_api_responses.dart';
import 'automation_api_router.dart';
import 'automation_snippet_render.dart';

final _log = AppLogger('AutomationApiSnippetListRoutes');

AutomationApiRouteGroup automationSnippetCatalogRoutes({
  required Future<List<Map<String, Object?>>> Function() listSnippets,
  required Future<SnippetRenderOutcome?> Function(
    String name,
    Map<String, String> values,
  )
  renderSnippet,
}) {
  return (router) {
    router.add('GET', '/v1/snippets', (Request request) async {
      try {
        return jsonResponse(200, {'snippets': await listSnippets()});
      } catch (e, st) {
        _log.warning('GET /v1/snippets failed', e, st);
        return jsonResponse(500, {'error': 'snippets_failed'});
      }
    });

    router.add('POST', '/v1/snippets/render', (Request request) async {
      final body = await readJsonObject(request.read());
      final name = body?['name'];
      if (name is! String || name.trim().isEmpty) {
        return jsonResponse(400, {'error': 'invalid_request'});
      }

      final rawValues = body?['values'] ?? const <String, Object?>{};
      if (rawValues is! Map || rawValues.values.any((v) => v is! String)) {
        return jsonResponse(400, {'error': 'invalid_request'});
      }
      final values = {
        for (final entry in rawValues.entries)
          entry.key as String: entry.value as String,
      };

      final SnippetRenderOutcome? outcome;
      try {
        outcome = await renderSnippet(name, values);
      } catch (e, st) {
        _log.warning('POST /v1/snippets/render failed', e, st);
        return jsonResponse(500, {'error': 'render_failed'});
      }

      return switch (outcome) {
        null => jsonResponse(404, {'error': 'snippet_not_found'}),
        SnippetRenderSuccess(:final text) => jsonResponse(200, {
          'name': name,
          'text': text,
        }),
        SnippetRenderMissingFields(:final names) => jsonResponse(400, {
          'error': 'missing_fields',
          'fields': names,
        }),
        SnippetRenderUnknownFields(:final names) => jsonResponse(400, {
          'error': 'unknown_fields',
          'fields': names,
        }),
      };
    });
  };
}
