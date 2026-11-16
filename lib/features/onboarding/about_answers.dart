/// The rules behind the "Über dich" questions (onboarding screen 2) and the
/// one-time follow-up card in the Übersicht: which answers count, when Next is
/// free, and who is asked again. Pure, so the rules are tested without a
/// widget tree; the page and the card only draw them.
library;

import '../../core/config/settings_sections.dart' show OnboardingSettings;

/// The answer "Keine Angabe". It is stored like any other id and counts as a
/// choice: whoever picks it has answered.
const String kAboutDeclined = 'declined';

/// Role ids of the "Wofür nutzt du WhisPaste?" chips, in display order,
/// without [kAboutDeclined]. They match `OnboardingRole` of the telemetry
/// service.
const List<String> kOnboardingAboutRoles = [
  'writing',
  'dev',
  'legal',
  'education',
  'business',
  'other',
];

/// Ids of the "Wie hast du uns gefunden?" chips, in display order, without
/// [kAboutDeclined]. They match `OnboardingAttribution` of the telemetry
/// service.
const List<String> kOnboardingAboutSources = [
  'search',
  'ai',
  'friend',
  'store',
  'social',
  'video',
  'github',
  'other',
];

/// Confirmed dictations before the follow-up card asks again.
const int kAboutFollowUpDictations = 10;

/// The two questions of the page; the follow-up card asks them in this order.
enum AboutQuestion { role, source }

/// The stored role answer as a set of ids.
Set<String> aboutRoles(String stored) =>
    stored.isEmpty ? const <String>{} : stored.split(',').toSet();

/// The stored form of [roles]: known ids in display order, comma-separated.
/// [kAboutDeclined] stands alone.
String storeAboutRoles(Set<String> roles) => roles.contains(kAboutDeclined)
    ? kAboutDeclined
    : [
        for (final r in kOnboardingAboutRoles)
          if (roles.contains(r)) r,
      ].join(',');

/// Toggles [id] in [roles]. "Keine Angabe" excludes every role and a role
/// lifts "Keine Angabe", so the answer is never both.
Set<String> toggleAboutRole(Set<String> roles, String id) {
  if (id == kAboutDeclined) {
    return roles.contains(kAboutDeclined) ? const {} : const {kAboutDeclined};
  }
  final next = {...roles}..remove(kAboutDeclined);
  if (!next.remove(id)) next.add(id);
  return next;
}

/// The source after tapping [id]: a second tap on the chosen chip clears it.
String chooseAboutSource(String current, String id) => current == id ? '' : id;

/// Whether [question] has an answer; "Keine Angabe" is one.
bool aboutAnswered(AboutQuestion question, OnboardingSettings onboarding) =>
    switch (question) {
      AboutQuestion.role => onboarding.userRoles.isNotEmpty,
      AboutQuestion.source => onboarding.userAttribution.isNotEmpty,
    };

/// The questions the follow-up card asks, role first; empty when no card is
/// due. Only an explicit "Keine Angabe" is asked again, once the onboarding is
/// done and [dictations] confirmed dictations have shown the app at work, and
/// never after the card was answered or dismissed.
List<AboutQuestion> aboutFollowUpQuestions(
  OnboardingSettings onboarding, {
  required int dictations,
}) {
  if (!onboarding.onboardingCompleted ||
      onboarding.aboutFollowUpDone ||
      dictations < kAboutFollowUpDictations) {
    return const [];
  }
  return [
    if (onboarding.userRoles == kAboutDeclined) AboutQuestion.role,
    if (onboarding.userAttribution == kAboutDeclined) AboutQuestion.source,
  ];
}
