/// Pure validation rules for automation hook URLs (WP-38 / 8.3).
///
/// Hooks are HTTP POSTs to URLs the user configures. Only loopback targets
/// are accepted: `127.0.0.0/8`, `::1`, and the hostname `localhost` (which
/// must resolve to loopback at send time). Everything else is rejected at
/// save time by [isLoopbackHookUrl] and again at send time by
/// [pinLoopbackHookTarget], which also pins the connection to the resolved
/// loopback address so a second DNS answer cannot move the request.
///
/// No Flutter and no logger imports: this file is shared with the CLI and
/// the MCP server, which run as plain Dart processes.
library;

import 'dart:convert';
import 'dart:io';

/// Strict dotted-quad IPv4 literal. Anything else with dots (`127.1`,
/// `0x7f.0.0.1`, `0177.0.0.1`) is treated as a hostname and rejected.
final RegExp _dottedQuad = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');

/// Save-time check: `true` only for an `http` URL whose host is a loopback
/// IPv4 literal, the IPv6 loopback literal `[::1]`, or the exact hostname
/// `localhost`. Userinfo, other schemes, and invalid ports are rejected.
bool isLoopbackHookUrl(String raw) {
  final uri = _tryParse(raw);
  if (uri == null) return false;
  return _isSyntacticallyAllowed(uri);
}

/// Send-time check. Returns the URI to connect to, or `null` when the target
/// is not loopback.
///
/// - A loopback IP literal is returned unchanged.
/// - `localhost` is resolved through [lookup]; every answer must be loopback.
///   The returned URI carries the first resolved IP literal as its host, so
///   the connection cannot be re-pointed by a later DNS answer.
/// - A lookup error counts as a rejection and is never thrown.
Future<Uri?> pinLoopbackHookTarget(
  Uri uri, {
  Future<List<InternetAddress>> Function(String host) lookup = _systemLookup,
}) async {
  if (!_isSyntacticallyAllowed(uri)) return null;

  final host = uri.host;
  if (_isIpLiteral(host)) {
    return isLoopbackAddressLiteral(host) ? uri : null;
  }

  final List<InternetAddress> answers;
  try {
    answers = await lookup(host);
  } on Object {
    return null;
  }
  if (answers.isEmpty) return null;
  if (!answers.every(_isLoopbackAddress)) return null;

  final first = answers.firstWhere(
    (a) => a.type == InternetAddressType.IPv4,
    orElse: () => answers.first,
  );
  return uri.replace(host: first.address);
}

/// Whether [host] is an IP literal (strict IPv4 dotted quad or any IPv6
/// literal) that is loopback.
bool isLoopbackAddressLiteral(String host) {
  if (_dottedQuad.hasMatch(host)) {
    final address = InternetAddress.tryParse(host);
    return address != null && _isLoopbackAddress(address);
  }
  if (host.contains(':')) {
    final address = InternetAddress.tryParse(host);
    return address != null && _isLoopbackAddress(address);
  }
  return false;
}

Future<List<InternetAddress>> _systemLookup(String host) =>
    InternetAddress.lookup(host);

Uri? _tryParse(String raw) {
  if (raw.isEmpty) return null;
  try {
    return Uri.parse(raw);
  } on FormatException {
    return null;
  }
}

bool _isSyntacticallyAllowed(Uri uri) {
  if (uri.scheme != 'http') return false;
  if (uri.hasAuthority && uri.userInfo.isNotEmpty) return false;
  if (uri.hasPort && (uri.port < 1 || uri.port > 65535)) return false;

  final host = uri.host;
  if (host.isEmpty) return false;
  if (_isIpLiteral(host)) return isLoopbackAddressLiteral(host);
  return host == 'localhost';
}

bool _isIpLiteral(String host) =>
    _dottedQuad.hasMatch(host) || host.contains(':');

