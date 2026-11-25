/// Contact names for the dictionary (#2036, part 1 of #161): a source hands
/// over names only (given and family name, full name, company), never
/// addresses, phone numbers or e-mail addresses. The file parsers (vCard
/// 2.1/3.0/4.0, Outlook and Google CSV) and the import plan are pure, so
/// their rules are tested without UI or database.
library;

import 'dart:convert';

import 'entry_validation.dart';
import 'term_import.dart';

/// Most contacts one source may hand over.
const int kContactNamesMaxContacts = termImportMaxRows;

/// One contact as the dictionary sees it: names only. Empty strings for
/// fields the source does not have.
class ContactName {
  const ContactName({
    this.given = '',
    this.family = '',
    this.full = '',
    this.organization = '',
  });

  final String given;
  final String family;
  final String full;
  final String organization;

  /// The full name, or given and family name joined when the source has
  /// no display name.
  String get displayName {
    final f = full.trim();
    if (f.isNotEmpty) return f;
    return [given.trim(), family.trim()].where((s) => s.isNotEmpty).join(' ');
  }

  @override
  bool operator ==(Object other) =>
      other is ContactName &&
      other.given == given &&
      other.family == family &&
      other.full == full &&
      other.organization == organization;

  @override
  int get hashCode => Object.hash(given, family, full, organization);

  @override
  String toString() => 'ContactName($given|$family|$full|$organization)';
}

/// Where contact names come from. Only names cross this boundary; consent is
/// stored per source (`ContactNameGroups`) and can be withdrawn, which
/// removes the source's names.
abstract interface class ContactNameSource {
  /// Stable kind of source, stored with the group (`file`).
  String get kind;

  /// What the user recognises the source by (a file name).
  String get label;

  Future<List<ContactName>> read();
}

/// Whether the contact page offers a system address book.
enum SystemContactsAvailability {
  /// The address book can be read: the page shows its read button.
  available,

  /// The address book service runs, but the sandbox of this build (Flatpak,
  /// Snap) does not let the app reach it: the page explains the file export
  /// instead of offering a button that cannot work.
  sandboxed,

  /// This system has no such address book: the page shows nothing for it.
  absent,
}

/// The address book of the operating system (Windows, macOS and GNOME
/// contacts): read only from the contact page, never on the hotkey path. At
/// most one import group per [kind]; a later read updates it.
abstract interface class SystemContactSource implements ContactNameSource {
  /// Checked when the contact page opens, before anything is read.
  Future<SystemContactsAvailability> availability();

  /// Whether a [read] would make the system ask for access first (macOS
  /// before the first answer). The page asks for consent in the app before,
  /// and the comparison on opening the page never reads then.
  Future<bool> asksForAccess();

  /// The system privacy setting for the contacts, `null` without one.
  Uri? get settingsUri;
}

/// Why a system contact source could not hand over names.
enum ContactSourceFailure {
  /// The system privacy setting refuses access to the contacts.
  denied,

  /// Access is blocked by a policy the user cannot change in the privacy
  /// setting (macOS: Screen Time or a device management profile).
  restricted,

  /// The unpackaged build (NSIS installer, ZIP) has no package identity, and
  /// Windows does not hand it the contacts; the Store version can.
  unpackaged,

  /// More contacts than [kContactNamesMaxContacts].
  tooMany,

  /// The address book cannot be read (missing, old system, a book that does
  /// not open, unexpected error).
  unavailable,

  /// Outlook (#2039): no classic Outlook is installed; the new Outlook has
  /// no interface for other apps.
  notInstalled,

  /// Outlook (#2039): classic Outlook is installed but not open. WhisPaste
  /// never starts it (it may ask for a profile or password).
  notRunning,

  /// Outlook (#2039): Outlook rejects or does not answer the call, for
  /// example while one of its dialogs is open.
  busy,
}

class ContactSourceException implements Exception {
  const ContactSourceException(this.reason);
  final ContactSourceFailure reason;

  @override
  String toString() => 'ContactSourceException(${reason.name})';
}

/// [value] with its whitespace collapsed, or empty when it is an e-mail
/// address or a phone number: a system address book can keep such a text in
/// a name field, and nothing but names may reach the dictionary.
String contactNameField(String value) {
  final text = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.contains('@')) return '';
  if (_phone.hasMatch(text) && RegExp(r'\d').hasMatch(text)) return '';
  return text;
}

final _phone = RegExp(r'^[\d\s+()./-]+$');

/// [contact] with [contactNameField] applied to every field.
ContactName contactNamesOnly(ContactName contact) => ContactName(
  given: contactNameField(contact.given),
  family: contactNameField(contact.family),
  full: contactNameField(contact.full),
  organization: contactNameField(contact.organization),
);

