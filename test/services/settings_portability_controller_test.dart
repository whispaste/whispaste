/// Tests for [SettingsPortabilityController] — orchestrates gather/apply +
/// path resolution (remembered path or native dialog) + toasts for the
/// settings-portability feature.
///
/// Mirrors `test/services/history/history_exporter_test.dart`: injectable
/// fakes for every collaborator, no real filesystem, no real Riverpod, and
/// (new in Ticket 03) no real `file_selector` platform channel — the dialog
/// itself is an injectable seam ([PickPathFn]) exercised via [_FakePicker].
library;

import 'dart:io';

import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';
import 'package:whispaste/services/settings_portability_controller.dart';
import 'package:whispaste/services/settings_portability_service.dart';
import 'package:whispaste/widgets/toast.dart';

// SettingsPortabilityController resolves paths via the platform-default
// `package:path` (correct for real production paths from path_provider /
// file_selector). The fixture's fake directories must therefore be genuine
// platform-native absolute paths, and the MemoryFileSystem must be told to
// use the matching style — a hardcoded POSIX literal like '/downloads'
// silently broke every test in this file on Windows CI (FileSystemException:
// No such file or directory, path = 'downloads') because
// MemoryFileSystem.test() defaults to posix regardless of host OS, while the
// real `p.join`/`p.dirname` used by the controller run in Windows-native
// style there.
final _downloadsPath = Platform.isWindows ? r'C:\downloads' : '/downloads';
final _documentsPath = Platform.isWindows ? r'C:\documents' : '/documents';

// ─── Fakes ────────────────────────────────────────────────────────────────

class _ToasterCall {
  _ToasterCall(this.type, this.message);
  final WpToastType type;
  final String message;
}

class _FakeToaster {
  final List<_ToasterCall> calls = [];

  void call(BuildContext context, WpToastType type, String message) {
    calls.add(_ToasterCall(type, message));
  }
}

/// Fakes the native save/open dialog. [responses] is consumed in call
/// order; a call past the end of [responses] returns `null` (cancelled) —
/// this makes an unexpectedly-extra dialog call fail the test loudly
/// (wrong path/toast) rather than silently reusing a prior answer.
class _FakePicker {
  _FakePicker(this.responses);

  final List<String?> responses;
  int callCount = 0;
  final List<bool> forExportCalls = [];
  final List<String?> initialDirectories = [];

  Future<String?> call({
    required bool forExport,
    required String suggestedName,
    String? initialDirectory,
  }) async {
    forExportCalls.add(forExport);
    initialDirectories.add(initialDirectory);
    final response = callCount < responses.length ? responses[callCount] : null;
    callCount++;
    return response;
  }
}

/// Default fake picker used when a test doesn't care about dialog
/// interaction: simulates the user accepting the pre-filled suggestion
/// (`<initialDirectory>/<suggestedName>`) — the same path the fixed-filename
/// behaviour resolved to before this ticket, so unrelated tests keep their
/// original assertions.
Future<String?> _acceptSuggestion({
  required bool forExport,
  required String suggestedName,
  String? initialDirectory,
}) async => p.join(initialDirectory ?? '.', suggestedName);

const _sampleBundle = SettingsExportBundle(
  settings: {
    'custom_vocabulary': 'WhisPaste',
    'hotkey_enabled': 'true',
    'hotkey_key': 'Space',
    'hotkey_key_display': 'Space',
    'hotkey_modifiers': 'ctrl+alt',
  },
  replacements: [
    Replacement(id: 'a', triggers: ['mfg'], replacement: 'MfG'),
  ],
);

// ─── Harness ──────────────────────────────────────────────────────────────

late L10n l10n;

