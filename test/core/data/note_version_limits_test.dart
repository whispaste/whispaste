/// Pure rules for note version history (WP-31a): count and byte bounds,
/// newest version kept, identical snapshots skipped.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/note_version_limits.dart';

void main() {
  group('noteVersionIdsToPrune', () {
    test('keeps everything under the count and byte limits', () {
      final ids = noteVersionIdsToPrune([
        const NoteVersionSize(id: 'v3', sizeBytes: 10),
        const NoteVersionSize(id: 'v2', sizeBytes: 10),
        const NoteVersionSize(id: 'v1', sizeBytes: 10),
      ]);
      expect(ids, isEmpty);
    });

    test('drops the oldest versions beyond maxCount', () {
      const limits = NoteVersionLimits(maxCount: 3);
      final newestFirst = [
        for (var i = 10; i >= 1; i--) NoteVersionSize(id: 'v$i', sizeBytes: 1),
      ];
      final ids = noteVersionIdsToPrune(newestFirst, limits: limits);
      expect(ids, ['v7', 'v6', 'v5', 'v4', 'v3', 'v2', 'v1']);
    });

    test('drops the oldest versions beyond the byte budget', () {
      const limits = NoteVersionLimits(maxCount: 100, maxTotalBytes: 100);
      final ids = noteVersionIdsToPrune(const [
        NoteVersionSize(id: 'new', sizeBytes: 60),
        NoteVersionSize(id: 'mid', sizeBytes: 30),
        NoteVersionSize(id: 'old', sizeBytes: 30),
      ], limits: limits);
      expect(ids, ['old']);
    });

    test('never prunes the newest version, even above the byte budget', () {
      const limits = NoteVersionLimits(maxCount: 100, maxTotalBytes: 10);
      final ids = noteVersionIdsToPrune(const [
        NoteVersionSize(id: 'new', sizeBytes: 50),
        NoteVersionSize(id: 'old', sizeBytes: 5),
      ], limits: limits);
      expect(ids, ['old']);
      expect(ids, isNot(contains('new')));
    });
  });

  group('shouldStoreNoteVersion', () {
    test('stores the first snapshot of a note', () {
      expect(
        shouldStoreNoteVersion(
          title: null,
          content: 'Hallo',
          newestTitle: null,
          newestContent: null,
          hasNewest: false,
        ),
        isTrue,
      );
    });

    test('skips a snapshot identical to the newest stored one', () {
      expect(
        shouldStoreNoteVersion(
          title: 'T',
          content: 'Hallo',
          newestTitle: 'T',
          newestContent: 'Hallo',
          hasNewest: true,
        ),
        isFalse,
      );
    });

    test('stores when only the title changed', () {
      expect(
        shouldStoreNoteVersion(
          title: 'Neu',
          content: 'Hallo',
          newestTitle: 'Alt',
          newestContent: 'Hallo',
          hasNewest: true,
        ),
        isTrue,
      );
    });

    test('skips a snapshot above the per-version size limit', () {
      const limits = NoteVersionLimits(maxVersionBytes: 10);
      expect(
        shouldStoreNoteVersion(
          title: null,
          content: 'x' * 100,
          newestTitle: null,
          newestContent: null,
          hasNewest: false,
          limits: limits,
        ),
        isFalse,
      );
    });
  });
}
