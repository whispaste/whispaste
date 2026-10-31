/// Unit tests for permissions_probe.dart (AC2).
library;

import 'package:test/test.dart';
import 'package:whispaste_diagnostics/src/probes/permissions_probe.dart';

void main() {
  // -------------------------------------------------------------------------
  // parseTccAllowed
  // -------------------------------------------------------------------------

  group('parseTccAllowed', () {
    test('returns true when auth_value is 2 (allowed)', () {
      expect(parseTccAllowed('2'), isTrue);
    });

    test('returns false when auth_value is 0 (denied)', () {
      expect(parseTccAllowed('0'), isFalse);
    });

    test('returns false when auth_value is 3 (limited)', () {
      expect(parseTccAllowed('3'), isFalse);
    });

    test('returns null for empty output', () {
      expect(parseTccAllowed(''), isNull);
    });

    test('returns null for null input', () {
      expect(parseTccAllowed(null), isNull);
    });

    test('handles trailing whitespace', () {
      expect(parseTccAllowed('2\n'), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // parseWindowsMicAllowed
  // -------------------------------------------------------------------------

  group('parseWindowsMicAllowed', () {
    test('returns true when Allow DWORD is 0x1', () {
      const output = '''
HKCU\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\CapabilityAccessManager\\ConsentStore\\microphone
    Allow    REG_DWORD    0x1
''';
      expect(parseWindowsMicAllowed(output), isTrue);
    });

    test('returns false when Allow DWORD is 0x0', () {
      const output = '''
HKCU\\...\\microphone
    Allow    REG_DWORD    0x0
''';
      expect(parseWindowsMicAllowed(output), isFalse);
    });

    test('returns null for null input', () {
      expect(parseWindowsMicAllowed(null), isNull);
    });

    test('returns null when Allow key is absent', () {
      expect(parseWindowsMicAllowed('some unrelated output'), isNull);
    });

    test('parses decimal value 1 as true', () {
      const output = '    Allow    REG_DWORD    1\n';
      expect(parseWindowsMicAllowed(output), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // tccAllowedQuery
  // -------------------------------------------------------------------------

  group('tccAllowedQuery', () {
    test('contains the service name', () {
      final q = tccAllowedQuery('kTCCServiceMicrophone');
      expect(q, contains('kTCCServiceMicrophone'));
    });

    test('contains com.silvio.whispaste', () {
      final q = tccAllowedQuery('kTCCServiceAccessibility');
      expect(q, contains('com.silvio.whispaste'));
    });
  });

  // -------------------------------------------------------------------------
  // gatherPermissionsProbe with injectable seams (stale-TCC cases)
  // -------------------------------------------------------------------------

  group('gatherPermissionsProbe via seams', () {
    tearDown(() {
      // Reset seams after each test.
      setTccRunnerForTesting(null);
      setAXTrustedCheckerForTesting(null);
      setRegistryReaderForTesting(null);
    });

    test('stale-TCC detected: TCC allowed but AXTrusted false', () async {
      // TCC says accessibility is allowed (auth_value = 2),
      // but AXIsProcessTrusted returns false → stale TCC.
      setTccRunnerForTesting((db, sql) async {
        if (sql.contains('kTCCServiceAccessibility')) return '2\n';
        if (sql.contains('kTCCServiceAppleEvents')) return '2\n';
        if (sql.contains('kTCCServiceMicrophone')) return '2\n';
        return null;
      });
      setAXTrustedCheckerForTesting(() async => false);

      final result = await gatherPermissionsProbe();

      // Stale-TCC = TCC ON but AX runtime OFF.
      expect(result.macosAccessibilityStale, isTrue);
      expect(result.macosAccessibilityGranted, isFalse);
    });

    test('normal granted: TCC allowed and AXTrusted true', () async {
      setTccRunnerForTesting((db, sql) async => '2\n');
      setAXTrustedCheckerForTesting(() async => true);

      final result = await gatherPermissionsProbe();

      expect(result.macosAccessibilityGranted, isTrue);
      expect(result.macosAccessibilityStale, isFalse);
    });

    test('denied: TCC denied (auth_value 0) and AXTrusted false', () async {
      setTccRunnerForTesting((db, sql) async => '0\n');
      setAXTrustedCheckerForTesting(() async => false);

      final result = await gatherPermissionsProbe();

      expect(result.macosAccessibilityGranted, isFalse);
      // Not stale — TCC is not toggled ON.
      expect(result.macosAccessibilityStale, isFalse);
    });

    test('microphone granted when TCC returns 2', () async {
      setTccRunnerForTesting((db, sql) async => '2\n');
      setAXTrustedCheckerForTesting(() async => true);

      final result = await gatherPermissionsProbe();
      expect(result.macosMicGranted, isTrue);
    });

    test('microphone denied when TCC returns 0', () async {
      setTccRunnerForTesting((db, sql) async {
        if (sql.contains('kTCCServiceMicrophone')) return '0\n';
        return '2\n';
      });
      setAXTrustedCheckerForTesting(() async => true);

      final result = await gatherPermissionsProbe();
      expect(result.macosMicGranted, isFalse);
    });
  });
}
