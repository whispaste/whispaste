/// Names from the GNOME contacts (#2040): which Evolution Data Server
/// services and address books are read, what crosses into the contact
/// names, the failures, and the way into the import group (update on open,
/// withdrawal).
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/services/dictionary/contact_names.dart';
import 'package:whispaste/services/dictionary/gnome_contact_source.dart';

const _sources = 'org.gnome.evolution.dataserver.Sources5';
const _books = 'org.gnome.evolution.dataserver.AddressBook10';

String _card(String fn, {String n = '', String org = '', String extra = ''}) =>
    [
      'BEGIN:VCARD',
      'VERSION:3.0',
      'UID:${fn.hashCode}',
      if (fn.isNotEmpty) 'FN:$fn',
      if (n.isNotEmpty) 'N:$n',
      if (org.isNotEmpty) 'ORG:$org',
      'EMAIL;TYPE=WORK:lea@example.org',
      'TEL;TYPE=CELL:+49 30 123456',
      'ADR;TYPE=HOME:;;Hauptstraße 1;Berlin;;10115;Germany',
      if (extra.isNotEmpty) extra,
      'END:VCARD',
    ].join('\r\n');

const _personal =
    '[Data Source]\nDisplayName=Personal\nEnabled=true\nParent=local-stub\n\n'
    '[Address Book]\nBackendName=local\n';

class _FakeBook implements EdsAddressBook {
  _FakeBook(this.cards, {this.fail = false});
  final List<String> cards;
  final bool fail;
  bool closed = false;
  int vcardCalls = 0;

  @override
  Future<List<String>> uids() async {
    if (fail) throw StateError('offline');
    return [for (var i = 0; i < cards.length; i++) '$i'];
  }

  @override
  Future<List<String>> vcards() async {
    vcardCalls++;
    return cards;
  }

  @override
  Future<void> close() async => closed = true;
}

class _FakeBus implements EdsBus {
  _FakeBus({
    this.busNames = const [_sources, _books],
    Map<String, String>? sources,
    Map<String, _FakeBook>? books,
  }) : sourceData = sources ?? {'system-address-book': _personal},
       books = books ?? {};

  final List<String> busNames;
  final Map<String, String> sourceData;
  final Map<String, _FakeBook> books;
  final opened = <(String, String)>[];
  String? sourcesAsked;
  bool closed = false;

  @override
  Future<List<String>> names() async => busNames;

  @override
  Future<Map<String, String>> sources(String service) async {
    sourcesAsked = service;
    return sourceData;
  }

  @override
  Future<EdsAddressBook> open(String service, String uid) async {
    opened.add((service, uid));
    final book = books[uid];
    if (book == null) throw StateError('no book $uid');
    return book;
  }

  @override
  Future<void> close() async => closed = true;
}

Matcher _fails(ContactSourceFailure reason) => throwsA(
  isA<ContactSourceException>().having((e) => e.reason, 'reason', reason),
);

GnomeContactSource _source(
  _FakeBus bus, {
  Map<String, String> env = const {'XDG_CURRENT_DESKTOP': 'ubuntu:GNOME'},
}) => GnomeContactSource(environment: env, connect: () => bus);

