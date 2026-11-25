/// Encrypted retained recordings (#1021): format, swap and migration.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/encryption_preference.dart';
import 'package:whispaste/services/audio/encryption/recording_cipher.dart';
import 'package:whispaste/services/audio/encryption/recording_migration.dart';
import 'package:whispaste/services/audio/encryption/recording_vault.dart';

final _dataKey = List<int>.generate(32, (i) => i);

Uint8List _wav(int length) =>
    Uint8List.fromList(List<int>.generate(length, (i) => (i * 7) & 0xff));

RecordingVault _vault({
  List<int>? dataKey,
  Future<void> Function(File temp, Uint8List bytes)? writeTemp,
}) => RecordingVault(
  dataKey: () async => dataKey ?? _dataKey,
  writeTemp: writeTemp,
);

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('wp1021-vault-');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  String path(String name) => '${tmp.path}${Platform.pathSeparator}$name';

  File plainFile(String name, [int length = 4096]) =>
      File(path(name))..writeAsBytesSync(_wav(length));

  group('cipher', () {
    final key = deriveRecordingKey(_dataKey);

    test('a sealed recording opens to the same bytes', () {
      final plain = _wav(1000);
      final sealed = sealRecording(plain, key);

      expect(isSealedRecording(sealed), isTrue);
      expect(sealed.length, plain.length + sealedOverhead);
      expect(openRecording(sealed, key), plain);
    });

    test('the recording key is not the data key', () {
      expect(key, isNot(_dataKey));
      expect(key, hasLength(32));
    });

    test('a wrong key or an altered byte does not open', () {
      final sealed = sealRecording(_wav(1000), key);
      final otherKey = deriveRecordingKey(List<int>.filled(32, 9));
      expect(
        () => openRecording(sealed, otherKey),
        throwsA(isA<RecordingCipherException>()),
      );

      final tampered = Uint8List.fromList(sealed)..[500] ^= 1;
      expect(
        () => openRecording(tampered, key),
        throwsA(isA<RecordingCipherException>()),
      );

      final cut = Uint8List.sublistView(sealed, 0, sealed.length - 1);
      expect(
        () => openRecording(cut, key),
        throwsA(isA<RecordingCipherException>()),
      );
    });

    test('a plain WAV is not taken for a sealed one', () {
      expect(isSealedRecording(ascii('RIFF....WAVE')), isFalse);
      expect(isSealedRecording(const []), isFalse);
    });
  });

  group('protect and read', () {
    test('seals the file in place and reads it back as the WAV', () async {
      final file = plainFile('a.wav');
      final plain = file.readAsBytesSync();
      final vault = _vault();

      expect(await vault.protect(file.path), ProtectOutcome.sealed);

      expect(isSealedRecording(file.readAsBytesSync()), isTrue);
      expect(await vault.read(file.path), plain);
      expect(File('${file.path}$protectTempSuffix').existsSync(), isFalse);
    });

    test('is idempotent', () async {
      final file = plainFile('a.wav');
      final vault = _vault();
      await vault.protect(file.path);
      final sealed = file.readAsBytesSync();

      expect(await vault.protect(file.path), ProtectOutcome.alreadySealed);
      expect(file.readAsBytesSync(), sealed);
    });

    test('a plain file reads unchanged', () async {
      final file = plainFile('a.wav');

      expect(await _vault().read(file.path), file.readAsBytesSync());
    });

    test('without the data key the file stays plain', () async {
      final file = plainFile('a.wav');
      final plain = file.readAsBytesSync();
      final vault = RecordingVault(dataKey: () async => null);

      expect(await vault.protect(file.path), ProtectOutcome.noKey);
      expect(file.readAsBytesSync(), plain);
    });

    test('a sealed file without the right key is locked', () async {
      final file = plainFile('a.wav');
      await _vault().protect(file.path);

      await expectLater(
        RecordingVault(dataKey: () async => null).read(file.path),
        throwsA(isA<RecordingLockedException>()),
      );
      await expectLater(
        _vault(dataKey: List<int>.filled(32, 9)).read(file.path),
        throwsA(isA<RecordingLockedException>()),
      );
    });

    test('a missing file is reported, nothing is written', () async {
      expect(await _vault().protect(path('gone.wav')), ProtectOutcome.missing);
      expect(tmp.listSync(), isEmpty);
    });
  });

  group('errors and aborts keep the original', () {
    test('a failing write keeps the plain WAV and leaves no temp', () async {
      final file = plainFile('a.wav');
      final plain = file.readAsBytesSync();
      final vault = _vault(
        writeTemp: (temp, bytes) async {
          temp.writeAsBytesSync(bytes.sublist(0, 100));
          throw const FileSystemException('disk full');
        },
      );

      expect(await vault.protect(file.path), ProtectOutcome.failed);
      expect(file.readAsBytesSync(), plain);
      expect(File('${file.path}$protectTempSuffix').existsSync(), isFalse);
    });

    test('a write that loses bytes is caught by the read-back', () async {
      final file = plainFile('a.wav');
      final plain = file.readAsBytesSync();
      final vault = _vault(
        writeTemp: (temp, bytes) =>
            temp.writeAsBytes(bytes.sublist(0, bytes.length - 3)),
      );

      expect(await vault.protect(file.path), ProtectOutcome.failed);
      expect(file.readAsBytesSync(), plain);
      expect(File('${file.path}$protectTempSuffix').existsSync(), isFalse);
    });

    test('a recording evicted while sealing is not brought back', () async {
      final file = plainFile('a.wav');
      final vault = _vault(
        writeTemp: (temp, bytes) async {
          await temp.writeAsBytes(bytes, flush: true);
          await file.delete();
        },
      );

      expect(await vault.protect(file.path), ProtectOutcome.missing);
      expect(tmp.listSync(), isEmpty);
    });

    test('after an abort the migration cleans up and seals', () async {
      // An earlier run died after writing part of the temp file.
      final file = plainFile('a.wav');
      final plain = file.readAsBytesSync();
      final leftover = File('${file.path}$protectTempSuffix')
        ..writeAsBytesSync(recordingMagic + [1, 2, 3]);
      final orphan = File(path('evicted.wav$protectTempSuffix'))
        ..writeAsBytesSync([1, 2, 3]);

      final vault = _vault();
      final counts = await vault.migrate([file.path], directories: [tmp.path]);

      expect(counts, {ProtectOutcome.sealed: 1});
      expect(leftover.existsSync(), isFalse);
      expect(orphan.existsSync(), isFalse);
      expect(await vault.read(file.path), plain);
    });
  });

  group('migration', () {
    late HistoryDatabase db;

    setUp(() {
      db = HistoryDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    Future<File> attach(String entryId) async {
      final file = plainFile('$entryId.wav');
      await db.insertAudioAttachment(
        entryId: entryId,
        filePath: file.path,
        sizeBytes: file.lengthSync(),
      );
      return file;
    }

    test('seals every linked plain recording, once', () async {
      final a = await attach('e1');
      final b = await attach('e2');
      final plainA = a.readAsBytesSync();
      final vault = _vault();
      await vault.protect(b.path);
      // A WAV in the folder without a row (a recording still being written)
      // is left alone.
      final inProgress = plainFile('capturing.wav');
      final inProgressBytes = inProgress.readAsBytesSync();

      final first = await migrateRetainedRecordings(
        db: db,
        vault: vault,
        audioDir: tmp.path,
      );
      expect(first, {
        ProtectOutcome.sealed: 1,
        ProtectOutcome.alreadySealed: 1,
      });
      expect(await vault.read(a.path), plainA);
      expect(inProgress.readAsBytesSync(), inProgressBytes);

      final second = await migrateRetainedRecordings(
        db: db,
        vault: vault,
        audioDir: tmp.path,
      );
      expect(second, {ProtectOutcome.alreadySealed: 2});
    });

    test('seals parked dictations with a record and their leftovers', () async {
      final pending = Directory(path('pending'))..createSync();
      String inPending(String name) =>
          '${pending.path}${Platform.pathSeparator}$name';
      final parked = File(inPending('p1.wav'))..writeAsBytesSync(_wav(4096));
      File(inPending('p1.json')).writeAsStringSync('{}');
      // A park still moving its WAV has no record yet.
      final parking = File(inPending('p2.wav'))..writeAsBytesSync(_wav(4096));
      final leftover = File(inPending('p1.wav$protectTempSuffix'))
        ..writeAsBytesSync(_wav(10));

      final counts = await migrateRetainedRecordings(
        db: db,
        vault: _vault(),
        audioDir: tmp.path,
        pendingDir: pending.path,
      );

      expect(counts, {ProtectOutcome.sealed: 1});
      expect(isSealedRecording(parked.readAsBytesSync()), isTrue);
      expect(await recordingPlainLength(parked.path), 4096);
      expect(isSealedRecording(parking.readAsBytesSync()), isFalse);
      expect(await recordingPlainLength(parking.path), 4096);
      expect(leftover.existsSync(), isFalse);
    });

    test('after a switch the start converts once, with progress', () async {
      final a = await attach('e1');
      final b = await attach('e2');
      final plainA = a.readAsBytesSync();
      final vault = _vault();
      await vault.migrate([a.path, b.path]);
      final preference = EncryptionPreference(path('appdata'))
        ..setWanted(false);
      final seen = <EncryptionConversionProgress?>[];
      void listener() => seen.add(encryptionConversionProgress.value);
      encryptionConversionProgress.addListener(listener);
      addTearDown(() => encryptionConversionProgress.removeListener(listener));

      Future<void> run() => convertRecordingsAfterSwitch(
        db: db,
        vault: vault,
        preference: preference,
        toPlain: true,
        audioDir: tmp.path,
      );
      await run();

      expect(a.readAsBytesSync(), plainA);
      expect(isSealedRecording(b.readAsBytesSync()), isFalse);
      expect(preference.switchPending, isFalse);
      expect(seen.last, isNull);
      expect(
        seen.whereType<EncryptionConversionProgress>().map(
          (p) => '${p.done}/${p.total}',
        ),
        ['0/0', '1/2', '2/2'],
      );

      // Without the marker a later start does not run it in front again.
      seen.clear();
      await run();
      expect(seen, isEmpty);
    });

    test('without the key nothing changes and a later run seals', () async {
      final a = await attach('e1');
      final plain = a.readAsBytesSync();

      final locked = await migrateRetainedRecordings(
        db: db,
        vault: RecordingVault(dataKey: () async => null),
        audioDir: tmp.path,
      );
      expect(locked, {ProtectOutcome.noKey: 1});
      expect(a.readAsBytesSync(), plain);

      final later = await migrateRetainedRecordings(
        db: db,
        vault: _vault(),
        audioDir: tmp.path,
      );
      expect(later, {ProtectOutcome.sealed: 1});
    });
  });

  // Encryption switched off in Settings → Privacy (#1022).
  group('encryption off', () {
    test('new recordings stay plain while the session is off', () async {
      final file = plainFile('a.wav');
      final plain = file.readAsBytesSync();
      final vault = RecordingVault(
        dataKey: () async => _dataKey,
        encryptionOn: () => false,
      );

      expect(await vault.protect(file.path), ProtectOutcome.encryptionOff);
      expect(file.readAsBytesSync(), plain);
    });

    test('unprotect opens a sealed file back into the same WAV', () async {
      final file = plainFile('a.wav');
      final plain = file.readAsBytesSync();
      final vault = _vault();
      await vault.protect(file.path);

      expect(await vault.unprotect(file.path), ProtectOutcome.unsealed);
      expect(file.readAsBytesSync(), plain);
      expect(await vault.unprotect(file.path), ProtectOutcome.alreadyPlain);
      expect(tmp.listSync(), hasLength(1));
    });

    test('a failed write keeps the sealed file', () async {
      final file = plainFile('a.wav');
      await _vault().protect(file.path);
      final sealed = file.readAsBytesSync();
      final vault = _vault(
        writeTemp: (temp, bytes) =>
            temp.writeAsBytes(bytes.sublist(0, bytes.length - 3)),
      );

      expect(await vault.unprotect(file.path), ProtectOutcome.failed);
      expect(file.readAsBytesSync(), sealed);
      expect(File('${file.path}$protectTempSuffix').existsSync(), isFalse);
    });

    test('without the key or with a wrong one nothing changes', () async {
      final file = plainFile('a.wav');
      await _vault().protect(file.path);
      final sealed = file.readAsBytesSync();

      expect(
        await RecordingVault(dataKey: () async => null).unprotect(file.path),
        ProtectOutcome.noKey,
      );
      expect(
        await _vault(dataKey: List<int>.filled(32, 9)).unprotect(file.path),
        ProtectOutcome.failed,
      );
      expect(file.readAsBytesSync(), sealed);
    });

    test('migrate toPlain opens every file and reports progress', () async {
      final a = plainFile('a.wav');
      final b = plainFile('b.wav', 2048);
      final plainA = a.readAsBytesSync();
      final plainB = b.readAsBytesSync();
      final vault = _vault();
      await vault.protect(a.path);
      final progress = <String>[];

      final counts = await vault.migrate(
        [a.path, b.path],
        directories: [tmp.path],
        toPlain: true,
        onProgress: (done, total) => progress.add('$done/$total'),
      );

      expect(counts, {
        ProtectOutcome.unsealed: 1,
        ProtectOutcome.alreadyPlain: 1,
      });
      expect(progress, ['1/2', '2/2']);
      expect(a.readAsBytesSync(), plainA);
      expect(b.readAsBytesSync(), plainB);
    });
  });
}

Uint8List ascii(String s) => Uint8List.fromList(s.codeUnits);
