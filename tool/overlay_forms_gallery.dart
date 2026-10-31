/// Overlay forms gallery — a dev harness, NOT part of the shipped app.
///
/// Shows every overlay form, size, state, status line, wave style and colour
/// preset side by side in one window, painted as still frames by the same
/// `WpFloatingOverlayView` the native shells host, Meant
/// for a visual review of what exists; it captures nothing and asserts
/// nothing.
///
/// Run:
///   flutter run -d macos -t tool/overlay_forms_gallery.dart
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'package:whispaste/core/theme/overlay_customization.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/floating_button/floating_button_controller_interface.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller_interface.dart';
import 'package:whispaste/services/floating_overlay/overlay_key_hints.dart';
import 'package:whispaste/widgets/floating_button/floating_button_view.dart';
import 'package:whispaste/widgets/floating_overlay/floating_overlay_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(1280, 900),
      center: true,
      title: 'Overlay-Formen',
    ),
    () async => windowManager.show(),
  );
  runApp(const _GalleryApp());
}

/// The new-install default (maintainer 2026-10-30): compact, amber with ink,
/// static outline.
const _defaultLook = (
  background: OverlayBackground.amber,
  wave: OverlayWave.ink,
  size: OverlaySizeVariant.compact,
  appearance: OverlayAppearance(waveFluid: false),
);

class _GalleryApp extends StatelessWidget {
  const _GalleryApp();

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(debugShowCheckedModeBanner: false, home: _Gallery());
}

class _Gallery extends StatefulWidget {
  const _Gallery();

  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  Widget _tile(
    String caption, {
    OverlayVisualState state = OverlayVisualState.recording,
    OverlaySizeVariant? size,
    OverlayBackground? background,
    OverlayWave? wave,
    OverlayAppearance? appearance,
    String elapsed = '0:07',
    bool countdown = false,
    OverlayKeyHints? keyHints,
    String? liveTranscript,
  }) {
    return _OverlayTile(
      caption: caption,
      snapshot: FloatingOverlaySnapshot(
        visible: true,
        state: state,
        size: size ?? _defaultLook.size,
        background: background ?? _defaultLook.background,
        wave: wave ?? _defaultLook.wave,
        appearance: appearance ?? _defaultLook.appearance,
        label: switch (state) {
          OverlayVisualState.recording => 'Aufnahme',
          OverlayVisualState.transcribing => 'Wird geschrieben …',
          OverlayVisualState.done => 'Eingefügt',
          OverlayVisualState.error => 'Fehler',
        },
        elapsed: state == OverlayVisualState.recording ? elapsed : '',
        countdown: countdown,
        keyHints: keyHints,
        liveTranscript: liveTranscript,
        errorMessage: state == OverlayVisualState.error
            ? 'Keine Verbindung'
            : null,
        doneMessage: state == OverlayVisualState.done ? 'Eingefügt' : null,
        progress: state == OverlayVisualState.recording ? 0.4 : 0.0,
        languageChip: 'DE',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF6E7480),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Heading(
              'Formen × Größen',
              'Alle Formen, die es im Code gibt. Standard für neue '
                  'Installationen: Pille, kompakt, Bernstein mit Tinte, fester Rand.',
            ),
            for (final form in OverlayForm.values)
              _Row(form.value, [
                for (final size in OverlaySizeVariant.values)
                  _tile(
                    size.name,
                    size: size,
                    appearance: OverlayAppearance(form: form, waveFluid: false),
                  ),
              ]),
            const _Heading('Zustände', 'Standard-Look, kompakt.'),
            _Row('', [
              for (final s in OverlayVisualState.values)
                _tile(s.name, state: s),
            ]),
            const _Heading(
              'Zustände · Nano',
              'Nur Welle und Zustandsglyphe, ohne Text und Zeit.',
            ),
            _Row('', [
              for (final s in OverlayVisualState.values)
                _tile(s.name, state: s, size: OverlaySizeVariant.mini),
            ]),
            const _Heading(
              'Statuszeile während der Aufnahme',
              'Neu im Overlay-Paket A (normale Größe). Vorrang: kein Signal > '
                  'Restzeit > zu leise > Live-Text > Zeit.',
            ),
            _Row('', [
              _tile('Zeit', size: OverlaySizeVariant.normal),
              _tile(
                'Tastenhinweise',
                size: OverlaySizeVariant.normal,
                keyHints: const OverlayKeyHints(stop: '⌥ Space', cancel: 'Esc'),
              ),
              _tile(
                'Restzeit (letzte 30 s)',
                size: OverlaySizeVariant.normal,
                elapsed: '0:24 übrig',
                countdown: true,
              ),
              _tile(
                'zu leise',
                size: OverlaySizeVariant.normal,
                elapsed: 'Mikrofon sehr leise',
              ),
              _tile(
                'kein Signal',
                size: OverlaySizeVariant.normal,
                elapsed: 'Kein Mikrofonsignal',
              ),
              _tile(
                'Live-Text (einzeilig)',
                size: OverlaySizeVariant.normal,
                elapsed: 'Ich schreibe gerade eine kurze Nachricht an',
              ),
            ]),
            const _Heading('Wellenstile', 'Standard-Look, normale Größe.'),
            _Row('', [
              for (final style in OverlayWaveStyle.values)
                _tile(
                  style.value,
                  size: OverlaySizeVariant.normal,
                  appearance: OverlayAppearance(
                    waveStyle: style,
                    waveFluid: false,
                  ),
                ),
              _tile(
                'fließender Rand',
                size: OverlaySizeVariant.normal,
                appearance: const OverlayAppearance(),
              ),
            ]),
            const _Heading(
              'Wellenstile · Nano',
              'Dieselben Wellenstile in der kleinsten Größe.',
            ),
            _Row('', [
              for (final style in OverlayWaveStyle.values)
                _tile(
                  style.value,
                  size: OverlaySizeVariant.mini,
                  appearance: OverlayAppearance(
                    waveStyle: style,
                    waveFluid: false,
                  ),
                ),
            ]),
            const _Heading(
              'Farben: Hintergrund × Welle',
              'Normale Größe, alle erlaubten Kombinationen (Kontrastregel).',
            ),
            for (final bg in OverlayBackground.values)
              _Row(bg.value, [
                for (final w in OverlayWave.values.where(
                  (w) => w.isValidOn(bg),
                ))
                  _tile(
                    w.value,
                    size: OverlaySizeVariant.normal,
                    background: bg,
                    wave: w,
                  ),
              ]),
            const _Heading(
              'Farben: Hintergrund × Welle · Nano',
              'Dieselben erlaubten Kombinationen in der kleinsten Größe.',
            ),
            for (final bg in OverlayBackground.values)
              _Row(bg.value, [
                for (final w in OverlayWave.values.where(
                  (w) => w.isValidOn(bg),
                ))
                  _tile(
                    w.value,
                    size: OverlaySizeVariant.mini,
                    background: bg,
                    wave: w,
                  ),
              ]),
            const _Heading(
              'F3 Ruhe-Kapsel',
              'Floating-Button im Ruhezustand: 56 × 20 Kapsel, beim Hover die '
                  '112 × 28 Pille mit Mikrofon. Ohne Hover bleibt sie schmal.',
            ),
            for (final bg in const [
              OverlayBackground.marine,
              OverlayBackground.graphit,
              OverlayBackground.gletscher,
              OverlayBackground.amber,
            ])
              _Row(bg.value, [
                _capsuleTile('Ruhe', background: bg, expanded: false),
                _capsuleTile('Hover', background: bg, expanded: true),
              ]),
          ],
        ),
      ),
    );
  }
}

