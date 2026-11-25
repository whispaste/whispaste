// loam-ignore: circular-dependencies – system_contact_source.dart holds both the SystemContactSource base and the platform pick; splitting base and factory is left until after the release
/// Names from the macOS contacts (#2037, part of #161): the Contacts
/// framework (CNContactStore) as a [SystemContactSource]. The native side
/// (`macos/Runner/SystemContactsHost.swift`) fetches only the name keys and
/// the company and hands over given, family and full name and the company;
/// `system_contact_source.dart` decodes its reply.
///
/// macOS asks for access once (TCC prompt with `NSContactsUsageDescription`).
/// The page asks for consent in the app first ([asksForAccess]), so the
/// prompt never comes out of the blue, and the comparison on opening the
/// page never triggers it.
library;

import 'package:flutter/services.dart';

import 'contact_names.dart';
import 'system_contact_source.dart';

/// The `ContactNameGroups.sourceKind` of the macOS contacts. One group of
/// this kind at most: a later read updates it.
const String kMacContactsKind = 'macos';

/// System Settings › Privacy & Security › Contacts.
const String kMacContactsSettingsUri =
    'x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts';

/// The macOS contact store through the runner's method channel.
class MacContactSource implements SystemContactSource {
  const MacContactSource({this.channel = _defaultChannel});

  static const _defaultChannel = MethodChannel('com.whispaste.system_contacts');

  final MethodChannel channel;

  @override
  String get kind => kMacContactsKind;

  /// Stored with the group; the page shows its own localized name for this
  /// kind.
  @override
  String get label => 'macOS';

  @override
  Uri get settingsUri => Uri.parse(kMacContactsSettingsUri);

  /// Whether access is granted shows only on reading (or before it, in
  /// [asksForAccess]); the page explains a refusal then.
  @override
  Future<SystemContactsAvailability> availability() async =>
      SystemContactsAvailability.available;

  /// Whether access was never asked (or reset): only then macOS shows its
  /// prompt on the next [read]. A host that does not answer counts as
  /// asking, so nothing is read without the user's step.
  @override
  Future<bool> asksForAccess() async {
    try {
      final status = await channel.invokeMethod<String>('status');
      return status == null || status == 'notDetermined';
    } on PlatformException {
      return true;
    } on MissingPluginException {
      return true;
    }
  }

  /// Reads the contacts; asks macOS for access first when it was never
  /// asked. Call only after the user's step in the app.
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
