// Parity guard for the memory reader (see lib/services/stt/memory_pressure.dart).
//
// Automatic keep-loaded and the pressure unload need a reading on every desktop
// platform. Windows reads GlobalMemoryStatusEx through dart:ffi, so the same
// contract as macOS (sysctlbyname) and Linux (/proc/meminfo) holds. A missing
// Windows branch would silently disable the pressure unload there.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _reader = 'lib/services/stt/memory_pressure.dart';

void main() {
  final source = File(_reader).readAsStringSync();

  test('readMemorySnapshot has a Windows branch', () {
    expect(source, contains('Platform.isWindows'));
  });

  test('the Windows branch calls GlobalMemoryStatusEx from kernel32', () {
    expect(source, contains("DynamicLibrary.open('kernel32.dll')"));
    expect(source, contains('lookupFunction'));
    expect(source, contains("'GlobalMemoryStatusEx'"));
  });

  test('every desktop platform has a memory reader branch', () {
    for (final branch in [
      'Platform.isLinux',
      'Platform.isMacOS',
      'Platform.isWindows',
    ]) {
      expect(source, contains(branch), reason: '$branch has no memory reader');
    }
  });
}