/// The names of the vCards a system address book holds (GNOME, KDE): FN, N
/// and ORG through [parseVCard], name fields that look like an e-mail
/// address or a phone number emptied ([contactNamesOnly]), contacts without
/// any name left out. Throws [ContactSourceException]:
/// [ContactSourceFailure.tooMany] above [kContactNamesMaxContacts],
/// otherwise [ContactSourceFailure.unavailable] when the text is no vCard.
List<ContactName> decodeSystemVCards(Iterable<String> vcards) {
  final text = vcards.join('\r\n');
  if (text.trim().isEmpty) return const [];
  final List<ContactName> parsed;
  try {
    parsed = parseVCard(text);
  } on FormatException catch (e) {
    if (e.message == 'rows') {
      throw const ContactSourceException(ContactSourceFailure.tooMany);
    }
    throw const ContactSourceException(ContactSourceFailure.unavailable);
  }
  return [
    for (final contact in parsed.map(contactNamesOnly))
      if (contact.displayName.isNotEmpty || contact.organization.isNotEmpty)
        contact,
  ];
}

/// A vCard or CSV export the user picked or dropped.
class ContactFileSource implements ContactNameSource {
  ContactFileSource({required this.label, required this.bytes});

  @override
  String get kind => 'file';

  @override
  final String label;

  /// Reads the file; called once per [read].
  final Future<List<int>> Function() bytes;

  @override
  Future<List<ContactName>> read() async =>
      decodeContactFile(await bytes(), filename: label);
}

/// The contacts in an export file: vCard when the text starts with
/// `BEGIN:VCARD` (or the name ends in .vcf/.vcard), otherwise CSV.
/// Throws [FormatException] (`size`, `rows`, `binary`, `empty`, `format`,
/// `quotes`) when the file cannot be read.
List<ContactName> decodeContactFile(
  List<int> bytes, {
  required String filename,
}) {
  final text = decodeImportText(bytes, latin1Fallback: true);
  final lower = filename.toLowerCase();
  final isVCard =
      text.toUpperCase().startsWith('BEGIN:VCARD') ||
      lower.endsWith('.vcf') ||
      lower.endsWith('.vcard');
  return isVCard ? parseVCard(text) : parseContactCsv(text);
}

// ── vCard ──────────────────────────────────────────────────────────────────

/// The contacts of a vCard text (2.1, 3.0, 4.0): FN, N and ORG; folded
/// lines, quoted-printable and the charsets UTF-8, ISO-8859-1 and
/// windows-1252. Throws [FormatException] (`format`) without any card and
/// (`rows`) for more than [kContactNamesMaxContacts] cards.
List<ContactName> parseVCard(String text) {
  final contacts = <ContactName>[];
  var inCard = false;
  var sawCard = false;
  String? fn;
  List<String>? n;
  String? org;
  for (final line in _unfold(text)) {
    final colon = _unquotedColon(line);
    if (colon < 0) continue;
    final head = line.substring(0, colon);
    final value = line.substring(colon + 1);
    final parts = head.split(';');
    var name = parts.first.trim().toUpperCase();
    final dot = name.lastIndexOf('.');
    if (dot >= 0) name = name.substring(dot + 1);
    if (name == 'BEGIN' && value.trim().toUpperCase() == 'VCARD') {
      inCard = true;
      sawCard = true;
      fn = null;
      n = null;
      org = null;
      continue;
    }
    if (!inCard) continue;
    if (name == 'END' && value.trim().toUpperCase() == 'VCARD') {
      inCard = false;
      final names = n ?? const <String>[];
      final contact = ContactName(
        family: names.isNotEmpty ? names[0] : '',
        given: names.length > 1 ? names[1] : '',
        full: fn ?? '',
        organization: org ?? '',
      );
      if (contact.displayName.isNotEmpty || contact.organization.isNotEmpty) {
        contacts.add(contact);
        if (contacts.length > kContactNamesMaxContacts) {
          throw const FormatException('rows');
        }
      }
      continue;
    }
    if (name != 'FN' && name != 'N' && name != 'ORG') continue;
    final decoded = _decodeValue(value, parts.skip(1));
    final components = _components(decoded);
    switch (name) {
      case 'FN':
        fn ??= _clean(_unescape(decoded));
      case 'N':
        n ??= [for (final c in components) _clean(c)];
      case 'ORG':
        org ??= components.isEmpty ? '' : _clean(components.first);
    }
  }
  if (!sawCard) throw const FormatException('format');
  return contacts;
}

