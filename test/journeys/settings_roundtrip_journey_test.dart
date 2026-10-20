/// Journey: Settings exportieren → Werte ändern → importieren → alles wieder da.
///
/// Real providers, real [SettingsPage] (for the change step, per key), real
/// [SettingsPortabilitySection] (export/import rows and the import confirm
/// dialog), real [SettingsPortabilityService] writing real JSON into a temp
/// directory, and a real in-memory Drift DB. Faked: only the OS seams — the
/// save/open dialog (picker), the Downloads/Documents lookup, and the
/// security-scoped bookmark layer (macOS-only, pinned off). Toasts are
/// recorded through the controller's toaster seam and still shown.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/config/automation_hooks.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';
import 'package:whispaste/features/settings/sections/settings_portability_section.dart';
import 'package:whispaste/features/settings/settings_page.dart';
import 'package:whispaste/features/snippets/snippets_page.dart';
import 'package:whispaste/services/hardware_info_service.dart';
import 'package:whispaste/services/secure_bookmark_service.dart';
import 'package:whispaste/services/settings_portability_controller.dart';
import 'package:whispaste/services/audio_service.dart';
import 'package:whispaste/services/settings_portability_service.dart';
import 'package:whispaste/widgets/toast.dart';

// ---------------------------------------------------------------------------
// Fakes (OS seams only)
// ---------------------------------------------------------------------------

/// In-memory key store — API keys never reach the real keychain.
class _FakeSecureKeyStore implements SecureKeyStore {
  final Map<String, String> store = {};

  @override
  Future<String?> readKey(String key) async => store[key];

  @override
  Future<void> writeKey(String key, String value) async => store[key] = value;

  @override
  Future<void> deleteKey(String key) async => store.remove(key);

  @override
  Future<Map<String, String>> readAllApiKeys() async => Map.of(store);
}

/// Bookmarks are a macOS sandbox concern; pinned off so the path flow is the
/// plain remembered-path flow on every test host.
class _NoBookmarks extends SecureBookmarkService {
  const _NoBookmarks();

  @override
  bool get isSupported => false;
}

/// One journey's state: the shared container, the temp directory the export
/// file lives in, the scripted dialog answers and the toasts shown so far.
class _Env {
  _Env({required this.container, required this.tmp});

  final ProviderContainer container;
  final Directory tmp;

  /// Answers for successive save/open dialogs; past the end a dialog reports
  /// a cancel, so an unexpected extra dialog ends the flow silently.
  final List<String?> picks = [];
  int pickCalls = 0;

  final List<(WpToastType, String)> messages = [];

  String get exportPath => p.join(tmp.path, settingsExportFileName);

  Future<String?> pick({
    required bool forExport,
    required String suggestedName,
    String? initialDirectory,
  }) async {
    final index = pickCalls++;
    return index < picks.length ? picks[index] : null;
  }

  void toast(BuildContext context, WpToastType type, String message) {
    messages.add((type, message));
    WpToast.show(context, message: message, type: type);
  }
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

ProviderContainer _container(Directory tmp) {
  return ProviderContainer(
    overrides: [
      historyDatabaseProvider.overrideWith((ref) {
        final db = HistoryDatabase.forTesting(NativeDatabase.memory());
        ref.onDispose(db.close);
        return db;
      }),
      gpuInfoProvider.overrideWith(
        (ref) async => const GpuInfo(vendor: GpuVendor.none, name: 'Test'),
      ),
      secureKeyStoreProvider.overrideWithValue(_FakeSecureKeyStore()),
      // Audio device probe (record plugin) — no microphone in the test host.
      audioInputDevicesProvider.overrideWith((ref) async => const ['Default']),
    ],
  );
}

/// The hotkey plugin's event stream and method channel, answered with
/// nothing: no global hotkey is registered in the test host.
const _hotkeyEventChannel = MethodChannel(
  'dev.leanflutter.plugins/hotkey_manager_event',
);
const _hotkeyChannel = MethodChannel('dev.leanflutter.plugins/hotkey_manager');

void _mockHotkeyChannels(bool on) {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final channel in [_hotkeyEventChannel, _hotkeyChannel]) {
    messenger.setMockMethodCallHandler(
      channel,
      on ? (call) async => null : null,
    );
  }
}