/// One idle-capsule frame (rest or hover pill) of the floating button, painted
/// by the same `WpFloatingButtonView` the native shell hosts.
Widget _capsuleTile(
  String caption, {
  required OverlayBackground background,
  required bool expanded,
}) {
  const look = FloatingButtonLook(idleCapsule: true);
  final content = WpFloatingButtonView.contentSizeFor(
    state: FloatingButtonVisualState.idle,
    diameter: look.diameter,
    look: look,
    expanded: expanded,
  );
  // The shell adds the shadow padding on every side.
  final window = Size(content.width + 16, content.height + 16);
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      ClipRect(
        child: SizedBox.fromSize(
          size: window,
          child: WpFloatingButtonView(
            state: FloatingButtonVisualState.idle,
            background: background,
            look: look,
            capsuleExpanded: expanded,
            animate: false,
          ),
        ),
      ),
      const SizedBox(height: 4),
      Text(caption, style: const TextStyle(color: Colors.white, fontSize: 11)),
    ],
  );
}

class _Heading extends StatelessWidget {
  const _Heading(this.title, this.note);
  final String title;
  final String note;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(note, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ],
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.tiles);
  final String label;
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
        Expanded(child: Wrap(spacing: 16, runSpacing: 12, children: tiles)),
      ],
    ),
  );
}

/// One still overlay frame and its caption.
///
/// Static on purpose: forty animated overlays in one debug window saturate
/// the machine, and a still frame shows every form just as well.
class _OverlayTile extends StatelessWidget {
  const _OverlayTile({required this.caption, required this.snapshot});

  final String caption;
  final FloatingOverlaySnapshot snapshot;

  static final List<double> _bars = List<double>.generate(
    OverlayDesignSpec.waveform.barCount,
    (i) => (0.5 + 0.3 * math.sin(i * 0.7) + 0.2 * math.sin(i * 1.9)).clamp(
      0.05,
      1.0,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final window = OverlayDesignSpec.windowSizeFor(snapshot.size);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The real overlay widget (pill width, shadow inset), clipped to the
        // native window box so nothing bleeds into its neighbours.
        ClipRect(
          child: SizedBox.fromSize(
            size: window,
            child: WpFloatingOverlayView(
              snapshot: snapshot,
              waveformBars: _bars,
              animate: false,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          caption,
          style: const TextStyle(color: Colors.white, fontSize: 11),
        ),
      ],
    );
  }
}
