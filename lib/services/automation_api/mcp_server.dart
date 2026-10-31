/// Minimal stdio MCP server that forwards tool calls to the automation API
/// (ticket / 8.4).
///
/// Hand-written JSON-RPC 2.0 over newline-delimited messages, as the MCP
/// stdio transport specifies. Only the pieces a tools-only server needs:
/// `initialize`, `notifications/initialized`, `ping`, `tools/list`, and
/// `tools/call`. Everything is forwarded to the local API through
/// [AutomationApiClient], so the app's own checks still apply.
///
/// Stdout carries protocol messages only. Diagnostics go to [log], which the
/// CLI wires to stderr.
library;

import 'dart:convert';

import 'automation_api_client.dart';

/// Protocol revision this server speaks.
const kMcpProtocolVersion = '2025-03-26';

const _errParse = -32700;
const _errInvalidRequest = -32600;
const _errMethodNotFound = -32601;
const _errInvalidParams = -32602;

class McpServer {
  McpServer({required this.client, this.serverVersion = '1', this.log});

  final AutomationApiClient client;
  final String serverVersion;

  /// Diagnostics sink. Never write to stdout from here.
  final void Function(String message)? log;

  /// Handles one incoming line. Returns the encoded response, or `null` when
  /// the message is a notification and gets no answer.
  Future<String?> handleLine(String line) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      return _encode(_error(null, _errParse, 'Parse error'));
    }
    if (decoded is! Map<String, dynamic>) {
      return _encode(_error(null, _errInvalidRequest, 'Invalid request'));
    }

    final id = decoded['id'];
    final method = decoded['method'];
    if (decoded['jsonrpc'] != '2.0' || method is! String) {
      return _encode(_error(id, _errInvalidRequest, 'Invalid request'));
    }

    final isNotification = !decoded.containsKey('id');
    final params = decoded['params'];

    final Map<String, Object?>? response;
    switch (method) {
      case 'initialize':
        response = _result(id, {
          'protocolVersion': kMcpProtocolVersion,
          'capabilities': {'tools': <String, Object?>{}},
          'serverInfo': {'name': 'whispaste', 'version': serverVersion},
        });
      case 'notifications/initialized':
        response = null;
      case 'ping':
        response = _result(id, <String, Object?>{});
      case 'tools/list':
        response = _result(id, {'tools': _toolDefinitions});
      case 'tools/call':
        response = await _toolsCall(id, params);
      default:
        response = isNotification
            ? null
            : _error(id, _errMethodNotFound, 'Method not found');
    }

    if (isNotification || response == null) return null;
    return _encode(response);
  }

  /// Reads newline-delimited messages from [lines] and writes each answer
  /// with [write]. Blank lines are skipped.
  Future<void> serve(
    Stream<String> lines,
    void Function(String encoded) write,
  ) async {
    await for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final answer = await handleLine(line);
      if (answer != null) write(answer);
    }
  }

  Future<Map<String, Object?>> _toolsCall(Object? id, Object? params) async {
    if (params is! Map<String, dynamic> || params['name'] is! String) {
      return _error(id, _errInvalidParams, 'Missing tool name');
    }
    final name = params['name']! as String;
    final rawArgs = params['arguments'];
    if (rawArgs != null && rawArgs is! Map<String, dynamic>) {
      return _error(id, _errInvalidParams, 'arguments must be an object');
    }
    final args = (rawArgs as Map<String, dynamic>?) ?? const {};

    final tool = _tools[name];
    if (tool == null) {
      return _error(id, _errInvalidParams, 'Unknown tool: $name');
    }

    try {
      final data = await tool(args);
      return _result(id, _toolResult(jsonEncode(data), isError: false));
    } on _InvalidArguments catch (e) {
      return _error(id, _errInvalidParams, e.message);
    } on AutomationApiException catch (e) {
      log?.call('tool $name failed: ${e.error} (${e.statusCode})');
      return _result(
        id,
        _toolResult(
          'The automation API answered with "${e.error}" '
          '(HTTP ${e.statusCode}).',
          isError: true,
        ),
      );
    }
  }

  late final Map<
    String,
    Future<Map<String, Object?>> Function(Map<String, dynamic>)
  >
  _tools = {
    'notes_list': (args) =>
        client.listNotes(limit: _optionalInt(args, 'limit', min: 1, max: 200)),
    'notes_create': (args) =>
        client.createNote(_requiredString(args, 'content')),
    'snippets_list': (_) => client.listSnippets(),
    'snippets_render': (args) => client.renderSnippet(
      _requiredString(args, 'name'),
      _stringMap(args['values']),
    ),
    'last_dictation': (_) => client.latestDictation(),
    'trigger_dictation': (args) => client.triggerDictation(
      wait: _optionalBool(args, 'wait'),
      language: _optionalLanguage(args),
    ),
  };

  static final List<Map<String, Object?>> _toolDefinitions = [
    {
      'name': 'notes_list',
      'description': 'List notes, newest and pinned first.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'limit': {'type': 'integer', 'minimum': 1, 'maximum': 200},
        },
        'additionalProperties': false,
      },
    },
    {
      'name': 'notes_create',
      'description': 'Create a note with the given text.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'content': {'type': 'string', 'minLength': 1},
        },
        'required': ['content'],
        'additionalProperties': false,
      },
    },
    {
      'name': 'snippets_list',
      'description': 'List snippets by title with their kind and fields.',
      'inputSchema': {
        'type': 'object',
        'properties': <String, Object?>{},
        'additionalProperties': false,
      },
    },
    {
      'name': 'snippets_render',
      'description':
          'Render a snippet with field values and return the text. Nothing is '
          'pasted.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'name': {'type': 'string', 'minLength': 1},
          'values': {
            'type': 'object',
            'additionalProperties': {'type': 'string'},
          },
        },
        'required': ['name'],
        'additionalProperties': false,
      },
    },
    {
      'name': 'last_dictation',
      'description': 'Return the most recent dictation from history.',
      'inputSchema': {
        'type': 'object',
        'properties': <String, Object?>{},
        'additionalProperties': false,
      },
    },
    {
      'name': 'trigger_dictation',
      'description':
          'Start a dictation in the app, as the hotkey would. With wait set, '
          'the call returns the transcript once recording has finished.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'wait': {'type': 'boolean'},
          'language': {
            'type': 'string',
            'description':
                'ISO 639-1 code such as "en", or "auto". Overrides the '
                'configured language for this recording only.',
          },
        },
        'additionalProperties': false,
      },
    },
  ];

  static Map<String, Object?> _toolResult(
    String text, {
    required bool isError,
  }) => {
    'content': [
      {'type': 'text', 'text': text},
    ],
    'isError': isError,
  };

  static Map<String, Object?> _result(
    Object? id,
    Map<String, Object?> result,
  ) => {'jsonrpc': '2.0', 'id': id, 'result': result};

  static Map<String, Object?> _error(Object? id, int code, String message) => {
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  };

  static String _encode(Map<String, Object?> message) => jsonEncode(message);
}

