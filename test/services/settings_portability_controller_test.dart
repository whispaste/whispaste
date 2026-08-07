/// Tests for [SettingsPortabilityController] — orchestrates gather/apply +
/// path resolution (remembered path or native dialog) + toasts for the
/// settings-portability feature.
///
/// Mirrors `test/services/history/history_exporter_test.dart`: injectable
/// fakes for every collaborator, no real filesystem, no real Riverpod, and
/// (since Ticket 03) no real `file_selector` platform channel — the dialog
/// itself is an injectable seam ([PickPathFn]) exercised via [_FakePicker].
/// Since Ticket 04, [SecureBookmarkService] is likewise an injectable seam
/// ([_FakeBookmarks]) — every pre-Ticket-04 test below runs against a fake
/// reporting `isSupported: false` (the default), so they exercise exactly
/// the Ticket 03 path-only behaviour, unaffected by this repo's tests
/// actually running on macOS. See `test/services/secure_bookmark_service_test.dart`
/// for [SecureBookmarkService]'s own MethodChannel-level tests.
library;

import 'dart:io';

import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';
import 'package:whispaste/services/secure_bookmark_service.dart';
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

/// Fakes [SecureBookmarkService]. Defaults to `isSupported: false` so every
/// pre-Ticket-04 test in this file (which never sets `bookmarks:` in
/// [_controller]) keeps exercising plain Ticket 03 path-only behaviour.
///
/// [createResponses] is consumed in call order, like [_FakePicker];
/// [resolveResponses]/[startAccessResponses] are keyed by bookmark string
/// since the controller always looks a specific remembered bookmark up
/// rather than calling these positionally.
class _FakeBookmarks extends SecureBookmarkService {
  _FakeBookmarks({
    this.isSupported = false,
    this.createResponses = const [],
    this.resolveResponses = const {},
    this.startAccessResponses = const {},
    this.onCreate,
  });

  @override
  final bool isSupported;

  final List<String?> createResponses;
  int _createCallCount = 0;
  final List<String> createCalls = [];

  /// Invoked (and awaited) inside [create] before the response is
  /// returned — lets a test assert on state (e.g. "the file already exists
  /// on disk") at the exact moment `create()` fires.
  final Future<void> Function(String path)? onCreate;

  final Map<String, BookmarkResolution?> resolveResponses;
  final List<String> resolveCalls = [];

  final Map<String, bool> startAccessResponses;
  final List<String> startAccessCalls = [];
  final List<String> stopAccessCalls = [];

  @override
  Future<String?> create(String path) async {
    createCalls.add(path);
    if (onCreate case final hook?) await hook(path);
    final response = _createCallCount < createResponses.length
        ? createResponses[_createCallCount]
        : null;
    _createCallCount++;
    return response;
  }

  @override
  Future<BookmarkResolution?> resolve(String bookmark) async {
    resolveCalls.add(bookmark);
    return resolveResponses[bookmark];
  }

  @override
  Future<bool> startAccess(String bookmark) async {
    startAccessCalls.add(bookmark);
    return startAccessResponses[bookmark] ?? false;
  }

