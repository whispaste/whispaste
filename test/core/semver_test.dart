import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/semver.dart';

void main() {
  group('parseSemver', () {
    test('parses standard X.Y.Z', () {
      final v = parseSemver('1.2.3')!;
      expect(v.core, [1, 2, 3]);
      expect(v.preRelease, isNull);
    });

    test('strips leading v', () {
      expect(parseSemver('v1.2.3')!.core, [1, 2, 3]);
    });

    test('captures the pre-release suffix', () {
      final v = parseSemver('1.2.3-beta.1')!;
      expect(v.core, [1, 2, 3]);
      expect(v.preRelease, 'beta.1');
    });

    test('strips build metadata but keeps pre-release', () {
      final v = parseSemver('1.2.3-beta.1+42')!;
      expect(v.core, [1, 2, 3]);
      expect(v.preRelease, 'beta.1');
    });

    test('returns null for too few segments', () {
      expect(parseSemver('1.2'), isNull);
    });

    test('returns null for non-numeric core', () {
      expect(parseSemver('abc.def.ghi'), isNull);
    });
  });

  group('isSemverNewer — the PRD Bug 3/4 regression', () {
    test('higher beta build number IS newer (the bug: this used to be '
        'false because -beta.N was stripped before comparing)', () {
      expect(isSemverNewer('1.2.44-beta.6', '1.2.44-beta.5'), isTrue);
    });

    test('a plain release outranks a beta of the same core', () {
      expect(isSemverNewer('1.2.44', '1.2.44-beta.6'), isTrue);
      expect(isSemverNewer('1.2.44-beta.6', '1.2.44'), isFalse);
    });

    test('higher core version is newer regardless of pre-release', () {
      expect(isSemverNewer('1.2.45-beta.1', '1.2.44-beta.9'), isTrue);
    });

    test('equal versions are not newer', () {
      expect(isSemverNewer('1.2.3', '1.2.3'), isFalse);
      expect(isSemverNewer('1.2.3-beta.1', '1.2.3-beta.1'), isFalse);
    });

    test('lower beta build number is not newer', () {
      expect(isSemverNewer('1.2.44-beta.1', '1.2.44-beta.2'), isFalse);
    });

    test('build metadata never affects precedence', () {
      expect(isSemverNewer('1.2.0+5', '1.2.0+3'), isFalse);
    });

    test('returns false for an unparseable candidate or current', () {
      expect(isSemverNewer('bad', '1.2.3'), isFalse);
      expect(isSemverNewer('1.2.3', 'bad'), isFalse);
    });
  });
}
