/// Names from the GNOME contacts (#2040, part of #161): the address books
/// of Evolution Data Server (EDS), which GNOME Contacts and Evolution keep,
/// read over the session bus as a [SystemContactSource].
///
/// The way in: the source registry (`…dataserver.Sources<N>`, an
/// ObjectManager) lists the address books; the factory
/// (`…dataserver.AddressBook<N>`, `OpenAddressBook`) opens each enabled one,
/// and
/// `GetContactList` hands over its vCards. Only FN, N and ORG survive the
/// vCard parser of the foundation ([decodeSystemVCards]); a name field
/// that looks like an e-mail address or a phone number is dropped. Directory books (LDAP) are skipped: they are
/// company directories, not the user's contacts, and can be huge.
///
/// All or nothing: when one address book does not open or read, the whole
/// read fails, so an update never removes the names of a book that was only
/// unreachable this time. Remote books (Google, CardDAV) answer from the EDS
/// cache when offline.
///
/// Read only from the contact page, never on the hotkey path; nothing runs
/// in the background, the page compares when it opens.
library;

import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';

import '../../core/logging/app_logger.dart';
import 'contact_names.dart';

final _log = AppLogger('GnomeContactSource');

/// The `ContactNameGroups.sourceKind` of the GNOME contacts. One group of
/// this kind at most: a later read updates it.
const String kGnomeContactsKind = 'gnome';

/// EDS query that matches every contact (`e_book_query_any_field_contains`
/// with an empty text).
const String kEdsAllContactsQuery = '(contains "x-evolution-any-field" "")';

const _sourcesPrefix = 'org.gnome.evolution.dataserver.Sources';
const _addressBookPrefix = 'org.gnome.evolution.dataserver.AddressBook';

/// The EDS services on the bus: the source registry and the address book
/// factory, each in the highest interface version present (EDS appends the
/// API version to the bus name, `Sources5`, `AddressBook10`). `null` when
/// either is missing.
({String sources, String addressBook})? edsServiceNames(
  Iterable<String> names,
) {
  String? highest(String prefix) {
    String? best;
    var bestVersion = -1;
    for (final name in names) {
      if (!name.startsWith(prefix)) continue;
      final version = int.tryParse(name.substring(prefix.length));
      if (version == null || version <= bestVersion) continue;
      best = name;
      bestVersion = version;
    }
    return best;
  }

  final sources = highest(_sourcesPrefix);
  final addressBook = highest(_addressBookPrefix);
  if (sources == null || addressBook == null) return null;
  return (sources: sources, addressBook: addressBook);
}

/// The sections and keys of an EDS source description (GLib key file).
Map<String, Map<String, String>> parseEdsKeyFile(String data) {
  final out = <String, Map<String, String>>{};
  Map<String, String>? section;
  for (final raw in data.split('\n')) {
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
    if (section == null || eq <= 0) continue;
    section[line.substring(0, eq).trim()] = line.substring(eq + 1).trim();
  }
  return out;
}

/// The UIDs of the address books to read, sorted, from the source
/// descriptions by UID: sources with an `[Address Book]` section that are
/// enabled, whose parent (an account) is enabled and has contacts turned on,
/// and that are no directory (LDAP).
List<String> edsAddressBookUids(Map<String, String> dataByUid) {
  final parsed = {
    for (final e in dataByUid.entries) e.key: parseEdsKeyFile(e.value),
  };
  bool off(String? value) => value?.toLowerCase() == 'false';
  final out = <String>[];
  for (final MapEntry(key: uid, value: source) in parsed.entries) {
    final book = source['Address Book'];
    if (book == null) continue;
    if ((book['BackendName'] ?? '').toLowerCase() == 'ldap') continue;
    final data = source['Data Source'] ?? const <String, String>{};
    if (off(data['Enabled'])) continue;
    final parent = parsed[data['Parent']];
    if (parent != null) {
      if (off(parent['Data Source']?['Enabled'])) continue;
      if (off(parent['Collection']?['ContactsEnabled'])) continue;
    }
    out.add(uid);
  }
  return out..sort();
}

/// The session bus as far as the GNOME source needs it; replaced in tests.
abstract interface class EdsBus {
  /// Names on the bus, running and activatable.
  Future<List<String>> names();

  /// The source descriptions (key files) of the registry [service], by UID.
  Future<Map<String, String>> sources(String service);

  /// Opens the address book [uid] through the factory [service].
  Future<EdsAddressBook> open(String service, String uid);

  Future<void> close();
}

/// One open EDS address book.
abstract interface class EdsAddressBook {
  /// UIDs of all contacts: counts them before any vCard is fetched.
  Future<List<String>> uids();

  /// The vCards of all contacts.
  Future<List<String>> vcards();

  Future<void> close();
}

/// The GNOME contacts through Evolution Data Server.
class GnomeContactSource implements SystemContactSource {
  GnomeContactSource({
    Map<String, String>? environment,
    EdsBus Function()? connect,
  }) : _environment = environment ?? Platform.environment,
       _connect = connect ?? DBusEdsBus.new;

  final Map<String, String> _environment;
  final EdsBus Function() _connect;

  @override
  String get kind => kGnomeContactsKind;

  /// Stored with the group; the page shows its own localized name for this
  /// kind.
  @override
  String get label => 'GNOME';

  bool get _sandboxed =>
      (_environment['FLATPAK_ID'] ?? '').isNotEmpty ||
      (_environment['SNAP'] ?? '').isNotEmpty;

