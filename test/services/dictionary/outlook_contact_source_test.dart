/// Names from the local classic Outlook (#2039): the handover of the native
/// Outlook reader (method `readOutlook` on `com.whispaste.system_contacts`)
/// to the contact names, its failures with a next step, and the way into
/// the import group (update on demand, withdrawal).
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/services/dictionary/contact_names.dart';
import 'package:whispaste/services/dictionary/outlook_contact_source.dart';
import 'package:whispaste/services/dictionary/windows_contact_source.dart';

const _channel = MethodChannel('com.whispaste.system_contacts');

Map<String, Object?> _ok(List<List<String>> contacts) => {
  'status': 'ok',
  'contacts': contacts,
};

Matcher _fails(ContactSourceFailure reason) => throwsA(
  isA<ContactSourceException>().having((e) => e.reason, 'reason', reason),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('decodeOutlookContactsReply', () {
    test('hands over names and companies, nothing else', () {
      final contacts = decodeOutlookContactsReply(
        _ok([
          ['Lea Maria', 'Wolf', 'Lea Maria Wolf', 'Nordwind GmbH'],
          ['', '', 'lea@example.org', 'Nordwind GmbH'],
          ['', '', '+49 30 123456', ''],
          ['', '', '', ''],
        ]),
      );
      expect(contacts, const [
        ContactName(
          given: 'Lea Maria',
          family: 'Wolf',
          full: 'Lea Maria Wolf',
          organization: 'Nordwind GmbH',
        ),
        ContactName(organization: 'Nordwind GmbH'),
      ]);
      expect(contactNameCandidates(contacts), [
        'Lea Maria Wolf',
        'Nordwind GmbH',
      ]);
    });

    test('an Outlook without contacts is no failure', () {
      expect(decodeOutlookContactsReply(_ok([])), isEmpty);
    });

    test('maps every status to what the user can do next', () {
      const cases = {
        'notInstalled': ContactSourceFailure.notInstalled,
        'notRunning': ContactSourceFailure.notRunning,
        'busy': ContactSourceFailure.busy,
        'tooMany': ContactSourceFailure.tooMany,
        'unavailable': ContactSourceFailure.unavailable,
        'somethingNew': ContactSourceFailure.unavailable,
      };
      for (final MapEntry(key: status, value: reason) in cases.entries) {
        expect(
          () => decodeOutlookContactsReply({'status': status}),
          _fails(reason),
          reason: status,
        );
      }
      expect(
        () => decodeOutlookContactsReply(null),
        _fails(ContactSourceFailure.unavailable),
      );
      expect(
        () => decodeOutlookContactsReply({'status': 'ok'}),
        _fails(ContactSourceFailure.unavailable),
      );
      expect(
        () => decodeOutlookContactsReply(
          _ok([
            for (var i = 0; i <= kContactNamesMaxContacts; i++) ['A$i', '', ''],
          ]),
        ),
        _fails(ContactSourceFailure.tooMany),
      );
    });
  });

  group('OutlookContactSource', () {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

    test('asks the host for the Outlook contacts with the limit', () async {
      MethodCall? call;
      messenger.setMockMethodCallHandler(_channel, (c) async {
        call = c;
        return _ok([
          ['Ida', 'Berg', 'Ida Berg', ''],
        ]);
      });
      const source = OutlookContactSource();
      expect(source.kind, kOutlookContactsKind);
      expect(source.kind, isNot(kWindowsContactsKind));
      expect(await source.read(), const [
        ContactName(given: 'Ida', family: 'Berg', full: 'Ida Berg'),
      ]);
      expect(call?.method, 'readOutlook');
      expect(call?.arguments, {'limit': kContactNamesMaxContacts});
    });

    test('a failing or missing host is unavailable', () async {
      messenger.setMockMethodCallHandler(
        _channel,
        (_) async => throw PlatformException(code: 'boom'),
      );
      await expectLater(
        const OutlookContactSource().read(),
        _fails(ContactSourceFailure.unavailable),
      );
      messenger.setMockMethodCallHandler(_channel, null);
      await expectLater(
        const OutlookContactSource().read(),
        _fails(ContactSourceFailure.unavailable),
      );
    });

    test('an Outlook that does not answer counts as busy', () async {
      final never = Completer<Object?>();
      messenger.setMockMethodCallHandler(_channel, (_) => never.future);
      await expectLater(
        const OutlookContactSource(timeout: Duration(milliseconds: 10)).read(),
        _fails(ContactSourceFailure.busy),
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

    Future<void> apply(
      String groupId,
      String kind,
      List<ContactImportRow> rows,
    ) {
      final changes = contactImportChanges(rows, const {});
      return db.applyContactNameImport(
        groupId: groupId,
        sourceKind: kind,
        sourceLabel: kind,
        consentedAt: t,
        add: [for (final n in changes.add) (id: '$groupId-$n', name: n)],
        removeIds: changes.removeIds,
        now: t,
      );
    }

    test('first read, update by a new read, withdrawal; a Windows group '
        'next to it stays untouched', () async {
      // The Windows contacts already form a group with one name.
      await apply(
        'win',
        kWindowsContactsKind,
        planContactImport(['Tom Rau'], await entries()),
      );

      var outlook = _ok([
        ['Lea', 'Wolf', 'Lea Wolf', 'Nordwind GmbH'],
        ['Ida', 'Berg', 'Ida Berg', ''],
        // Also in the Windows group: shown as existing, not added twice.
        ['Tom', 'Rau', 'Tom Rau', ''],
      ]);
      List<String> candidates() =>
          contactNameCandidates(decodeOutlookContactsReply(outlook));

      final first = planContactImport(candidates(), await entries());
      expect(
        {for (final r in first) r.name: r.status},
        {
          'Lea Wolf': ContactImportStatus.fresh,
          'Nordwind GmbH': ContactImportStatus.fresh,
          'Ida Berg': ContactImportStatus.fresh,
          'Tom Rau': ContactImportStatus.existing,
        },
      );
      await apply('ol', kOutlookContactsKind, first);
      final groups = await db.readContactNameGroups();
      expect(groups.map((g) => g.sourceKind).toSet(), {
        kWindowsContactsKind,
        kOutlookContactsKind,
      });

      // A later read: one contact came, one went.
      outlook = _ok([
        ['Lea', 'Wolf', 'Lea Wolf', 'Nordwind GmbH'],
        ['Max', 'Kern', 'Max Kern', ''],
      ]);
      final update = planContactImport(
        candidates(),
        await entries(),
        groupId: 'ol',
      );
      expect(contactImportHasChanges(update), isTrue);
      expect(
        {for (final r in update) r.name: r.status},
        {
          'Lea Wolf': ContactImportStatus.kept,
          'Nordwind GmbH': ContactImportStatus.kept,
          'Max Kern': ContactImportStatus.fresh,
          'Ida Berg': ContactImportStatus.dropped,
        },
      );
      await apply('ol', kOutlookContactsKind, update);
      expect((await entries()).map((e) => e.replacement).toSet(), {
        'Tom Rau',
        'Lea Wolf',
        'Nordwind GmbH',
        'Max Kern',
      });

      // Withdrawal removes the Outlook group with its names only.
      await db.deleteContactNameGroup('ol');
      expect(
        (await db.readContactNameGroups()).single.sourceKind,
        kWindowsContactsKind,
      );
      expect((await entries()).map((e) => e.replacement).toSet(), {'Tom Rau'});
    });
  });
}
