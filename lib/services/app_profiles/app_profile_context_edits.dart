/// Context-source decisions for the profile editor (R7-7): which consent a
/// context source needs, and what a grant leaves behind. The editor asks the
/// user and saves the result; it never reads the source itself.
library;

import 'app_profile.dart';
import 'app_profile_consent.dart';

/// The context-source rules as one extension on the profile.
extension AppProfileContextEdits on AppProfile {
  /// The stored context source by name, for the choice control.
  String get contextSourceName => contextSource.name;

  /// Whether the profile sends any context at all.
  bool get hasContextSource => contextSource != AppProfileContextSource.none;

  /// Whether the stored consent covers the current source for [providerId].
  bool consentCoversContext(String providerId) =>
      hasContextSource &&
      (consent?.covers(currentProviderId: providerId, source: contextSource) ??
          false);

  /// The consent that stays after storing [source] for [providerId].
  AppProfileConsent? consentAfterContextEdit(
    AppProfileContextSource source,
    String providerId,
  ) => consentAfterEdit(
    previous: consent,
    previousProvider: consent?.providerId,
    nextProvider: providerId,
    previousSource: contextSource,
    nextSource: source,
  );

  /// Whether storing [source] needs a fresh grant from the user first.
  bool contextEditNeedsGrant(
    AppProfileContextSource source,
    String providerId,
  ) {
    if (source == AppProfileContextSource.none) return false;
    final kept = consentAfterContextEdit(source, providerId);
    return !(kept?.covers(currentProviderId: providerId, source: source) ??
        false);
  }

  /// The consent after the user agreed to [source] for [providerId].
  AppProfileConsent grantContextConsent(
    AppProfileContextSource source,
    String providerId,
  ) {
    final kept = consentAfterContextEdit(source, providerId);
    return AppProfileConsent(
      providerId: providerId,
      selectionCovered:
          source == AppProfileContextSource.selection ||
          (kept?.selectionCovered ?? false),
      clipboardCovered:
          source == AppProfileContextSource.clipboard ||
          (kept?.clipboardCovered ?? false),
      textVersion: kAppProfileConsentTextVersion,
      givenAtUtc: DateTime.now().toUtc(),
    );
  }
}
