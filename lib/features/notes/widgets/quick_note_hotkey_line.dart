import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_labels.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/config/settings_sections.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../settings/quick_note_hotkey_flow.dart';
import '../../settings/settings_widgets.dart';
import '../../../widgets/wp_button.dart';
import '../../../widgets/wp_focus_ring.dart';

/// Die Tastenkombination der Schnellnotiz, direkt bei ihrer Markierung.
///
/// Zweite Aufrufstelle für dieselbe Einstellung, nicht zweite Einstellung: sie
/// liest [settingsProvider] und schreibt über [recordQuickNoteHotkey] —
/// denselben Weg samt Kollisionsprüfung, den die Einstellungsseite geht. Wer
/// hier die Ziel-Notiz festlegt, steht genau dann vor der Frage „womit löse ich
/// das aus?"; ohne diese Zeile wäre die Antwort ein Weg in die Einstellungen
/// und zurück.
///
/// Bewusst *unter* der Aktionsleiste des Editors und nicht in ihr: diese Row
/// ist bis 280 dp Panel-Breite knapp bemessen und hat eine dokumentierte
/// Überlauf-Historie (FLUTTER_WHISPASTE-64); jedes weitere unflexible Kind
/// darin ginge zu Lasten der Aktionen. Eine eigene Zeile hat außerdem den
/// Platz für den Fall „Hotkey aus", der ohne Text nicht zu erzählen ist.
///
/// Nachgeordnet heißt hier: kleine, gedämpfte Schrift, keine Fläche, kein
/// Rahmen, keine Überschrift — sichtbar nur an der markierten Notiz. Der
/// Aufrufer entscheidet über die Sichtbarkeit (siehe `NoteEditorPanel`), diese
/// Zeile stellt sich nie selbst infrage.
class QuickNoteHotkeyLine extends ConsumerStatefulWidget {
  const QuickNoteHotkeyLine({super.key});

  @override
  ConsumerState<QuickNoteHotkeyLine> createState() =>
      _QuickNoteHotkeyLineState();
}

class _QuickNoteHotkeyLineState extends ConsumerState<QuickNoteHotkeyLine> {
  /// Name der Aktion, die die zuletzt gewählte Kombination schon belegt —
  /// `null`, solange nichts kollidiert.
  ///
  /// Zustand und keine Momentan-Meldung (Toast): der Nutzer muss den Dialog
  /// erneut öffnen, um den Fehler zu beheben, und eine Meldung, die
  /// währenddessen verschwindet, hilft ihm dabei nicht. Dieselbe Entscheidung
  /// wie in den Einstellungen.
  String? _collidingAction;

  final _comboFocusNode = FocusNode(debugLabel: 'QuickNoteHotkeyCombo');

  @override
  void dispose() {
    _comboFocusNode.dispose();
    super.dispose();
  }

  Future<void> _record(AppSettings settings) async {
    final result = await recordQuickNoteHotkey(
      context: context,
      ref: ref,
      settings: settings,
    );
    if (!mounted) return;
    // Abbruch lässt eine stehende Meldung stehen — sie gehört zur Kombination,
    // die sie ausgelöst hat, und die ist unverändert.
    if (result.change == QuickNoteHotkeyChange.cancelled) return;
    setState(() => _collidingAction = result.collidingActionLabel);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    // Solange die Einstellungen nicht geladen sind, behauptet die Zeile nichts
    // — weder eine Kombination noch „ausgeschaltet". Beides wäre geraten.
    final settings = ref.watch(settingsProvider).value;
    if (settings == null) return const SizedBox.shrink();

    final quickNote = settings.quickNoteHotkey;
    const labelStyle = TextStyle(
      fontSize: WpTypography.small,
      color: WpColors.textMuted,
    );

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        WpSpacing.xl,
        0,
        WpSpacing.xl,
        WpSpacing.xs,
      ),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // [Wrap] statt [Row], damit Beschriftung und Tastenkappen bei
            // vergrößerter Systemschrift umbrechen statt am schmalen Panel
            // abgeschnitten zu werden.
            Wrap(
              spacing: WpSpacing.xs,
              runSpacing: WpSpacing.xxs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: quickNote.quickNoteHotkeyEnabled
                  ? [
                      Text(l10n.notesQuickNoteHotkeyLabel, style: labelStyle),
                      // loam-ignore: a11y-interactive-semantics – Semantics lives inside _ComboButton, das die Kombination für die Beschriftung erst formatiert
                      _ComboButton(
                        focusNode: _comboFocusNode,
                        quickNote: quickNote,
                        onPressed: () => unawaited(_record(settings)),
                      ),
                    ]
                  : [
                      // Ohne diesen Fall richtete sich jemand hier eine
                      // Schnellnotiz ein, die nichts tut — und erführe es
                      // nirgends. Der Umschalter bleibt in den Einstellungen,
                      // hier steht nur die eine Aktion, die diesen Zustand
                      // auflöst.
                      Text(l10n.notesQuickNoteHotkeyOff, style: labelStyle),
                      WpButton(
                        key: const Key('notesQuickNoteHotkeyEnable'),
                        label: l10n.notesQuickNoteHotkeyEnable,
                        variant: WpButtonVariant.ghost,
                        size: WpButtonSize.dense,
                        onPressed: () => unawaited(
                          setQuickNoteHotkeyEnabled(ref, enabled: true),
                        ),
                      ),
                    ],
            ),
            if (_collidingAction != null)
              _CollisionNotice(
                text: l10n.settingsQuickNoteHotkeyCollision(_collidingAction!),
              ),
          ],
        ),
      ),
    );
  }
}

