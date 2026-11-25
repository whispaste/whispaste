/// Names from the KDE address book (#2041): which Akonadi resources are
/// read and from where, what crosses into the contact names, when the page
/// offers the source, the failures, and the way into the import group
/// (update on open, withdrawal).
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/services/dictionary/contact_names.dart';
import 'package:whispaste/services/dictionary/gnome_contact_source.dart';
import 'package:whispaste/services/dictionary/kde_contact_source.dart';
import 'package:whispaste/services/dictionary/system_contact_source.dart';

String _card(String fn, {String n = '', String org = ''}) => [
  'BEGIN:VCARD',
  'VERSION:3.0',
  'UID:${fn.hashCode}',
  if (fn.isNotEmpty) 'FN:$fn',
  if (n.isNotEmpty) 'N:$n',
  if (org.isNotEmpty) 'ORG:$org',
  'EMAIL;TYPE=WORK:lea@example.org',
  'TEL;TYPE=CELL:+49 30 123456',
  'ADR;TYPE=HOME:;;Hauptstraße 1;Berlin;;10115;Germany',
  'END:VCARD',
].join('\r\n');

const _agentsrc = '''
[Instances][akonadi_contacts_resource_0]
AgentType=akonadi_contacts_resource

[Instances][akonadi_maildir_resource_0]
AgentType=akonadi_maildir_resource

[Instances][akonadi_davgroupware_resource_0]
AgentType=akonadi_davgroupware_resource
''';

Matcher _fails(ContactSourceFailure reason) => throwsA(
  isA<ContactSourceException>().having((e) => e.reason, 'reason', reason),
);

