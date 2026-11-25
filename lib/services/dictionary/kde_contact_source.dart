/// Names from the KDE address book (#2041, part of #161): the contact
/// resources of Akonadi, which KAddressBook, Kontact and KMail keep, read as
/// a [SystemContactSource].
///
/// The way in: Akonadi on the session bus (`org.freedesktop.Akonadi.Control`,
/// running or activatable) says that KDE's address book is there; its agent
/// list (`akonadi/agentsrc`) names the resources, and each resource's own
/// settings (`<id>rc`) the place where it keeps its vCards. Read are the
/// resources that store their contacts as vCard files: the personal contacts
/// (`akonadi_contacts_resource`, one file per contact in a folder tree), a
/// vCard folder (`akonadi_vcarddir_resource`) and a vCard file
/// (`akonadi_vcard_resource`). Only FN, N and ORG survive
/// [decodeSystemVCards]; a name field that looks like an e-mail address or a
/// phone number is dropped.
///
/// Not read: online address books (CardDAV, Google, Exchange). Akonadi keeps
/// them only in its own database, reachable through its private binary
/// protocol, which changes with Akonadi versions; they reach the dictionary
/// through a vCard export. Nothing here calls Akonadi itself, so reading
/// never starts the Akonadi server and its database.
///
/// All or nothing: when one resource's folder or file is missing or cannot
/// be read, the whole read fails, so an update never removes the names of a
/// resource that was only unreachable this time (an unmounted drive).
///
/// Read only from the contact page, never on the hotkey path; nothing runs
/// in the background, the page compares when it opens.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dbus/dbus.dart';

import '../../core/logging/app_logger.dart';
import 'contact_names.dart';

final _log = AppLogger('KdeContactSource');

/// The `ContactNameGroups.sourceKind` of the KDE address book. One group of
/// this kind at most: a later read updates it.
const String kKdeContactsKind = 'kde';

/// Akonadi's control process on the session bus.
const String kAkonadiControlService = 'org.freedesktop.Akonadi.Control';

/// Largest vCard file read; a contact with a big photo stays well below.
const int kAkonadiMaxFileBytes = 32 * 1024 * 1024;

/// Whether Akonadi is on the bus [names] (also with an instance suffix,
/// `org.freedesktop.Akonadi.Control.<instance>`).
bool akonadiOnBus(Iterable<String> names) => names.any(
  (n) =>
      n == kAkonadiControlService || n.startsWith('$kAkonadiControlService.'),
);

/// The groups and keys of a KConfig file (`agentsrc`, `<resource>rc`).
/// Nested group headers (`[Instances][akonadi_contacts_resource_0]`) keep
/// their inner text (`Instances][akonadi_contacts_resource_0`). Keys with
/// the `[$e]` flag have `$VAR`, `${VAR}` and a leading `~` expanded from
/// [environment]; values with a shell command (`$(…)`) are dropped, never
/// run. Localized keys (`Name[de]`) are skipped. Escapes (`\s`, `\t`, `\n`,
/// `\r`, `\\`, `\xNN`) are decoded.
Map<String, Map<String, String>> parseKConfig(
  String data, {
  Map<String, String> environment = const {},
}) {
  final out = <String, Map<String, String>>{};
  var section = out.putIfAbsent('', () => <String, String>{});
  for (final raw in const LineSplitter().convert(data)) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (line.startsWith('[') && line.endsWith(']')) {
      section = out.putIfAbsent(
        line.substring(1, line.length - 1),
        () => <String, String>{},
      );
      continue;
    }
    final eq = line.indexOf('=');
    if (eq <= 0) continue;
    var key = line.substring(0, eq).trim();
    var expand = false;
    final bracket = key.indexOf('[');
    if (bracket >= 0) {
      final flags = key.substring(bracket);
      if (!flags.startsWith(r'[$')) continue;
      expand = flags.contains('e');
      key = key.substring(0, bracket).trim();
    }
    var value = _kconfigUnescape(line.substring(eq + 1).trim());
    if (expand) {
      final expanded = _expand(value, environment);
      if (expanded == null) continue;
      value = expanded;
    }
    section[key] = value;
  }
  return out;
}

