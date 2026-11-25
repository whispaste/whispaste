/// Names from the local classic Outlook (#2039, part of #161): the contacts
/// folders of the Outlook running on this computer as a [ContactNameSource].
/// The native side (`windows/runner/outlook_contacts_reader.cpp`, method
/// `readOutlook` of the contact host) attaches to a running Outlook over
/// COM, never starts one, never uses Microsoft Graph or an account, and
/// reads only members that raise no Outlook security prompt. It hands over
/// given, family and full name and the company only; this file turns its
/// reply into [ContactName]s and its failures into a
/// [ContactSourceException] the contact page explains with a next step
/// (mostly: export a CSV from Outlook and choose the file). Read only from
/// the contact page on the user's click, never on the hotkey path and never
/// when the page opens.
library;

import 'dart:async';

import 'package:flutter/services.dart';

import 'contact_names.dart';
import 'system_contact_source.dart';

/// The `ContactNameGroups.sourceKind` of the Outlook contacts. One group of
/// this kind at most: a later read updates it.
const String kOutlookContactsKind = 'outlook';

/// How long the page waits for Outlook. A large address book answers in a
/// few seconds; longer means Outlook hangs on a dialog.
const Duration kOutlookContactsTimeout = Duration(seconds: 60);

/// The local classic Outlook through the runner's contact channel.
class OutlookContactSource implements SystemContactSource {
  const OutlookContactSource({
    this.channel = _defaultChannel,
    this.timeout = kOutlookContactsTimeout,
  });

  static const _defaultChannel = MethodChannel('com.whispaste.system_contacts');

  final MethodChannel channel;
  final Duration timeout;

  @override
  String get kind => kOutlookContactsKind;

  /// Stored with the group; the page shows its own localized name for this
  /// kind.
  @override
  String get label => 'Outlook';

  /// Always offered on Windows: whether a classic Outlook is installed and
  /// open is only known by asking it, and that happens on a click only. A
  /// read without it explains the CSV export as the way out.
  @override
  Future<SystemContactsAvailability> availability() async =>
      SystemContactsAvailability.available;

  /// Outlook has no privacy setting of its own to send the user to.
  @override
  Uri? get settingsUri => null;

  /// Reading never brings up a system access prompt; Outlook prompts are
  /// avoided by reading only members that raise none.
  @override
  Future<bool> asksForAccess() async => false;

  @override
  Future<List<ContactName>> read() async {
    Object? reply;
    try {
      reply = await channel
          .invokeMethod<Object?>('readOutlook', {
            'limit': kContactNamesMaxContacts,
          })
          .timeout(timeout);
    } on TimeoutException {
      throw const ContactSourceException(ContactSourceFailure.busy);
    } on PlatformException {
      throw const ContactSourceException(ContactSourceFailure.unavailable);
    } on MissingPluginException {
      throw const ContactSourceException(ContactSourceFailure.unavailable);
    }
    return decodeOutlookContactsReply(reply);
  }
}

/// The contacts of a `readOutlook` reply of the native contact host, with
/// the same filtering as the Windows contacts ([decodeSystemContactList]).
/// Throws [ContactSourceException] for every status but `ok`; an unknown
/// status is [ContactSourceFailure.unavailable].
List<ContactName> decodeOutlookContactsReply(Object? reply) {
  if (reply is! Map) {
    throw const ContactSourceException(ContactSourceFailure.unavailable);
  }
  final failure = switch (reply['status']) {
    'ok' => null,
    'notInstalled' => ContactSourceFailure.notInstalled,
    'notRunning' => ContactSourceFailure.notRunning,
    'busy' => ContactSourceFailure.busy,
    'tooMany' => ContactSourceFailure.tooMany,
    _ => ContactSourceFailure.unavailable,
  };
  if (failure != null) throw ContactSourceException(failure);
  return decodeSystemContactList(reply['contacts']);
}
