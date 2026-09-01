import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/persisted_l10n.dart';
import 'package:whispaste/core/l10n/persisted_locale.dart';

void main() {
  late Directory tempDir;
  late File mirror;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('wp_locale_mirror');
    mirror = File('${tempDir.path}/locale');
    localeMirrorPathOverride = mirror.path;
  });

  tearDown(() {
    localeMirrorPathOverride = null;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('locale mirror', () {
    test('round-trips a supported code', () {
      writeLocaleMirror('de');
      expect(readLocaleMirror(), 'de');
    });

    test('reads null when no mirror exists', () {
      expect(readLocaleMirror(), isNull);
    });

    test('ignores an empty or null value instead of clearing the mirror', () {
      writeLocaleMirror('he');
      writeLocaleMirror(null);
      writeLocaleMirror('');
      writeLocaleMirror('   ');
      expect(readLocaleMirror(), 'he');
    });

    test('does not rewrite an unchanged value', () {
      writeLocaleMirror('de');
      final firstWrite = mirror.lastModifiedSync();
      mirror.setLastModifiedSync(firstWrite.subtract(const Duration(days: 1)));
      final stamped = mirror.lastModifiedSync();

      writeLocaleMirror('de');

      expect(mirror.lastModifiedSync(), stamped);
    });

    test('creates the parent directory on first write', () {
      final nested = '${tempDir.path}/does/not/exist/locale';
      localeMirrorPathOverride = nested;

      writeLocaleMirror('en');

      expect(File(nested).existsSync(), isTrue);
      expect(readLocaleMirror(), 'en');
    });

    test('a broken mirror path never throws', () {
      // A directory where the file is expected: every read/write must swallow
      // the FileSystemException — a secondary engine must boot regardless.
      final asDirectory = '${tempDir.path}/locale_dir';
      Directory(asDirectory).createSync();
      localeMirrorPathOverride = asDirectory;

      expect(() => writeLocaleMirror('de'), returnsNormally);
      expect(readLocaleMirror(), isNull);
    });
  });

  group('resolvePersistedL10n', () {
    test('resolves the mirrored locale', () async {
      writeLocaleMirror('de');
      final l10n = await resolvePersistedL10n();
      expect(l10n.localeName, 'de');
    });

    test('falls back to English when nothing is mirrored', () async {
      final l10n = await resolvePersistedL10n();
      expect(l10n.localeName, 'en');
    });

    test('falls back to English for an unsupported code', () async {
      writeLocaleMirror('fr');
      final l10n = await resolvePersistedL10n();
      expect(l10n.localeName, 'en');
    });

    // Regression guard for the 2026-09-01 `EXC_BAD_ACCESS` inside
    // `sqlite3Close` (crash report WhisPaste-2026-09-01-135123.ips).
    //
    // The crash needs a second, independently `dlopen`ed copy of
    // `sqlite3.framework` in the process, which a lazily booted secondary
    // Flutter engine produces once the bundle's binary has been replaced on
    // disk under the running app. The only thing that made those engines touch
    // SQLite at all was this function opening (and closing) an ad-hoc
    // `HistoryDatabase` to read one row.
    //
    // A native SIGSEGV cannot be provoked from a Dart test, so this asserts the
    // property that removes the precondition: the secondary-engine locale path
    // resolves without any database work. Reading no rows means opening no
    // connection, and opening no connection means never closing one.
    test('resolves without opening a database', () async {
      writeLocaleMirror('he');
      final dbFilesBefore = tempDir.listSync().map((e) => e.path).toSet();

      final l10n = await resolvePersistedL10n();

      expect(l10n.localeName, 'he');
      expect(tempDir.listSync().map((e) => e.path).toSet(), dbFilesBefore);
    });
  });

  group('HistoryDatabase keeps the mirror in sync', () {
    late HistoryDatabase db;

    setUp(() => db = HistoryDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('writeAppSettings mirrors the locale', () async {
      await db.writeAppSettings({'locale': 'he', 'theme': 'dark'});
      expect(readLocaleMirror(), 'he');
    });

    test('readAppSettings heals a missing mirror', () async {
      await db.customStatement(
        'INSERT INTO app_settings (key, value) VALUES (?, ?)',
        ['locale', 'de'],
      );
      expect(readLocaleMirror(), isNull);

      await db.readAppSettings();

      expect(readLocaleMirror(), 'de');
    });

    test(
      'a settings write without a locale leaves the mirror intact',
      () async {
        writeLocaleMirror('de');
        await db.writeAppSettings({'theme': 'dark'});
        expect(readLocaleMirror(), 'de');
      },
    );
  });
}