/// The same app shell [makeTestable] builds, but around a container the
/// whole journey shares — so the settings page, the section and the data
/// survive swapping one page for the other, as they do in the running app.
Widget _app(ProviderContainer container, Widget child) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: wpDarkTheme(),
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      navigatorObservers: [WpToastPopupObserver()],
      home: MediaQuery(
        data: const MediaQueryData(size: Size(1280, 800)),
        child: Scaffold(body: child),
      ),
    ),
  );
}

/// The section with its controller wired exactly like production
/// (`SettingsPortabilitySection._controller`), except for the OS seams:
/// the dialog, the Downloads/Documents lookup and bookmarks.
Widget _section(_Env env) {
  return Consumer(
    builder: (context, ref, _) {
      AppSettings current() =>
          ref.read(settingsProvider).value ?? AppSettings.defaults;

      return SettingsPortabilitySection(
        controllerOverride: SettingsPortabilityController(
          gather: () async => buildSettingsExportBundle(
            settings: current(),
            replacements: ref.read(replacementsProvider).value ?? const [],
            snippets: ref.read(snippetsProvider).value ?? const [],
          ),
          apply: (bundle) async {
            await ref
                .read(settingsProvider.notifier)
                .updateSettings(
                  (s) => mergeImportedSettings(s, bundle.settings),
                );
            await ref
                .read(replacementsProvider.notifier)
                .replaceAll(bundle.replacements);
            if (bundle.snippets case final snippets?) {
              await ref.read(snippetsProvider.notifier).replaceAll(snippets);
            }
          },
          getExportPath: () async => current().portabilityPaths.exportPath,
          setExportPath: (v) => ref
              .read(settingsProvider.notifier)
              .updateSettings(
                (s) => s.copyWithSections(
                  portabilityPaths: s.portabilityPaths.copyWith(exportPath: v),
                ),
              ),
          getImportPath: () async => current().portabilityPaths.importPath,
          setImportPath: (v) => ref
              .read(settingsProvider.notifier)
              .updateSettings(
                (s) => s.copyWithSections(
                  portabilityPaths: s.portabilityPaths.copyWith(importPath: v),
                ),
              ),
          getExportBookmark: () async =>
              current().portabilityPaths.exportBookmark,
          setExportBookmark: (v) => ref
              .read(settingsProvider.notifier)
              .updateSettings(
                (s) => s.copyWithSections(
                  portabilityPaths: s.portabilityPaths.copyWith(
                    exportBookmark: v,
                  ),
                ),
              ),
          getImportBookmark: () async =>
              current().portabilityPaths.importBookmark,
          setImportBookmark: (v) => ref
              .read(settingsProvider.notifier)
              .updateSettings(
                (s) => s.copyWithSections(
                  portabilityPaths: s.portabilityPaths.copyWith(
                    importBookmark: v,
                  ),
                ),
              ),
          bookmarks: const _NoBookmarks(),
          downloadsDirFn: () async => env.tmp,
          documentsDirFn: () async => env.tmp,
          pickPath: env.pick,
          toaster: env.toast,
        ),
      );
    },
  );
}

/// Waits until [done] holds, polling with real yields. File I/O does not
/// complete under FakeAsync, so each poll lets the real event loop run for a
/// moment; the wall-clock deadline keeps a stuck flow from hanging the run.
Future<void> _pollUntil(WidgetTester tester, bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for the settings file operation to finish');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> _openSettings(WidgetTester tester, _Env env) async {
  await tester.pumpWidget(_app(env.container, const SettingsPage()));
  await tester.pumpAndSettle();
}

Future<void> _openPortability(WidgetTester tester, _Env env) async {
  await tester.pumpWidget(_app(env.container, _section(env)));
  await tester.pumpAndSettle();
}

