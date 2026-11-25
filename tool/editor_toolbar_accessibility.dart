/// Native screen-reader fixture for #1372 (follow-up of #652). Shows the
/// production editor block (toolbar, find/replace bar, text view and "More"
/// menus) with a sample text; never opens a user's database or settings.
///
/// flutter run -d macos -t tool/editor_toolbar_accessibility.dart
/// Add --dart-define=EDITOR_TOOLBAR_NARROW=true for a 320 dp editor, where
/// the last buttons move into the "More" menu, or
/// --dart-define=EDITOR_TOOLBAR_LOCALE=en for another app language.
/// Procedure and results: internal-notes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:whispaste/core/accessibility/accessibility_reply_binding.dart';
import 'package:whispaste/core/editor/editor_text_view.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/widgets/find_replace.dart';
import 'package:whispaste/widgets/wp_text_editor.dart';
import 'package:whispaste/widgets/wp_text_field.dart';

const _narrow = bool.fromEnvironment('EDITOR_TOOLBAR_NARROW');

Future<void> main() async {
  WpRenderEngineBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      title: 'WhisPaste Editor Accessibility Fixture',
      size: Size(900, 640),
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
  runApp(
    ProviderScope(
      overrides: [editorTextViewProvider.overrideWith(_MemoryTextView.new)],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: wpThemeFor(WpColors.current),
        locale: const Locale(
          String.fromEnvironment('EDITOR_TOOLBAR_LOCALE', defaultValue: 'de'),
        ),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: const _FixturePage(),
      ),
    ),
  );
}

/// Text view choices live for the session only; nothing is written.
class _MemoryTextView extends EditorTextViewNotifier {
  @override
  Future<EditorTextView> build() async => EditorTextView.standard;

  @override
  Future<void> choose(EditorTextView view) async => state = AsyncData(view);
}

class _FixturePage extends StatefulWidget {
  const _FixturePage();

  @override
  State<_FixturePage> createState() => _FixturePageState();
}

class _FixturePageState extends State<_FixturePage> {
  final _controller = WpFindHighlightController(
    text:
        'Einkaufsliste für Samstag\n'
        'Milch, Brot und Kaffee kaufen. Danach Kaffee mit Anna.\n'
        'Shopping list: milk, bread, coffee.',
  );
  final _focus = FocusNode(debugLabel: 'fixture.body');

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A button before and after the editor, so the Tab order around the
    // block (before -> text -> toolbar -> after) can be heard as well.
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextButton(
              autofocus: true,
              onPressed: () {},
              child: const Text('Vorher / Before'),
            ),
            Expanded(
              child: SizedBox(
                width: _narrow ? 320 : null,
                child: WpTextEditor(
                  testId: 'notes-editor',
                  controller: _controller,
                  focusNode: _focus,
                  variant: WpTextFieldVariant.passage,
                  expands: true,
                  semanticsLabel: L10n.of(context).notesLongEditorLabel,
                  onSave: () {},
                  onInsertSnippet: () {},
                  onSaveSelectionAsSnippet: () {},
                ),
              ),
            ),
            TextButton(onPressed: () {}, child: const Text('Nachher / After')),
          ],
        ),
      ),
    );
  }
}