/// Die Tastenkappen als Schaltfläche: ein Klick darauf öffnet den
/// Aufzeichnungs-Dialog.
///
/// [HotkeyDisplay] ist eine [Row] aus einzelnen [Text]-Kappen — ein
/// Screenreader läse „Strg", „+", „Y" als drei Fetzen vor. Deshalb trägt die
/// Schaltfläche die Kombination in ihrer eigenen Beschriftung und blendet die
/// Kappen aus der Semantik aus.
class _ComboButton extends StatelessWidget {
  const _ComboButton({
    required this.focusNode,
    required this.quickNote,
    required this.onPressed,
  });

  final FocusNode focusNode;
  final QuickNoteHotkeySettings quickNote;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final label = l10n.notesQuickNoteHotkeyChange(
      formatHotkeyShortcut(
        quickNote.quickNoteHotkeyModifiers,
        quickNote.quickNoteHotkeyKey,
        l10n: l10n,
        displayOverride: quickNote.quickNoteHotkeyKeyDisplay,
      ),
    );

    return Semantics(
      label: label,
      button: true,
      child: Tooltip(
        message: label,
        // Der Hinweis ist für die Maus da; die Semantik trägt denselben Satz
        // schon als Beschriftung. Ohne dieses Flag landet er ein zweites Mal
        // als `tooltip` am selben Knoten — der Screenreader läse die
        // Kombination doppelt vor.
        excludeFromSemantics: true,
        child: WpFocusRing(
          focusNode: focusNode,
          child: InkWell(
            key: const Key('notesQuickNoteHotkeyCombo'),
            onTap: onPressed,
            focusNode: focusNode,
            borderRadius: WpRadius.borderSm,
            // WpFocusRing owns all focus visuals — suppress InkWell's own.
            focusColor: Colors.transparent,
            child: ExcludeSemantics(
              child: HotkeyDisplay(
                // Umbrechend: die Kappen stehen hier in einer Spalte, die bis
                // 280 dp schmal wird — bei vergrößerter Systemschrift passt
                // „Strg + Umschalt + Y" in keine Zeile davon.
                wrap: true,
                hotkeyKey: quickNote.quickNoteHotkeyKey,
                hotkeyModifiers: quickNote.quickNoteHotkeyModifiers,
                hotkeyKeyDisplay: quickNote.quickNoteHotkeyKeyDisplay,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// „Schon vergeben" — dieselbe Meldung wie in den Einstellungen, weil es
/// dieselbe Regel ist; nur ohne Kasten, weil sie hier an einer Notiz hängt.
class _CollisionNotice extends StatelessWidget {
  const _CollisionNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('notesQuickNoteHotkeyCollisionNotice'),
      padding: const EdgeInsets.only(top: WpSpacing.xxs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsetsDirectional.only(end: WpSpacing.xxs, top: 2),
            child: Icon(
              LucideIcons.circleAlert,
              size: WpIconSize.sm,
              color: WpColors.error,
            ),
          ),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: WpTypography.small,
                color: WpColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
