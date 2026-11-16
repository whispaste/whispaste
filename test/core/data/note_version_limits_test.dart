/// Pure rules for note version history (ticket): count and byte bounds,
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
      const limits = NoteVersionLimits(
        maxCount: 100,
        maxTotalBytes: 100,
        minKeep: 1,
      );
      final ids = noteVersionIdsToPrune(const [
        NoteVersionSize(id: 'new', sizeBytes: 60),
        NoteVersionSize(id: 'mid', sizeBytes: 30),
        NoteVersionSize(id: 'old', sizeBytes: 30),
      ], limits: limits);
      expect(ids, ['old']);
    });

    test('never prunes the newest version, even above the byte budget', () {
      const limits = NoteVersionLimits(
        maxCount: 100,
        maxTotalBytes: 10,
        minKeep: 1,
      );
      final ids = noteVersionIdsToPrune(const [
        NoteVersionSize(id: 'new', sizeBytes: 50),
        NoteVersionSize(id: 'old', sizeBytes: 5),
      ], limits: limits);
      expect(ids, ['old']);
      expect(ids, isNot(contains('new')));
    });
  });

  group('decideNoteVersion', () {
    test('stores the first snapshot of a note', () {
      expect(
        decideNoteVersion(
          title: null,
          content: 'Hallo',
          newestTitle: null,
          newestContent: null,
          hasNewest: false,
        ),
        NoteVersionOutcome.stored,
      );
    });

    test('skips a snapshot identical to the newest stored one', () {
      expect(
        decideNoteVersion(
          title: 'T',
          content: 'Hallo',
          newestTitle: 'T',
          newestContent: 'Hallo',
          hasNewest: true,
        ),
        NoteVersionOutcome.unchanged,
      );
    });

    test('stores when only the title changed', () {
      expect(
        decideNoteVersion(
          title: 'Neu',
          content: 'Hallo',
          newestTitle: 'Alt',
          newestContent: 'Hallo',
          hasNewest: true,
        ),
        NoteVersionOutcome.stored,
      );
    });

    test('reports a snapshot above the per-version size limit', () {
      const limits = NoteVersionLimits(maxVersionChars: 10);
      expect(
        decideNoteVersion(
          title: null,
          content: 'x' * 100,
          newestTitle: null,
          newestContent: null,
          hasNewest: false,
          limits: limits,
        ),
        NoteVersionOutcome.tooLarge,
      );
    });
  });

  group('minKeep', () {
    test('the newest versions survive the byte budget', () {
      const limits = NoteVersionLimits(
        maxCount: 50,
        maxTotalBytes: 100,
        minKeep: 3,
      );
      final ids = noteVersionIdsToPrune([
        for (var i = 5; i >= 1; i--) NoteVersionSize(id: 'v$i', sizeBytes: 80),
      ], limits: limits);
      expect(ids, ['v2', 'v1']);
    });

    test('without minKeep the same budget would drop them', () {
      const limits = NoteVersionLimits(
        maxCount: 50,
        maxTotalBytes: 100,
        minKeep: 1,
      );
      final ids = noteVersionIdsToPrune([
        for (var i = 5; i >= 1; i--) NoteVersionSize(id: 'v$i', sizeBytes: 80),
      ], limits: limits);
      expect(ids, ['v4', 'v3', 'v2', 'v1']);
    });

    test('the hard ceiling also limits the protected versions', () {
      const limits = NoteVersionLimits(
        maxCount: 50,
        maxTotalBytes: 100,
        minKeep: 20,
        hardMaxTotalBytes: 200,
      );
      final ids = noteVersionIdsToPrune([
        for (var i = 5; i >= 1; i--) NoteVersionSize(id: 'v$i', sizeBytes: 80),
      ], limits: limits);
      // 80 + 80 fit under 200, the third would reach 240.
      expect(ids, ['v3', 'v2', 'v1']);
    });
  });

  group('body encoding', () {
    test('short text stays plain', () {
      expect(encodeNoteVersionBody('kurz'), 'kurz');
      expect(decodeNoteVersionBody('kurz'), 'kurz');
    });

    test('long text round-trips through compression', () {
      final text = 'Äußerst lange Zeile mit Umlauten und 日本語. ' * 500;
      final stored = encodeNoteVersionBody(text);
      expect(stored, startsWith(kNoteVersionGzipMarker));
      expect(stored.length, lessThan(text.length));
      expect(decodeNoteVersionBody(stored), text);
    });

    test('a short text that starts like the marker round-trips too', () {
      const text = '${kNoteVersionGzipMarker}kein Archiv';
      expect(decodeNoteVersionBody(encodeNoteVersionBody(text)), text);
    });

    test('a broken packed body is returned as it is', () {
      const broken = '$kNoteVersionGzipMarker!!!';
      expect(decodeNoteVersionBody(broken), broken);
    });
  });
}