void main() {
  group('parseKConfig', () {
    test('nested groups, escapes, flags and localized keys', () {
      final config = parseKConfig(
        '# comment\n'
        'Top=1\n'
        '[Instances][akonadi_contacts_resource_0]\n'
        'AgentType = akonadi_contacts_resource\n'
        '[General]\n'
        r'Name=\sLea\tWolf\x21'
        '\n'
        'Name[de]=Lea\n'
        r'Path[$e]=$HOME/Kontakte/${USER}'
        '\n'
        r'Other[$e]=~/x'
        '\n'
        r'Run[$e]=$(rm -rf ~)'
        '\n',
        environment: const {'HOME': '/home/lea', 'USER': 'lea'},
      );
      expect(config['']!['Top'], '1');
      expect(
        config['Instances][akonadi_contacts_resource_0']!['AgentType'],
        'akonadi_contacts_resource',
      );
      final general = config['General']!;
      expect(general['Name'], ' Lea\tWolf!');
      expect(general['Path'], '/home/lea/Kontakte/lea');
      expect(general['Other'], '/home/lea/x');
      expect(general.containsKey('Run'), isFalse);
    });
  });

  group('akonadiContactResources', () {
    test('local contact resources only, with their place', () {
      final settings = {
        'akonadi_vcarddir_resource_1': '[General]\nPath=/srv/karten\n',
        'akonadi_vcard_resource_2':
            '[General]\nPath=file:///home/lea/Meine%20Kontakte.vcf\n',
        'akonadi_vcard_resource_3':
            '[General]\nPath=https://example.org/contacts.vcf\n',
      };
      final resources = akonadiContactResources(
        '$_agentsrc'
        '[Instances][akonadi_vcarddir_resource_1]\n'
        'AgentType=akonadi_vcarddir_resource\n'
        '[Instances][akonadi_vcard_resource_2]\n'
        'AgentType=akonadi_vcard_resource\n'
        '[Instances][akonadi_vcard_resource_3]\n'
        'AgentType=akonadi_vcard_resource\n'
        '[Instances][akonadi_vcard_resource_4]\n'
        'AgentType=akonadi_vcard_resource\n'
        '[Instances][../../etc]\n'
        'AgentType=akonadi_contacts_resource\n',
        settingsOf: (id) => settings[id],
        dataHome: '/home/lea/.local/share',
      );
      expect(resources, [
        (
          id: 'akonadi_contacts_resource_0',
          store: AkonadiStore.folder,
          path: '/home/lea/.local/share/contacts/',
        ),
        (
          id: 'akonadi_vcard_resource_2',
          store: AkonadiStore.file,
          path: '/home/lea/Meine Kontakte.vcf',
        ),
        (
          id: 'akonadi_vcarddir_resource_1',
          store: AkonadiStore.folder,
          path: '/srv/karten',
        ),
      ]);
    });

    test('the personal contacts follow a configured folder', () {
      expect(
        akonadiContactResources(
          _agentsrc,
          settingsOf: (_) => '[General]\nPath[\$e]=\$HOME/Adressen\n',
          dataHome: '/x',
          environment: const {'HOME': '/home/lea'},
        ).single.path,
        '/home/lea/Adressen',
      );
    });
  });

  test('akonadiOnBus', () {
    expect(akonadiOnBus(['org.freedesktop.Akonadi.Control']), isTrue);
    expect(akonadiOnBus(['org.freedesktop.Akonadi.Control.work']), isTrue);
    expect(
      akonadiOnBus(['org.freedesktop.Akonadi', 'org.freedesktop.Akonadi.X']),
      isFalse,
    );
  });

  test('linuxContactSources puts the running desktop first', () {
    final gnome = GnomeContactSource(environment: const {});
    final kde = KdeContactSource(environment: const {});
    expect(linuxContactSources('KDE', gnome: gnome, kde: kde), [kde, gnome]);
    expect(linuxContactSources('ubuntu:GNOME', gnome: gnome, kde: kde), [
      gnome,
      kde,
    ]);
    expect(linuxContactSources('', gnome: gnome, kde: kde), [gnome, kde]);
  });

  group('KdeContactSource on a home folder', () {
    late Directory home;
    late Directory contacts;
    var onBus = true;

    Map<String, String> env([Map<String, String> extra = const {}]) => {
      'HOME': home.path,
      'XDG_CURRENT_DESKTOP': 'KDE',
      ...extra,
    };

    KdeContactSource source([Map<String, String> extra = const {}]) =>
        KdeContactSource(
          environment: env(extra),
          busNames: () async =>
              onBus ? const ['org.freedesktop.Akonadi.Control'] : const [],
        );

    void write(String path, String text) => File('${home.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(text);

    setUp(() {
      onBus = true;
      home = Directory.systemTemp.createTempSync('wp-kde-');
      write('.config/akonadi/agentsrc', _agentsrc);
      contacts = Directory('${home.path}/.local/share/contacts')
        ..createSync(recursive: true);
      write(
        '.local/share/contacts/lea.vcf',
        _card('Lea Wolf', n: 'Wolf;Lea', org: 'Nordwind GmbH'),
      );
      write('.local/share/contacts/Arbeit/ida.vcf', _card('Ida Berg'));
      write(
        '.local/share/contacts/Arbeit/mail-only.vcf',
        _card('ida@example.org'),
      );
      write('.local/share/contacts/team.ctg', '<contactGroup name="Team"/>');
    });

    tearDown(() => home.deleteSync(recursive: true));

    test(
      'reads names and companies only, from the whole folder tree',
      () async {
        final names = await source().read();
        expect(names, [
          const ContactName(full: 'Ida Berg'),
          const ContactName(
            given: 'Lea',
            family: 'Wolf',
            full: 'Lea Wolf',
            organization: 'Nordwind GmbH',
          ),
        ]);
        expect(contactNameCandidates(names), [
          'Ida Berg',
          'Lea Wolf',
          'Nordwind GmbH',
        ]);
      },
    );

    test('a configured vCard file adds its contacts', () async {
      write(
        '.config/akonadi/agentsrc',
        '$_agentsrc'
            '[Instances][akonadi_vcard_resource_0]\n'
            'AgentType=akonadi_vcard_resource\n',
      );
      write(
        '.config/akonadi_vcard_resource_0rc',
        '[General]\nPath[\$e]=\$HOME/alt.vcf\n',
      );
      write('alt.vcf', '${_card('Tom Rau')}\r\n${_card('Eva Kern')}');
      expect(
        contactNameCandidates(await source().read()),
        containsAll(['Tom Rau', 'Eva Kern', 'Lea Wolf']),
      );
    });

    test(
      'offered with Akonadi on the bus and a local contact resource',
      () async {
        expect(
          await source().availability(),
          SystemContactsAvailability.available,
        );
        onBus = false;
        expect(
          await source().availability(),
          SystemContactsAvailability.absent,
        );
        onBus = true;
        write(
          '.config/akonadi/agentsrc',
          '[Instances][akonadi_google_resource_0]\n'
              'AgentType=akonadi_google_resource\n',
        );
        expect(
          await source().availability(),
          SystemContactsAvailability.absent,
        );
        File('${home.path}/.config/akonadi/agentsrc').deleteSync();
        expect(
          await source().availability(),
          SystemContactsAvailability.absent,
        );
      },
    );

    test('Flatpak and Snap explain the export on KDE and stay silent '
        'elsewhere, without reading', () async {
      expect(
        await source(const {'FLATPAK_ID': 'de.whispaste.app'}).availability(),
        SystemContactsAvailability.sandboxed,
      );
      expect(
        await source(const {
          'SNAP': '/snap/whispaste/12',
          'XDG_CURRENT_DESKTOP': 'ubuntu:GNOME',
        }).availability(),
        SystemContactsAvailability.absent,
      );
      await expectLater(
        source(const {'SNAP': '/snap/whispaste/12'}).read(),
        _fails(ContactSourceFailure.unavailable),
      );
    });

    test('a missing folder fails the whole read', () async {
      write(
        '.config/akonadi/agentsrc',
        '$_agentsrc'
            '[Instances][akonadi_vcarddir_resource_0]\n'
            'AgentType=akonadi_vcarddir_resource\n',
      );
      write(
        '.config/akonadi_vcarddir_resource_0rc',
        '[General]\nPath=/nonexistent/usb-stick\n',
      );
      await expectLater(
        source().read(),
        _fails(ContactSourceFailure.unavailable),
      );
    });

    test('more contact files than the limit fail before reading', () async {
      for (var i = 0; i <= kContactNamesMaxContacts; i++) {
        File('${contacts.path}/c$i.vcf').createSync();
      }
      await expectLater(source().read(), _fails(ContactSourceFailure.tooMany));
    });

    test('an empty address book hands over nothing', () async {
      contacts.deleteSync(recursive: true);
      contacts.createSync();
      expect(await source().read(), isEmpty);
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
          groupId: 'kde',
          sourceKind: kKdeContactsKind,
          sourceLabel: source().label,
          consentedAt: t,
          add: [for (final n in changes.add) (id: 'kde-$n', name: n)],
          removeIds: changes.removeIds,
          now: t,
        );
      }

      Future<List<String>> candidates() async =>
          contactNameCandidates(await source().read());

      test('first read, unchanged book on open, changed book on open, '
          'withdrawal', () async {
        final first = planContactImport(await candidates(), await entries());
        expect(
          first.map((r) => r.status),
          everyElement(ContactImportStatus.fresh),
        );
        await apply(first);
        expect(
          (await db.readContactNameGroups()).single.sourceKind,
          kKdeContactsKind,
        );

        final same = planContactImport(
          await candidates(),
          await entries(),
          groupId: 'kde',
        );
        expect(contactImportHasChanges(same), isFalse);

        File('${contacts.path}/Arbeit/ida.vcf').deleteSync();
        write('.local/share/contacts/tom.vcf', _card('Tom Rau'));
        final changed = planContactImport(
          await candidates(),
          await entries(),
          groupId: 'kde',
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

        await db.deleteContactNameGroup('kde');
        expect(await db.readContactNameGroups(), isEmpty);
        expect(await entries(), isEmpty);
      });
    });
  });
}
