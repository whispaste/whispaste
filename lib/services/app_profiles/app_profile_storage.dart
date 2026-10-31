/// Converts app profiles to and from their Drift rows (WP-33a).
///
/// Pure functions, so the round trip is testable without a database. Rule and
/// profile order both come from explicit `position` columns (DEV-239).
library;

import 'package:drift/drift.dart';

import '../../core/data/database.dart';
import 'app_profile.dart';
import 'app_profile_consent.dart';

/// Consent is restored only when every field is present; a partial record
/// reads as no consent (fail-closed).
AppProfileConsent? _consentFromRow(AppProfileRow row) {
  final provider = row.consentProvider;
  final version = row.consentTextVersion;
  final givenAt = row.consentGivenAt;
  if (provider == null || version == null || givenAt == null) return null;
  return AppProfileConsent(
    providerId: provider,
    selectionCovered: row.consentSelection,
    clipboardCovered: row.consentClipboard,
    textVersion: version,
    givenAtUtc: givenAt.toUtc(),
  );
}

/// Builds profiles from rows. [profileRows] and [ruleRows] are expected in
/// their stored order; rules are grouped under their profile without changing
/// that order.
List<AppProfile> appProfilesFromRows(
  List<AppProfileRow> profileRows,
  List<AppProfileRuleRow> ruleRows,
) {
  final rulesByProfile = <String, List<AppMatchRule>>{};
  for (final row in ruleRows) {
    (rulesByProfile[row.profileId] ??= []).add(
      AppMatchRule(identifier: row.identifier, teamId: row.teamId),
    );
  }
  return [
    for (final row in profileRows)
      AppProfile(
        id: row.id,
        name: row.name,
        rules: rulesByProfile[row.id] ?? const [],
        smartMode: AppProfileSmartMode.fromStorage(row.smartMode),
        asrLanguage: row.asrLanguage,
        modelId: row.modelId,
        contextSource: AppProfileContextSource.fromStorage(row.contextSource),
        consent: _consentFromRow(row),
        hotkeyKey: row.hotkeyKey,
        hotkeyModifiers: row.hotkeyModifiers,
        afterTranscription: row.afterTranscription,
        microphone: row.microphone,
      ),
  ];
}

/// The profile row for [profile] at [position]. [createdAt] is kept by the
/// caller on edits, so only the first save sets it.
AppProfilesCompanion appProfileToCompanion(
  AppProfile profile, {
  required int position,
  required DateTime createdAt,
  required DateTime updatedAt,
}) {
  return AppProfilesCompanion(
    id: Value(profile.id),
    name: Value(profile.name),
    position: Value(position),
    smartMode: Value(profile.smartMode.storageValue),
    asrLanguage: Value(profile.asrLanguage),
    modelId: Value(profile.modelId),
    contextSource: Value(profile.contextSource.storageValue),
    hotkeyKey: Value(profile.hotkeyKey),
    hotkeyModifiers: Value(profile.hotkeyModifiers),
    afterTranscription: Value(profile.afterTranscription),
    microphone: Value(profile.microphone),
    consentProvider: Value(profile.consent?.providerId),
    consentSelection: Value(profile.consent?.selectionCovered ?? false),
    consentClipboard: Value(profile.consent?.clipboardCovered ?? false),
    consentTextVersion: Value(profile.consent?.textVersion),
    consentGivenAt: Value(profile.consent?.givenAtUtc),
    createdAt: Value(createdAt),
    updatedAt: Value(updatedAt),
  );
}

/// Rule rows for [profile], positioned in list order.
List<AppProfileRulesCompanion> appProfileRulesToCompanions(AppProfile profile) {
  return [
    for (var i = 0; i < profile.rules.length; i++)
      AppProfileRulesCompanion(
        id: Value('${profile.id}#$i'),
        profileId: Value(profile.id),
        position: Value(i),
        identifier: Value(profile.rules[i].identifier),
        teamId: Value(profile.rules[i].teamId),
      ),
  ];
}