/// Logical lines: a line starting with a space or tab continues the one
/// before (RFC 6350 folding), and a quoted-printable line ending in `=`
/// continues on the next (vCard 2.1 soft break).
List<String> _unfold(String text) {
  final out = <String>[];
  for (final raw in text.split(RegExp(r'\r\n|\r|\n'))) {
    if (out.isNotEmpty && raw.isNotEmpty && (raw[0] == ' ' || raw[0] == '\t')) {
      out[out.length - 1] += raw.substring(1);
      continue;
    }
    if (out.isNotEmpty &&
        out.last.endsWith('=') &&
        _isQuotedPrintable(out.last)) {
      out[out.length - 1] =
          out.last.substring(0, out.last.length - 1) + raw.trimLeft();
      continue;
    }
    out.add(raw);
  }
  return out;
}

bool _isQuotedPrintable(String line) {
  final colon = _unquotedColon(line);
  if (colon < 0) return false;
  return line.substring(0, colon).toUpperCase().contains('QUOTED-PRINTABLE');
}

/// The colon between property and value, skipping colons in quoted
/// parameter values.
int _unquotedColon(String line) {
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == '"') quoted = !quoted;
    if (c == ':' && !quoted) return i;
  }
  return -1;
}

String _decodeValue(String value, Iterable<String> params) {
  var qp = false;
  String? charset;
  for (final p in params) {
    final upper = p.trim().toUpperCase();
    if (upper == 'QUOTED-PRINTABLE' || upper == 'ENCODING=QUOTED-PRINTABLE') {
      qp = true;
    } else if (upper.startsWith('CHARSET=')) {
      charset = upper.substring(8).replaceAll('"', '');
    }
  }
  if (!qp) return value;
  final bytes = <int>[];
  for (var i = 0; i < value.length; i++) {
    final c = value[i];
    if (c == '=' && i + 2 < value.length) {
      final hex = int.tryParse(value.substring(i + 1, i + 3), radix: 16);
      if (hex != null) {
        bytes.add(hex);
        i += 2;
        continue;
      }
    }
    bytes.addAll(utf8.encode(c));
  }
  if (charset == 'ISO-8859-1' ||
      charset == 'WINDOWS-1252' ||
      charset == 'CP1252' ||
      charset == 'LATIN1') {
    return latin1.decode(bytes, allowInvalid: true);
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes, allowInvalid: true);
  }
}

/// The `;`-separated components of a structured value (N, ORG), unescaped.
List<String> _components(String value) {
  final out = <String>[];
  final buf = StringBuffer();
  for (var i = 0; i < value.length; i++) {
    final c = value[i];
    if (c == '\\' && i + 1 < value.length) {
      buf.write(c);
      buf.write(value[i + 1]);
      i++;
    } else if (c == ';') {
      out.add(_unescape(buf.toString()));
      buf.clear();
    } else {
      buf.write(c);
    }
  }
  out.add(_unescape(buf.toString()));
  return out;
}

String _unescape(String value) => value.replaceAllMapped(RegExp(r'\\(.)'), (m) {
  final c = m[1]!;
  return c == 'n' || c == 'N' ? ' ' : c;
});

