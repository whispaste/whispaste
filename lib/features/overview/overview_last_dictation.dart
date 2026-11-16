import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show NumberFormat;

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/overview/last_dictation.dart';
import '../../core/overview/last_dictation_notifier.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/wp_card.dart';

/// "Letztes Diktat": where the most recent dictation was processed (CPU,
/// GPU or cloud), its transcription time, and a note when a GPU that was
/// wanted did not take the work. Nothing is measured here; the pipeline
/// stored the values when the dictation finished.
class OverviewLastDictation extends ConsumerWidget {
  const OverviewLastDictation({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final last = ref.watch(lastDictationProvider);
    return WpCard(
      key: const ValueKey('overview-last-dictation'),
      title: l10n.overviewLastDictationTitle,
      titleTestId: 'overview-last-dictation-title',
      child: last == null
          ? Text(
              l10n.overviewLastDictationNone,
              key: const ValueKey('overview-last-dictation-none'),
              style: WpTextStyles.rowNote,
            )
          : _Detail(last: last),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.last});

  final LastDictation last;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final seconds = NumberFormat('0.0', lang).format(last.processingMs / 1000);
    final where = switch (last.processing) {
      DictationProcessing.cpu => l10n.overviewLastDictationCpu,
      DictationProcessing.gpu => l10n.overviewLastDictationGpu,
      DictationProcessing.cloud => l10n.overviewLastDictationCloud,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          key: const ValueKey('overview-last-dictation-processing'),
          '$where · ${l10n.overviewLastDictationDuration(seconds)}',
          style: WpTextStyles.rowTitle,
        ),
        if (last.fellBack) ...[
          const SizedBox(height: WpSpacing.xs),
          Text(
            key: const ValueKey('overview-last-dictation-fallback'),
            l10n.overviewLastDictationFallback,
            style: WpTextStyles.rowNote,
          ),
        ],
      ],
    );
  }
}
