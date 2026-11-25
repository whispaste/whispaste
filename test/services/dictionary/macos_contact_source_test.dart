/// Names from the macOS contacts (#2037): the handover of the native
/// contact host (`macos/Runner/SystemContactsHost.swift`, method channel
/// `com.whispaste.system_contacts`) to the contact names, the access status
/// that decides whether the app explains the read before macOS asks, the
/// comparison on opening the page that never brings up the system prompt,
/// and the way into the import group (update, withdrawal).
library;

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/services/dictionary/contact_names.dart';
import 'package:whispaste/services/dictionary/macos_contact_source.dart';
import 'package:whispaste/services/dictionary/system_contact_source.dart';

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
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  /// A host with access [status] and a store holding [store]; records the
  /// methods it was asked for.
  List<String> host(String status, Object? Function() store) {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'status':
          return status;
        case 'read':
          expect(call.arguments, {'limit': kContactNamesMaxContacts});
          return store();
      }
      return null;
    });
    return calls;
  }

  group('MacContactSource', () {
    test('reads names and companies with the limit', () async {
      final calls = host(
        'authorized',
        () => _ok([
          ['Lea Maria', 'Wolf', 'Lea Maria Wolf', 'Nordwind GmbH'],
          ['', '', '', 'Apfel & Birne KG'],
        ]),
      );
      const source = MacContactSource();
      expect(source.kind, kMacContactsKind);
      expect(source.settingsUri.toString(), kMacContactsSettingsUri);
      expect(await source.read(), const [
        ContactName(
          given: 'Lea Maria',
          family: 'Wolf',
          full: 'Lea Maria Wolf',
          organization: 'Nordwind GmbH',
        ),
        ContactName(organization: 'Apfel & Birne KG'),
      ]);
      expect(calls, ['read']);
    });

    test('asks for access only while macOS never asked', () async {
      for (final (status, asks) in [
        ('notDetermined', true),
        ('authorized', false),
        ('denied', false),
        ('restricted', false),
      ]) {
        host(status, () => null);
        expect(
          await const MacContactSource().asksForAccess(),
          asks,
          reason: status,
        );
      }
      // A host that does not answer never lets the page read unasked.
      messenger.setMockMethodCallHandler(_channel, null);
      expect(await const MacContactSource().asksForAccess(), isTrue);
      messenger.setMockMethodCallHandler(
        _channel,
        (_) async => throw PlatformException(code: 'boom'),
      );
      expect(await const MacContactSource().asksForAccess(), isTrue);
    });

    test('maps refused, restricted, too large and failing stores', () async {
      for (final (status, failure) in [
        ('denied', ContactSourceFailure.denied),
        ('restricted', ContactSourceFailure.restricted),
        ('tooMany', ContactSourceFailure.tooMany),
        ('unavailable', ContactSourceFailure.unavailable),
      ]) {
        host('authorized', () => {'status': status});
        await expectLater(
          const MacContactSource().read(),
          _fails(failure),
          reason: status,
        );
      }
      messenger.setMockMethodCallHandler(_channel, null);
      await expectLater(
        const MacContactSource().read(),
        _fails(ContactSourceFailure.unavailable),
      );
    });

    test('drops e-mail addresses and phone numbers in name fields', () async {
      host(
        'authorized',
        () => _ok([
          ['', '', 'lea@example.org', 'Nordwind GmbH'],
          ['', '', '+49 30 123456', ''],
        ]),
      );
      expect(contactNameCandidates(await const MacContactSource().read()), [
        'Nordwind GmbH',
      ]);
    });
  });

  group('readSystemContactsOnOpen', () {
    test(
      'never reads, and so never prompts, while access was not asked',
      () async {
        final calls = host('notDetermined', () => _ok([]));
        expect(
          await readSystemContactsOnOpen(const MacContactSource()),
          isNull,
        );
        expect(calls, ['status']);
      },
    );

    test('compares the store once access was granted', () async {
      final calls = host(
        'authorized',
        () => _ok([
          ['Lea', 'Wolf', 'Lea Wolf', 'Nordwind GmbH'],
        ]),
      );
      expect(await readSystemContactsOnOpen(const MacContactSource()), [
        'Lea Wolf',
        'Nordwind GmbH',
      ]);
      expect(calls, ['status', 'read']);
    });

    test('a refusal since the last read is reported', () async {
      host('denied', () => {'status': 'denied'});
      await expectLater(
        readSystemContactsOnOpen(const MacContactSource()),
        _fails(ContactSourceFailure.denied),
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
        groupId: 'mac',
        sourceKind: kMacContactsKind,
        sourceLabel: const MacContactSource().label,
        consentedAt: t,
        add: [for (final n in changes.add) (id: 'mac-$n', name: n)],
        removeIds: changes.removeIds,
        now: t,
      );
    }

    test('first read, changed store on open, withdrawal', () async {
      var store = _ok([
        ['Lea', 'Wolf', 'Lea Wolf', 'Nordwind GmbH'],
        ['Ida', 'Berg', 'Ida Berg', ''],
      ]);
      host('authorized', () => store);
      const source = MacContactSource();

      final first = planContactImport(
        contactNameCandidates(await source.read()),
        await entries(),
      );
      expect(
        first.map((r) => r.status),
        everyElement(ContactImportStatus.fresh),
      );
      await apply(first);
      expect(
        (await db.readContactNameGroups()).single.sourceKind,
        kMacContactsKind,
      );

      final same = planContactImport(
        (await readSystemContactsOnOpen(source))!,
        await entries(),
        groupId: 'mac',
      );
      expect(contactImportHasChanges(same), isFalse);

      store = _ok([
        ['Lea', 'Wolf', 'Lea Wolf', 'Nordwind GmbH'],
        ['Tom', 'Rau', 'Tom Rau', ''],
      ]);
      final changed = planContactImport(
        (await readSystemContactsOnOpen(source))!,
        await entries(),
        groupId: 'mac',
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

      // Withdrawal in the app removes the group with its names.
      await db.deleteContactNameGroup('mac');
      expect(await db.readContactNameGroups(), isEmpty);
      expect(await entries(), isEmpty);
    });
  });
}
