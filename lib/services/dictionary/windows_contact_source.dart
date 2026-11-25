/// Names from the Windows contacts (#2038, part of #161): the system contact
/// store (Windows.ApplicationModel.Contacts, read only) as a
/// [SystemContactSource]. The native side (`windows/runner/
/// system_contacts_host.cpp`) hands over given, family and full name and the
/// company only; `system_contact_source.dart` decodes its reply. Read only
/// from the contact page, never on the hotkey path.
library;

import 'package:flutter/services.dart';

import 'contact_names.dart';
import 'system_contact_source.dart';

/// The `ContactNameGroups.sourceKind` of the Windows contacts. One group of
/// this kind at most: a later read updates it.
const String kWindowsContactsKind = 'windows';

/// Privacy page of the system setting "Contacts".
const String kWindowsContactsSettingsUri = 'ms-settings:privacy-contacts';

/// The Windows contact store through the runner's method channel.
class WindowsContactSource implements SystemContactSource {
  const WindowsContactSource({this.channel = _defaultChannel});

  static const _defaultChannel = MethodChannel('com.whispaste.system_contacts');

  final MethodChannel channel;

  @override
  String get kind => kWindowsContactsKind;

  /// Stored with the group; the page shows its own localized name for this
  /// kind.
  @override
  String get label => 'Windows';

  /// Whether access is granted shows only when reading; the page explains a
  /// refusal then.
  @override
  Future<SystemContactsAvailability> availability() async =>
      SystemContactsAvailability.available;

  @override
  Uri get settingsUri => Uri.parse(kWindowsContactsSettingsUri);

  /// Windows shows no prompt: the privacy setting decides alone.
  @override
  Future<bool> asksForAccess() async => false;

  @override
  Future<List<ContactName>> read() async {
    Object? reply;
    try {
      reply = await channel.invokeMethod<Object?>('read', {
        'limit': kContactNamesMaxContacts,
      });
    } on PlatformException {
      throw const ContactSourceException(ContactSourceFailure.unavailable);
    } on MissingPluginException {
      throw const ContactSourceException(ContactSourceFailure.unavailable);
    }
    return decodeSystemContactsReply(reply);
  }
}
