/// Start screen while the data is converted after an encryption switch
/// (#1022).
library;

import 'package:flutter/material.dart';

import '../../core/data/encryption_preference.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/wp_progress_bar.dart';
import 'startup_screen_frame.dart';

/// Says what is being converted and how far it is. The history step has no
/// share it could report (one copy-and-swap), so its bar sweeps; the
/// recordings count up. No button: the run is safe to cut off, and quitting
/// stays possible the usual way.
class EncryptionConversionScreen extends StatelessWidget {
  const EncryptionConversionScreen({super.key, required this.progress});

  final EncryptionConversionProgress progress;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final step = switch (progress.step) {
      EncryptionConversionStep.history => l10n.encryptionConversionHistory,
      EncryptionConversionStep.recordings =>
        progress.total > 0
            ? l10n.encryptionConversionRecordings(progress.done, progress.total)
            : l10n.encryptionConversionRecordingsStart,
    };
    return StartupScreenFrame(
      key: const ValueKey('encryption-conversion-screen'),
      title: progress.toPlain
          ? l10n.encryptionConversionTitleOff
          : l10n.encryptionConversionTitleOn,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(step, key: const ValueKey('encryption-conversion-step')),
        ),
        const SizedBox(height: WpSpacing.md),
        WpProgressBar(
          key: const ValueKey('encryption-conversion-progress'),
          value: progress.fraction,
          semanticsLabel: step,
        ),
        const SizedBox(height: WpSpacing.md),
        Text(l10n.encryptionConversionSafe),
      ],
    );
  }
}

/// Shows [EncryptionConversionScreen] while a conversion runs, [idle]
/// otherwise.
class EncryptionConversionListener extends StatelessWidget {
  const EncryptionConversionListener({super.key, required this.idle});

  final Widget idle;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<EncryptionConversionProgress?>(
        valueListenable: encryptionConversionProgress,
        builder: (context, progress, _) => progress == null
            ? idle
            : EncryptionConversionScreen(progress: progress),
      );
}
