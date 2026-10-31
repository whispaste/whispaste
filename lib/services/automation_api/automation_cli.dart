/// Command-line front end for the local automation API (WP-38 / 8.2).
///
/// `tool/whispaste.dart` is a thin wrapper around [runAutomationCli]. The
/// CLI only talks to a running app over loopback. It never starts the app,
/// never reads the app's database, and never touches the keyboard.
///
/// The token comes from the `WHISPASTE_API_TOKEN` environment variable so it
/// does not end up in shell history or the process list.
library;

import 'dart:convert';
import 'dart:io';

import 'automation_api_client.dart';
import 'automation_api_port.dart';
import 'mcp_server.dart';

const _usage = '''
Usage: whispaste [--port N] <command>

Commands:
  status                          API version, dictation phase, history lock
  note create <text...>           Create a note
  note list [--limit N]           List notes (1-200, default 50)
  snippet list                    List snippets
  snippet render NAME [--field k=v]...
                                  Render a snippet with field values (no paste)
  transcribe FILE.wav             Transcribe a 16 kHz mono 16-bit WAV file
  mcp                             Run the MCP server on stdin/stdout

Environment:
  WHISPASTE_API_TOKEN   Bearer token from Settings > Automation (required)
  WHISPASTE_API_PORT    Port when --port is not given (default 8765)
''';

typedef AutomationClientFactory =
    AutomationApiClient Function({required String token, required int port});

/// Runs one CLI invocation and returns the process exit code.
///
/// Exit codes: `0` success, `1` the API or the app failed, `2` usage error.
Future<int> runAutomationCli(
  List<String> args, {
  required Map<String, String> environment,
  required StringSink out,
  required StringSink err,
  Stream<List<int>>? stdinStream,
  AutomationClientFactory? clientFactory,
  Future<List<int>> Function(String path)? readFile,
}) async {
  final parsed = _ParsedArgs.parse(args);
  if (parsed.error != null) {
    err.writeln('whispaste: ${parsed.error}');
    err.write(_usage);
    return 2;
  }
  if (parsed.positional.isEmpty || parsed.help) {
    out.write(_usage);
    return parsed.help ? 0 : 2;
  }

  final port = parsed.port ?? _portFromEnv(environment);
  if (port == null) {
    err.writeln(
      'whispaste: WHISPASTE_API_PORT must be a number from 1 to 65535',
    );
    return 2;
  }

  final token = environment['WHISPASTE_API_TOKEN']?.trim() ?? '';
  if (token.isEmpty) {
    err.writeln(
      'whispaste: set WHISPASTE_API_TOKEN to the token shown in '
      'Settings > Automation.',
    );
    return 2;
  }

  final make =
      clientFactory ??
      ({required String token, required int port}) =>
          AutomationApiClient(token: token, port: port);
  final client = make(token: token, port: port);

  try {
    return await _dispatch(
      parsed,
      client,
      out: out,
      err: err,
      stdinStream: stdinStream,
      readFile: readFile ?? _readFile,
    );
  } on AutomationApiException catch (e) {
    err.writeln(_describe(e, port));
    return 1;
  } on FileSystemException catch (e) {
    err.writeln('whispaste: cannot read ${e.path ?? 'the file'}');
    return 2;
  }
}

Future<int> _dispatch(
  _ParsedArgs parsed,
  AutomationApiClient client, {
  required StringSink out,
  required StringSink err,
  required Stream<List<int>>? stdinStream,
  required Future<List<int>> Function(String path) readFile,
}) async {
  switch (parsed.positional) {
    case ['status']:
      _printJson(out, await client.status());
    case ['note', 'create', ...final words] when words.isNotEmpty:
      _printJson(out, await client.createNote(words.join(' ')));
    case ['note', 'list']:
      _printJson(out, await client.listNotes(limit: parsed.limit));
    case ['snippet', 'list']:
      _printJson(out, await client.listSnippets());
    case ['snippet', 'render', final name]:
      final response = await client.renderSnippet(name, parsed.fields);
      out.writeln(response['text'] ?? '');
    case ['transcribe', final path]:
      final bytes = await readFile(path);
      final response = await client.transcribe(bytes);
      out.writeln(response['transcript'] ?? '');
    case ['mcp']:
      final server = McpServer(
        client: client,
        log: (message) => err.writeln('whispaste mcp: $message'),
      );
      final lines = (stdinStream ?? stdin)
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await server.serve(lines, (encoded) => out.writeln(encoded));
    default:
      err.writeln('whispaste: unknown command: ${parsed.positional.join(' ')}');
      err.write(_usage);
      return 2;
  }
  return 0;
}

String _describe(AutomationApiException e, int port) => switch (e.error) {
  'unreachable' =>
    'whispaste: no WhisPaste API answered on 127.0.0.1:$port. Is the app '
        'running with the automation API enabled?',
  'timeout' => 'whispaste: the API did not answer in time.',
  'busy' =>
    'whispaste: WhisPaste is busy with a dictation. Try again when the '
        'recording has finished.',
  'invalid_response' => 'whispaste: the API sent an unreadable answer.',
  _ when e.statusCode == 401 =>
    'whispaste: the token was rejected. Copy the current token from '
        'Settings > Automation.',
  _ => 'whispaste: ${e.error} (HTTP ${e.statusCode})',
};

void _printJson(StringSink out, Object? value) {
  out.writeln(const JsonEncoder.withIndent('  ').convert(value));
}

int? _portFromEnv(Map<String, String> environment) {
  final raw = environment['WHISPASTE_API_PORT'];
  if (raw == null || raw.isEmpty) return kAutomationApiDefaultPort;
  return _validPort(raw);
}

int? _validPort(String raw) {
  final value = int.tryParse(raw);
  if (value == null || value < 1 || value > 65535) return null;
  return value;
}

Future<List<int>> _readFile(String path) => File(path).readAsBytes();

class _ParsedArgs {
  _ParsedArgs();

  final List<String> positional = [];
  final Map<String, String> fields = {};
  int? port;
  int? limit;
  bool help = false;
  String? error;

  static _ParsedArgs parse(List<String> args) {
    final result = _ParsedArgs();
    var i = 0;
    String? takeValue(String flag) {
      if (i + 1 >= args.length) {
        result.error = '$flag needs a value';
        return null;
      }
      i += 1;
      return args[i];
    }

    while (i < args.length && result.error == null) {
      final arg = args[i];
      switch (arg) {
        case '-h' || '--help':
          result.help = true;
        case '--port':
          final value = takeValue('--port');
          if (value == null) break;
          result.port = _validPort(value);
          if (result.port == null) result.error = '--port must be 1-65535';
        case '--limit':
          final value = takeValue('--limit');
          if (value == null) break;
          final parsed = int.tryParse(value);
          if (parsed == null || parsed < 1 || parsed > 200) {
            result.error = '--limit must be 1-200';
          }
          result.limit = parsed;
        case '--field':
          final value = takeValue('--field');
          if (value == null) break;
          final eq = value.indexOf('=');
          if (eq <= 0) {
            result.error = '--field expects key=value';
          } else {
            result.fields[value.substring(0, eq)] = value.substring(eq + 1);
          }
        default:
          result.positional.add(arg);
      }
      i += 1;
    }
    return result;
  }
}
