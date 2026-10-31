/// Tests for [SettingsPortabilitySection] — the standalone "Backup & Transfer"
/// settings section that hosts the file-based settings export/import entry
/// (moved out of AdvancedSection).
///
/// Only structural/render coverage lives here — tapping either button
/// resolves a real Downloads/Documents directory via `path_provider`,
/// which hangs in `flutter_test` without a platform-channel mock. The
/// actual export/import/round-trip behaviour is covered by
/// `test/services/settings_portability_controller_test.dart` and
/// `test/services/settings_portability_service_test.dart` against
/// injected fakes.
///
/// The second group covers discoverability: the section is reachable via the
/// settings search, and selecting its suggestion scrolls to the section and
/// draws the temporary highlight border around it.
///
/// The Ticket 05 group (remembered locations) exercises the interactive
/// choose-location affordance through the section's `controllerOverride`
/// test seam with a [SettingsPortabilityController] built entirely from
/// injected fakes ([_FakePicker], [MemoryFileSystem], a no-op bookmarks
/// service) — same approach as
/// `test/services/settings_portability_controller_test.dart` — so no real
/// `path_provider`/`file_selector` platform channel is ever touched.
///
/// The Ticket 26 group (Autosicherung) covers the same surface for the
/// automatic backup: what the section shows in each state, and that arming
/// the feature goes through the directory chooser and never through the
/// export file picker. The runs themselves live in
/// `test/services/settings_autosave_service_test.dart`, and the structural
/// no-dialog guarantee in
/// `test/services/settings_autosave_no_dialog_guard_test.dart`.
library;

import 'dart:io' show Platform;

import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:path/path.dart' as p;
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/features/settings/search/settings_search_provider.dart';
import 'package:whispaste/features/settings/sections/settings_portability_section.dart';
import 'package:whispaste/features/settings/settings_page.dart';
import 'package:whispaste/features/settings/widgets/settings_search_field.dart';
import 'package:whispaste/services/secure_bookmark_service.dart';
import 'package:whispaste/services/settings_autosave_folder_chooser.dart';
import 'package:whispaste/services/settings_portability_controller.dart';
import 'package:whispaste/services/settings_portability_service.dart';

import '../../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Fakes for the Ticket 05 remembered-location group
// ---------------------------------------------------------------------------

/// In-memory [SettingsNotifier] — same pattern as
/// `test/features/settings/sections/history_section_test.dart`. Holds the
/// portability paths the section displays and lets the injected controller
/// write them back through the real provider, so the UI re-renders.
class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier(this._settings);
  AppSettings _settings;

  AppSettings get current => state.value ?? _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    state = AsyncData(_settings);
  }
}

/// Fakes the native save/open dialog; responses are consumed in call order,
/// calls past the end return `null` (cancelled) so an unexpected extra
/// dialog fails loudly.
class _FakePicker {
  _FakePicker(this.responses);
  final List<String?> responses;
  int callCount = 0;
  final List<bool> forExportCalls = [];

  Future<String?> call({
    required bool forExport,
    required String suggestedName,
    String? initialDirectory,
  }) async {
    forExportCalls.add(forExport);
    final response = callCount < responses.length ? responses[callCount] : null;
    callCount++;
    return response;
  }
}

/// Bookmarks are a macOS-only concern; the widget tests here pin them off
/// so they behave identically on every test host.
class _NoBookmarks extends SecureBookmarkService {
  const _NoBookmarks();
  @override
  bool get isSupported => false;
}