void main() {
  group('edsServiceNames', () {
    test('picks the highest version of registry and factory', () {
      expect(
        edsServiceNames([
          'org.freedesktop.DBus',
          'org.gnome.evolution.dataserver.Sources4',
          _sources,
          'org.gnome.evolution.dataserver.AddressBook9',
          _books,
          'org.gnome.evolution.dataserver.Calendar8',
          'org.gnome.evolution.dataserver.AddressBookX',
        ]),
        (sources: _sources, addressBook: _books),
      );
    });

    test('is null without registry or factory', () {
      expect(edsServiceNames([_sources]), isNull);
      expect(edsServiceNames([_books]), isNull);
      expect(edsServiceNames(const []), isNull);
    });
  });

  group('edsAddressBookUids', () {
    test('reads enabled address books, skips calendars, LDAP directories, '
        'disabled books and books of disabled accounts', () {
      expect(
        edsAddressBookUids({
          'system-address-book': _personal,
          'local-stub': '[Data Source]\nDisplayName=On This Computer\n',
          'birthdays': '[Data Source]\nEnabled=true\n\n[Calendar]\n',
          'ldap-company': '[Data Source]\n[Address Book]\nBackendName=ldap\n',
          'off': '[Data Source]\nEnabled=false\n[Address Book]\n',
          'goa-account':
              '[Data Source]\nEnabled=true\n[Collection]\n'
              'ContactsEnabled=true\n',
          'goa-contacts':
              '[Data Source]\nParent=goa-account\n'
              '[Address Book]\nBackendName=carddav\n',
          'old-account': '[Data Source]\nEnabled=false\n[Collection]\n',
          'old-contacts': '[Data Source]\nParent=old-account\n[Address Book]\n',
          'no-contacts-account':
              '[Data Source]\n[Collection]\nContactsEnabled=false\n',
          'no-contacts-book':
              '[Data Source]\nParent=no-contacts-account\n[Address Book]\n',
        }),
        ['goa-contacts', 'system-address-book'],
      );
    });
  });

  group('GnomeContactSource.read', () {
    test('hands over names and companies of every book, nothing else, and '
        'closes what it opened', () async {
      final personal = _FakeBook([
        _card('Lea Maria Wolf', n: 'Wolf;Lea Maria;;;', org: 'Nordwind GmbH'),
        _card('', n: 'Berg;Ida;;;'),
      ]);
      final google = _FakeBook([
        _card('lea@example.org', org: 'Südlicht AG'),
        _card('+49 (30) 123-456'),
        _card('Tom Rau', extra: 'PHOTO;ENCODING=b;TYPE=JPEG:/9j/4AAQSkZJRg=='),
      ]);
      final bus = _FakeBus(
        sources: {
          'system-address-book': _personal,
          'google': '[Data Source]\n[Address Book]\nBackendName=carddav\n',
        },
        books: {'system-address-book': personal, 'google': google},
      );
      final source = _source(bus);
      expect(source.kind, kGnomeContactsKind);
      expect(await source.read(), const [
        ContactName(organization: 'Südlicht AG'),
        ContactName(full: 'Tom Rau'),
        ContactName(
          given: 'Lea Maria',
          family: 'Wolf',
          full: 'Lea Maria Wolf',
          organization: 'Nordwind GmbH',
        ),
        ContactName(given: 'Ida', family: 'Berg'),
      ]);
      expect(bus.sourcesAsked, _sources);
      expect(bus.opened, [(_books, 'google'), (_books, 'system-address-book')]);
      expect(personal.closed && google.closed && bus.closed, isTrue);
    });

    test('an empty address book is no failure', () async {
      final bus = _FakeBus(books: {'system-address-book': _FakeBook([])});
      expect(await _source(bus).read(), isEmpty);
    });

    test('too many contacts fail before any vCard is fetched', () async {
      final big = _FakeBook([
        for (var i = 0; i <= kContactNamesMaxContacts; i++) _card('P $i'),
      ]);
      final bus = _FakeBus(books: {'system-address-book': big});
      await expectLater(
        _source(bus).read(),
        _fails(ContactSourceFailure.tooMany),
      );
      expect(big.vcardCalls, 0);
      expect(big.closed && bus.closed, isTrue);
    });

    test('one book that does not read fails the whole read, so an update '
        'never drops the names of an unreachable book', () async {
      final bus = _FakeBus(
        sources: {
          'system-address-book': _personal,
          'google': '[Data Source]\n[Address Book]\n',
        },
        books: {
          'system-address-book': _FakeBook([_card('Lea Wolf')]),
          'google': _FakeBook([_card('Tom Rau')], fail: true),
        },
      );
      await expectLater(
        _source(bus).read(),
        _fails(ContactSourceFailure.unavailable),
      );
      expect(bus.closed, isTrue);
    });

    test('without EDS or inside a sandbox the read is unavailable', () async {
      await expectLater(
        _source(_FakeBus(busNames: const ['org.freedesktop.DBus'])).read(),
        _fails(ContactSourceFailure.unavailable),
      );
      final bus = _FakeBus();
      await expectLater(
        _source(bus, env: const {'FLATPAK_ID': 'de.whispaste.app'}).read(),
        _fails(ContactSourceFailure.unavailable),
      );
      expect(bus.opened, isEmpty);
    });
  });

  group('GnomeContactSource.availability', () {
    test('available with EDS on the bus, absent without', () async {
      expect(
        await _source(_FakeBus()).availability(),
        SystemContactsAvailability.available,
      );
      expect(
        await _source(_FakeBus(busNames: const [])).availability(),
        SystemContactsAvailability.absent,
      );
    });

    test('Flatpak and Snap explain the export on GNOME and stay silent '
        'elsewhere', () async {
      for (final env in const [
        {'FLATPAK_ID': 'de.whispaste.app', 'XDG_CURRENT_DESKTOP': 'GNOME'},
        {'SNAP': '/snap/whispaste/12', 'XDG_CURRENT_DESKTOP': 'ubuntu:GNOME'},
      ]) {
        expect(
          await _source(_FakeBus(), env: env).availability(),
          SystemContactsAvailability.sandboxed,
        );
      }
      expect(
        await _source(
          _FakeBus(),
          env: const {'FLATPAK_ID': 'x', 'XDG_CURRENT_DESKTOP': 'KDE'},
        ).availability(),
        SystemContactsAvailability.absent,
      );
    });
  });

  group('into the import group', () {
    late HistoryDatabase db;
    final t = DateTime(2026);

    setUp(() async {
      db = HistoryDatabase.forTesting(NativeDatabase.memory());
      await db.writeAppSettings({'replacementsSamplesSeeded': '1'});
    });
    tearDown(() => db.close());

    Future<List<ContactPlanEntry>> entries() async => [
      for (final r in await db.readAllReplacements())
        (
          id: r.row.id,
          triggers: r.triggers,
          replacement: r.row.replacement,
          importGroupId: r.row.importGroupId,
        ),
    ];

    Future<void> apply(List<ContactImportRow> rows) {
      final changes = contactImportChanges(rows, const {});
      return db.applyContactNameImport(
        groupId: 'gnome',
        sourceKind: kGnomeContactsKind,
        sourceLabel: _source(_FakeBus()).label,
        consentedAt: t,
        add: [for (final n in changes.add) (id: 'gnome-$n', name: n)],
        removeIds: changes.removeIds,
        now: t,
      );
    }

    test('first read, unchanged book on open, changed book on open, '
        'withdrawal', () async {
      var cards = [_card('Lea Wolf', org: 'Nordwind GmbH'), _card('Ida Berg')];
      Future<List<String>> candidates() async => contactNameCandidates(
        await _source(
          _FakeBus(books: {'system-address-book': _FakeBook(cards)}),
        ).read(),
      );

      final first = planContactImport(await candidates(), await entries());
      expect(
        first.map((r) => r.status),
        everyElement(ContactImportStatus.fresh),
      );
      await apply(first);
      expect(
        (await db.readContactNameGroups()).single.sourceKind,
        kGnomeContactsKind,
      );

      final same = planContactImport(
        await candidates(),
        await entries(),
        groupId: 'gnome',
      );
      expect(contactImportHasChanges(same), isFalse);

      cards = [_card('Lea Wolf', org: 'Nordwind GmbH'), _card('Tom Rau')];
      final changed = planContactImport(
        await candidates(),
        await entries(),
        groupId: 'gnome',
      );
      expect(
        {for (final r in changed) r.name: r.status},
        {
          'Lea Wolf': ContactImportStatus.kept,
          'Nordwind GmbH': ContactImportStatus.kept,
          'Tom Rau': ContactImportStatus.fresh,
          'Ida Berg': ContactImportStatus.dropped,
        },
      );
      await apply(changed);
      expect((await entries()).map((e) => e.replacement).toSet(), {
        'Lea Wolf',
        'Nordwind GmbH',
        'Tom Rau',
      });

      await db.deleteContactNameGroup('gnome');
      expect(await db.readContactNameGroups(), isEmpty);
      expect(await entries(), isEmpty);
    });
  });
}
