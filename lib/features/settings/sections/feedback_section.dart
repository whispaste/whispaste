/// Keyboard Shortcut & Sound Feedback settings sections.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/build_config.dart';
import '../../../core/config/settings_enums.dart';
import '../../../core/config/settings_labels.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/config/settings_sections.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/hotkey_conflicts.dart';
import '../../../services/hotkey_service.dart';
import '../../../services/paste/paste_capability_notifier.dart';
import '../../../services/paste/paste_policy.dart';
import '../../../services/paste/paster.dart';
import '../../../services/sound_feedback_service.dart';
import '../../../services/telemetry_service.dart';
import '../../../widgets/hotkey_recorder.dart';
import '../../../widgets/paste_capability_indicator.dart';
import '../../../widgets/section.dart';
import '../../../widgets/wp_button.dart';
import '../settings_widgets.dart';

// ---------------------------------------------------------------------------
// Keyboard Shortcut section
// ---------------------------------------------------------------------------

class KeyboardShortcutSection extends ConsumerWidget {
  const KeyboardShortcutSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;

    return WpSection(
      title: l10n.settingsKeyboardShortcut,
      subtitle: l10n.settingsKeyboardShortcutSubtitle,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SettingRow(
            icon: LucideIcons.toggleRight,
            label: l10n.settingsHotkeyEnabled,
            semanticToggledValue: settings.hotkeyEnabled,
            trailing: settingsToggle(
              value: settings.hotkeyEnabled,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(hotkeyEnabled: v)),
            ),
          ),
          AnimatedOpacity(
            opacity: settings.hotkeyEnabled ? 1.0 : 0.4,
            duration: WpMotion.durationFor(context, WpMotion.normal),
            // ExcludeFocus alongside IgnorePointer: the dimmed row blocked the
            // mouse but stayed in the tab order, so keyboard users could focus
            // a 40%-opacity "Change hotkey" button and open the recorder for a
            // hotkey that is switched off. Blocking one input device and not
            // the other is the defect; both go together.
            child: ExcludeFocus(
              excluding: !settings.hotkeyEnabled,
              child: IgnorePointer(
                ignoring: !settings.hotkeyEnabled,
                child: SettingRow(
                  icon: LucideIcons.keyboard,
                  label: l10n.settingsCurrentHotkey,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      HotkeyDisplay(
                        hotkeyKey: settings.hotkeyKey,
                        hotkeyModifiers: settings.hotkeyModifiers,
                        hotkeyKeyDisplay: settings.hotkey.hotkeyKeyDisplay,
                      ),
                      const SizedBox(width: WpSpacing.sm),
                      WpButton(
                        label: l10n.settingsChangeHotkey,
                        variant: WpButtonVariant.secondary,
                        onPressed: () async {
                          final result = await WpHotkeyRecorderDialog.show(
                            context,
                            initialKey: settings.hotkeyKey,
                            initialDisplayKey: settings.hotkey.hotkeyKeyDisplay,
                            initialModifiers: settings.hotkeyModifiers,
                          );
                          if (result != null) {
                            ref
                                .read(settingsProvider.notifier)
                                .updateSettings(
                                  (s) => s.copyWith(
                                    hotkeyKey: result.key,
                                    hotkeyKeyDisplay: result.displayKey,
                                    hotkeyModifiers: result.modifiers,
                                  ),
                                );
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _PushToTalkRow(settings: settings),
          // Bewusst *unter* der Push-to-talk-Zeile: die gehört zum
          // Haupt-Hotkey, und eingeschoben zwischen beide würde sie optisch an
          // den Schnellnotiz-Block andocken, für den sie gar nicht gilt (der
          // ist Toggle-only).
          _QuickNoteHotkeyBlock(settings: settings),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick-note hotkey block (subordinate to the main hotkey)
// ---------------------------------------------------------------------------

/// Der zweite, optionale Hotkey — sichtbar dem Haupt-Hotkey nachgeordnet.
///
/// Nachgeordnet heißt hier dreierlei, weil Einrückung allein zu leise wäre:
/// eine Haarlinie trennt den Block vom Haupt-Hotkey ab, der ganze Block ist
/// gegenüber den Zeilen darüber eingerückt, und die Kombination steht nicht
/// als rechtsbündige `trailing`-Spalte einer vollwertigen [SettingRow],
/// sondern als ruhige Zeile darunter.
///
/// Dass die Kombinations-Zeile umbricht statt rechts zu kleben, ist zugleich
/// die Antwort auf die Accessibility-Textgröße: die `trailing`-Variante des
/// Haupt-Hotkeys (Tastenkappen + Button in einer festen [Row]) läuft ab
/// Textskalierung 1.5 rechts über — gemessen, siehe Bericht. Ein [Wrap] kann
/// das strukturell nicht.
class _QuickNoteHotkeyBlock extends ConsumerStatefulWidget {
  const _QuickNoteHotkeyBlock({required this.settings});

  final AppSettings settings;

  @override
  ConsumerState<_QuickNoteHotkeyBlock> createState() =>
      _QuickNoteHotkeyBlockState();
}

class _QuickNoteHotkeyBlockState extends ConsumerState<_QuickNoteHotkeyBlock> {
  /// Name der Aktion, die die zuletzt gewählte Kombination schon belegt —
  /// `null`, solange nichts kollidiert.
  ///
  /// Bewusst Zustand und keine Momentan-Meldung (Toast/Snackbar): der Nutzer
  /// muss den Aufzeichnungs-Dialog erneut öffnen, um den Fehler zu beheben,
  /// und eine Meldung, die währenddessen verschwindet, hilft ihm dabei nicht.
  String? _collidingAction;

  /// Alle WhisPaste-Hotkeys, gegen die eine neue Kombination geprüft wird.
  ///
  /// Nur eingeschaltete Hotkeys zählen: ein abgeschalteter belegt beim OS
  /// nichts, also gibt es auch nichts zu kollidieren. (Kehrseite — er kollidiert
  /// dann eben in dem Moment, in dem er wieder eingeschaltet wird; siehe
  /// Bericht.)
  List<HotkeyBinding> _activeBindings(AppSettings settings, L10n l10n) => [
    if (settings.hotkeyEnabled)
      HotkeyBinding(
        actionId: 'global',
        actionLabel: l10n.settingsHotkeyActionRecording,
        key: settings.hotkeyKey,
        modifiers: settings.hotkeyModifiers,
      ),
    if (settings.quickNoteHotkey.quickNoteHotkeyEnabled)
      HotkeyBinding(
        actionId: 'quickNote',
        actionLabel: l10n.settingsHotkeyActionQuickNote,
        key: settings.quickNoteHotkey.quickNoteHotkeyKey,
        modifiers: settings.quickNoteHotkey.quickNoteHotkeyModifiers,
      ),
  ];

  Future<void> _record() async {
    final l10n = L10n.of(context);
    final quickNote = widget.settings.quickNoteHotkey;
    final result = await WpHotkeyRecorderDialog.show(
      context,
      initialKey: quickNote.quickNoteHotkeyKey,
      initialDisplayKey: quickNote.quickNoteHotkeyKeyDisplay,
      initialModifiers: quickNote.quickNoteHotkeyModifiers,
    );
    if (result == null || !mounted) return;

    // Vor dem Speichern, nicht danach: eine doppelt vergebene Kombination
    // ließe sich zwar speichern, aber einer der beiden Hotkeys löste danach
    // still nicht mehr aus — ohne dass irgendwo etwas sichtbar fehlschlüge.
    // Gegen den kanonischen Token geprüft, nicht gegen die Anzeige-Taste: beim
    // OS registriert wird der kanonische, also kollidiert auch nur der.
    final collision = findHotkeyCollision(
      modifiers: result.modifiers,
      key: result.key,
      bindings: _activeBindings(widget.settings, l10n),
      excludeActionId: 'quickNote',
    );
    if (collision != null) {
      setState(() => _collidingAction = collision.actionLabel);
      return;
    }

    setState(() => _collidingAction = null);
    await ref
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWithSections(
            quickNoteHotkey: s.quickNoteHotkey.copyWith(
              quickNoteHotkeyKey: result.key,
              quickNoteHotkeyKeyDisplay: result.displayKey,
              quickNoteHotkeyModifiers: result.modifiers,
            ),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final settings = widget.settings;
    final quickNote = settings.quickNoteHotkey;
    final enabled = quickNote.quickNoteHotkeyEnabled;

    // `enabled &&` ist nicht kosmetisch: der Registrierungs-Status ist ein
    // In-Memory-Wert, den nur Registrierungs-Versuche schreiben — das
    // Abschalten des Hotkeys setzt ihn nicht zurück. Ohne diese Bedingung
    // stünde „nicht aktiv, bitte neu belegen" dauerhaft an einem Hotkey, den
    // der Nutzer gerade selbst ausgeschaltet hat.
    final registrationFailed =
        enabled &&
        ref.watch(quickNoteHotkeyRegistrationStatusProvider) ==
            HotkeyRegistrationStatus.conflict;

    return Padding(
      padding: const EdgeInsets.only(top: WpSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: kSettingRowInset),
            child: Divider(
              height: 1,
              thickness: 1,
              color: WpColors.borderSubtle,
            ),
          ),
          const SizedBox(height: WpSpacing.xs),
          Padding(
            // Die Einrückung, die den Block als Unterpunkt des Haupt-Hotkeys
            // liest — dasselbe Idiom, mit dem Betriebssystem-Einstellungen
            // abhängige Optionen unter ihre Hauptoption setzen.
            //
            // `EdgeInsetsDirectional`, nicht `EdgeInsets`: die Einrückung ist
            // das *einzige* Signal, das die Unterordnung trägt. Physisch links
            // gesetzt läge sie auf Hebräisch an der Schlusskante und läse sich
            // als beliebige Lücke statt als Einrückung.
            padding: const EdgeInsetsDirectional.only(start: WpSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SettingRow(
                  icon: LucideIcons.notebookPen,
                  label: l10n.settingsQuickNoteHotkeyEnabled,
                  // Der Ein-Zeilen-Hinweis, wohin der Text geht. Er steht am
                  // Umschalter und nicht an der Kombination, weil er die Frage
                  // beantwortet, die *beim Einschalten* aufkommt — und weil er
                  // so auch sichtbar bleibt, wenn der Hotkey aus ist.
                  subtitle: l10n.settingsQuickNoteHotkeyHint,
                  semanticToggledValue: enabled,
                  trailing: settingsToggle(
                    key: const Key('quickNoteHotkeyToggle'),
                    value: enabled,
                    onChanged: (v) {
                      // Eine Kollisions-Meldung gehört zur Kombination, die
                      // sie ausgelöst hat; beim Umschalten ist sie erledigt.
                      setState(() => _collidingAction = null);
                      ref
                          .read(settingsProvider.notifier)
                          .updateSettings(
                            (s) => s.copyWithSections(
                              quickNoteHotkey: s.quickNoteHotkey.copyWith(
                                quickNoteHotkeyEnabled: v,
                              ),
                            ),
                          );
                    },
                  ),
                ),
                AnimatedOpacity(
                  opacity: enabled ? 1.0 : 0.4,
                  duration: WpMotion.durationFor(context, WpMotion.normal),
                  // Dasselbe Paar wie beim Haupt-Hotkey: die abgeblendete
                  // Zeile darf weder mit der Maus noch mit der Tabulatortaste
                  // erreichbar sein.
                  child: ExcludeFocus(
                    excluding: !enabled,
                    child: IgnorePointer(
                      ignoring: !enabled,
                      child: _QuickNoteComboLine(
                        quickNote: quickNote,
                        onChange: _record,
                      ),
                    ),
                  ),
                ),
                if (_collidingAction != null)
                  _QuickNoteNotice(
                    noticeKey: const Key('quickNoteHotkeyCollisionNotice'),
                    icon: LucideIcons.circleAlert,
                    color: WpColors.error,
                    text: l10n.settingsQuickNoteHotkeyCollision(
                      _collidingAction!,
                    ),
                  ),
                if (registrationFailed)
                  _QuickNoteNotice(
                    noticeKey: const Key('quickNoteHotkeyInactiveNotice'),
                    icon: LucideIcons.triangleAlert,
                    color: WpColors.warning,
                    // Sagt „nicht aktiv" und „wähl eine andere" — und nennt
                    // bewusst keine Ersatzkombination, weil es anders als beim
                    // Haupt-Hotkey keine gibt. Eine zu suggerieren wäre die
                    // schlimmere Variante des Fehlers: der Nutzer hielte den
                    // Hotkey für belegt und fände nie heraus, womit.
                    text: l10n.settingsQuickNoteHotkeyInactive,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Die Kombinations-Zeile des Schnellnotiz-Hotkeys.
///
/// [Wrap] statt [Row]: bei vergrößerter Systemschrift rutschen Tastenkappen
/// und „Ändern"-Button in die nächste Zeile, statt rechts abgeschnitten zu
/// werden.
class _QuickNoteComboLine extends StatelessWidget {
  const _QuickNoteComboLine({required this.quickNote, required this.onChange});

  final QuickNoteHotkeySettings quickNote;
  final Future<void> Function() onChange;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        kSettingRowInset,
        WpSpacing.xxs,
        kSettingRowInset,
        WpSpacing.xs,
      ),
      child: Wrap(
        spacing: WpSpacing.sm,
        runSpacing: WpSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            l10n.settingsQuickNoteCurrentHotkey,
            style: tt.bodySmall?.copyWith(color: WpColors.textMuted),
          ),
          HotkeyDisplay(
            hotkeyKey: quickNote.quickNoteHotkeyKey,
            hotkeyModifiers: quickNote.quickNoteHotkeyModifiers,
            hotkeyKeyDisplay: quickNote.quickNoteHotkeyKeyDisplay,
          ),
          WpButton(
            label: l10n.settingsChangeHotkey,
            variant: WpButtonVariant.secondary,
            onPressed: () => unawaited(onChange()),
          ),
        ],
      ),
    );
  }
}

/// Unaufdringlicher Inline-Hinweis unter der Kombinations-Zeile.
///
/// Farbgebung und Icon-Konvention wie die Konflikt-Warnung im
/// Aufzeichnungs-Dialog, aber ohne Rahmen und Füllung: dort ist die Warnung
/// das zentrale Element eines Dialogs, hier eine Fußnote an einer von vielen
/// Einstellungszeilen. Ein Kasten in der Einstellungsspalte zöge mehr
/// Aufmerksamkeit auf sich als der Hotkey selbst.
class _QuickNoteNotice extends StatelessWidget {
  const _QuickNoteNotice({
    required this.noticeKey,
    required this.icon,
    required this.color,
    required this.text,
  });

  final Key noticeKey;
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: noticeKey,
      padding: const EdgeInsets.fromLTRB(
        kSettingRowInset,
        0,
        kSettingRowInset,
        WpSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            // Auf die Grundlinie der ersten Textzeile gesetzt, damit das Icon
            // bei mehrzeiligem Text nicht mittig neben dem Absatz schwebt.
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: WpIconSize.sm, color: color),
          ),
          const SizedBox(width: WpSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: WpTypography.caption,
                height: 1.4,
              ).copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Push-to-Talk toggle row (platform-aware)
// ---------------------------------------------------------------------------

/// Renders the Hold-to-Record (Push-to-Talk) toggle.
///
/// When the current platform does not support key-up events
/// ([HotkeyService.supportsKeyUp] is false), the toggle is disabled
/// and wrapped in a [Tooltip] explaining the limitation.
class _PushToTalkRow extends ConsumerWidget {
  const _PushToTalkRow({required this.settings});

  static final _log = AppLogger('PushToTalkRow');

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);

    // Read the notifier directly — we only need supportsKeyUp once per build
    // and do not need to rebuild on hotkey-service state changes.
    final supportsKeyUp = ref
        .read(hotkeyServiceProvider.notifier)
        .supportsKeyUp;

    final toggle = settingsToggle(
      value: settings.pushToTalk,
      onChanged: supportsKeyUp
          ? (v) {
              ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(pushToTalk: v));
              try {
                ref.read(telemetryProvider).trackSettingChange('hotkey_mode');
              } catch (e) {
                _log.debug('telemetry failed: $e');
              }
            }
          : null, // null disables the switch
    );

    // Mirrors the onboarding twin in `trigger_step.dart`: the subtitle always
    // describes what pressing the hotkey does *right now*, so the toggle's
    // effect is never abstract. The two rows had drifted apart despite the
    // comment over there promising they would not — this row had neither the
    // live hint nor a state a screen reader could hear.
    final modeHint = settings.pushToTalk && supportsKeyUp
        ? l10n.onboardingTriggerModeHoldHint
        : l10n.onboardingTriggerModeToggleHint;

    return SettingRow(
      icon: LucideIcons.hand,
      label: l10n.settingsHoldToRecord,
      subtitle: modeHint,
      // Was the one toggle row in all of Settings that never announced its
      // state. Null where the platform cannot do push-to-talk, so the row
      // does not claim a state its disabled switch will not accept.
      semanticToggledValue: supportsKeyUp ? settings.pushToTalk : null,
      trailing: supportsKeyUp
          ? toggle
          : Tooltip(message: l10n.pushToTalkUnavailableTooltip, child: toggle),
    );
  }
}

// ---------------------------------------------------------------------------
// Sound & Feedback section
// ---------------------------------------------------------------------------

class SoundFeedbackSection extends ConsumerWidget {
  const SoundFeedbackSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;

    return WpSection(
      title: l10n.settingsSoundFeedback,
      subtitle: l10n.settingsSoundFeedbackSubtitle,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SettingRow(
            icon: LucideIcons.volume1,
            label: l10n.settingsSoundVolume,
            trailing: settingsSlider(
              context: context,
              value: settings.soundVolume,
              min: 0,
              max: 100,
              divisions: 20,
              valueLabel: settings.soundVolume == 0
                  ? l10n.settingsOff
                  : '${settings.soundVolume.round()}%',
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(soundVolume: v)),
              onChangeEnd: (v) =>
                  ref.read(soundFeedbackProvider.notifier).playVolumePreview(v),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// After Transcription section
// ---------------------------------------------------------------------------

class AfterTranscriptionSection extends ConsumerWidget {
  const AfterTranscriptionSection({
    super.key,
    this.autoPasteSupported = kAutoPasteSupported,
  });

  /// Overridable for tests; defaults to the real build-time flag ([kAutoPasteSupported]).
  final bool autoPasteSupported;

  static final _log = AppLogger('AfterTranscriptionSection');

  static String _labelFor(AfterTranscriptionAction action, L10n l10n) =>
      afterTranscriptionSettingsLabel(action, l10n);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;

    // Auto-paste-requiring actions don't exist as a selectable option at all
    // when the build can't perform them (MAS sandbox) — greying them out
    // with a tooltip would look like a bug to users who don't know they're
    // running a store build. The current value is routed through the same
    // resolver the recording pipeline uses, so a stale/synced "paste"
    // preference displays (and behaves) as "clipboard" instead of pointing
    // at an option that no longer exists in the list.
    final visibleActions = autoPasteSupported
        ? AfterTranscriptionAction.values
        : AfterTranscriptionAction.values
              .where(
                (a) =>
                    a != AfterTranscriptionAction.paste &&
                    a != AfterTranscriptionAction.clipboardAndPaste,
              )
              .toList();
    final resolvedAction = resolveAfterTranscriptionAction(
      settings.afterTranscriptionAction,
      autoPasteSupported: autoPasteSupported,
    );

    return WpSection(
      title: l10n.settingsAfterTranscription,
      subtitle: l10n.settingsAfterTranscriptionSubtitle,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SettingRow(
            icon: LucideIcons.clipboardCheck,
            label: l10n.settingsAfterTranscriptionActionLabel,
            trailing: settingsDropdown(
              context: context,
              value: resolvedAction.value,
              items: visibleActions.map((e) => e.value).toList(),
              labels: visibleActions.map((e) => _labelFor(e, l10n)).toList(),
              onChanged: (v) {
                if (v == null) return;
                final newAction = AfterTranscriptionAction.values.firstWhere(
                  (a) => a.value == v,
                );
                ref
                    .read(settingsProvider.notifier)
                    .updateSettings((s) => s.copyWith(afterTranscription: v));
                try {
                  ref.read(telemetryProvider).trackSettingChange('auto_paste');
                } catch (e) {
                  _log.debug('telemetry failed: $e');
                }
                // The user just switched TO an Auto-Paste-requiring option —
                // request the OS permission right now instead of leaving them
                // to notice and tap the indicator's own "Grant" button below.
                // Skipped when already ready so re-selecting the same option
                // doesn't re-trigger the deep-link to System Settings.
                final requiresPaste =
                    newAction == AfterTranscriptionAction.paste ||
                    newAction == AfterTranscriptionAction.clipboardAndPaste;
                final alreadyReady =
                    ref
                        .read(pasteCapabilityNotifierProvider)
                        .capability
                        ?.status ==
                    PasteCapabilityStatus.ready;
                if (requiresPaste && Platform.isMacOS && !alreadyReady) {
                  unawaited(
                    ref
                        .read(pasteCapabilityNotifierProvider.notifier)
                        .requestGrant(),
                  );
                }
              },
            ),
          ),
          if (resolvedAction == AfterTranscriptionAction.paste ||
              resolvedAction == AfterTranscriptionAction.clipboardAndPaste)
            const Padding(
              // kSettingRowInset horizontally, like every other inline block
              // in Settings. This one sat at 16 and started 4 px right of the
              // rows it belongs to — the kind of drift that reads as sloppy
              // without ever being noticed as a specific mistake.
              padding: EdgeInsets.fromLTRB(
                kSettingRowInset,
                WpSpacing.sm,
                kSettingRowInset,
                WpSpacing.xs,
              ),
              child: WpPasteCapabilityIndicator(),
            ),
        ],
      ),
    );
  }
}