/// A real [SettingsPortabilityController] wired to the fakes above and to
/// [notifier]'s portability paths — the production wiring shape, minus every
/// platform channel. [log] records `gather`/`apply` calls so tests can
/// assert the choose-location affordance never runs an export/import.
SettingsPortabilityController _testController({
  required _FakeSettingsNotifier notifier,
  required _FakePicker picker,
  required MemoryFileSystem fs,
  required List<String> log,
}) {
  Future<void> update(
    SettingsPortabilityPathSettings Function(SettingsPortabilityPathSettings)
    updater,
  ) => notifier.updateSettings(
    (s) => s.copyWithSections(portabilityPaths: updater(s.portabilityPaths)),
  );

  return SettingsPortabilityController(
    gather: () async {
      log.add('gather');
      return const SettingsExportBundle(settings: {}, replacements: []);
    },
    apply: (_) async => log.add('apply'),
    service: SettingsPortabilityService(fileSystem: fs),
    downloadsDirFn: () async => null,
    documentsDirFn: () async => null,
    getExportPath: () async => notifier.current.portabilityPaths.exportPath,
    setExportPath: (path) => update((s) => s.copyWith(exportPath: path)),
    getImportPath: () async => notifier.current.portabilityPaths.importPath,
    setImportPath: (path) => update((s) => s.copyWith(importPath: path)),
    getExportBookmark: () async =>
        notifier.current.portabilityPaths.exportBookmark,
    setExportBookmark: (b) => update((s) => s.copyWith(exportBookmark: b)),
    getImportBookmark: () async =>
        notifier.current.portabilityPaths.importBookmark,
    setImportBookmark: (b) => update((s) => s.copyWith(importBookmark: b)),
    bookmarks: const _NoBookmarks(),
    pickPath: picker.call,
    toaster: (context, type, message) {},
  );
}

/// Platform-native absolute base path — see the style note in
/// `settings_portability_controller_test.dart` for why a hardcoded POSIX
/// literal would break on Windows.
final _basePath = Platform.isWindows
    ? r'C:\Users\tester\Documents'
    : '/Users/tester/Documents';

