import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/app_profiles/app_profile_choice.dart';
import 'package:whispaste/widgets/floating_overlay/overlay_painter.dart';

void main() {
  bool fitsAll(String _) => true;

  group('overlayChipLabelFor', () {
    test('joins the language and the profile when both fit', () {
      expect(
        overlayChipLabelFor(language: 'DE', profile: 'Mail', fits: fitsAll),
        'DE · Mail',
      );
    });

    test('drops the profile first when the joined text does not fit', () {
      expect(
        overlayChipLabelFor(
          language: 'DE',
          profile: 'Mail',
          fits: (text) => text == 'DE',
        ),
        'DE',
      );
    });

    test('shows the profile alone when there is no language', () {
      expect(
        overlayChipLabelFor(language: null, profile: 'Mail', fits: fitsAll),
        'Mail',
      );
    });

    test('shows nothing when neither part is set', () {
      expect(
        overlayChipLabelFor(language: '', profile: null, fits: fitsAll),
        isNull,
      );
    });
  });

  group('profileChipLabelFor', () {
    test('trims and shortens a long name with an ellipsis', () {
      expect(profileChipLabelFor('  Mail  '), 'Mail');
      expect(
        profileChipLabelFor('Ein sehr langer Profilname'),
        'Ein sehr lang…',
      );
    });

    test('a blank name has no chip', () {
      expect(profileChipLabelFor('   '), isNull);
    });
  });
}