String _clean(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

// ── CSV ────────────────────────────────────────────────────────────────────

const _givenHeaders = {
  'first name',
  'given name',
  'vorname',
  'prénom',
  'nombre',
};
const _middleHeaders = {
  'middle name',
  'additional name',
  'weitere vornamen',
  'zweiter vorname',
};
const _familyHeaders = {
  'last name',
  'family name',
  'surname',
  'nachname',
  'nom',
  'apellidos',
};
const _fullHeaders = {
  'name',
  'full name',
  'display name',
  'anzeigename',
  'vollständiger name',
};
const _orgHeaders = {
  'company',
  'organization name',
  'organization 1 - name',
  'organization',
  'firma',
  'unternehmen',
  'société',
  'empresa',
};

int _column(List<String> header, Set<String> names) =>
    header.indexWhere((h) => names.contains(h.trim().toLowerCase()));

/// The contacts of a CSV export (Outlook, Google, or any file with a name
/// column), columns detected from the header. Throws [FormatException]
/// (`format`) when no name column is found.
List<ContactName> parseContactCsv(String text) {
  final rows = importCsvRecords(text);
  if (rows.isEmpty) throw const FormatException('empty');
  final header = rows.first;
  final given = _column(header, _givenHeaders);
  final middle = _column(header, _middleHeaders);
  final family = _column(header, _familyHeaders);
  final full = _column(header, _fullHeaders);
  final org = _column(header, _orgHeaders);
  if (given < 0 && family < 0 && full < 0 && org < 0) {
    throw const FormatException('format');
  }
  String cell(List<String> row, int i) =>
      i < 0 || i >= row.length ? '' : _clean(row[i]);
  final contacts = <ContactName>[];
  for (final row in rows.skip(1)) {
    final first = [
      cell(row, given),
      cell(row, middle),
    ].where((s) => s.isNotEmpty).join(' ');
    final contact = ContactName(
      given: first,
      family: cell(row, family),
      full: cell(row, full),
      organization: cell(row, org),
    );
    if (contact.displayName.isEmpty && contact.organization.isEmpty) continue;
    contacts.add(contact);
  }
  return contacts;
}

// ── Candidates and plan ────────────────────────────────────────────────────

/// The dictionary candidates of [contacts]: each full name and each company,
/// once (case ignored), in file order. Given or family names alone are not
/// offered: a single name such as "Mark" or "Rose" would collide with
/// everyday words. Texts the dictionary cannot hold (longer than
/// [kDictionaryEntryMaxLength], only punctuation, a comma or a line break)
/// are left out.
List<String> contactNameCandidates(Iterable<ContactName> contacts) {
  final seen = <String>{};
  final out = <String>[];
  void add(String raw) {
    final name = _clean(raw);
    if (name.isEmpty || name.contains(',')) return;
    if (checkDictionaryEntry(name, existing: const []) != null) return;
    if (seen.add(name.toLowerCase())) out.add(name);
  }

  for (final c in contacts) {
    add(c.displayName);
    add(c.organization);
  }
  return out;
}

/// What a candidate means for the dictionary.
enum ContactImportStatus {
  /// Not in the dictionary yet; offered, preselected.
  fresh,

  /// Already a trigger or replacement of an own entry; not added again.
  existing,

  /// Already in this source's group; stays.
  kept,

  /// In this source's group but no longer in the source; offered for
  /// removal, preselected.
  dropped,
}

class ContactImportRow {
  const ContactImportRow(this.name, this.status, {this.entryId});

  final String name;
  final ContactImportStatus status;

  /// The dictionary entry of a [ContactImportStatus.dropped] or
  /// [ContactImportStatus.kept] row.
  final String? entryId;

  /// Whether the user decides about the row (add or remove).
  bool get selectable =>
      status == ContactImportStatus.fresh ||
      status == ContactImportStatus.dropped;

  @override
  String toString() => 'ContactImportRow($name, ${status.name})';
}

/// One dictionary entry as the plan sees it.
typedef ContactPlanEntry = ({
  String id,
  List<String> triggers,
  String replacement,
  String? importGroupId,
});

/// The rows of a contact import of [candidates] against the dictionary
/// [entries]. With [groupId] (an update of that source's group), the
/// group's entries that are still in the source are [kept], the others
/// [dropped]. Entries of other groups count as existing, so one name is
/// never in the dictionary twice. Candidate order first, dropped rows last.
List<ContactImportRow> planContactImport(
  List<String> candidates,
  Iterable<ContactPlanEntry> entries, {
  String? groupId,
}) {
  final group = <String, ContactPlanEntry>{};
  final taken = <String>{};
  for (final e in entries) {
    if (groupId != null && e.importGroupId == groupId) {
      group[e.replacement.trim().toLowerCase()] = e;
    } else {
      taken.add(e.replacement.trim().toLowerCase());
      for (final t in e.triggers) {
        taken.add(t.trim().toLowerCase());
      }
    }
  }
  final rows = <ContactImportRow>[];
  final inSource = <String>{};
  for (final name in candidates) {
    final key = name.trim().toLowerCase();
    if (!inSource.add(key)) continue;
    final own = group[key];
    if (own != null) {
      rows.add(
        ContactImportRow(name, ContactImportStatus.kept, entryId: own.id),
      );
    } else if (taken.contains(key)) {
      rows.add(ContactImportRow(name, ContactImportStatus.existing));
    } else {
      rows.add(ContactImportRow(name, ContactImportStatus.fresh));
    }
  }
  for (final entry in group.entries) {
    if (inSource.contains(entry.key)) continue;
    rows.add(
      ContactImportRow(
        entry.value.replacement.trim(),
        ContactImportStatus.dropped,
        entryId: entry.value.id,
      ),
    );
  }
  return rows;
}

/// Whether [rows] offer anything to add or remove. Opening the contact page
/// shows the comparison with a system source only then (#2038).
bool contactImportHasChanges(List<ContactImportRow> rows) =>
    rows.any((r) => r.selectable);

/// What a confirmed import changes: the names of the [ContactImportRow.selectable]
/// rows of [rows] the user kept selected (every index not in [excluded]),
/// split into new names to add and dropped entries to remove. Existing and
/// kept rows never change anything.
({List<String> add, List<String> removeIds}) contactImportChanges(
  List<ContactImportRow> rows,
  Set<int> excluded,
) {
  final add = <String>[];
  final removeIds = <String>[];
  for (var i = 0; i < rows.length; i++) {
    if (excluded.contains(i)) continue;
    final row = rows[i];
    if (row.status == ContactImportStatus.fresh) {
      add.add(row.name);
    } else if (row.status == ContactImportStatus.dropped) {
      removeIds.add(row.entryId!);
    }
  }
  return (add: add, removeIds: removeIds);
}
