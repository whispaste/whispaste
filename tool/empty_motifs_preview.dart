/// Native preview of the paper-cut empty-state motifs (#1595). Shows the
/// production [WpEmptyState] of Recordings, Notes and Snippets side by side;
/// a switch flips between the light, dark and Marine colour sets. Never opens
/// a user's database or settings, and its buttons do nothing.
///
/// flutter run -d macos -t tool/empty_motifs_preview.dart
/// (use `windows` or `linux` on those desktops). Add
/// --dart-define=EMPTY_MOTIFS_LOCALE=en for another app language.
/// Procedure and results: internal-notes.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/widgets/empty_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      title: 'WhisPaste Empty Motifs Fixture',
      size: Size(1320, 640),
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
  runApp(const _FixtureApp());
}

class _FixtureApp extends StatefulWidget {
  const _FixtureApp();

  @override
  State<_FixtureApp> createState() => _FixtureAppState();
}

/// [WpColors] is global, as in the app: a switch activates one set and
/// rebuilds the whole tree, the way the appearance setting does.
class _FixtureAppState extends State<_FixtureApp> {
  static const _sets = {
    'Hell': wpLightColors,
    'Dunkel': wpDarkColors,
    'Marine': wpNavyColors,
  };
  String _set = 'Hell';

  @override
  Widget build(BuildContext context) {
    final colors = _sets[_set]!;
    WpColors.activate(colors);
    return MaterialApp(
      key: ValueKey(_set),
      debugShowCheckedModeBanner: false,
      theme: wpThemeFor(colors),
      locale: const Locale(
        String.fromEnvironment('EMPTY_MOTIFS_LOCALE', defaultValue: 'de'),
      ),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        backgroundColor: colors.background,
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: SegmentedButton<String>(
                segments: [
                  for (final name in _sets.keys)
                    ButtonSegment(value: name, label: Text(name)),
                ],
                selected: {_set},
                onSelectionChanged: (s) => setState(() => _set = s.first),
              ),
            ),
            const Expanded(child: _Motifs()),
          ],
        ),
      ),
    );
  }
}

class _Motifs extends StatelessWidget {
  const _Motifs();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Row(
      children: [
        Expanded(
          child: WpEmptyState(
            icon: LucideIcons.mic,
            motif: WpEmptyMotif.recordings,
            title: l10n.historyEmpty,
            hint: l10n.historyNoRecordingsHint,
            actionLabel: l10n.dockDictate,
            onAction: () {},
          ),
        ),
        Expanded(
          child: WpEmptyState(
            icon: LucideIcons.stickyNote,
            motif: WpEmptyMotif.notes,
            title: l10n.notesEmptyTitle,
            hint: l10n.notesEmptyHint,
            actionLabel: l10n.notesNewNote,
            onAction: () {},
          ),
        ),
        Expanded(
          child: WpEmptyState(
            icon: LucideIcons.notebookText,
            motif: WpEmptyMotif.snippets,
            title: l10n.snippetsEmpty,
            hint: l10n.snippetsEmptyHint,
            actionLabel: l10n.snippetsAdd,
            onAction: () {},
          ),
        ),
      ],
    );
  }
}
