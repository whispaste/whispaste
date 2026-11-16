import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/system_user_name.dart';

void main() {
  group('extractFirstName', () {
    test('takes the first token of a full name', () {
      expect(
        extractFirstName('Silvio Lindstedt', loginName: 'silvio'),
        'Silvio',
      );
      expect(extractFirstName('  Anna  Maria Weber ', loginName: 'aw'), 'Anna');
    });

    test('GECOS keeps only the part before the first comma', () {
      expect(
        extractFirstName('Maik Gräfendorf,Room 2,+49 123,', loginName: 'maik'),
        'Maik',
      );
      expect(extractFirstName(',,,', loginName: 'maik'), isNull);
    });

    test('Windows display name in directory form yields the given name', () {
      expect(
        extractFirstName(
          'Lindstedt, Silvio',
          loginName: 'slindstedt',
          windowsDisplayName: true,
        ),
        'Silvio',
      );
    });

    test('empty and missing values are null', () {
      expect(extractFirstName(null), isNull);
      expect(extractFirstName(''), isNull);
      expect(extractFirstName('   '), isNull);
    });

    test('a value equal to the login name is null', () {
      expect(extractFirstName('silvio', loginName: 'silvio'), isNull);
      expect(extractFirstName('JDoe', loginName: 'JDoe'), isNull);
      // A capitalised full name is chosen, even when it spells the login.
      expect(extractFirstName('Silvio', loginName: 'silvio'), 'Silvio');
    });

    test('a single lowercase word counts as a login name', () {
      expect(extractFirstName('jdoe', loginName: 'other'), isNull);
    });

    test('generic account names are null', () {
      for (final name in const [
        'root',
        'User',
        'Administrator',
        'Guest',
        'Gast',
        'Benutzer',
        'Owner',
      ]) {
        expect(extractFirstName(name, loginName: 'x'), isNull, reason: name);
      }
      expect(extractFirstName('System Administrator'), isNull);
      expect(extractFirstName('Administrator Konto'), isNull);
    });

    test('leading titles are skipped', () {
      expect(extractFirstName('Dr. Eva Schmidt', loginName: 'eva'), 'Eva');
    });
  });
}