/// Loopback means `127.0.0.0/8` for IPv4 and exactly `::1` for IPv6.
/// IPv4-mapped (`::ffff:127.0.0.1`) and IPv4-compatible forms are not
/// loopback under this rule, so they are rejected.
bool _isLoopbackAddress(InternetAddress address) {
  final raw = address.rawAddress;
  if (address.type == InternetAddressType.IPv4) {
    return raw.isNotEmpty && raw[0] == 127;
  }
  if (address.type == InternetAddressType.IPv6 && raw.length == 16) {
    for (var i = 0; i < 15; i++) {
      if (raw[i] != 0) return false;
    }
    return raw[15] == 1;
  }
  return false;
}

// ---------------------------------------------------------------------------
// Hook model, settings encoding and event payload
// ---------------------------------------------------------------------------

/// Events a hook can subscribe to. Adding one is an additive change to the
/// payload contract and needs a test in `automation_hook_model_test.dart`.
const kAutomationHookEvents = {'transcript.finished', 'note.changed'};

/// Upper bound on configured hooks, so a bad settings file cannot fan out
/// unbounded deliveries.
const kAutomationHookMaxCount = 8;

/// Settings key the hook list is stored under. Additive: a settings file
/// without it loads as "no hooks".
const kAutomationHooksSettingsKey = 'automation_hooks';

/// Wire identifier of the event payload.
const kAutomationEventSchema = 'whispaste.automation-event';

/// Wire version of the event payload. Bumped only for breaking changes.
const kAutomationEventVersion = 1;

enum AutomationHookValidation {
  ok,
  invalidUrl,
  noEvents,
  unknownEvent,
  tooMany,
}

/// One user-configured destination for automation events.
class AutomationHook {
  const AutomationHook({required this.url, required this.events});

  final String url;
  final Set<String> events;

  @override
  bool operator ==(Object other) =>
      other is AutomationHook &&
      url == other.url &&
      _sameEvents(events, other.events);

  @override
  int get hashCode => Object.hash(url, Object.hashAllUnordered(events));

  @override
  String toString() => 'AutomationHook($url, $events)';
}

bool _sameEvents(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

/// Save-time validation for one hook. Callers show the matching message.
AutomationHookValidation validateAutomationHook(
  String url,
  Set<String> events, {
  int existingCount = 0,
}) {
  if (existingCount >= kAutomationHookMaxCount) {
    return AutomationHookValidation.tooMany;
  }
  if (!isLoopbackHookUrl(url)) return AutomationHookValidation.invalidUrl;
  if (events.isEmpty) return AutomationHookValidation.noEvents;
  if (!events.every(kAutomationHookEvents.contains)) {
    return AutomationHookValidation.unknownEvent;
  }
  return AutomationHookValidation.ok;
}

/// Encodes hooks for the flat settings map.
String encodeAutomationHooks(List<AutomationHook> hooks) => jsonEncode([
  for (final hook in hooks)
    {'url': hook.url, 'events': hook.events.toList()..sort()},
]);

/// Decodes the settings value. Never throws: a corrupt value, or any entry
/// that fails [validateAutomationHook], is dropped. Send time repeats the
/// loopback check regardless.
List<AutomationHook> decodeAutomationHooks(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return const [];
  }
  if (decoded is! List) return const [];

  final hooks = <AutomationHook>[];
  for (final entry in decoded) {
    if (entry is! Map) continue;
    final url = entry['url'];
    final events = entry['events'];
    if (url is! String || events is! List) continue;
    final eventSet = {
      for (final e in events)
        if (e is String) e,
    };
    if (validateAutomationHook(url, eventSet, existingCount: hooks.length) !=
        AutomationHookValidation.ok) {
      continue;
    }
    hooks.add(AutomationHook(url: url, events: eventSet));
  }
  return hooks;
}

/// The versioned JSON body POSTed to a hook.
Map<String, Object?> buildAutomationEventPayload({
  required String event,
  required DateTime at,
  required Map<String, Object?> data,
}) => {
  'schema': kAutomationEventSchema,
  'version': kAutomationEventVersion,
  'event': event,
  'occurred_at': at.toUtc().toIso8601String(),
  'data': data,
};