/// Flips the Settings-UI close-to-tray switch (addressed by key).
Future<void> _toggleCloseToTray(WidgetTester tester, _Env env) async {
  await _openSettings(tester, env);
  final toggle = find.byKey(const ValueKey('interface-close-to-tray'));
  await tester.ensureVisible(toggle);
  await tester.tap(toggle);
  await tester.pumpAndSettle();
}

bool _closeToTray(_Env env) =>
    env.container.read(settingsProvider).value!.behavior.closeToTray;

/// The stored settings without the remembered export/import locations: picking
/// a file remembers its location by design, so that is not a settings change.
Map<String, String> _settingsMap(_Env env) => {
  for (final entry
      in env.container.read(settingsProvider).value!.toStorageMap().entries)
    if (!entry.key.startsWith('settings_export_') &&
        !entry.key.startsWith('settings_import_'))
      entry.key: entry.value,
};

List<String> _snippetTitles(_Env env) => [
  for (final s
      in env.container.read(snippetsProvider).value ?? const <SnippetItem>[])
    s.title,
];

List<List<String>> _replacementTriggers(_Env env) => [
  for (final r
      in env.container.read(replacementsProvider).value ??
          const <Replacement>[])
    r.triggers,
];

String _customVocabulary(_Env env) =>
    env.container.read(settingsProvider).value!.stt.customVocabulary;

/// Loads the async notifiers (real DB reads) so their state is readable.
Future<void> _load(WidgetTester tester, _Env env) async {
  await tester.runAsync(() async {
    await env.container.read(settingsProvider.future);
    await env.container.read(snippetsProvider.future);
    await env.container.read(replacementsProvider.future);
  });
}

/// Tap the import row, confirm the dialog, and wait for the outcome.
Future<void> _importAndConfirm(WidgetTester tester, _Env env) async {
  await _openPortability(tester, env);
  final before = env.messages.length;
  // The export's success toast, shown by the toaster seam, may still be up
  // when the import dialog opens; it steps back behind the dialog.
  await tester.tap(find.byKey(const ValueKey('portability-import-action')));
  await tester.pumpAndSettle();
  await _tapReachable(
    tester,
    find.byKey(const ValueKey('confirm-dialog-confirm')),
  );
  await tester.pumpAndSettle();
  await _pollUntil(tester, () => env.messages.length > before);
}

/// Taps the centre of [finder] and fails, naming what lies on top, when the
/// tap would not reach it. A covered button otherwise only shows up as a
/// timeout further down.
Future<void> _tapReachable(WidgetTester tester, Finder finder) async {
  final target = tester.renderObject(finder);
  final centre = tester.getCenter(finder);
  final hits = [
    for (final entry in tester.hitTestOnBinding(centre).path)
      if (entry.target is RenderObject) entry.target as RenderObject,
  ];
  if (!hits.contains(target)) {
    final onTop = hits
        .take(15)
        .map((r) => '${r.debugCreator ?? r.runtimeType}')
        .join('\n');
    fail('$finder is covered at $centre by:\n$onTop');
  }
  await tester.tapAt(centre);
}