void main() {
  group('SettingsPortabilitySection', () {
    testWidgets('renders without error', (tester) async {
      await tester.pumpWidget(makeTestable(const SettingsPortabilitySection()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('renders one row per direction, each with its own action '
        'button', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: SettingsPortabilitySection()),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Backup & Transfer'), findsOneWidget);
      expect(find.byKey(const ValueKey(kPortabilityExportRowKey)), findsOne);
      expect(find.byKey(const ValueKey(kPortabilityImportRowKey)), findsOne);
      expect(find.widgetWithText(OutlinedButton, 'Export'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Import'), findsOneWidget);
    });

    testWidgets(
      'each direction is complete on its own row — location, action and '
      'chooser together, and nothing from the other direction (E10=b)',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: SettingsPortabilitySection()),
            locale: const Locale('en'),
          ),
        );
        await tester.pumpAndSettle();

        final exportRow = find.byKey(const ValueKey(kPortabilityExportRowKey));
        final importRow = find.byKey(const ValueKey(kPortabilityImportRowKey));

        // This is the structural point of the layout: reading a path and
        // finding the button that acts on it must not require pairing two
        // parallel lists by position.
        for (final (row, own, foreign, action, tooltip) in [
          (
            exportRow,
            "You'll be asked on first export",
            "You'll be asked on first import",
            'Export',
            'Choose a different export destination (nothing is exported yet)',
          ),
          (
            importRow,
            "You'll be asked on first import",
            "You'll be asked on first export",
            'Import',
            'Choose a different import source (nothing is imported yet)',
          ),
        ]) {
          expect(find.descendant(of: row, matching: find.text(own)), findsOne);
          expect(
            find.descendant(of: row, matching: find.text(foreign)),
            findsNothing,
            reason: 'a direction row must not carry the other direction',
          );
          expect(
            find.descendant(
              of: row,
              matching: find.widgetWithText(OutlinedButton, action),
            ),
            findsOne,
          );
          expect(
            find.descendant(of: row, matching: find.byTooltip(tooltip)),
            findsOne,
          );
        }
      },
    );

    // Acceptance criterion of Ticket 25: "keine zwei Textebenen der Sektion
    // sagen mehr dasselbe". Asserted mechanically over whatever the section
    // actually renders rather than against two pinned literals, so it keeps
    // holding after the next wording change — and so Ticket 26's toggle and
    // timestamp line cannot quietly reintroduce a duplicate layer.
    //
    // Scoped to the unset state on purpose, and not a universal invariant of
    // the section: with a remembered location on both directions the user may
    // legitimately have picked the same file for both (export a backup, then
    // import it back), and the section then renders that one path twice. What
    // is asserted here is that the section's own *prose* never says a thing
    // twice — not that no two strings on the surface can ever coincide.
    for (final locale in ['de', 'en', 'he']) {
      testWidgets('no two rendered text layers repeat each other ($locale)', (
        tester,
      ) async {
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: SettingsPortabilitySection()),
            locale: Locale(locale),
          ),
        );
        await tester.pumpAndSettle();

        final texts = tester
            .widgetList<Text>(
              find.descendant(
                of: find.byType(SettingsPortabilitySection),
                matching: find.byType(Text),
              ),
            )
            .map((t) => t.data)
            .whereType<String>()
            .toList();

        expect(
          texts.length,
          greaterThanOrEqualTo(6),
          reason: 'section header, both locations and both actions render',
        );
        expect(
          texts.toSet(),
          hasLength(texts.length),
          reason: 'a text layer is repeated verbatim: $texts',
        );
      });
    }
  });

  group('Settings search — portability section is discoverable', () {
    List<String> sectionKeysFor(String query, {String locale = 'en'}) =>
        matchSettingsEntries(
          kSettingsSearchTable,
          query,
          locale,
        ).map((e) => e.sectionKey).toList();

    test('EN queries (export, import, migrate, backup, restore) match', () {
      for (final query in [
        'export',
        'import',
        'migrate',
        'transfer',
        'move',
        'backup',
        'restore',
      ]) {
        expect(
          sectionKeysFor(query),
          contains('settingsPortability'),
          reason: '"$query" must find the portability section',
        );
      }
    });

    test('DE queries (Umzug, übertragen, sichern, …) match', () {
      for (final query in [
        'Umzug',
        'übertragen',
        'sichern',
        'wiederherstellen',
        'Gerätewechsel',
      ]) {
        expect(
          sectionKeysFor(query, locale: 'de'),
          contains('settingsPortability'),
          reason: '"$query" must find the portability section',
        );
      }
    });
  });

  group('Settings search — jump to portability section sets highlight', () {
    testWidgets(
      'selecting the search suggestion scrolls to the section and draws '
      'the highlight border, which auto-clears afterwards',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(const SettingsPage(), locale: const Locale('en')),
        );
        await tester.pumpAndSettle();

        final element = tester.element(find.byType(SettingsPage));
        final container = ProviderScope.containerOf(element);

        // Type a query that uniquely matches the portability entry; set the
        // provider directly as well to bypass the 250 ms debounce.
        final field = find.descendant(
          of: find.byType(SettingsSearchField),
          matching: find.byType(TextField),
        );
        await tester.enterText(field, 'migrate');
        container.read(settingsSearchQueryProvider.notifier).set('migrate');
        await tester.pumpAndSettle();

        final matches = container.read(settingsSearchMatchesProvider);
        expect(
          matches.map((e) => e.sectionKey),
          contains('settingsPortability'),
          reason: '"migrate" must surface the portability suggestion',
        );
        expect(
          matches.first.sectionKey,
          'settingsPortability',
          reason: '"migrate" must match only the portability entry',
        );

        // ArrowDown highlights the first suggestion; Enter selects it — the
        // same path a keyboard user takes (see settings_search_field.dart's
        // _selectEntry, which sets scroll + highlight targets).
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();

        expect(
          container.read(settingsHighlightTargetProvider),
          'settingsPortability',
          reason: 'Selecting the suggestion must set the highlight target',
        );

        // Let the scroll-jump and the highlight animation play out.
        await tester.pumpAndSettle();

        // The sectionWithHighlight wrapper (settings_page.dart) renders the
        // highlight as a bordered BoxDecoration on an AnimatedContainer
        // directly around the section widget — in the *foreground* decoration,
        // so the ring is painted over the section instead of insetting it by
        // its own 2 px (see settings_highlight_layout_shift_test.dart).
        final wrapperFinder = find
            .ancestor(
              of: find.byType(SettingsPortabilitySection),
              matching: find.byType(AnimatedContainer),
            )
            .first;
        final highlighted = tester.widget<AnimatedContainer>(wrapperFinder);
        expect(
          highlighted.foregroundDecoration,
          isA<BoxDecoration>().having((d) => d.border, 'border', isNotNull),
          reason: 'Jump target must carry the highlight border',
        );

        // The highlight clears itself after 1.5 s (SettingsPage timer).
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();

        expect(container.read(settingsHighlightTargetProvider), isNull);
        final cleared = tester.widget<AnimatedContainer>(wrapperFinder);
        expect(
          (cleared.foregroundDecoration as BoxDecoration?)?.border,
          isNull,
          reason: 'Highlight border must be gone after the clear timer',
        );
      },
    );
  });

  group('Remembered locations (Ticket 05)', () {
    const chooseExportTooltip =
        'Choose a different export destination (nothing is exported yet)';
    const chooseImportTooltip =
        'Choose a different import source (nothing is imported yet)';

    _FakeSettingsNotifier seeded({
      String exportPath = '',
      String importPath = '',
    }) => _FakeSettingsNotifier(
      AppSettings.defaults.copyWithSections(
        portabilityPaths: SettingsPortabilityPathSettings(
          exportPath: exportPath,
          importPath: importPath,
        ),
      ),
    );

    Future<void> pump(
      WidgetTester tester,
      _FakeSettingsNotifier notifier, {
      SettingsPortabilityController? controller,
      Locale locale = const Locale('en'),
      double? width,
      double textScale = 1.0,
    }) async {
      Widget section = SingleChildScrollView(
        child: SettingsPortabilitySection(controllerOverride: controller),
      );
      if (width != null) {
        section = Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: section),
        );
      }
      if (textScale != 1.0) {
        final inner = section;
        section = Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: inner,
          ),
        );
      }
      await tester.pumpWidget(
        makeTestable(
          section,
          overrides: [settingsProvider.overrideWith(() => notifier)],
          locale: locale,
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'shows the remembered export location — basename intact, full path '
      'in a tooltip — while the import side shows the honest unset state',
      (tester) async {
        final exportPath = p.join(
          _basePath,
          'backups',
          'whispaste-settings-export.json',
        );
        await pump(tester, seeded(exportPath: exportPath));

        expect(find.text('whispaste-settings-export.json'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (w) => w is Tooltip && w.message == exportPath,
          ),
          findsOneWidget,
          reason: 'the full path must stay reachable via tooltip',
        );
        expect(find.text("You'll be asked on first import"), findsOneWidget);
      },
    );

    testWidgets('no remembered location yet → both directions show the honest '
        '"asked on first …" state, never an invented suggestion path', (
      tester,
    ) async {
      await pump(tester, seeded());

      expect(find.text("You'll be asked on first export"), findsOneWidget);
      expect(find.text("You'll be asked on first import"), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is Tooltip && (w.message?.contains(p.separator) ?? false),
        ),
        findsNothing,
        reason: 'no path may be displayed that the user never confirmed',
      );
    });

    testWidgets(
      'the choose-location affordance calls chooseNewLocation — it only '
      'sets the location: nothing is exported, imported, or written',
      (tester) async {
        final oldPath = p.join(_basePath, 'old-export.json');
        final newPath = p.join(_basePath, 'new-export.json');
        final notifier = seeded(exportPath: oldPath);
        final picker = _FakePicker([newPath]);
        final fs = MemoryFileSystem.test(
          style: Platform.isWindows
              ? FileSystemStyle.windows
              : FileSystemStyle.posix,
        );
        final log = <String>[];
        await pump(
          tester,
          notifier,
          controller: _testController(
            notifier: notifier,
            picker: picker,
            fs: fs,
            log: log,
          ),
        );

        await tester.tap(find.byTooltip(chooseExportTooltip));
        await tester.pumpAndSettle();

        expect(picker.forExportCalls, [true]);
        expect(
          log,
          isEmpty,
          reason: 'choosing a location must not run export or import',
        );
        expect(
          fs.file(newPath).existsSync(),
          isFalse,
          reason: 'choosing a location must not write the export file',
        );
        expect(notifier.current.portabilityPaths.exportPath, newPath);
        expect(
          find.text('new-export.json'),
          findsOneWidget,
          reason: 'the displayed location must update reactively',
        );
      },
    );

    testWidgets(
      'cancelling the chooser leaves the displayed location unchanged',
      (tester) async {
        final oldPath = p.join(_basePath, 'old-import.json');
        final notifier = seeded(importPath: oldPath);
        final picker = _FakePicker([null]);
        final fs = MemoryFileSystem.test(
          style: Platform.isWindows
              ? FileSystemStyle.windows
              : FileSystemStyle.posix,
        );
        final log = <String>[];
        await pump(
          tester,
          notifier,
          controller: _testController(
            notifier: notifier,
            picker: picker,
            fs: fs,
            log: log,
          ),
        );

        await tester.tap(find.byTooltip(chooseImportTooltip));
        await tester.pumpAndSettle();

        expect(picker.callCount, 1);
        expect(log, isEmpty);
        expect(notifier.current.portabilityPaths.importPath, oldPath);
        expect(find.text('old-import.json'), findsOneWidget);
      },
    );

    testWidgets(
      'a very long path under the Hebrew RTL locale in a narrow layout '
      'truncates without overflow and keeps the basename visible',
      (tester) async {
        final longPath = p.joinAll([
          _basePath,
          'a-very-long-directory-name-level-one',
          'an-even-longer-directory-name-level-two',
          'and-one-more-nested-level-three',
          'whispaste-settings-export.json',
        ]);
        await pump(
          tester,
          seeded(exportPath: longPath, importPath: longPath),
          locale: const Locale('he'),
          width: 480,
        );

        expect(
          tester.takeException(),
          isNull,
          reason: 'a long path must not overflow the line',
        );
        expect(
          find.text('whispaste-settings-export.json'),
          findsNWidgets(2),
          reason:
              'the basename is the informative end and must never be the '
              'first thing to disappear',
        );
      },
    );

    // Ticket 25 acceptance criterion: 280 dp panel width at text scale 1.3.
    // The real settings column never gets that narrow (≈680 dp at the
    // 800 dp minimum window), so this is a stress floor, not a layout the
    // user rests on — but the direction row now packs a path, a button and
    // an icon button onto one line, and only the path is allowed to give
    // way. German is the load-bearing case: "Exportieren"/"Importieren"
    // are roughly twice the width of "Export"/"Import", so an English-only
    // check would pass over exactly the locale that overflows.
    for (final locale in ['de', 'en', 'he']) {
      for (final width in [280.0, 320.0, 480.0]) {
        testWidgets(
          'direction rows do not overflow at ${width}dp / 1.3x ($locale)',
          (tester) async {
            await pump(
              tester,
              seeded(
                exportPath: p.join(_basePath, 'whispaste-settings-export.json'),
              ),
              locale: Locale(locale),
              width: width,
              textScale: 1.3,
            );

            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });

  // -------------------------------------------------------------------------
  // Ticket 26 — Autosicherung
  // -------------------------------------------------------------------------
  //
  // The runs themselves belong to `test/services/settings_autosave_*`; what
  // is asserted here is the surface: what the section shows in each state,
  // and that arming the feature goes through the *directory* chooser and
  // never through the export file picker (H1, seen from the outside).
  group('Autosicherung (Ticket 26)', () {
    const chooseFolderTooltip =
        'Choose a different folder for automatic backups (nothing is backed '
        'up yet)';
    final backupFolder = p.join(_basePath, 'WhisPaste-Backups');

    _FakeSettingsNotifier seededAutosave({
      bool enabled = false,
      String folder = '',
      String lastSuccess = '',
      String lastError = '',
    }) => _FakeSettingsNotifier(
      AppSettings.defaults.copyWithSections(
        autosave: SettingsAutosaveSettings(
          enabled: enabled,
          folder: folder,
          lastSuccess: lastSuccess,
          lastError: lastError,
        ),
      ),
    );

    /// Pumps the section with a real [SettingsAutosaveFolderChooser] whose
    /// only fake part is the native panel, and a real export controller whose
    /// file picker fails the test if it is ever reached.
    Future<({_FakePicker exportPicker, List<String?> folderPrompts})> pump(
      WidgetTester tester,
      _FakeSettingsNotifier notifier, {
      List<String?> folderResponses = const [],
      Locale locale = const Locale('en'),
    }) async {
      final exportPicker = _FakePicker([]);
      final prompts = <String?>[];
      var call = 0;
      final chooser = SettingsAutosaveFolderChooser(
        pickFolder: ({String? initialDirectory}) async {
          prompts.add(initialDirectory);
          final response = call < folderResponses.length
              ? folderResponses[call]
              : null;
          call++;
          return response;
        },
        bookmarks: const _NoBookmarks(),
      );

      await tester.pumpWidget(
        makeTestable(
          SingleChildScrollView(
            child: SettingsPortabilitySection(
              controllerOverride: _testController(
                notifier: notifier,
                picker: exportPicker,
                fs: MemoryFileSystem.test(
                  style: Platform.isWindows
                      ? FileSystemStyle.windows
                      : FileSystemStyle.posix,
                ),
                log: [],
              ),
              autosaveFolderChooserOverride: chooser,
            ),
          ),
          overrides: [settingsProvider.overrideWith(() => notifier)],
          locale: locale,
        ),
      );
      await tester.pumpAndSettle();
      return (exportPicker: exportPicker, folderPrompts: prompts);
    }

    Finder switchIn(Finder row) =>
        find.descendant(of: row, matching: find.byType(Switch));

    final autosaveRow = find.byKey(const ValueKey(kPortabilityAutosaveRowKey));
    final statusLine = find.byKey(
      const ValueKey(kPortabilityAutosaveStatusKey),
    );

    testWidgets('off by default, and off costs the section one quiet line — '
        'no destination, no chooser, no status', (tester) async {
      await pump(tester, seededAutosave());

      expect(autosaveRow, findsOne);
      expect(find.text('Automatic backup'), findsOne);
      expect(tester.widget<Switch>(switchIn(autosaveRow)).value, isFalse);
      expect(find.byTooltip(chooseFolderTooltip), findsNothing);
      expect(statusLine, findsNothing);
    });

    testWidgets('it sits between the two directions — under the export it '
        'automates, above the import it does not', (tester) async {
      await pump(tester, seededAutosave());

      double top(Finder f) => tester.getTopLeft(f).dy;
      expect(
        top(find.byKey(const ValueKey(kPortabilityExportRowKey))),
        lessThan(top(autosaveRow)),
      );
      expect(
        top(autosaveRow),
        lessThan(top(find.byKey(const ValueKey(kPortabilityImportRowKey)))),
      );
    });

    testWidgets('turning it on asks for a folder — the directory chooser, '
        'never the export file picker (H1)', (tester) async {
      final notifier = seededAutosave();
      final fakes = await pump(
        tester,
        notifier,
        folderResponses: [backupFolder],
      );

      await tester.tap(switchIn(autosaveRow));
      await tester.pumpAndSettle();

      expect(fakes.folderPrompts, hasLength(1));
      expect(
        fakes.exportPicker.callCount,
        0,
        reason:
            'the autosave surface must never route into the export file '
            'dialog — that flow falls back to a dialog on every bookmark '
            'failure, which is exactly what H1 forbids',
      );
      expect(notifier.current.autosave.enabled, isTrue);
      expect(notifier.current.autosave.folder, backupFolder);
      // The manual export destination is a separate setting and must not
      // have moved (decision E11c).
      expect(notifier.current.portabilityPaths.exportPath, isEmpty);
      expect(find.text('WhisPaste-Backups'), findsOne);
      expect(find.byTooltip(chooseFolderTooltip), findsOne);
    });

    testWidgets('cancelling the folder dialog leaves the switch off and '
        'nothing persisted', (tester) async {
      final notifier = seededAutosave();
      final fakes = await pump(tester, notifier, folderResponses: [null]);

      await tester.tap(switchIn(autosaveRow));
      await tester.pumpAndSettle();

      expect(fakes.folderPrompts, hasLength(1));
      expect(notifier.current.autosave.enabled, isFalse);
      expect(notifier.current.autosave.folder, isEmpty);
      expect(tester.widget<Switch>(switchIn(autosaveRow)).value, isFalse);
    });

    testWidgets('turning it off keeps the folder, so switching it back on '
        'does not cost a second trip through the panel', (tester) async {
      final notifier = seededAutosave(enabled: true, folder: backupFolder);
      final fakes = await pump(tester, notifier);

      await tester.tap(switchIn(autosaveRow));
      await tester.pumpAndSettle();
      expect(notifier.current.autosave.enabled, isFalse);
      expect(notifier.current.autosave.folder, backupFolder);

      await tester.tap(switchIn(autosaveRow));
      await tester.pumpAndSettle();
      expect(notifier.current.autosave.enabled, isTrue);
      expect(fakes.folderPrompts, isEmpty);
    });

    testWidgets('the chooser repoints the folder without touching the '
        'export destination', (tester) async {
      final moved = p.join(_basePath, 'Elsewhere');
      final notifier = seededAutosave(enabled: true, folder: backupFolder);
      final fakes = await pump(tester, notifier, folderResponses: [moved]);

      await tester.tap(find.byTooltip(chooseFolderTooltip));
      await tester.pumpAndSettle();

      expect(fakes.folderPrompts.single, backupFolder);
      expect(notifier.current.autosave.folder, moved);
      expect(notifier.current.portabilityPaths.exportPath, isEmpty);
    });

    testWidgets('enabled but never run says so, rather than implying a '
        'backup exists', (tester) async {
      await pump(tester, seededAutosave(enabled: true, folder: backupFolder));

      expect(tester.widget<Text>(statusLine).data, 'No backup yet');
    });

    testWidgets('a successful run is visible as a timestamp and nothing '
        'else (E11d)', (tester) async {
      const iso = '2026-08-11T12:30:00.000Z';
      await pump(
        tester,
        seededAutosave(enabled: true, folder: backupFolder, lastSuccess: iso),
      );

      final expected = DateFormat.yMd(
        'en',
      ).add_Hm().format(DateTime.parse(iso).toLocal());
      expect(tester.widget<Text>(statusLine).data, 'Last backup: $expected');
    });

    testWidgets('a failure never renders as a success, and does not throw '
        'away the last backup that worked', (tester) async {
      const iso = '2026-08-11T12:30:00.000Z';
      await pump(
        tester,
        seededAutosave(
          enabled: true,
          folder: backupFolder,
          lastSuccess: iso,
          lastError: '2026-08-11T13:00:00.000Z',
        ),
      );

      final expected = DateFormat.yMd(
        'en',
      ).add_Hm().format(DateTime.parse(iso).toLocal());
      expect(
        tester.widget<Text>(statusLine).data,
        'Last attempt failed — last backup: $expected',
      );
    });

    testWidgets('a failure with no successful run behind it reports only '
        'the failure', (tester) async {
      await pump(
        tester,
        seededAutosave(
          enabled: true,
          folder: backupFolder,
          lastError: '2026-08-11T13:00:00.000Z',
        ),
      );

      expect(tester.widget<Text>(statusLine).data, 'Backup failed');
    });

    // Same overflow sweep the direction rows get: the enabled state is the
    // tall one (name, destination, status line) and German is the widest.
    for (final locale in ['de', 'en', 'he']) {
      for (final width in [280.0, 480.0]) {
        testWidgets(
          'the enabled autosave row does not overflow at ${width}dp / 1.3x '
          '($locale)',
          (tester) async {
            final notifier = seededAutosave(
              enabled: true,
              folder: backupFolder,
              lastSuccess: '2026-08-11T12:30:00.000Z',
            );
            await tester.pumpWidget(
              makeTestable(
                Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: width,
                    child: Builder(
                      builder: (context) => MediaQuery(
                        data: MediaQuery.of(
                          context,
                        ).copyWith(textScaler: const TextScaler.linear(1.3)),
                        child: const SingleChildScrollView(
                          child: SettingsPortabilitySection(),
                        ),
                      ),
                    ),
                  ),
                ),
                overrides: [settingsProvider.overrideWith(() => notifier)],
                locale: Locale(locale),
              ),
            );
            await tester.pumpAndSettle();

            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });
}