/// Pumps a minimal localized widget tree and exposes its [BuildContext] to
/// the test body — needed so [L10n.of(context)] resolves inside the
/// controller.
Future<void> _withContext(
  WidgetTester tester,
  Future<void> Function(BuildContext context) body,
) async {
  late BuildContext capturedContext;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('en'),
      home: Builder(
        builder: (ctx) {
          capturedContext = ctx;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  await body(capturedContext);
}

/// Simple in-memory stand-in for `AppSettings.portabilityPaths` — mirrors
/// what `settings_portability_section.dart` wires against the real
/// Riverpod-backed settings in production.
class _PathStore {
  String exportPath;
  String importPath;
  final List<String> exportWrites = [];
  final List<String> importWrites = [];

  _PathStore({this.exportPath = '', this.importPath = ''});

  Future<String> getExport() async => exportPath;
  Future<void> setExport(String path) async {
    exportPath = path;
    exportWrites.add(path);
  }

  Future<String> getImport() async => importPath;
  Future<void> setImport(String path) async {
    importPath = path;
    importWrites.add(path);
  }
}

SettingsPortabilityController _controller({
  required MemoryFileSystem fs,
  required _FakeToaster toaster,
  GatherBundleFn? gather,
  ApplyBundleFn? apply,
  Directory? downloads,
  Directory? documents,
  _PathStore? pathStore,
  PickPathFn? pickPath,
}) {
  final paths = pathStore ?? _PathStore();
  return SettingsPortabilityController(
    gather: gather ?? () async => _sampleBundle,
    apply: apply ?? (_) async {},
    service: SettingsPortabilityService(fileSystem: fs),
    downloadsDirFn: () async => downloads,
    documentsDirFn: () async => documents,
    getExportPath: paths.getExport,
    setExportPath: paths.setExport,
    getImportPath: paths.getImport,
    setImportPath: paths.setImport,
    pickPath: pickPath ?? _acceptSuggestion,
    toaster: toaster.call,
  );
}

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  late MemoryFileSystem fs;

  setUp(() {
    fs = MemoryFileSystem.test(
      style: Platform.isWindows
          ? FileSystemStyle.windows
          : FileSystemStyle.posix,
    );
  });

  // ───────────────────────────────────────────────────────────────────────
  // export()
  // ───────────────────────────────────────────────────────────────────────

  testWidgets('export writes the gathered bundle and shows a success toast', (
    tester,
  ) async {
    final toaster = _FakeToaster();
    final sut = _controller(
      fs: fs,
      toaster: toaster,
      downloads: Directory(_downloadsPath),
    );

    await _withContext(tester, (ctx) async {
      await sut.export(ctx);
    });

    final written = await fs
        .file(p.join(_downloadsPath, settingsExportFileName))
        .readAsString();
    expect(written, contains('WhisPaste'));
    expect(written, contains('mfg'));

    expect(toaster.calls, hasLength(1));
    expect(toaster.calls.single.type, WpToastType.success);
    expect(
      toaster.calls.single.message,
      l10n.settingsPortabilityExportSuccess(
        p.join(_downloadsPath, settingsExportFileName),
      ),
    );
  });

  testWidgets('export falls back to Documents when Downloads is null', (
    tester,
  ) async {
    final toaster = _FakeToaster();
    final sut = _controller(
      fs: fs,
      toaster: toaster,
      downloads: null,
      documents: Directory(_documentsPath),
    );

    await _withContext(tester, (ctx) async {
      await sut.export(ctx);
    });

    expect(
      await fs.file(p.join(_documentsPath, settingsExportFileName)).exists(),
      isTrue,
    );
  });

  testWidgets('export shows an error toast when gather throws', (tester) async {
    final toaster = _FakeToaster();
    final picker = _FakePicker([]);
    final sut = _controller(
      fs: fs,
      toaster: toaster,
      downloads: Directory(_downloadsPath),
      gather: () async => throw Exception('db unavailable'),
      pickPath: picker.call,
    );

    await _withContext(tester, (ctx) async {
      await sut.export(ctx);
    });

    expect(toaster.calls, hasLength(1));
    expect(toaster.calls.single.type, WpToastType.error);
    expect(
      toaster.calls.single.message,
      l10n.settingsPortabilityExportError('db unavailable'),
    );
    // gather() fails before any path is resolved — the user should not be
    // made to pick a save location just to be shown an error afterwards.
    expect(picker.callCount, 0);
  });

  // ───────────────────────────────────────────────────────────────────────
  // import()
  // ───────────────────────────────────────────────────────────────────────

  testWidgets('import reads the file and applies the bundle, success toast', (
    tester,
  ) async {
    final toaster = _FakeToaster();
    SettingsExportBundle? applied;
    final sut = _controller(
      fs: fs,
      toaster: toaster,
      downloads: Directory(_downloadsPath),
      apply: (bundle) async => applied = bundle,
    );

    // Pre-populate the export file (as if a previous export or a copied
    // file from another device placed it there).
    await fs.directory(_downloadsPath).create(recursive: true);
    await fs
        .file(p.join(_downloadsPath, settingsExportFileName))
        .writeAsString(
          const SettingsPortabilityService().encode(_sampleBundle),
        );

    await _withContext(tester, (ctx) async {
      await sut.import(ctx);
    });

    expect(applied, isNotNull);
    expect(applied!.settings['custom_vocabulary'], 'WhisPaste');
    expect(applied!.replacements.single.triggers, ['mfg']);

    expect(toaster.calls, hasLength(1));
    expect(toaster.calls.single.type, WpToastType.success);
    expect(
      toaster.calls.single.message,
      l10n.settingsPortabilityImportSuccess(
        p.join(_downloadsPath, settingsExportFileName),
      ),
    );
  });

  testWidgets(
    'import shows a "not found" toast when the picked file still does not '
    'exist after a retry',
    (tester) async {
      final toaster = _FakeToaster();
      var applyCalled = false;
      // No remembered path and no file at the suggested location: the
      // controller opens the dialog, gets a path with nothing there, treats
      // that as "unusable", forgets it, and re-prompts exactly once more —
      // still nothing there, so the friendly "not found" message is the
      // deliberate residual case (see the ARB description on
      // settingsPortabilityImportNotFound).
      final picker = _FakePicker([
        p.join(_downloadsPath, settingsExportFileName),
        p.join(_downloadsPath, settingsExportFileName),
      ]);
      final sut = _controller(
        fs: fs,
        toaster: toaster,
        downloads: Directory(_downloadsPath),
        apply: (_) async => applyCalled = true,
        pickPath: picker.call,
      );

      await _withContext(tester, (ctx) async {
        await sut.import(ctx);
      });

      expect(applyCalled, isFalse);
      expect(picker.callCount, 2);
      expect(toaster.calls, hasLength(1));
      expect(toaster.calls.single.type, WpToastType.error);
      expect(
        toaster.calls.single.message,
        l10n.settingsPortabilityImportNotFound(
          p.join(_downloadsPath, settingsExportFileName),
        ),
      );
    },
  );

  testWidgets('import shows an error toast for malformed export content', (
    tester,
  ) async {
    final toaster = _FakeToaster();
    var applyCalled = false;
    final sut = _controller(
      fs: fs,
      toaster: toaster,
      downloads: Directory(_downloadsPath),
      apply: (_) async => applyCalled = true,
    );

    await fs.directory(_downloadsPath).create(recursive: true);
    await fs
        .file(p.join(_downloadsPath, settingsExportFileName))
        .writeAsString('not json');

    await _withContext(tester, (ctx) async {
      await sut.import(ctx);
    });

    expect(applyCalled, isFalse);
    expect(toaster.calls, hasLength(1));
    expect(toaster.calls.single.type, WpToastType.error);
  });

  // ───────────────────────────────────────────────────────────────────────
  // Dialog seam — remembered path vs. native dialog (Ticket 03)
  // ───────────────────────────────────────────────────────────────────────

  group('dialog seam', () {
    testWidgets(
      'no remembered export path → dialog is opened exactly once, and the '
      'picked path is persisted',
      (tester) async {
        final toaster = _FakeToaster();
        final paths = _PathStore();
        final picked = p.join(_downloadsPath, 'custom-export.json');
        final picker = _FakePicker([picked]);
        final sut = _controller(
          fs: fs,
          toaster: toaster,
          downloads: Directory(_downloadsPath),
          pathStore: paths,
          pickPath: picker.call,
        );

        await _withContext(tester, (ctx) async {
          await sut.export(ctx);
        });

        expect(picker.callCount, 1);
        expect(picker.forExportCalls.single, isTrue);
        expect(await fs.file(picked).exists(), isTrue);
        expect(
          paths.exportPath,
          picked,
          reason: 'the picked path is remembered',
        );
        expect(toaster.calls.single.type, WpToastType.success);
      },
    );

    testWidgets(
      'remembered export path present and usable → dialog is not opened',
      (tester) async {
        final toaster = _FakeToaster();
        final remembered = p.join(_downloadsPath, 'already-chosen.json');
        final paths = _PathStore(exportPath: remembered);
        final picker = _FakePicker([]);
        final sut = _controller(
          fs: fs,
          toaster: toaster,
          downloads: Directory(_downloadsPath),
          pathStore: paths,
          pickPath: picker.call,
        );

        await _withContext(tester, (ctx) async {
          await sut.export(ctx);
        });

        expect(picker.callCount, 0);
        expect(await fs.file(remembered).exists(), isTrue);
        expect(toaster.calls.single.type, WpToastType.success);
      },
    );

    testWidgets('cancelling the dialog writes nothing and shows no toast', (
      tester,
    ) async {
      final toaster = _FakeToaster();
      final picker = _FakePicker([null]);
      final sut = _controller(
        fs: fs,
        toaster: toaster,
        downloads: Directory(_downloadsPath),
        pickPath: picker.call,
      );

      await _withContext(tester, (ctx) async {
        await sut.export(ctx);
      });

      expect(picker.callCount, 1);
      expect(toaster.calls, isEmpty);
      expect(
        await fs.directory(_downloadsPath).exists(),
        isFalse,
        reason:
            'a cancelled dialog must not create so much as the '
            'directory',
      );
    });

    testWidgets('remembered export path no longer usable (parent no longer a '
        'directory) → dialog opens again exactly once and the new path wins', (
      tester,
    ) async {
      final toaster = _FakeToaster();
      // Simulate the remembered folder having been replaced by a file
      // (e.g. a sync client left a same-named file behind, or the mount
      // point vanished) — `exportToFile`'s `parent.create(recursive:
      // true)` throws FileSystemException against a path segment that is
      // no longer a directory.
      await fs.directory(_downloadsPath).create(recursive: true);
      await fs.file(p.join(_downloadsPath, 'sub')).create();
      final stale = p.join(_downloadsPath, 'sub', settingsExportFileName);
      final paths = _PathStore(exportPath: stale);
      final fresh = p.join(_downloadsPath, 'fresh-export.json');
      final picker = _FakePicker([fresh]);
      final sut = _controller(
        fs: fs,
        toaster: toaster,
        downloads: Directory(_downloadsPath),
        pathStore: paths,
        pickPath: picker.call,
      );

      await _withContext(tester, (ctx) async {
        await sut.export(ctx);
      });

      expect(picker.callCount, 1);
      expect(await fs.file(fresh).exists(), isTrue);
      expect(paths.exportPath, fresh);
      expect(toaster.calls, hasLength(1));
      expect(toaster.calls.single.type, WpToastType.success);
      expect(
        toaster.calls.single.message,
        l10n.settingsPortabilityExportSuccess(fresh),
      );
    });

    testWidgets(
      'remembered import path deleted → dialog opens again exactly once '
      'and the freshly picked file is imported',
      (tester) async {
        final toaster = _FakeToaster();
        final paths = _PathStore(
          importPath: p.join(_downloadsPath, 'gone.json'),
        );
        final fresh = p.join(_downloadsPath, 'fresh-import.json');
        await fs.directory(_downloadsPath).create(recursive: true);
        await fs
            .file(fresh)
            .writeAsString(
              const SettingsPortabilityService().encode(_sampleBundle),
            );
        final picker = _FakePicker([fresh]);
        SettingsExportBundle? applied;
        final sut = _controller(
          fs: fs,
          toaster: toaster,
          downloads: Directory(_downloadsPath),
          pathStore: paths,
          pickPath: picker.call,
          apply: (bundle) async => applied = bundle,
        );

        await _withContext(tester, (ctx) async {
          await sut.import(ctx);
        });

        expect(picker.callCount, 1);
        expect(applied, isNotNull);
        expect(paths.importPath, fresh);
        expect(toaster.calls, hasLength(1));
        expect(toaster.calls.single.type, WpToastType.success);
      },
    );
  });

  // ───────────────────────────────────────────────────────────────────────
  // Import ≠ export target (Ticket 03)
  // ───────────────────────────────────────────────────────────────────────

  testWidgets(
    'import followed by export does not write into the import source',
    (tester) async {
      final toaster = _FakeToaster();
      final importSource = p.join(_downloadsPath, 'from-other-device.json');
      final originalContent = const SettingsPortabilityService().encode(
        _sampleBundle,
      );
      await fs.directory(_downloadsPath).create(recursive: true);
      await fs.file(importSource).writeAsString(originalContent);

      final exportTarget = p.join(_downloadsPath, 'my-export.json');
      final paths = _PathStore(importPath: importSource);
      final picker = _FakePicker([exportTarget]);
      final sut = _controller(
        fs: fs,
        toaster: toaster,
        downloads: Directory(_downloadsPath),
        pathStore: paths,
        pickPath: picker.call,
      );

      await _withContext(tester, (ctx) async {
        await sut.import(ctx);
        await sut.export(ctx);
      });

      expect(
        await fs.file(importSource).readAsString(),
        originalContent,
        reason: 'export must never touch the file import just read from',
      );
      expect(await fs.file(exportTarget).exists(), isTrue);
      expect(paths.importPath, importSource);
      expect(paths.exportPath, exportTarget);
      // The import path was already remembered, so only the export's dialog
      // fires.
      expect(picker.callCount, 1);
      expect(picker.forExportCalls.single, isTrue);
    },
  );
}