  /// EDS has no access prompt and no privacy setting of its own.
  @override
  Future<bool> asksForAccess() async => false;

  @override
  Uri? get settingsUri => null;

  /// Flatpak and Snap get no access to EDS (the manifests grant no bus name
  /// for it; the whole contacts and calendar store would be reachable). There
  /// the page explains the vCard export on GNOME desktops and shows nothing
  /// elsewhere; outside a sandbox the EDS services on the bus decide.
  @override
  Future<SystemContactsAvailability> availability() async {
    if (_sandboxed) {
      final desktop = (_environment['XDG_CURRENT_DESKTOP'] ?? '').toUpperCase();
      return desktop.contains('GNOME')
          ? SystemContactsAvailability.sandboxed
          : SystemContactsAvailability.absent;
    }
    final bus = _connect();
    try {
      return edsServiceNames(await bus.names()) == null
          ? SystemContactsAvailability.absent
          : SystemContactsAvailability.available;
    } on Object {
      return SystemContactsAvailability.absent;
    } finally {
      await _quietly(bus.close);
    }
  }

  @override
  Future<List<ContactName>> read() async {
    if (_sandboxed) {
      throw const ContactSourceException(ContactSourceFailure.unavailable);
    }
    final bus = _connect();
    try {
      final services = edsServiceNames(await bus.names());
      if (services == null) {
        throw const ContactSourceException(ContactSourceFailure.unavailable);
      }
      final books = edsAddressBookUids(await bus.sources(services.sources));
      final vcards = <String>[];
      var count = 0;
      for (final uid in books) {
        final book = await bus.open(services.addressBook, uid);
        try {
          count += (await book.uids()).length;
          if (count > kContactNamesMaxContacts) {
            throw const ContactSourceException(ContactSourceFailure.tooMany);
          }
          vcards.addAll(await book.vcards());
        } finally {
          await _quietly(book.close);
        }
      }
      return decodeSystemVCards(vcards);
    } on ContactSourceException {
      rethrow;
    } on Object {
      throw const ContactSourceException(ContactSourceFailure.unavailable);
    } finally {
      await _quietly(bus.close);
    }
  }
}

Future<void> _quietly(Future<void> Function() close) async {
  try {
    await close();
  } on Object catch (e) {
    // Closing is best effort: the bus drops what a closed connection held.
    _log.debug('Session bus not closed cleanly', e);
  }
}

/// [EdsBus] on the session bus.
class DBusEdsBus implements EdsBus {
  DBusEdsBus({DBusClient? client}) : _client = client ?? DBusClient.session();

  final DBusClient _client;

  /// Opening a remote book can wait for the network; a book that takes
  /// longer fails the read instead of holding the page.
  static const _timeout = Duration(seconds: 30);

  static const _registryPath = '/org/gnome/evolution/dataserver/SourceManager';
  static const _factoryPath =
      '/org/gnome/evolution/dataserver/AddressBookFactory';
  static const _sourceInterface = 'org.gnome.evolution.dataserver.Source';
  static const _factoryInterface =
      'org.gnome.evolution.dataserver.AddressBookFactory';

  @override
  Future<List<String>> names() async => [
    ...await _client.listNames(),
    ...await _client.listActivatableNames(),
  ];

  @override
  Future<Map<String, String>> sources(String service) async {
    final registry = DBusRemoteObjectManager(
      _client,
      name: service,
      path: DBusObjectPath(_registryPath),
    );
    final objects = await registry.getManagedObjects().timeout(_timeout);
    final out = <String, String>{};
    for (final interfaces in objects.values) {
      final properties = interfaces[_sourceInterface];
      final uid = properties?['UID'];
      final data = properties?['Data'];
      if (uid is DBusString && data is DBusString) out[uid.value] = data.value;
    }
    return out;
  }

  @override
  Future<EdsAddressBook> open(String service, String uid) async {
    final factory = DBusRemoteObject(
      _client,
      name: service,
      path: DBusObjectPath(_factoryPath),
    );
    final reply = await factory
        .callMethod(_factoryInterface, 'OpenAddressBook', [
          DBusString(uid),
        ], replySignature: DBusSignature('ss'))
        .timeout(_timeout);
    final book = _DBusEdsAddressBook(
      DBusRemoteObject(
        _client,
        name: reply.values[1].asString(),
        path: DBusObjectPath(reply.values[0].asString()),
      ),
    );
    await book.call('Open', replySignature: DBusSignature('as'));
    return book;
  }

  @override
  Future<void> close() => _client.close();
}

class _DBusEdsAddressBook implements EdsAddressBook {
  _DBusEdsAddressBook(this._object);

  final DBusRemoteObject _object;

  static const _interface = 'org.gnome.evolution.dataserver.AddressBook';

  Future<DBusMethodSuccessResponse> call(
    String method, {
    List<DBusValue> values = const [],
    DBusSignature? replySignature,
  }) => _object
      .callMethod(_interface, method, values, replySignature: replySignature)
      .timeout(DBusEdsBus._timeout);

  Future<List<String>> _strings(String method) async => (await call(
    method,
    values: const [DBusString(kEdsAllContactsQuery)],
    replySignature: DBusSignature('as'),
  )).values.single.asStringArray().toList();

  @override
  Future<List<String>> uids() => _strings('GetContactListUids');

  @override
  Future<List<String>> vcards() => _strings('GetContactList');

  @override
  Future<void> close() async {
    await call('Close', replySignature: DBusSignature(''));
  }
}
