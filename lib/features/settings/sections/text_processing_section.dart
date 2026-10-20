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
          semanticToggledValue: settings.stt.stripPunctuation,
          trailing: settingsToggle(
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
          semanticToggledValue: settings.stt.numericOnlyMode,
          trailing: settingsToggle(
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
        // transform path as the two rows above (handy-catchup ticket 16),
        // so it stays visible for every engine. Default off.
        WpSettingsRow(
          rowId: 'text-remove-filler',
          title: l10n.settingsRemoveFillerWords,
          subtitle: l10n.settingsRemoveFillerWordsSubtitle,
          semanticToggledValue: settings.stt.removeFillerWords,
          trailing: settingsToggle(
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
          semanticToggledValue: settings.stt.voiceLineBreaks,
          trailing: settingsToggle(
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
          semanticToggledValue: settings.stt.spokenPunctuation,
          trailing: settingsToggle(
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
      ],
    );
  }
}
