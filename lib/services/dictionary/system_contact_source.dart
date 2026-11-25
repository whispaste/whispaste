/// The address books of the operating system for the contact page (#161):
/// Windows contacts (#2038) and the local classic Outlook (#2039) on
/// Windows, macOS contacts (#2037) on the Mac; on Linux the GNOME contacts of
/// Evolution Data Server (#2040) and the KDE address book of Akonadi (#2041),
/// each offered when it is there. The Windows and macOS hosts answer on the
/// method channel `com.whispaste.system_contacts` with the same reply, which
/// [decodeSystemContactsReply] turns into [ContactName]s and its failures
/// into a [ContactSourceException] the contact page explains with a next
/// step. Read only from the contact page, never on the hotkey path.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'contact_names.dart';
import 'gnome_contact_source.dart';
import 'kde_contact_source.dart';
import 'macos_contact_source.dart';
import 'outlook_contact_source.dart';
import 'windows_contact_source.dart';

/// The system address books of this platform, the one of the running
/// desktop first; empty without any. Overridden in tests.
final systemContactSourcesProvider = Provider<List<SystemContactSource>>(
  (ref) => switch (defaultTargetPlatform) {
    TargetPlatform.windows => const [
      WindowsContactSource(),
      OutlookContactSource(),
    ],
    TargetPlatform.macOS => const [MacContactSource()],
    TargetPlatform.linux => linuxContactSources(
      Platform.environment['XDG_CURRENT_DESKTOP'] ?? '',
      gnome: GnomeContactSource(),
      kde: KdeContactSource(),
    ),
    _ => const [],
  },
);

/// The Linux address books in the order the page shows them: KDE's first on
/// a KDE desktop ([desktop] is `XDG_CURRENT_DESKTOP`), GNOME's first
/// elsewhere.
List<SystemContactSource> linuxContactSources(
  String desktop, {
  required SystemContactSource gnome,
  required SystemContactSource kde,
}) => desktop.toUpperCase().split(':').contains('KDE')
    ? [kde, gnome]
    : [gnome, kde];

/// The comparison when the contact page opens: the candidates of [source],
/// or `null` when reading would show the system access prompt (access was
/// reset or never asked). Only an explicit read in the app may lead there.
Future<List<String>?> readSystemContactsOnOpen(
  SystemContactSource source,
) async {
  if (await source.asksForAccess()) return null;
  return contactNameCandidates(await source.read());
}

/// The contacts of a `read` reply of a native contact host. Each contact
/// is a list `[given, family, full, organization]`. A field that looks like
/// an e-mail address or a phone number is dropped, so nothing but names can
/// reach the dictionary even when a contact keeps such a text in a name
/// field. Throws [ContactSourceException] for a refused or failed read; a
/// Windows read without the package identity (`packaged: false`) that does
/// not succeed is [ContactSourceFailure.unpackaged], because that is the
/// limit the user can act on.
List<ContactName> decodeSystemContactsReply(Object? reply) {
  if (reply is! Map) {
    throw const ContactSourceException(ContactSourceFailure.unavailable);
  }
  final status = reply['status'];
  final packaged = reply['packaged'] != false;
  if (status != 'ok') {
    if (status == 'tooMany') {
      throw const ContactSourceException(ContactSourceFailure.tooMany);
    }
    if (!packaged) {
      throw const ContactSourceException(ContactSourceFailure.unpackaged);
    }
    throw ContactSourceException(switch (status) {
      'denied' => ContactSourceFailure.denied,
      'restricted' => ContactSourceFailure.restricted,
      _ => ContactSourceFailure.unavailable,
    });
  }
  return decodeSystemContactList(reply['contacts']);
}

/// The contact list of a native contact reply (Windows and macOS contacts,
/// Outlook): each contact a list `[given, family, full, organization]`.
/// Fields that look like an e-mail address or a phone number are dropped,
/// contacts without any name skipped. Throws [ContactSourceException] when
/// [raw] is no list or holds more than [kContactNamesMaxContacts] contacts.
List<ContactName> decodeSystemContactList(Object? raw) {
  if (raw is! List) {
    throw const ContactSourceException(ContactSourceFailure.unavailable);
  }
  if (raw.length > kContactNamesMaxContacts) {
    throw const ContactSourceException(ContactSourceFailure.tooMany);
  }
  final out = <ContactName>[];
  for (final entry in raw) {
    if (entry is! List) continue;
    String field(int i) {
      final value = i < entry.length ? entry[i] : null;
      return value is String ? contactNameField(value) : '';
    }

    final contact = ContactName(
      given: field(0),
      family: field(1),
      full: field(2),
      organization: field(3),
    );
    if (contact.displayName.isEmpty && contact.organization.isEmpty) continue;
    out.add(contact);
  }
  return out;
}