/// Unmounts the widget tree and releases the container, as a test body must
/// do before its checks end (not in a tearDown).
Future<void> _teardown(WidgetTester tester, _Env env) async {
  await tester.pump(const Duration(seconds: 10));
  await tester.pumpAndSettle();
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  env.container.dispose();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('wp40-settings-roundtrip-');
    _mockHotkeyChannels(true);
  });

  tearDown(() {
    _mockHotkeyChannels(false);
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('Settings roundtrip journey', () {
    testWidgets(
      'change per key, export, reset to other values, import, and every '
      'exported value is back (settings, snippets, replacements, vocabulary)',
      (tester) async {
        final env = _Env(container: _container(tmp), tmp: tmp);
        env.picks.addAll([env.exportPath, env.exportPath]);

        // Start from a known state: vocabulary and a snippet and a replacement.
        // Await the async notifiers first so their initial load cannot
        // overwrite the seeded values afterwards.
        await _load(tester, env);
        await tester.runAsync(() async {
          final s = env.container.read(settingsProvider.notifier);
          await s.updateSettings(
            (x) => x.copyWithSections(
              stt: x.stt.copyWith(customVocabulary: 'WhisPaste'),
            ),
          );
          await env.container
              .read(snippetsProvider.notifier)
              .add('Greeting', 'Hello there');
          await env.container.read(replacementsProvider.notifier).add([
            'wp smile',
          ], ':)');
        });
        await _openSettings(tester, env);
        final exportedCloseToTray = !_closeToTray(env);
        await _toggleCloseToTray(tester, env);
        expect(_closeToTray(env), exportedCloseToTray);

        // Export.
        await _openPortability(tester, env);
        final before = env.messages.length;
        await tester.tap(
          find.byKey(const ValueKey('portability-export-action')),
        );
        await tester.pumpAndSettle();
        await _pollUntil(tester, () => env.messages.length > before);
        expect(env.messages.last.$1, WpToastType.success);

        final exported =
            jsonDecode(File(env.exportPath).readAsStringSync())
                as Map<String, dynamic>;
        final exportedSettings = exported['settings'] as Map<String, dynamic>;
        expect(exportedSettings['close_to_tray'], '$exportedCloseToTray');
        expect(exportedSettings['custom_vocabulary'], 'WhisPaste');
        // Machine-bound keys never leave the machine.
        expect(exportedSettings.containsKey('window_x'), isFalse);
        expect(exportedSettings.containsKey('microphone'), isFalse);
        expect(exportedSettings.containsKey('openai_api_key'), isFalse);
        final exportedSnippets = (exported['snippets'] as List)
            .cast<Map<String, dynamic>>();
        final greeting = exportedSnippets.singleWhere(
          (s) => s['title'] == 'Greeting',
        );
        expect(greeting['body'], 'Hello there');
        final exportedReplacements = (exported['replacements'] as List)
            .cast<Map<String, dynamic>>();
        final smile = exportedReplacements.singleWhere(
          (r) => r['replacement'] == ':)',
        );
        expect(smile['triggers'], ['wp smile']);

        // Change to other values, in the settings UI and in the data.
        final snippetsAtExport = _snippetTitles(env);
        final replacementsAtExport = _replacementTriggers(env);
        await _toggleCloseToTray(tester, env);
        expect(_closeToTray(env), !exportedCloseToTray);
        await tester.runAsync(() async {
          await env.container
              .read(settingsProvider.notifier)
              .updateSettings(
                (x) => x.copyWithSections(
                  stt: x.stt.copyWith(customVocabulary: 'Something else'),
                ),
              );
          await env.container.read(snippetsProvider.notifier).replaceAll([]);
          await env.container
              .read(replacementsProvider.notifier)
              .replaceAll([]);
        });
        expect(_snippetTitles(env), isEmpty);
        expect(_replacementTriggers(env), isEmpty);

        // Import.
        await _importAndConfirm(tester, env);
        expect(env.messages.last.$1, WpToastType.success);
        expect(_closeToTray(env), exportedCloseToTray);
        expect(_customVocabulary(env), 'WhisPaste');
        expect(_snippetTitles(env), snippetsAtExport);
        expect(_replacementTriggers(env), replacementsAtExport);
        expect(_snippetTitles(env), contains('Greeting'));
        expect(
          _replacementTriggers(env).expand((t) => t),
          contains('wp smile'),
        );

        await _teardown(tester, env);
      },
    );

    testWidgets(
      'a file from a newer schema version is read best-effort: known values '
      'apply, unknown keys and sections are ignored, nothing is rejected',
      (tester) async {
        final env = _Env(container: _container(tmp), tmp: tmp);
        await _load(tester, env);
        final file = File(p.join(tmp.path, 'newer.json'))
          ..writeAsStringSync(
            jsonEncode({
              'format_version': 3,
              'settings': {'close_to_tray': 'true', 'future_setting': 'x'},
              'replacements': [],
              'future_section': {'a': 1},
            }),
          );
        env.picks.add(file.path);

        await _importAndConfirm(tester, env);

        expect(env.messages.last.$1, WpToastType.success);
        expect(_closeToTray(env), isTrue);
        await _teardown(tester, env);
      },
    );

    for (final broken in <({String name, String content})>[
      (name: 'truncated JSON', content: '{"format_version": 2, "settings": {'),
      (name: 'foreign JSON object', content: '{"name": "other-app"}'),
      (name: 'JSON array root', content: '[1, 2, 3]'),
    ]) {
      testWidgets(
        'import of a ${broken.name} shows an error and leaves every setting '
        'and data row unchanged',
        (tester) async {
          final env = _Env(container: _container(tmp), tmp: tmp);
          await _load(tester, env);
          await tester.runAsync(() async {
            await env.container
                .read(snippetsProvider.notifier)
                .add('Keep me', 'body');
          });
          final file = File(p.join(tmp.path, 'broken.json'))
            ..writeAsStringSync(broken.content);
          env.picks.add(file.path);
          final settingsBefore = _settingsMap(env);
          final closeBefore = _closeToTray(env);

          await _importAndConfirm(tester, env);

          expect(env.messages.last.$1, WpToastType.error);
          expect(_settingsMap(env), settingsBefore);
          expect(_closeToTray(env), closeBefore);
          expect(_snippetTitles(env), ['Keep me']);
          await _teardown(tester, env);
        },
      );
    }

    testWidgets(
      'importing a path whose file has vanished asks again and, on cancel, '
      'changes nothing and shows no toast',
      (tester) async {
        final env = _Env(container: _container(tmp), tmp: tmp);
        await _load(tester, env);
        final missing = p.join(tmp.path, 'gone.json');
        // First dialog: the missing file. Retry dialog after it is forgotten:
        // a cancel (null).
        env.picks.addAll([missing, null]);
        final settingsBefore = _settingsMap(env);

        await _openPortability(tester, env);
        await tester.tap(
          find.byKey(const ValueKey('portability-import-action')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('confirm-dialog-confirm')));
        await tester.pumpAndSettle();
        await _pollUntil(tester, () => env.pickCalls == 2);

        expect(env.messages, isEmpty);
        expect(_settingsMap(env), settingsBefore);
        await _teardown(tester, env);
      },
    );

    // Security: an import must not switch the local Automation API on. The
    // file below is a plain settings export with `automation_api_enabled`
    // flipped to "true". Import refuses the key (WP-43a, review finding
    // C-M-5); the setting stays as it was.
    testWidgets('importing a file with automation_api_enabled=true leaves the '
        'Automation API off (C-M-5)', (tester) async {
      final env = _Env(container: _container(tmp), tmp: tmp);
      await _load(tester, env);
      final file = File(p.join(tmp.path, 'automation.json'))
        ..writeAsStringSync(
          jsonEncode({
            'format_version': 2,
            'settings': {'automation_api_enabled': 'true'},
            'replacements': [],
            'hotkey': <String, String>{},
          }),
        );
      env.picks.add(file.path);

      await _importAndConfirm(tester, env);

      expect(
        _settingsMap(env)['automation_api_enabled'],
        isNot('true'),
        reason:
            'import must not enable the Automation API without an explicit, '
            'separate confirmation',
      );
      await _teardown(tester, env);
    });

    // Same as above for hooks: a loopback hook list in a foreign file must not
    // be installed silently.
    testWidgets(
      'importing a file with automation_hooks installs no hooks (C-M-5)',
      (tester) async {
        final env = _Env(container: _container(tmp), tmp: tmp);
        await _load(tester, env);
        final hooks = jsonEncode([
          {
            'url': 'http://127.0.0.1:9/hook',
            'events': ['transcript.finished'],
          },
        ]);
        final file = File(p.join(tmp.path, 'hooks.json'))
          ..writeAsStringSync(
            jsonEncode({
              'format_version': 2,
              'settings': {'automation_hooks': hooks},
              'replacements': [],
              'hotkey': <String, String>{},
            }),
          );
        env.picks.add(file.path);

        await _importAndConfirm(tester, env);

        expect(
          decodeAutomationHooks(_settingsMap(env)['automation_hooks']),
          isEmpty,
          reason: 'import must not install automation hooks silently',
        );
        await _teardown(tester, env);
      },
    );
  });
}
