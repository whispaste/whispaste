// Text processing (spec 07-settings-ia §3 "Text & Einfügen"): deterministic
// transforms of the final transcript, independent of the speech engine.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../settings_widgets.dart';
import '../widgets/wp_settings_group.dart';

class TextProcessingSection extends ConsumerWidget {
  const TextProcessingSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;

    return WpSettingsGroup(
      heading: l10n.settingsTextProcessingHeading,
      children: [
        // Strip punctuation — engine/provider-independent. Unlike
        // punctuationPriming below (a Whisper-only prompt nudge), this is
        // a deterministic post-processing step applied to the final
        // transcript in RecordingOrchestrator regardless of which STT
        // engine or provider produced it, so it works identically for
        // on-device Whisper, Parakeet, and every cloud provider.
        WpSettingsRow(
          rowId: 'text-strip-punctuation',
          title: l10n.settingsStripPunctuation,
          subtitle: l10n.settingsStripPunctuationSubtitle,
          switchNamesRow: true,
          trailing: settingsToggle(
            label: l10n.settingsStripPunctuation,
            value: settings.stt.stripPunctuation,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .updateSettings(
                  (s) => s.copyWithSections(
                    stt: s.stt.copyWith(stripPunctuation: v),
                  ),
                ),
          ),
        ),

        // Numbers-only mode — engine/provider-independent, same as Strip
        // Punctuation above (itn-cad-zahlen: a deterministic post-
        // transcription text transform in RecordingOrchestrator, not an
        // ASR-level mode, so it works identically for every engine).
        WpSettingsRow(
          rowId: 'text-numeric-only',
          title: l10n.settingsNumericOnlyMode,
          subtitle: l10n.settingsNumericOnlyModeSubtitle,
          switchNamesRow: true,
          trailing: settingsToggle(
            label: l10n.settingsNumericOnlyMode,
            value: settings.stt.numericOnlyMode,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .updateSettings(
                  (s) => s.copyWithSections(
                    stt: s.stt.copyWith(numericOnlyMode: v),
                  ),
                ),
          ),
        ),

        // Filler word removal — same engine/provider-independent text
        // transform path as the two rows above (catchup ticket 16),
        // so it stays visible for every engine. Default off.
        WpSettingsRow(
          rowId: 'text-remove-filler',
          title: l10n.settingsRemoveFillerWords,
          subtitle: l10n.settingsRemoveFillerWordsSubtitle,
          switchNamesRow: true,
          trailing: settingsToggle(
            label: l10n.settingsRemoveFillerWords,
            key: const Key('removeFillerWordsToggle'),
            value: settings.stt.removeFillerWords,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .updateSettings(
                  (s) => s.copyWithSections(
                    stt: s.stt.copyWith(removeFillerWords: v),
                  ),
                ),
          ),
        ),

        // Spoken line breaks ("new paragraph" → blank line). Same
        // engine-independent text transform path as filler removal above.
        // Default on: spoken paragraph commands are the point of it.
        WpSettingsRow(
          rowId: 'text-voice-line-breaks',
          title: l10n.settingsVoiceLineBreaks,
          subtitle: l10n.settingsVoiceLineBreaksSubtitle,
          switchNamesRow: true,
          trailing: settingsToggle(
            label: l10n.settingsVoiceLineBreaks,
            key: const Key('voiceLineBreaksToggle'),
            value: settings.stt.voiceLineBreaks,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .updateSettings(
                  (s) => s.copyWithSections(
                    stt: s.stt.copyWith(voiceLineBreaks: v),
                  ),
                ),
          ),
        ),
        // Spoken punctuation ("Komma" → ","). Same text path as the line
        // breaks above, applied before them. Default off: words stay words.
        WpSettingsRow(
          rowId: 'text-spoken-punctuation',
          title: l10n.settingsSpokenPunctuation,
          subtitle: l10n.settingsSpokenPunctuationSubtitle,
          switchNamesRow: true,
          trailing: settingsToggle(
            label: l10n.settingsSpokenPunctuation,
            key: const Key('spokenPunctuationToggle'),
            value: settings.stt.spokenPunctuation,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .updateSettings(
                  (s) => s.copyWithSections(
                    stt: s.stt.copyWith(spokenPunctuation: v),
                  ),
                ),
          ),
        ),

        // Written forms ("Schreibformen"): spoken e-mail addresses, web
        // addresses, dates, times and amounts of money are written the usual
        // way. Runs after the line breaks and before the dictionary. Master
        // switch plus one switch per kind; all default on.
        WpSettingsRow(
          rowId: 'text-written-forms',
          title: l10n.settingsWrittenForms,
          subtitle: l10n.settingsWrittenFormsSubtitle,
          switchNamesRow: true,
          trailing: settingsToggle(
            label: l10n.settingsWrittenForms,
            key: const Key('writtenFormsToggle'),
            value: settings.stt.writtenForms.enabled,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .updateSettings(
                  (s) => s.copyWithSections(
                    stt: s.stt.copyWith(
                      writtenForms: s.stt.writtenForms.copyWith(enabled: v),
                    ),
                  ),
                ),
          ),
        ),

        WpSettingsRow(
          rowId: 'text-written-form-email',
          title: l10n.settingsWrittenFormEmail,
          indent: true,
          switchNamesRow: true,
          trailing: settingsToggle(
            label: l10n.settingsWrittenFormEmail,
            key: const Key('writtenFormEmailToggle'),
            value: settings.stt.writtenForms.email,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .updateSettings(
                  (s) => s.copyWithSections(
                    stt: s.stt.copyWith(
                      writtenForms: s.stt.writtenForms.copyWith(email: v),
                    ),
                  ),
                ),
          ),
        ),

        WpSettingsRow(
          rowId: 'text-written-form-url',
          title: l10n.settingsWrittenFormUrl,
          indent: true,
          switchNamesRow: true,
          trailing: settingsToggle(
            label: l10n.settingsWrittenFormUrl,
            key: const Key('writtenFormUrlToggle'),
            value: settings.stt.writtenForms.url,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .updateSettings(
                  (s) => s.copyWithSections(
                    stt: s.stt.copyWith(
                      writtenForms: s.stt.writtenForms.copyWith(url: v),
                    ),
                  ),
                ),
          ),
        ),

        WpSettingsRow(
          rowId: 'text-written-form-date',
          title: l10n.settingsWrittenFormDate,
          indent: true,
          switchNamesRow: true,
          trailing: settingsToggle(
            label: l10n.settingsWrittenFormDate,
            key: const Key('writtenFormDateToggle'),
            value: settings.stt.writtenForms.date,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .updateSettings(
                  (s) => s.copyWithSections(
                    stt: s.stt.copyWith(
                      writtenForms: s.stt.writtenForms.copyWith(date: v),
                    ),
                  ),
                ),
          ),
        ),

        WpSettingsRow(
          rowId: 'text-written-form-time',
          title: l10n.settingsWrittenFormTime,
          indent: true,
          switchNamesRow: true,
          trailing: settingsToggle(
            label: l10n.settingsWrittenFormTime,
            key: const Key('writtenFormTimeToggle'),
            value: settings.stt.writtenForms.time,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .updateSettings(
                  (s) => s.copyWithSections(
                    stt: s.stt.copyWith(
                      writtenForms: s.stt.writtenForms.copyWith(time: v),
                    ),
                  ),
                ),
          ),
        ),

        WpSettingsRow(
          rowId: 'text-written-form-money',
          title: l10n.settingsWrittenFormMoney,
          indent: true,
          switchNamesRow: true,
          trailing: settingsToggle(
            label: l10n.settingsWrittenFormMoney,
            key: const Key('writtenFormMoneyToggle'),
            value: settings.stt.writtenForms.money,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .updateSettings(
                  (s) => s.copyWithSections(
                    stt: s.stt.copyWith(
                      writtenForms: s.stt.writtenForms.copyWith(money: v),
                    ),
                  ),
                ),
          ),
        ),
      ],
    );
  }
}