class _InvalidArguments implements Exception {
  const _InvalidArguments(this.message);
  final String message;
}

String _requiredString(Map<String, dynamic> args, String key) {
  final value = args[key];
  if (value is! String || value.trim().isEmpty) {
    throw _InvalidArguments('$key must be a non-empty string');
  }
  return value;
}

int? _optionalInt(
  Map<String, dynamic> args,
  String key, {
  required int min,
  required int max,
}) {
  final value = args[key];
  if (value == null) return null;
  if (value is! int || value < min || value > max) {
    throw _InvalidArguments('$key must be an integer from $min to $max');
  }
  return value;
}

String? _optionalLanguage(Map<String, dynamic> args) {
  final value = args['language'];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw const _InvalidArguments('language must be a non-empty string');
  }
  return value;
}

bool _optionalBool(Map<String, dynamic> args, String key) {
  final value = args[key];
  if (value == null) return false;
  if (value is! bool) throw _InvalidArguments('$key must be a boolean');
  return value;
}

Map<String, String> _stringMap(Object? value) {
  if (value == null) return const {};
  if (value is! Map) throw const _InvalidArguments('values must be an object');
  final out = <String, String>{};
  for (final entry in value.entries) {
    final v = entry.value;
    if (v is! String) {
      throw const _InvalidArguments('every value must be a string');
    }
    out[entry.key.toString()] = v;
  }
  return out;
}
