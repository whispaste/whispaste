import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/services/app_identity/app_category.dart';
import 'package:whispaste/services/app_identity/app_identity_service.dart';

void main() {
  late Directory root;
  late String dir;
  late DateTime now;
  late List<String> asked;

  setUp(() {
    root = Directory.systemTemp.createTempSync('app_identity_test');
    dir = p.join(root.path, appIconFolderName);
    now = DateTime(2026, 10, 30, 12);
    asked = [];
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  AppIdentityService service(NativeAppInfo? Function(String id) answer) =>
      AppIdentityService(
        directory: dir,
        lookup: (id, size) async {
          asked.add(id);
          return answer(id);
        },
        now: () => now,
      );

  final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);

  group('cleanAppName', () {
    test('turns raw identifiers into readable names', () {
      expect(cleanAppName('dev.warp.Warp-Stable'), 'Warp');
      expect(cleanAppName('notepad.exe'), 'Notepad');
      expect(cleanAppName('org.gnome.Terminal'), 'Terminal');
      expect(cleanAppName('gnome-terminal-server'), 'Gnome terminal');
      expect(cleanAppName('com.microsoft.VSCode'), 'VSCode');
    });

    test('keeps an identifier that cleans to nothing', () {
      expect(cleanAppName('__'), '__');
    });
  });

  group('NativeAppInfo.fromMap (channel reply)', () {
    test('reads name and icon', () {
      final info = NativeAppInfo.fromMap({'name': ' Warp ', 'icon': png});
      expect(info?.name, 'Warp');
      expect(info?.iconPng, png);
    });

    test('empty parts count as missing; nothing at all is null', () {
      expect(NativeAppInfo.fromMap({'name': '', 'icon': Uint8List(0)}), isNull);
      expect(NativeAppInfo.fromMap(null), isNull);
      expect(NativeAppInfo.fromMap({'name': 'Mail'})?.iconPng, isNull);
    });
  });

  group('AppIdentityService', () {
    test('uses the system name and caches the icon as a file', () async {
      final s = service((_) => NativeAppInfo(name: 'Warp', iconPng: png));
      final identity = await s.resolve('dev.warp.Warp-Stable');
      expect(identity.name, 'Warp');
      expect(identity.category, AppCategory.terminal);
      expect(File(identity.iconPath!).readAsBytesSync(), png);
    });

    test('asks the system once per app, also across restarts', () async {
      final first = service((_) => NativeAppInfo(name: 'Warp', iconPng: png));
      await first.resolve('dev.warp.Warp-Stable');
      await first.resolve('dev.warp.Warp-Stable');
      final restarted = service((_) => throw StateError('must not ask'));
      final identity = await restarted.resolve('dev.warp.Warp-Stable');
      expect(asked, ['dev.warp.Warp-Stable']);
      expect(identity.name, 'Warp');
      expect(identity.iconPath, isNotNull);
    });

    test('concurrent rows share one lookup', () async {
      final gate = Completer<NativeAppInfo?>();
      var calls = 0;
      final s = AppIdentityService(
        directory: dir,
        lookup: (id, size) {
          calls++;
          return gate.future;
        },
      );
      final a = s.resolve('slack');
      final b = s.resolve('slack');
      gate.complete(const NativeAppInfo(name: 'Slack'));
      expect((await a).name, 'Slack');
      expect((await b).name, 'Slack');
      expect(calls, 1);
    });

    test('an unknown app falls back and is asked again after a week', () async {
      final s = service((_) => null);
      final identity = await s.resolve('com.example.Gone-Beta');
      expect(identity.name, 'Gone');
      expect(identity.category, AppCategory.unknown);
      expect(identity.iconPath, isNull);

      now = now.add(appIdentityMissRetry - const Duration(minutes: 1));
      await s.resolve('com.example.Gone-Beta');
      expect(asked, hasLength(1));

      now = now.add(const Duration(minutes: 2));
      await s.resolve('com.example.Gone-Beta');
      expect(asked, hasLength(2));
    });

    test('a failing system lookup still gives the fallback', () async {
      final s = service((_) => throw StateError('channel broke'));
      final identity = await s.resolve('WindowsTerminal');
      expect(identity.name, 'WindowsTerminal');
      expect(identity.category, AppCategory.terminal);
    });

    test('a missing host is never cached as "no such app"', () async {
      // An older native build without the host: Dart is new, the channel is
      // not there yet.
      final old = service((_) => throw MissingPluginException());
      await old.resolve('dev.warp.Warp-Stable');
      await old.resolve('dev.warp.Warp-Stable');
      expect(asked, hasLength(1), reason: 'asked once per session');
      final index = File(p.join(dir, 'index.json'));
      expect(
        index.existsSync() ? index.readAsStringSync() : '',
        isNot(contains('warp')),
      );

      // After the native update the next start asks and gets the icon.
      final updated = service((_) => NativeAppInfo(name: 'Warp', iconPng: png));
      final identity = await updated.resolve('dev.warp.Warp-Stable');
      expect(asked, hasLength(2));
      expect(identity.iconPath, isNotNull);
    });

    test('a host error is not cached either', () async {
      final s = service(
        (_) => throw PlatformException(code: 'icon', message: 'failed'),
      );
      await s.resolve('slack');
      final restarted = service((_) => const NativeAppInfo(name: 'Slack'));
      expect((await restarted.resolve('slack')).name, 'Slack');
      expect(asked, ['slack', 'slack']);
    });

    test(
      'a host that does not answer in time is treated as no answer',
      () async {
        final hang = Completer<NativeAppInfo?>();
        final s = AppIdentityService(
          directory: dir,
          lookup: (id, size) async => id == 'slack' ? hang.future : null,
        );
        // Loads the index with real file IO, which fake time cannot finish.
        await s.resolve('com.example.Other');
        fakeAsync((async) {
          AppIdentity? identity;
          s.resolve('slack').then((v) => identity = v);
          async.elapse(appIdentityLookupTimeout);
          expect(identity?.name, 'Slack');
        });
        final index = File(p.join(dir, 'index.json')).readAsStringSync();
        expect(index, isNot(contains('slack')));
      },
    );
  });
}
