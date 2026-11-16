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
        lookup: (id, size, _) async {
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

    test('reads the path; a path alone is still an answer', () {
      final info = NativeAppInfo.fromMap({'path': r'C:\a\app.exe'});
      expect(info?.path, r'C:\a\app.exe');
      expect(info?.name, isNull);
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

    test('tells a system name from a cleaned identifier', () async {
      final known = service((_) => const NativeAppInfo(name: 'Firefox'));
      expect((await known.resolve('Navigator')).nameFromSystem, isTrue);
      final unknown = service((_) => null);
      final fallback = await unknown.resolve('com.example.Gone');
      expect(fallback.name, 'Gone');
      expect(fallback.nameFromSystem, isFalse);
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
        lookup: (id, size, _) {
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

    test(
      'an unknown app falls back and is asked again after the retry window',
      () async {
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
      },
    );

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

    test('an unlocatable app (host error) is not cached as a miss', () async {
      // Windows host: the app is closed and no path is known yet.
      final s = service(
        (_) => throw PlatformException(code: 'UNRESOLVED', message: 'gone'),
      );
      await s.resolve('CalculatorApp');
      now = now.add(const Duration(minutes: 1));
      final restarted = service(
        (_) => NativeAppInfo(name: 'Calculator', iconPng: png),
      );
      final identity = await restarted.resolve('CalculatorApp');
      expect(identity.iconPath, isNotNull);
      expect(asked, ['CalculatorApp', 'CalculatorApp']);
    });

    test(
      'a successful answer without an icon is retried after hours',
      () async {
        final s = service((_) => const NativeAppInfo(path: r'C:\x\a.exe'));
        await s.resolve('a');
        now = now.add(appIdentityMissRetry + const Duration(minutes: 1));
        await s.resolve('a');
        expect(asked, hasLength(2));
        expect(appIdentityMissRetry, lessThan(const Duration(days: 1)));
      },
    );

    test('the stored path reaches the native lookup after a restart', () async {
      final paths = <String?>[];
      AppIdentityService withPaths(NativeAppInfo? Function(String?) answer) =>
          AppIdentityService(
            directory: dir,
            lookup: (id, size, knownPath) async {
              paths.add(knownPath);
              return answer(knownPath);
            },
            now: () => now,
          );

      // Capture session: the app runs, the host reports its path, no icon.
      final first = withPaths(
        (_) => const NativeAppInfo(path: r'C:\a\app.exe'),
      );
      await first.resolve('app');

      // New session after the miss window: the app is closed, the host can
      // only succeed through the persisted path.
      now = now.add(appIdentityMissRetry + const Duration(minutes: 1));
      final restarted = withPaths(
        (known) => known == null
            ? throw PlatformException(code: 'UNRESOLVED')
            : NativeAppInfo(name: 'App', iconPng: png, path: known),
      );
      final identity = await restarted.resolve('app');
      expect(paths, [null, r'C:\a\app.exe']);
      expect(identity.iconPath, isNotNull);
      expect(
        File(p.join(dir, 'index.json')).readAsStringSync(),
        contains('app.exe'),
      );
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
          lookup: (id, size, _) async => id == 'slack' ? hang.future : null,
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

    test(
      'a lookup still running when the cache is cleared stays out',
      () async {
        final answer = Completer<NativeAppInfo?>();
        final s = AppIdentityService(
          directory: dir,
          lookup: (id, size, _) async =>
              id == 'slack' ? answer.future : NativeAppInfo(name: id),
        );
        await s.resolve('mail');
        final pending = s.resolve('slack');
        await Future<void>.delayed(Duration.zero);
        await s.clear();
        answer.complete(NativeAppInfo(name: 'Slack', iconPng: png));
        await pending;

        expect(Directory(dir).existsSync(), isFalse);
      },
    );

    test('a located app without icon is asked again and heals', () async {
      var withIcon = false;
      final s = service(
        (_) => NativeAppInfo(
          name: 'Calculator',
          path: r'C:\WindowsApps\CalculatorApp.exe',
          iconPng: withIcon ? png : null,
        ),
      );
      expect((await s.resolve('calculatorapp')).iconPath, isNull);
      expect(asked, hasLength(1));

      // Within the retry window the cached name is believed.
      now = now.add(const Duration(hours: 1));
      expect((await s.resolve('calculatorapp')).name, 'Calculator');
      expect(asked, hasLength(1));

      // After the window the lookup runs again; the icon arrives.
      withIcon = true;
      now = now.add(appIdentityMissRetry);
      final healed = await s.resolve('calculatorapp');
      expect(asked, hasLength(2));
      expect(File(healed.iconPath!).readAsBytesSync(), png);

      // With an icon the entry is final.
      now = now.add(appIdentityMissRetry * 4);
      await s.resolve('calculatorapp');
      expect(asked, hasLength(2));
    });

    test('a failed retry keeps the cached name', () async {
      var fail = false;
      final s = AppIdentityService(
        directory: dir,
        lookup: (id, size, path) async {
          if (fail) throw PlatformException(code: 'UNRESOLVED');
          return const NativeAppInfo(name: 'Calculator', path: r'C:\a.exe');
        },
        now: () => now,
      );
      await s.resolve('calculatorapp');
      fail = true;
      now = now.add(appIdentityMissRetry);
      final identity = await s.resolve('calculatorapp');
      expect(identity.name, 'Calculator');
      expect(identity.nameFromSystem, isTrue);
    });

    test('lookups finishing together all land in the index', () async {
      final s = service((id) => NativeAppInfo(name: id, iconPng: png));
      await Future.wait([
        for (final id in ['a', 'b', 'c', 'd']) s.resolve(id),
      ]);

      final index = File(p.join(dir, 'index.json')).readAsStringSync();
      expect(index, allOf(contains('"a"'), contains('"b"'), contains('"d"')));
    });
  });
}
