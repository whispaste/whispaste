/// Standalone dev gallery for [WpButton] — NOT wired into the production app,
/// following the same separate-entrypoint pattern as
/// `main_smart_mode_debug.dart`.
///
/// Run it with:
///
///   flutter run -t lib/main_wp_button_gallery.dart -d macos
///
/// It shows the full Variant × Tone × Size matrix in every state the component
/// can be *put* into from the outside (resting, with icon, disabled, loading)
/// and a theme switch, so dark and light can be captured from one running
/// process. The three pointer/keyboard states cannot be forced from code
/// without faking them, so the gallery makes them reachable instead: the first
/// button autofocuses (ring), Tab walks the matrix, and hover/press are the
/// mouse's job. That is deliberate — the dropdown bug this component's state
/// doctrine comes from was invisible on a resting screenshot.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';

import 'core/theme/theme.dart';
import 'core/theme/tokens.dart';
import 'widgets/wp_button.dart';

/// Width of one state column — wide enough that a standard accent button and
/// its dense twin sit on the same grid.
const double _kCellWidth = 190;

/// Width of the leading "variant · tone" label column.
const double _kLabelWidth = 170;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Distinct title so this window is never confused with the real app's.
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(title: 'WpButton Gallery', size: Size(1180, 980)),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
  runApp(const WpButtonGalleryApp());
}

class WpButtonGalleryApp extends StatefulWidget {
  const WpButtonGalleryApp({super.key});

  @override
  State<WpButtonGalleryApp> createState() => _WpButtonGalleryAppState();
}

class _WpButtonGalleryAppState extends State<WpButtonGalleryApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'WpButton Gallery',
      theme: wpDarkTheme(),
      home: const _GalleryScreen(),
    );
  }
}

class _GalleryScreen extends StatelessWidget {
  const _GalleryScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(WpSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Header(),
              const SizedBox(height: WpSpacing.xl),
              const _Matrix(size: WpButtonSize.standard),
              const SizedBox(height: WpSpacing.xxl),
              const _Matrix(size: WpButtonSize.dense),
              const SizedBox(height: WpSpacing.xxl),
              Text('expanded', style: theme.textTheme.titleLarge),
              const SizedBox(height: WpSpacing.xs),
              Text(
                'Füllt die Elternbreite — ersetzt SizedBox(width: infinity).',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: WpSpacing.sm),
              SizedBox(
                width: 420,
                child: Semantics(
                  label: 'Weiter',
                  button: true,
                  child: const WpButton(
                    label: 'Weiter',
                    variant: WpButtonVariant.primary,
                    onPressed: _noop,
                    expanded: true,
                  ),
                ),
              ),
              const SizedBox(height: WpSpacing.md),
              SizedBox(
                width: 420,
                child: Semantics(
                  label: 'Alle Daten löschen',
                  button: true,
                  child: const WpButton(
                    label: 'Alle Daten löschen',
                    variant: WpButtonVariant.secondary,
                    tone: WpButtonTone.danger,
                    icon: LucideIcons.trash2,
                    onPressed: _noop,
                    expanded: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('WpButton', style: theme.textTheme.headlineLarge),
            ),
            // The Dark / Light pair that used to sit here went with the light
            // stack (2026-08-11). It had already stopped working: the gallery
            // pins `wpDarkTheme()`, so the flag the buttons flipped was
            // written and never read.
          ],
        ),
        const SizedBox(height: WpSpacing.xs),
        Text(
          'Hover und Pressed mit der Maus erzeugen — Fokus liegt beim Start '
          'auf dem ersten Button, Tab läuft die Matrix ab.',
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }
}

/// One full Variant × Tone block for a single [WpButtonSize].
class _Matrix extends StatelessWidget {
  const _Matrix({required this.size});

  final WpButtonSize size;

  bool get _isStandard => size == WpButtonSize.standard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _isStandard ? 'standard — 48 px' : 'dense — 32 px',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: WpSpacing.sm),
        const _ColumnHeaders(),
        const SizedBox(height: WpSpacing.xs),
        for (final variant in WpButtonVariant.values)
          for (final tone in WpButtonTone.values)
            _StateRow(
              variant: variant,
              tone: tone,
              size: size,
              // Exactly one button in the whole gallery starts focused, so the
              // ring is on screen without a keystroke.
              autofocus:
                  _isStandard &&
                  variant == WpButtonVariant.primary &&
                  tone == WpButtonTone.accent,
            ),
      ],
    );
  }
}

class _ColumnHeaders extends StatelessWidget {
  const _ColumnHeaders();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium;

    return Row(
      children: [
        const SizedBox(width: _kLabelWidth),
        for (final label in ['Ruhe', 'Icon', 'Disabled', 'Loading'])
          SizedBox(
            width: _kCellWidth,
            child: Text(label, style: style),
          ),
      ],
    );
  }
}

/// One `variant · tone` line: the same button in each externally reachable
/// state, side by side.
class _StateRow extends StatelessWidget {
  const _StateRow({
    required this.variant,
    required this.tone,
    required this.size,
    required this.autofocus,
  });

  final WpButtonVariant variant;
  final WpButtonTone tone;
  final WpButtonSize size;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: WpSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: _kLabelWidth,
            child: Text(
              '${variant.name} · ${tone.name}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          _Cell(
            child: Semantics(
              label: 'Aktion',
              button: true,
              child: WpButton(
                label: 'Aktion',
                variant: variant,
                tone: tone,
                size: size,
                autofocus: autofocus,
                onPressed: _noop,
              ),
            ),
          ),
          _Cell(
            child: Semantics(
              label: 'Aktion',
              button: true,
              child: WpButton(
                label: 'Aktion',
                variant: variant,
                tone: tone,
                size: size,
                icon: LucideIcons.check,
                onPressed: _noop,
              ),
            ),
          ),
          _Cell(
            child: Semantics(
              label: 'Aktion',
              button: true,
              child: WpButton(
                label: 'Aktion',
                variant: variant,
                tone: tone,
                size: size,
                icon: LucideIcons.check,
                onPressed: null,
                disabledTooltip: 'Deaktiviert, weil nichts ausgewählt ist.',
              ),
            ),
          ),
          _Cell(
            child: Semantics(
              label: 'Aktion',
              button: true,
              child: WpButton(
                label: 'Aktion',
                variant: variant,
                tone: tone,
                size: size,
                icon: LucideIcons.check,
                isLoading: true,
                onPressed: _noop,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _kCellWidth,
      child: Align(alignment: AlignmentDirectional.centerStart, child: child),
    );
  }
}

/// The gallery only shows shapes — pressing a button here does nothing on
/// purpose, so the callback stays const-friendly.
void _noop() {}
