// BIZ-68: a consent lapses as soon as the provider, the context source or the
// consent text version it was given for changes. The stored record is then
// cleared, not kept as a dormant "yes".
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/app_profiles/app_profile_consent.dart';
import 'package:whispaste/services/app_profiles/app_profile_context_source.dart';

AppProfileConsent _consent({
  String provider = 'openai',
  String textVersion = kAppProfileConsentTextVersion,
}) => AppProfileConsent(
  providerId: provider,
  selectionCovered: true,
  clipboardCovered: false,
  textVersion: textVersion,
  givenAtUtc: DateTime.utc(2026, 10, 1),
);

void main() {
  test('an unchanged profile keeps its consent', () {
    final kept = consentAfterEdit(
      previous: _consent(),
      previousProvider: 'openai',
      nextProvider: 'openai',
      previousSource: AppProfileContextSource.selection,
      nextSource: AppProfileContextSource.selection,
    );
    expect(kept, isNotNull);
  });

  test('a changed provider clears the consent', () {
    final cleared = consentAfterEdit(
      previous: _consent(),
      previousProvider: 'openai',
      nextProvider: 'anthropic',
      previousSource: AppProfileContextSource.selection,
      nextSource: AppProfileContextSource.selection,
    );
    expect(cleared, isNull);
  });

  test('a changed context source clears the consent', () {
    final cleared = consentAfterEdit(
      previous: _consent(),
      previousProvider: 'openai',
      nextProvider: 'openai',
      previousSource: AppProfileContextSource.selection,
      nextSource: AppProfileContextSource.clipboard,
    );
    expect(cleared, isNull);
  });

  test('a consent given for an older text version is cleared on save', () {
    final cleared = consentAfterEdit(
      previous: _consent(textVersion: 'v0'),
      previousProvider: 'openai',
      nextProvider: 'openai',
      previousSource: AppProfileContextSource.selection,
      nextSource: AppProfileContextSource.selection,
    );
    expect(cleared, isNull);
  });

  test('no previous consent stays absent', () {
    expect(
      consentAfterEdit(
        previous: null,
        previousProvider: null,
        nextProvider: 'openai',
        previousSource: AppProfileContextSource.none,
        nextSource: AppProfileContextSource.selection,
      ),
      isNull,
    );
  });
}
