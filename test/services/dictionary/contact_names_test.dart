/// Contact names for the dictionary (#2036): the vCard and CSV parsers, the
/// candidates, the plan against the dictionary, the selection and the hint
/// for the local engines.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/dictionary/contact_names.dart';
import 'package:whispaste/services/dictionary/contact_terms.dart';

List<ContactName> _file(String text, {String name = 'contacts.vcf'}) =>
    decodeContactFile(utf8.encode(text), filename: name);

Matcher _fails(String message) => throwsA(
  isA<FormatException>().having((e) => e.message, 'message', message),
);

void main() {
  group('vCard', () {
    test('2.1 with quoted-printable, charset and soft break', () {
      final contacts = parseVCard(
        'BEGIN:VCARD\r\n'
        'VERSION:2.1\r\n'
        'N;CHARSET=ISO-8859-1;ENCODING=QUOTED-PRINTABLE:M=FCller;J=FCrgen\r\n'
        'FN;ENCODING=QUOTED-PRINTABLE;CHARSET=UTF-8:J=C3=BCrgen M=C3=BC=\r\n'
        'ller\r\n'
        'TEL;CELL:+49 170 0000000\r\n'
        'END:VCARD\r\n',
      );
      expect(contacts, [
        const ContactName(
          given: 'Jürgen',
          family: 'Müller',
          full: 'Jürgen Müller',
        ),
      ]);
    });

    test('3.0 with escapes, ORG and a group prefix', () {
      final contacts = parseVCard(
        'BEGIN:VCARD\nVERSION:3.0\n'
        'item1.FN:Anna Schmidt\n'
        r'N:Schmidt;Anna;;;'
        '\n'
        r'ORG:Schmidt\, Söhne & Co;Vertrieb'
        '\n'
        'EMAIL:anna@example.org\n'
        'END:VCARD\n',
      );
      expect(contacts.single.displayName, 'Anna Schmidt');
      expect(contacts.single.organization, 'Schmidt, Söhne & Co');
    });

    test('4.0 folded lines; a card without any name is skipped', () {
      final contacts = parseVCard(
        'BEGIN:VCARD\r\nVERSION:4.0\r\n'
        'FN:Maximilian von \r\n'
        ' Hohenberg\r\n'
        'END:VCARD\r\n'
        'BEGIN:VCARD\r\nVERSION:4.0\r\nTEL:123\r\nEND:VCARD\r\n'
        'BEGIN:VCARD\r\nVERSION:4.0\r\nN:Ito;Hana;;;\r\nEND:VCARD\r\n',
      );
      expect(contacts.map((c) => c.displayName), [
        'Maximilian von Hohenberg',
        'Hana Ito',
      ]);
    });

    test('a text without any card is not a vCard', () {
      expect(() => parseVCard('hello'), _fails('format'));
    });

    test('more than the contact limit is refused', () {
      final many = StringBuffer();
      for (var i = 0; i <= kContactNamesMaxContacts; i++) {
        many.write('BEGIN:VCARD\nFN:Person $i\nEND:VCARD\n');
      }
      expect(() => parseVCard(many.toString()), _fails('rows'));
    });
  });

  group('CSV', () {
    test('Outlook export: first, middle and last name, company', () {
      final contacts = _file(
        'Title,First Name,Middle Name,Last Name,Company,E-mail Address\n'
        'Dr.,Eva,Maria,Klein,Klein GmbH,eva@example.org\n'
        ',,,,Nur Firma AG,\n',
        name: 'outlook.csv',
      );
      expect(contacts, [
        const ContactName(
          given: 'Eva Maria',
          family: 'Klein',
          organization: 'Klein GmbH',
        ),
        const ContactName(organization: 'Nur Firma AG'),
      ]);
      expect(contacts.first.displayName, 'Eva Maria Klein');
    });

    test('Google export: Name and Organization 1 - Name', () {
      final contacts = _file(
        'Name,Given Name,Family Name,Organization 1 - Name,Phone 1 - Value\n'
        '"Ōtani, Shohei",Shohei,Ōtani,,+1 555\n'
        'Lea Wolf,Lea,Wolf,Wolf & Partner,\n',
        name: 'google.csv',
      );
      expect(contacts.map((c) => c.displayName), ['Ōtani, Shohei', 'Lea Wolf']);
      expect(contacts.last.organization, 'Wolf & Partner');
    });

    test('a Latin-1 file is read', () {
      final contacts = decodeContactFile(
        latin1.encode('Vorname;Nachname\nBjörn;Größe\n'),
        filename: 'kontakte.csv',
      );
      expect(contacts.single.displayName, 'Björn Größe');
    });

    test('a file without a name column is refused', () {
      expect(
        () => _file('Phone,Email\n123,a@b.c\n', name: 'x.csv'),
        _fails('format'),
      );
    });

    test('size and row limits come from the term import', () {
      expect(
        () => decodeContactFile(
          List.filled(1024 * 1024 + 1, 0x41),
          filename: 'big.csv',
        ),
        _fails('size'),
      );
      final rows = StringBuffer('Name\n');
      for (var i = 0; i < 5001; i++) {
        rows.write('Person $i\n');
      }
      expect(() => _file(rows.toString(), name: 'x.csv'), _fails('rows'));
    });
  });

  test('a ContactFileSource is a file source that reads names only', () async {
    final source = ContactFileSource(
      label: 'team.vcf',
      bytes: () async => utf8.encode('BEGIN:VCARD\nFN:Ida Berg\nEND:VCARD\n'),
    );
    expect(source.kind, 'file');
    expect((await source.read()).single.displayName, 'Ida Berg');
  });

  test('candidates: full names and companies only, each once, '
      'without what the dictionary cannot hold', () {
    expect(
      contactNameCandidates([
        const ContactName(given: 'Eva', family: 'Klein', organization: 'ACME'),
        const ContactName(full: 'eva klein'),
        const ContactName(full: 'Ōtani, Shohei'),
        ContactName(full: 'X' * 61),
        const ContactName(full: '!!!'),
        const ContactName(organization: 'acme'),
        const ContactName(full: '  Lea   Wolf '),
      ]),
      ['Eva Klein', 'ACME', 'Lea Wolf'],
    );
  });

  group('plan', () {
    ContactPlanEntry entry(
      String id,
      String name, {
      String? group,
      List<String>? triggers,
    }) => (
      id: id,
      triggers: triggers ?? [name],
      replacement: name,
      importGroupId: group,
    );

    test('first import: new and existing names', () {
      final rows = planContactImport(
        ['Eva Klein', 'ACME', 'Lea Wolf', 'eva klein'],
        [
          entry('own', 'Acme Corporation', triggers: ['acme']),
          entry('other', 'Lea Wolf', group: 'g2'),
        ],
      );
      expect(
        [for (final r in rows) (r.name, r.status)],
        [
          ('Eva Klein', ContactImportStatus.fresh),
          ('ACME', ContactImportStatus.existing),
          ('Lea Wolf', ContactImportStatus.existing),
        ],
      );
      expect(rows.map((r) => r.selectable), [true, false, false]);
    });

    test('update: kept, new and dropped names, dropped last', () {
      final rows = planContactImport(
        ['Lea Wolf', 'Neu Person'],
        [
          entry('a', 'Lea Wolf', group: 'g1'),
          entry('b', 'Alt Person', group: 'g1'),
          entry('c', 'Fremd', group: 'g2'),
          // Edited by the user: it left the group and is an own entry now.
          entry('d', 'Neu Person'),
        ],
        groupId: 'g1',
      );
      expect(
        [for (final r in rows) (r.name, r.status, r.entryId)],
        [
          ('Lea Wolf', ContactImportStatus.kept, 'a'),
          ('Neu Person', ContactImportStatus.existing, null),
          ('Alt Person', ContactImportStatus.dropped, 'b'),
        ],
      );
    });

    test('the selection adds new names and removes dropped entries', () {
      const rows = [
        ContactImportRow('Eva Klein', ContactImportStatus.fresh),
        ContactImportRow('Lea Wolf', ContactImportStatus.kept, entryId: 'a'),
        ContactImportRow('ACME', ContactImportStatus.existing),
        ContactImportRow('Ida Berg', ContactImportStatus.fresh),
        ContactImportRow('Alt', ContactImportStatus.dropped, entryId: 'b'),
        ContactImportRow('Bleibt', ContactImportStatus.dropped, entryId: 'c'),
      ];
      final changes = contactImportChanges(rows, {3, 5});
      expect(changes.add, ['Eva Klein']);
      expect(changes.removeIds, ['b']);
    });
  });

  group('local hint', () {
    final t = DateTime(2026);

    test('most used first, then newest, each once, capped', () {
      expect(
        contactHintTerms([
          (name: 'Alt', usageCount: 1, changed: t),
          (name: 'Neu', usageCount: 1, changed: DateTime(2026, 5)),
          (name: 'Oft', usageCount: 9, changed: t),
          (name: 'oft', usageCount: 0, changed: t),
          (name: 'Ōtani, Shohei', usageCount: 9, changed: t),
        ]),
        ['Oft', 'Neu', 'Alt'],
      );
      expect(
        contactHintTerms([
          for (var i = 0; i < kContactTermsMax + 10; i++)
            (name: 'P$i', usageCount: 0, changed: t),
        ]),
        hasLength(kContactTermsMax),
      );
    });

    test('contacts go behind the own terms, each once', () {
      expect(
        localVocabularyHint('WhisPaste, Lea Wolf', ['lea wolf', 'Ida Berg']),
        'WhisPaste, Lea Wolf, Ida Berg',
      );
      expect(localVocabularyHint('A\nB', ['C']), 'A\nB\nC');
      expect(localVocabularyTerms('A', ['B']), ['A', 'B']);
      expect(localVocabularyHint(' A ,B', const []), 'A, B');
    });
  });
}
