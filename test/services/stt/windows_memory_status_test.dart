import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/stt/memory_pressure.dart';

/// Builds a 64-byte MEMORYSTATUSEX buffer as GlobalMemoryStatusEx fills it.
ByteData _memoryStatusEx({required int totalPhys, required int availPhys}) {
  final data = ByteData(64)..setUint32(0, 64, Endian.little);
  data
    ..setUint32(4, 50, Endian.little)
    ..setUint64(8, totalPhys, Endian.little)
    ..setUint64(16, availPhys, Endian.little);
  return data;
}

void main() {
  const mb = 1024 * 1024;

  group('parseWindowsMemoryStatus', () {
    test('reads ullTotalPhys and ullAvailPhys at their offsets in MB', () {
      final snapshot = parseWindowsMemoryStatus(
        _memoryStatusEx(totalPhys: 16384 * mb, availPhys: 4096 * mb),
      );
      expect(snapshot?.totalMB, 16384);
      expect(snapshot?.availableMB, 4096);
    });

    test('ignores dwMemoryLoad (offset 4) and the page-file fields', () {
      final data = _memoryStatusEx(totalPhys: 8192 * mb, availPhys: 1024 * mb)
        ..setUint32(4, 99, Endian.little)
        ..setUint64(24, 1, Endian.little);
      final snapshot = parseWindowsMemoryStatus(data);
      expect(snapshot?.totalMB, 8192);
      expect(snapshot?.availableMB, 1024);
    });

    test('returns null for a buffer shorter than the fields it reads', () {
      expect(parseWindowsMemoryStatus(ByteData(20)), isNull);
    });

    test('returns null when the total is zero', () {
      expect(
        parseWindowsMemoryStatus(_memoryStatusEx(totalPhys: 0, availPhys: 0)),
        isNull,
      );
    });

    test('clamps available memory to the total', () {
      final snapshot = parseWindowsMemoryStatus(
        _memoryStatusEx(totalPhys: 4096 * mb, availPhys: 9000 * mb),
      );
      expect(snapshot?.availableMB, 4096);
    });

    test('feeds the same pressure classification as macOS and Linux', () {
      final low = parseWindowsMemoryStatus(
        _memoryStatusEx(totalPhys: 16384 * mb, availPhys: 1024 * mb),
      );
      expect(classifyMemoryPressure(low), MemoryPressure.low);
      final normal = parseWindowsMemoryStatus(
        _memoryStatusEx(totalPhys: 16384 * mb, availPhys: 8192 * mb),
      );
      expect(classifyMemoryPressure(normal), MemoryPressure.normal);
    });
  });
}
