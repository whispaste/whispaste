/// Consent for an app profile's context source (WP-33a, BIZ Art. 7(1)).
///
/// A consent is provable and specific: it names the cloud provider, the
/// source(s) it covers, the text version the user saw and the UTC time. It
/// lapses when any of those stops matching the current state: another
/// provider, another source, or a new text version.
library;

import 'app_profile_context_source.dart';
import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Version of the consent text. Bump it when [kAppProfileConsentCanonicalText]
/// changes; then every stored consent of an older version lapses. The hash
/// test pins the canonical text, so a silent wording change fails the build.
const String kAppProfileConsentTextVersion = 'v1';

/// Canonical English wording of the consent that the version refers to. The
/// localised strings in the ARB files are presentation only; the hash pins
/// this canonical text.
const String kAppProfileConsentCanonicalText =
    'When this profile is active, the selected text or the clipboard contents of the target window are sent to the cloud provider named in this profile, only to refine this dictation. You can withdraw this consent at any time in the profile settings.';

/// SHA-256 of [kAppProfileConsentCanonicalText] for version v1.
const String kAppProfileConsentTextV1Hash =
    'bda9e8d3457b82d8d5a89135adcf22fdef587b5471549c5169b2d7ef041b6d5e';

/// The consent a profile keeps after an edit (BIZ-68). A consent lapses when
/// its provider, its context source or its text version no longer matches
/// the edited profile, so it is cleared instead of kept as a dormant record.
AppProfileConsent? consentAfterEdit({
  required AppProfileConsent? previous,
  required String? previousProvider,
  required String? nextProvider,
  required AppProfileContextSource previousSource,
  required AppProfileContextSource nextSource,
}) {
  if (previous == null) return null;
  if (previousProvider != nextProvider) return null;
  if (previousSource != nextSource) return null;
  if (previous.textVersion != kAppProfileConsentTextVersion) return null;
  return previous;
}

/// SHA-256 (lower-case hex) of [text].
String appProfileConsentTextHash(String text) =>
    sha256.convert(utf8.encode(text)).toString();

/// A recorded consent for one profile.
class AppProfileConsent {
  AppProfileConsent({
    required this.providerId,
    required this.selectionCovered,
    required this.clipboardCovered,
    required this.textVersion,
    required this.givenAtUtc,
  }) : assert(givenAtUtc.isUtc, 'consent times are stored in UTC');

  /// Cloud Smart Mode provider the consent names.
  final String providerId;

  /// Whether selection context is covered (separately from clipboard).
  final bool selectionCovered;

  /// Whether clipboard context is covered.
  final bool clipboardCovered;

  /// The consent text version the user saw.
  final String textVersion;

  /// When the user confirmed, in UTC.
  final DateTime givenAtUtc;

  /// Whether this consent covers [source] for [providerId] at the current
  /// text version. Any mismatch means it has lapsed.
  bool covers({
    required String currentProviderId,
    required AppProfileContextSource source,
  }) {
    if (providerId != currentProviderId) return false;
    if (textVersion != kAppProfileConsentTextVersion) return false;
    return switch (source) {
      AppProfileContextSource.none => false,
      AppProfileContextSource.selection => selectionCovered,
      AppProfileContextSource.clipboard => clipboardCovered,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is AppProfileConsent &&
      other.providerId == providerId &&
      other.selectionCovered == selectionCovered &&
      other.clipboardCovered == clipboardCovered &&
      other.textVersion == textVersion &&
      other.givenAtUtc == givenAtUtc;

  @override
  int get hashCode => Object.hash(
    providerId,
    selectionCovered,
    clipboardCovered,
    textVersion,
    givenAtUtc,
  );
}
