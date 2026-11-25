/// Names from the Windows contacts (#2038): the handover of the native
/// contact host (method channel `com.whispaste.system_contacts`) to the
/// contact names, its failures, and the way into the import plan and the
/// import group (update on open, withdrawal).
library;

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/services/dictionary/contact_names.dart';
import 'package:whispaste/services/dictionary/system_contact_source.dart';
import 'package:whispaste/services/dictionary/windows_contact_source.dart';

const _channel = MethodChannel('com.whispaste.system_contacts');

Map<String, Object?> _ok(List<List<String>> contacts) => {
  'status': 'ok',
  'packaged': true,
  'contacts': contacts,
};

Matcher _fails(ContactSourceFailure reason) => throwsA(
  isA<ContactSourceException>().having((e) => e.reason, 'reason', reason),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('decodeSystemContactsReply', () {
    test('hands over given, family, full name and company', () {
      final contacts = decodeSystemContactsReply(
        _ok([
          ['Lea Maria', 'Wolf', 'Lea Maria Wolf', 'Nordwind GmbH'],
          ['Ida', 'Berg', '', ''],
        ]),
      );
      expect(contacts, const [
        ContactName(
          given: 'Lea Maria',
          family: 'Wolf',
          full: 'Lea Maria Wolf',
          organization: 'Nordwind GmbH',
        ),
        ContactName(given: 'Ida', family: 'Berg'),
      ]);
    });

    test('drops e-mail addresses and phone numbers in name fields and '
        'contacts without any name', () {
      final contacts = decodeSystemContactsReply(
        _ok([
          ['', '', 'lea@example.org', 'Nordwind GmbH'],
          ['', '', '+49 (30) 123-456', ''],
          ['', '', '', ''],
          ['Max', '', '', 'max@firma.de'],
        ]),
      );
      expect(contacts, const [
        ContactName(organization: 'Nordwind GmbH'),
        ContactName(given: 'Max'),
      ]);
      expect(contactNameCandidates(contacts), ['Nordwind GmbH', 'Max']);
    });

    test('ignores malformed entries and missing fields', () {
      final contacts = decodeSystemContactsReply({
        'status': 'ok',
        'packaged': true,
        'contacts': [
          'not a list',
          ['Ida', 'Berg'],
          [1, 2, 'Lea Wolf', null],
        ],
      });
      expect(contacts, const [
        ContactName(given: 'Ida', family: 'Berg'),
        ContactName(full: 'Lea Wolf'),
      ]);
    });

    test('an empty store is no failure', () {
      expect(decodeSystemContactsReply(_ok([])), isEmpty);
    });

    test('maps the failures to what the user can do', () {
      expect(
        () => decodeSystemContactsReply({'status': 'denied', 'packaged': true}),
        _fails(ContactSourceFailure.denied),
      );
      expect(
        () => decodeSystemContactsReply({
          'status': 'unavailable',
          'packaged': true,
        }),
        _fails(ContactSourceFailure.unavailable),
      );
      // Without package identity (NSIS, ZIP) any refusal is that limit.
      for (final status in ['denied', 'unavailable']) {
        expect(
          () =>
              decodeSystemContactsReply({'status': status, 'packaged': false}),
          _fails(ContactSourceFailure.unpackaged),
        );
      }
      expect(
        () =>
            decodeSystemContactsReply({'status': 'tooMany', 'packaged': false}),
        _fails(ContactSourceFailure.tooMany),
      );
      expect(
        () => decodeSystemContactsReply(null),
        _fails(ContactSourceFailure.unavailable),
      );
      expect(
        () => decodeSystemContactsReply({'status': 'ok', 'packaged': true}),
        _fails(ContactSourceFailure.unavailable),
      );
      expect(
        () => decodeSystemContactsReply(
          _ok([
            for (var i = 0; i <= kContactNamesMaxContacts; i++) ['A$i', '', ''],
          ]),
        ),
        _fails(ContactSourceFailure.tooMany),
      );
    });
  });

  group('WindowsContactSource', () {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

    test('asks the host for the contacts with the limit', () async {
      MethodCall? call;
      messenger.setMockMethodCallHandler(_channel, (c) async {
        call = c;
        return _ok([
          ['Lea', 'Wolf', 'Lea Wolf', ''],
        ]);
      });
      const source = WindowsContactSource();
      expect(source.kind, kWindowsContactsKind);
      expect(await source.read(), const [
        ContactName(given: 'Lea', family: 'Wolf', full: 'Lea Wolf'),
      ]);
      expect(call?.method, 'read');
      expect(call?.arguments, {'limit': kContactNamesMaxContacts});
    });

    test('a failing or missing host is unavailable', () async {
      messenger.setMockMethodCallHandler(
        _channel,
        (_) async => throw PlatformException(code: 'boom'),
      );
      await expectLater(
        const WindowsContactSource().read(),
        _fails(ContactSourceFailure.unavailable),
      );
      messenger.setMockMethodCallHandler(_channel, null);
      await expectLater(
        const WindowsContactSource().read(),
        _fails(ContactSourceFailure.unavailable),
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
        groupId: 'win',
        sourceKind: kWindowsContactsKind,
        sourceLabel: const WindowsContactSource().label,
        consentedAt: t,
        add: [for (final n in changes.add) (id: 'win-$n', name: n)],
        removeIds: changes.removeIds,
        now: t,
      );
    }

    test('first read, unchanged store on open, changed store on open, '
        'withdrawal', () async {
      var store = _ok([
        ['Lea', 'Wolf', 'Lea Wolf', 'Nordwind GmbH'],
        ['Ida', 'Berg', 'Ida Berg', ''],
      ]);
      List<String> candidates() =>
          contactNameCandidates(decodeSystemContactsReply(store));

      // First read: every name new, the consent creates the group.
      final first = planContactImport(candidates(), await entries());
      expect(
        first.map((r) => r.status),
        everyElement(ContactImportStatus.fresh),
      );
      await apply(first);
      final group = (await db.readContactNameGroups()).single;
      expect(group.sourceKind, kWindowsContactsKind);

      // Opening again with the same store: nothing to show.
      final same = planContactImport(
        candidates(),
        await entries(),
        groupId: 'win',
      );
      expect(contactImportHasChanges(same), isFalse);

      // A contact came, one went: the page shows both for confirmation.
      store = _ok([
        ['Lea', 'Wolf', 'Lea Wolf', 'Nordwind GmbH'],
        ['Tom', 'Rau', 'Tom Rau', ''],
      ]);
      final changed = planContactImport(
        candidates(),
        await entries(),
        groupId: 'win',
      );
      expect(contactImportHasChanges(changed), isTrue);
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

      // Withdrawal removes the group with its names.
      await db.deleteContactNameGroup('win');
      expect(await db.readContactNameGroups(), isEmpty);
      expect(await entries(), isEmpty);
    });
  });
}