String _kconfigUnescape(String value) {
  if (!value.contains(r'\')) return value;
  final buf = StringBuffer();
  for (var i = 0; i < value.length; i++) {
    final c = value[i];
    if (c != r'\' || i + 1 >= value.length) {
      buf.write(c);
      continue;
    }
    final next = value[++i];
    switch (next) {
      case 's':
        buf.write(' ');
      case 't':
        buf.write('\t');
      case 'n':
        buf.write('\n');
      case 'r':
        buf.write('\r');
      case 'x' when i + 2 < value.length:
        final code = int.tryParse(value.substring(i + 1, i + 3), radix: 16);
        if (code == null) {
          buf.write(next);
        } else {
          buf.writeCharCode(code);
          i += 2;
        }
      default:
        buf.write(next);
    }
  }
  return buf.toString();
}

/// [value] with environment variables expanded, `null` for a shell command.
String? _expand(String value, Map<String, String> environment) {
  if (value.contains(r'$(')) return null;
  var out = value.replaceAllMapped(
    RegExp(r'\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)'),
    (m) => environment[m[1] ?? m[2]!] ?? '',
  );
  if (out == '~' || out.startsWith('~/')) {
    out = '${environment['HOME'] ?? ''}${out.substring(1)}';
  }
  return out;
}

/// Where an Akonadi resource keeps its vCards.
enum AkonadiStore {
  /// A folder tree of vCard files.
  folder,

  /// One vCard file.
  file,
}

/// One Akonadi contact resource that stores vCards locally.
typedef AkonadiContactResource = ({String id, AkonadiStore store, String path});

const _agentTypes = {
  'akonadi_contacts_resource': AkonadiStore.folder,
  'akonadi_vcarddir_resource': AkonadiStore.folder,
  'akonadi_vcard_resource': AkonadiStore.file,
};

/// The Akonadi agents in [agentsrc] that keep vCards locally, by id (sorted)
/// with their type. Other agents (mail, calendar, online address books) are
/// left out, and so are ids that are no plain file name.
List<({String id, String type})> akonadiContactAgents(String agentsrc) {
  const prefix = 'Instances][';
  final out = <({String id, String type})>[];
  for (final MapEntry(key: group, value: keys) in parseKConfig(
    agentsrc,
  ).entries) {
    if (!group.startsWith(prefix)) continue;
    final id = group.substring(prefix.length);
    if (!RegExp(r'^[A-Za-z0-9_-][A-Za-z0-9_.-]*$').hasMatch(id)) continue;
    final type = keys['AgentType'] ?? '';
    if (_agentTypes.containsKey(type)) out.add((id: id, type: type));
  }
  out.sort((a, b) => a.id.compareTo(b.id));
  return out;
}

/// The local contact resources among the Akonadi agents of [agentsrc],
/// sorted by id: [settingsOf] gives a resource's settings file (`null` when
/// it has none), [dataHome] is `$XDG_DATA_HOME`, where the personal contacts
/// live unless their settings name another folder. A vCard folder or file
/// without a configured place and online places (`https://…`) are left out.
List<AkonadiContactResource> akonadiContactResources(
  String agentsrc, {
  required String? Function(String id) settingsOf,
  required String dataHome,
  Map<String, String> environment = const {},
}) {
  final out = <AkonadiContactResource>[];
  for (final (:id, :type) in akonadiContactAgents(agentsrc)) {
    final settings = settingsOf(id);
    final configured = settings == null
        ? null
        : parseKConfig(settings, environment: environment)['General']?['Path'];
    var path = configured?.trim() ?? '';
    if (path.isEmpty && type == 'akonadi_contacts_resource') {
      path = '$dataHome/contacts/';
    }
    final local = _localPath(path);
    if (local == null || local.isEmpty) continue;
    out.add((id: id, store: _agentTypes[type]!, path: local));
  }
  return out;
}

/// [path] as a local path: `file://` URLs decoded, other URLs `null`. A
/// scheme has two characters at least, so a drive letter (`C:\…`, the
/// Windows test hosts) stays a path.
String? _localPath(String path) {
  final scheme = RegExp(r'^([A-Za-z][A-Za-z0-9+.-]+):').firstMatch(path);
  if (scheme == null) return path;
  if (scheme[1]!.toLowerCase() != 'file') return null;
  try {
    // Akonadi runs on Linux: its places are POSIX paths on every host.
    return Uri.parse(path).toFilePath(windows: false);
  } on Object {
    return null;
  }
}

/// The KDE address book through the vCards of its Akonadi resources.
class KdeContactSource implements SystemContactSource {
  KdeContactSource({
    Map<String, String>? environment,
    Future<List<String>> Function()? busNames,
  }) : _environment = environment ?? Platform.environment,
       _busNames = busNames ?? _sessionBusNames;

  final Map<String, String> _environment;
  final Future<List<String>> Function() _busNames;

  @override
  String get kind => kKdeContactsKind;

  /// Stored with the group; the page shows its own localized name for this
  /// kind.
  @override
  String get label => 'KDE';

  bool get _sandboxed =>
      (_environment['FLATPAK_ID'] ?? '').isNotEmpty ||
      (_environment['SNAP'] ?? '').isNotEmpty;

  String get _home => _environment['HOME'] ?? '';

  String _xdg(String variable, String fallback) {
    final value = _environment[variable] ?? '';
    return value.startsWith('/') ? value : '$_home/$fallback';
  }

  String get _configHome => _xdg('XDG_CONFIG_HOME', '.config');

  String get _dataHome => _xdg('XDG_DATA_HOME', '.local/share');

  /// Akonadi's agent list: per instance under `akonadi/instance/<name>/`.
  String get _agentsrcPath {
    final instance = _environment['AKONADI_INSTANCE'] ?? '';
    return instance.isEmpty
        ? '$_configHome/akonadi/agentsrc'
        : '$_configHome/akonadi/instance/$instance/agentsrc';
  }

  /// The local contact resources; `null` without an agent list.
  Future<List<AkonadiContactResource>?> _resources() async {
    final agentsrc = await _readText(_agentsrcPath);
    if (agentsrc == null) return null;
    final settings = <String, String?>{};
    for (final (:id, type: _) in akonadiContactAgents(agentsrc)) {
      settings[id] = await _readText('$_configHome/${id}rc');
    }
    return akonadiContactResources(
      agentsrc,
      settingsOf: (id) => settings[id],
      dataHome: _dataHome,
      environment: _environment,
    );
  }

  /// Akonadi reads local vCard files: no access prompt and no privacy
  /// setting of its own.
  @override
  Future<bool> asksForAccess() async => false;

  @override
  Uri? get settingsUri => null;

  /// Flatpak and Snap reach neither the Akonadi settings nor its files (the
  /// manifests grant no home access). There the page explains the vCard
  /// export on KDE desktops and shows nothing elsewhere; outside a sandbox
  /// KDE's address book is offered when Akonadi is on the bus and has a
  /// resource with local vCards.
  @override
  Future<SystemContactsAvailability> availability() async {
    if (_sandboxed) {
      final desktop = (_environment['XDG_CURRENT_DESKTOP'] ?? '').toUpperCase();
      return desktop.contains('KDE')
          ? SystemContactsAvailability.sandboxed
          : SystemContactsAvailability.absent;
    }
    try {
      if (!akonadiOnBus(await _busNames())) {
        return SystemContactsAvailability.absent;
      }
      final resources = await _resources();
      return resources == null || resources.isEmpty
          ? SystemContactsAvailability.absent
          : SystemContactsAvailability.available;
    } on Object {
      return SystemContactsAvailability.absent;
    }
  }

  @override
  Future<List<ContactName>> read() async {
    if (_sandboxed) {
      throw const ContactSourceException(ContactSourceFailure.unavailable);
    }
    try {
      final resources = await _resources();
      if (resources == null || resources.isEmpty) {
        throw const ContactSourceException(ContactSourceFailure.unavailable);
      }
      final files = <File>[];
      for (final resource in resources) {
        files.addAll(await _vcardFiles(resource));
        if (files.length > kContactNamesMaxContacts) {
          throw const ContactSourceException(ContactSourceFailure.tooMany);
        }
      }
      final vcards = <String>[];
      for (final file in files) {
        if (await file.length() > kAkonadiMaxFileBytes) {
          throw const ContactSourceException(ContactSourceFailure.tooMany);
        }
        vcards.add(_decode(await file.readAsBytes()));
      }
      return decodeSystemVCards(vcards);
    } on ContactSourceException {
      rethrow;
    } on Object {
      throw const ContactSourceException(ContactSourceFailure.unavailable);
    }
  }
}

/// The vCard files of [resource]; throws when its place is missing.
Future<List<File>> _vcardFiles(AkonadiContactResource resource) async {
  switch (resource.store) {
    case AkonadiStore.file:
      final file = File(resource.path);
      if (!await file.exists()) {
        throw const ContactSourceException(ContactSourceFailure.unavailable);
      }
      return [file];
    case AkonadiStore.folder:
      final dir = Directory(resource.path);
      if (!await dir.exists()) {
        throw const ContactSourceException(ContactSourceFailure.unavailable);
      }
      final out = <File>[];
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final name = entity.path.toLowerCase();
        if (name.endsWith('.vcf') || name.endsWith('.vcard')) out.add(entity);
        if (out.length > kContactNamesMaxContacts) {
          throw const ContactSourceException(ContactSourceFailure.tooMany);
        }
      }
      out.sort((a, b) => a.path.compareTo(b.path));
      return out;
  }
}

/// A vCard file's text: UTF-8 (byte order mark dropped), Latin-1 when it is
/// no valid UTF-8 (old vCard 2.1 exports).
String _decode(List<int> bytes) {
  var start = 0;
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    start = 3;
  }
  final body = bytes.sublist(start);
  try {
    return utf8.decode(body);
  } on FormatException {
    return latin1.decode(body, allowInvalid: true);
  }
}

Future<String?> _readText(String path) async {
  final file = File(path);
  if (!await file.exists()) return null;
  return _decode(await file.readAsBytes());
}

Future<List<String>> _sessionBusNames() async {
  final client = DBusClient.session();
  try {
    return [
      ...await client.listNames(),
      ...await client.listActivatableNames(),
    ];
  } finally {
    try {
      await client.close();
    } on Object catch (e) {
      // Closing is best effort.
      _log.debug('Session bus not closed cleanly', e);
    }
  }
}
