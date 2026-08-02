/// Tests for [SettingsPortabilityController] — orchestrates gather/apply +
/// path resolution + toasts for the settings-portability feature.
///
/// Mirrors `test/services/history/history_exporter_test.dart`: injectable
/// fakes for every collaborator, no real filesystem, no real Riverpod.
library;

import 'dart:io';

import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';
import 'package:whispaste/services/settings_portability_controller.dart';
import 'package:whispaste/services/settings_portability_service.dart';
import 'package:whispaste/widgets/toast.dart';

// SettingsPortabilityController.resolvePath() joins the injected directory
// with the export filename via the platform-default `package:path` (correct
// for real production paths from path_provider). The fixture's fake
// directories must therefore be genuine platform-native absolute paths, and
// the MemoryFileSystem must be told to use the matching style — a hardcoded
// POSIX literal like '/downloads' silently broke every test in this file on
// Windows CI (FileSystemException: No such file or directory, path =
// 'downloads') because MemoryFileSystem.test() defaults to posix regardless
// of host OS, while the real `p.join` used by the controller runs in
// Windows-native style there.
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

const _sampleBundle = SettingsExportBundle(
  customVocabulary: 'WhisPaste',
  hotkey: HotkeySettings(),
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

SettingsPortabilityController _controller({
  required MemoryFileSystem fs,
  required _FakeToaster toaster,
  GatherBundleFn? gather,
  ApplyBundleFn? apply,
  Directory? downloads,
  Directory? documents,
}) {
  return SettingsPortabilityController(
    gather: gather ?? () async => _sampleBundle,
    apply: apply ?? (_) async {},
    service: SettingsPortabilityService(fileSystem: fs),
    downloadsDirFn: () async => downloads,
    documentsDirFn: () async => documents,
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
    final sut = _controller(
      fs: fs,
      toaster: toaster,
      downloads: Directory(_downloadsPath),
      gather: () async => throw Exception('db unavailable'),
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
    expect(applied!.customVocabulary, 'WhisPaste');
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

  testWidgets('import shows a "not found" toast when no export file exists', (
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

    await _withContext(tester, (ctx) async {
      await sut.import(ctx);
    });

    expect(applyCalled, isFalse);
    expect(toaster.calls, hasLength(1));
    expect(toaster.calls.single.type, WpToastType.error);
    expect(
      toaster.calls.single.message,
      l10n.settingsPortabilityImportNotFound(
        p.join(_downloadsPath, settingsExportFileName),
      ),
    );
  });

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
}