  @override
  Future<void> stopAccess(String bookmark) async {
    stopAccessCalls.add(bookmark);
  }
}

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
  String exportBookmark;
  String importBookmark;
  final List<String> exportWrites = [];
  final List<String> importWrites = [];
  final List<String> exportBookmarkWrites = [];
  final List<String> importBookmarkWrites = [];

  _PathStore({
    this.exportPath = '',
    this.importPath = '',
    this.exportBookmark = '',
    this.importBookmark = '',
  });

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

  Future<String> getExportBookmark() async => exportBookmark;
  Future<void> setExportBookmark(String bookmark) async {
    exportBookmark = bookmark;
    exportBookmarkWrites.add(bookmark);
  }

  Future<String> getImportBookmark() async => importBookmark;
  Future<void> setImportBookmark(String bookmark) async {
    importBookmark = bookmark;
    importBookmarkWrites.add(bookmark);
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
  SecureBookmarkService? bookmarks,
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
    getExportBookmark: paths.getExportBookmark,
    setExportBookmark: paths.setExportBookmark,
    getImportBookmark: paths.getImportBookmark,
    setImportBookmark: paths.setImportBookmark,
    bookmarks: bookmarks ?? _FakeBookmarks(),
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

  // ───────────────────────────────────────────────────────────────────────
  // Bookmark seam — macOS security-scoped bookmarks (Ticket 04)
  // ───────────────────────────────────────────────────────────────────────

  group('bookmark seam (Ticket 04)', () {
    testWidgets('first-ever export: bookmark is created only after the write '
        'succeeds, not at dialog-pick time', (tester) async {
      final toaster = _FakeToaster();
      final paths = _PathStore();
      final fresh = p.join(_downloadsPath, 'first-export.json');
      final picker = _FakePicker([fresh]);
      final bookmarks = _FakeBookmarks(
        isSupported: true,
        createResponses: ['export-bookmark-1'],
        onCreate: (path) async {
          expect(
            await fs.file(path).exists(),
            isTrue,
            reason:
                'creating the export bookmark at pick time (before the '
                'file exists) would silently store no bookmark for the '
                'very first export — the exact trap this ticket names',
          );
        },
      );
      final sut = _controller(
        fs: fs,
        toaster: toaster,
        downloads: Directory(_downloadsPath),
        pathStore: paths,
        pickPath: picker.call,
        bookmarks: bookmarks,
      );

      await _withContext(tester, (ctx) async {
        await sut.export(ctx);
      });

      expect(bookmarks.createCalls, [fresh]);
      expect(paths.exportBookmark, 'export-bookmark-1');
      expect(toaster.calls.single.type, WpToastType.success);
    });

    testWidgets(
      'first-ever import: bookmark is created immediately at pick time '
      '(the file already exists)',
      (tester) async {
        final toaster = _FakeToaster();
        final paths = _PathStore();
        final picked = p.join(_downloadsPath, 'first-import.json');
        await fs.directory(_downloadsPath).create(recursive: true);
        await fs
            .file(picked)
            .writeAsString(
              const SettingsPortabilityService().encode(_sampleBundle),
            );
        final picker = _FakePicker([picked]);
        final bookmarks = _FakeBookmarks(
          isSupported: true,
          createResponses: ['import-bookmark-1'],
        );
        SettingsExportBundle? applied;
        final sut = _controller(
          fs: fs,
          toaster: toaster,
          downloads: Directory(_downloadsPath),
          pathStore: paths,
          pickPath: picker.call,
          bookmarks: bookmarks,
          apply: (bundle) async => applied = bundle,
        );

        await _withContext(tester, (ctx) async {
          await sut.import(ctx);
        });

        expect(bookmarks.createCalls, [picked]);
        expect(paths.importBookmark, 'import-bookmark-1');
        expect(applied, isNotNull);
      },
    );

    testWidgets(
      'remembered path with a valid bookmark → resolve+startAccess is used, '
      'no dialog, exactly one stopAccess balances the start',
      (tester) async {
        final toaster = _FakeToaster();
        final remembered = p.join(_downloadsPath, 'already-chosen.json');
        final paths = _PathStore(
          exportPath: remembered,
          exportBookmark: 'bm-1',
        );
        final picker = _FakePicker([]);
        final bookmarks = _FakeBookmarks(
          isSupported: true,
          resolveResponses: {
            'bm-1': BookmarkResolution(path: remembered, isStale: false),
          },
          startAccessResponses: {'bm-1': true},
        );
        final sut = _controller(
          fs: fs,
          toaster: toaster,
          downloads: Directory(_downloadsPath),
          pathStore: paths,
          pickPath: picker.call,
          bookmarks: bookmarks,
        );

        await _withContext(tester, (ctx) async {
          await sut.export(ctx);
        });

        expect(picker.callCount, 0);
        expect(bookmarks.resolveCalls, ['bm-1']);
        expect(bookmarks.startAccessCalls, ['bm-1']);
        expect(bookmarks.stopAccessCalls, ['bm-1']);
        expect(
          bookmarks.createCalls,
          isEmpty,
          reason: 'a valid, non-stale bookmark must not be recreated',
        );
        expect(toaster.calls.single.type, WpToastType.success);
      },
    );

    testWidgets(
      'remembered import path with a valid bookmark → resolve+startAccess '
      'is used, no dialog',
      (tester) async {
        final toaster = _FakeToaster();
        final remembered = p.join(_downloadsPath, 'already-chosen-import.json');
        await fs.directory(_downloadsPath).create(recursive: true);
        await fs
            .file(remembered)
            .writeAsString(
              const SettingsPortabilityService().encode(_sampleBundle),
            );
        final paths = _PathStore(
          importPath: remembered,
          importBookmark: 'bm-import-1',
        );
        final picker = _FakePicker([]);
        final bookmarks = _FakeBookmarks(
          isSupported: true,
          resolveResponses: {
            'bm-import-1': BookmarkResolution(path: remembered, isStale: false),
          },
          startAccessResponses: {'bm-import-1': true},
        );
        SettingsExportBundle? applied;
        final sut = _controller(
          fs: fs,
          toaster: toaster,
          downloads: Directory(_downloadsPath),
          pathStore: paths,
          pickPath: picker.call,
          bookmarks: bookmarks,
          apply: (bundle) async => applied = bundle,
        );

        await _withContext(tester, (ctx) async {
          await sut.import(ctx);
        });

        expect(picker.callCount, 0);
        expect(bookmarks.resolveCalls, ['bm-import-1']);
        expect(bookmarks.startAccessCalls, ['bm-import-1']);
        expect(bookmarks.stopAccessCalls, ['bm-import-1']);
        expect(applied, isNotNull);
        expect(toaster.calls.single.type, WpToastType.success);
      },
    );

    testWidgets('stale bookmark is recreated and replaces the stored one; the '
        'current operation still uses the original access session', (
      tester,
    ) async {
      final toaster = _FakeToaster();
      final remembered = p.join(_downloadsPath, 'already-chosen.json');
      final paths = _PathStore(
        exportPath: remembered,
        exportBookmark: 'bm-old',
      );
      final picker = _FakePicker([]);
      final bookmarks = _FakeBookmarks(
        isSupported: true,
        resolveResponses: {
          'bm-old': BookmarkResolution(path: remembered, isStale: true),
        },
        startAccessResponses: {'bm-old': true},
        createResponses: ['bm-new'],
      );
      final sut = _controller(
        fs: fs,
        toaster: toaster,
        downloads: Directory(_downloadsPath),
        pathStore: paths,
        pickPath: picker.call,
        bookmarks: bookmarks,
      );

      await _withContext(tester, (ctx) async {
        await sut.export(ctx);
      });

      expect(picker.callCount, 0);
      expect(bookmarks.startAccessCalls, ['bm-old']);
      expect(bookmarks.stopAccessCalls, ['bm-old']);
      expect(bookmarks.createCalls, [remembered]);
      expect(
        paths.exportBookmark,
        'bm-new',
        reason: 'the stale bookmark is replaced for next time',
      );
      expect(toaster.calls.single.type, WpToastType.success);
    });

    testWidgets(
      'bookmark resolve failure falls back to the dialog, no error toast',
      (tester) async {
        final toaster = _FakeToaster();
        final remembered = p.join(_downloadsPath, 'already-chosen.json');
        final paths = _PathStore(
          exportPath: remembered,
          exportBookmark: 'bm-broken',
        );
        final fresh = p.join(_downloadsPath, 'fresh-export.json');
        final picker = _FakePicker([fresh]);
        final bookmarks = _FakeBookmarks(
          isSupported: true,
          resolveResponses: {'bm-broken': null},
        );
        final sut = _controller(
          fs: fs,
          toaster: toaster,
          downloads: Directory(_downloadsPath),
          pathStore: paths,
          pickPath: picker.call,
          bookmarks: bookmarks,
        );

        await _withContext(tester, (ctx) async {
          await sut.export(ctx);
        });

        expect(picker.callCount, 1);
        expect(paths.exportPath, fresh);
        expect(
          paths.exportBookmark,
          isEmpty,
          reason: 'the broken bookmark must be forgotten, not carried over',
        );
        expect(toaster.calls, hasLength(1));
        expect(
          toaster.calls.single.type,
          WpToastType.success,
          reason: 'a bookmark failure is not a user-facing error',
        );
      },
    );

    testWidgets(
      'bookmark startAccess failure falls back to the dialog, no error '
      'toast, and nothing needs to be stopped',
      (tester) async {
        final toaster = _FakeToaster();
        final remembered = p.join(_downloadsPath, 'already-chosen.json');
        final paths = _PathStore(
          exportPath: remembered,
          exportBookmark: 'bm-broken',
        );
        final fresh = p.join(_downloadsPath, 'fresh-export.json');
        final picker = _FakePicker([fresh]);
        final bookmarks = _FakeBookmarks(
          isSupported: true,
          resolveResponses: {
            'bm-broken': BookmarkResolution(path: remembered, isStale: false),
          },
          startAccessResponses: {'bm-broken': false},
        );
        final sut = _controller(
          fs: fs,
          toaster: toaster,
          downloads: Directory(_downloadsPath),
          pathStore: paths,
          pickPath: picker.call,
          bookmarks: bookmarks,
        );

        await _withContext(tester, (ctx) async {
          await sut.export(ctx);
        });

        expect(picker.callCount, 1);
        expect(
          bookmarks.stopAccessCalls,
          isEmpty,
          reason: 'no session was ever started, nothing to balance',
        );
        expect(toaster.calls.single.type, WpToastType.success);
      },
    );

    testWidgets(
      'stale bookmark recreation failure falls back to the dialog, but '
      'still balances the access session that was already started',
      (tester) async {
        final toaster = _FakeToaster();
        final remembered = p.join(_downloadsPath, 'already-chosen.json');
        final paths = _PathStore(
          exportPath: remembered,
          exportBookmark: 'bm-old',
        );
        final fresh = p.join(_downloadsPath, 'fresh-export.json');
        final picker = _FakePicker([fresh]);
        final bookmarks = _FakeBookmarks(
          isSupported: true,
          resolveResponses: {
            'bm-old': BookmarkResolution(path: remembered, isStale: true),
          },
          startAccessResponses: {'bm-old': true},
          createResponses: [null],
        );
        final sut = _controller(
          fs: fs,
          toaster: toaster,
          downloads: Directory(_downloadsPath),
          pathStore: paths,
          pickPath: picker.call,
          bookmarks: bookmarks,
        );

        await _withContext(tester, (ctx) async {
          await sut.export(ctx);
        });

        expect(bookmarks.startAccessCalls, ['bm-old']);
        expect(
          bookmarks.stopAccessCalls,
          ['bm-old'],
          reason:
              'the started session must be balanced even though the '
              'target turned out unusable',
        );
        expect(picker.callCount, 1);
        expect(toaster.calls.single.type, WpToastType.success);
      },
    );

    testWidgets(
      'a write failure against a bookmarked remembered path still balances '
      'stopAccess before falling back to the dialog',
      (tester) async {
        // Same "parent replaced by a file" trigger as the Ticket 03 test
        // above, this time with an active bookmark session around it.
        await fs.directory(_downloadsPath).create(recursive: true);
        await fs.file(p.join(_downloadsPath, 'sub')).create();
        final stale = p.join(_downloadsPath, 'sub', settingsExportFileName);
        final paths = _PathStore(exportPath: stale, exportBookmark: 'bm-1');
        final fresh = p.join(_downloadsPath, 'fresh-export.json');
        final picker = _FakePicker([fresh]);
        final bookmarks = _FakeBookmarks(
          isSupported: true,
          resolveResponses: {
            'bm-1': BookmarkResolution(path: stale, isStale: false),
          },
          startAccessResponses: {'bm-1': true},
          createResponses: ['bm-fresh'],
        );
        final toaster = _FakeToaster();
        final sut = _controller(
          fs: fs,
          toaster: toaster,
          downloads: Directory(_downloadsPath),
          pathStore: paths,
          pickPath: picker.call,
          bookmarks: bookmarks,
        );

        await _withContext(tester, (ctx) async {
          await sut.export(ctx);
        });

        expect(bookmarks.startAccessCalls, ['bm-1']);
        expect(
          bookmarks.stopAccessCalls,
          ['bm-1'],
          reason: 'balanced even though the write itself failed',
        );
        expect(
          paths.exportBookmark,
          'bm-fresh',
          reason: 'the fresh export creates its own bookmark after success',
        );
        expect(picker.callCount, 1);
        expect(toaster.calls.single.type, WpToastType.success);
      },
    );

    testWidgets(
      'unsupported platform (Windows/Linux): bookmark methods are never '
      'called, behaviour is plain Ticket 03 pass-through',
      (tester) async {
        final toaster = _FakeToaster();
        final remembered = p.join(_downloadsPath, 'already-chosen.json');
        final paths = _PathStore(
          exportPath: remembered,
          // A leftover value from e.g. a synced settings file created on
          // macOS — must be ignored outright, not just fail gracefully.
          exportBookmark: 'irrelevant-bm',
        );
        final picker = _FakePicker([]);
        final bookmarks = _FakeBookmarks(isSupported: false);
        final sut = _controller(
          fs: fs,
          toaster: toaster,
          downloads: Directory(_downloadsPath),
          pathStore: paths,
          pickPath: picker.call,
          bookmarks: bookmarks,
        );

        await _withContext(tester, (ctx) async {
          await sut.export(ctx);
        });

        expect(bookmarks.resolveCalls, isEmpty);
        expect(bookmarks.startAccessCalls, isEmpty);
        expect(bookmarks.stopAccessCalls, isEmpty);
        expect(bookmarks.createCalls, isEmpty);
        expect(
          picker.callCount,
          0,
          reason:
              'the raw remembered path is used directly, Ticket 03 behaviour',
        );
        expect(toaster.calls.single.type, WpToastType.success);
      },
    );
  });

  // ───────────────────────────────────────────────────────────────────────
  // chooseNewLocation — the Ticket 05 affordance seam
  // ───────────────────────────────────────────────────────────────────────

  group('chooseNewLocation', () {
    testWidgets(
      'picks a new export location, writes nothing, imports nothing',
      (tester) async {
        final remembered = p.join(_downloadsPath, 'already-chosen.json');
        final fresh = p.join(_downloadsPath, 'newly-chosen.json');
        final paths = _PathStore(exportPath: remembered);
        final picker = _FakePicker([fresh]);
        SettingsExportBundle? applied;
        final sut = _controller(
          fs: fs,
          toaster: _FakeToaster(),
          downloads: Directory(_downloadsPath),
          pathStore: paths,
          pickPath: picker.call,
          apply: (bundle) async => applied = bundle,
        );

        final result = await sut.chooseNewLocation(forExport: true);

        expect(result, isTrue);
        expect(paths.exportPath, fresh);
        expect(picker.forExportCalls.single, isTrue);
        expect(
          await fs.file(fresh).exists(),
          isFalse,
          reason: 'choosing a location must not write the export file',
        );
        expect(
          applied,
          isNull,
          reason: 'choosing a location must not import anything',
        );
      },
    );

    testWidgets('cancelling leaves the previously remembered path and bookmark '
        'completely untouched', (tester) async {
      final remembered = p.join(_downloadsPath, 'already-chosen.json');
      final paths = _PathStore(
        importPath: remembered,
        importBookmark: 'bm-untouched',
      );
      final picker = _FakePicker([null]);
      final sut = _controller(
        fs: fs,
        toaster: _FakeToaster(),
        downloads: Directory(_downloadsPath),
        pathStore: paths,
        pickPath: picker.call,
      );

      final result = await sut.chooseNewLocation(forExport: false);

      expect(result, isFalse);
      expect(paths.importPath, remembered);
      expect(paths.importBookmark, 'bm-untouched');
      expect(
        paths.importBookmarkWrites,
        isEmpty,
        reason:
            'a cancelled pick must not touch the bookmark at all, not '
            'even clear-then-restore it',
      );
    });

    testWidgets(
      'choosing a new export location clears the old bookmark, so a later '
      'export cannot silently resolve back to the old path',
      (tester) async {
        final oldPath = p.join(_downloadsPath, 'old-export.json');
        final newPath = p.join(_downloadsPath, 'new-export.json');
        final paths = _PathStore(exportPath: oldPath, exportBookmark: 'bm-old');
        final picker = _FakePicker([newPath]);
        final bookmarks = _FakeBookmarks(isSupported: true);
        final sut = _controller(
          fs: fs,
          toaster: _FakeToaster(),
          downloads: Directory(_downloadsPath),
          pathStore: paths,
          pickPath: picker.call,
          bookmarks: bookmarks,
        );

        final result = await sut.chooseNewLocation(forExport: true);

        expect(result, isTrue);
        expect(paths.exportPath, newPath);
        expect(
          paths.exportBookmark,
          isEmpty,
          reason:
              'the stale bookmark from the old path must not survive — a '
              'later export() would otherwise resolve bm-old back to '
              'old-export.json and silently overwrite paths.exportPath '
              'with the old path again',
        );
      },
    );

    testWidgets(
      'choosing a new import location immediately gets its own bookmark, '
      'not the previous one',
      (tester) async {
        final oldPath = p.join(_downloadsPath, 'old-import.json');
        final newPath = p.join(_downloadsPath, 'new-import.json');
        await fs.directory(_downloadsPath).create(recursive: true);
        await fs
            .file(newPath)
            .writeAsString(
              const SettingsPortabilityService().encode(_sampleBundle),
            );
        final paths = _PathStore(importPath: oldPath, importBookmark: 'bm-old');
        final picker = _FakePicker([newPath]);
        final bookmarks = _FakeBookmarks(
          isSupported: true,
          createResponses: ['bm-new'],
        );
        final sut = _controller(
          fs: fs,
          toaster: _FakeToaster(),
          downloads: Directory(_downloadsPath),
          pathStore: paths,
          pickPath: picker.call,
          bookmarks: bookmarks,
        );

        final result = await sut.chooseNewLocation(forExport: false);

        expect(result, isTrue);
        expect(paths.importPath, newPath);
        expect(paths.importBookmark, 'bm-new');
        expect(bookmarks.createCalls, [newPath]);
      },
    );
  });
}
