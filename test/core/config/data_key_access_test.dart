import 'dart:io';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/data_key_access.dart';
import 'package:whispaste/core/config/data_key_store.dart';
import 'package:whispaste/core/config/secure_key_store.dart';

/// In-memory stand-in for the system key store.
class _FakeSecureStore extends SecureKeyStore {
  _FakeSecureStore() : super(null, () async => KeyringAvailability.usable);

  final values = <String, String>{};
  Object? failWith;

  @override
  Future<String?> readKey(String key) async {
    if (failWith != null) throw failWith!;
    return values[key];
  }

  @override
  Future<void> writeKey(String key, String value) async {
    if (failWith != null) throw failWith!;
    values[key] = value;
  }

  @override
  Future<void> deleteKey(String key) async => values.remove(key);
}

void main() {
  final dirs = <Directory>[];
  late Directory dir;
  late _FakeSecureStore secure;

  void freshDir() {
    dir = Directory.systemTemp.createTempSync('wp_data_key_access_');
    dirs.add(dir);
  }

  DataKeyStore store({bool linux = false}) => DataKeyStore(
    secure,
    dataDir: () => dir.path,
    isLinux: linux,
    posix: !Platform.isWindows,
  );

  setUp(() {
    secure = _FakeSecureStore();
    freshDir();
  });
  tearDown(() {
    for (final d in dirs) {
      d.deleteSync(recursive: true);
    }
    dirs.clear();
  });

  group('dataKeyAccessStatusOf', () {
    test('system store and file fallback stay apart', () async {
      expect(
        dataKeyAccessStatusOf(await store().obtain()),
        DataKeyAccessStatus.ready,
      );
      secure.failWith = PlatformException(code: 'Libsecret error');
      freshDir();
      expect(
        dataKeyAccessStatusOf(await store(linux: true).obtain()),
        DataKeyAccessStatus.fileFallback,
      );
    });

    test('a technical store failure is failed, neither declined nor lost', () {
      expect(
        dataKeyAccessStatusOf(
          const DataKeyUnavailable(DataKeyUnavailableReason.storageFailed),
        ),
        DataKeyAccessStatus.failed,
      );
    });

    test('locked or silent keyring is reported as locked', () {
      for (final reason in [
        DataKeyUnavailableReason.keyringLocked,
        DataKeyUnavailableReason.keyringUnreachable,
      ]) {
        expect(
          dataKeyAccessStatusOf(DataKeyUnavailable(reason)),
          DataKeyAccessStatus.keyringLocked,
        );
      }
    });

    test('a missing earlier key is lost', () {
      expect(
        dataKeyAccessStatusOf(const DataKeyLost(DataKeyBackend.systemKeyStore)),
        DataKeyAccessStatus.lost,
      );
    });
  });

  test(
    'recorded backend follows the marker without asking the store',
    () async {
      expect(store().recordedBackend(), isNull);
      await store().obtain();
      secure.failWith = StateError('store must not be asked');
      expect(store().recordedBackend(), DataKeyBackend.systemKeyStore);
      expect(
        dataKeyStatusFromMarker(store().recordedBackend()),
        DataKeyAccessStatus.ready,
      );
    },
  );

  test('status from the marker alone', () {
    expect(dataKeyStatusFromMarker(null), DataKeyAccessStatus.notRequested);
    expect(
      dataKeyStatusFromMarker(DataKeyBackend.systemKeyStore),
      DataKeyAccessStatus.ready,
    );
    expect(
      dataKeyStatusFromMarker(DataKeyBackend.file),
      DataKeyAccessStatus.fileFallback,
    );
  });

  test('allow is offered only while no key is settled', () {
    final offering = {
      for (final s in DataKeyAccessStatus.values)
        if (dataKeyStatusOffersAllow(s)) s,
    };
    expect(offering, {
      DataKeyAccessStatus.notRequested,
      DataKeyAccessStatus.declined,
      DataKeyAccessStatus.failed,
      DataKeyAccessStatus.keyringLocked,
    });
  });

  group('shouldExplainDataKeyToExistingUser', () {
    bool explain({
      bool completed = true,
      bool explained = false,
      bool recorded = false,
      bool surface = false,
    }) => shouldExplainDataKeyToExistingUser(
      onboardingCompleted: completed,
      dataKeyExplained: explained,
      keyRecorded: recorded,
      onboardingSurfaceActive: surface,
    );

    test('existing user without explanation and key gets it once', () {
      expect(explain(), isTrue);
    });

    test('nothing when already explained, key present or onboarding shown', () {
      expect(explain(explained: true), isFalse);
      expect(explain(recorded: true), isFalse);
      expect(explain(surface: true), isFalse);
      expect(explain(completed: false), isFalse);
    });
  });
}
