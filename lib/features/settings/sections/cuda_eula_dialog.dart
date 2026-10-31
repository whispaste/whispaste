import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/stt/whisper/cuda_pack.dart'
    show
        kCudaEulaAssetPath,
        kCudaEulaSha256,
        kCudaEulaVersion,
        kCudaNvidiaEulaUrl;
import '../../../widgets/dialog.dart';
import '../../../widgets/wp_text_link.dart';

/// Consent dialog shown before the optional CUDA pack is downloaded. The pack
/// ships NVIDIA components under NVIDIA's CUDA EULA, so the download starts
/// only after "Zustimmen und herunterladen" (accept). Cancel, Esc and a tap
/// outside leave everything untouched.
///
/// Resolves to `true` only on accept.
Future<bool> showCudaEulaDialog(BuildContext context) async {
  final l10n = L10n.of(context);
  final result = await showWpDialog<bool>(
    context: context,
    title: l10n.cudaEulaDialogTitle,
    content: _CudaEulaContent(l10n: l10n),
    actions: [
      WpDialogAction<bool>(
        label: l10n.cudaEulaDialogCancel,
        testId: 'cuda-eula-cancel',
        role: WpDialogActionRole.cancel,
        value: false,
      ),
      WpDialogAction<bool>(
        label: l10n.cudaEulaDialogAccept,
        testId: 'cuda-eula-accept',
        role: WpDialogActionRole.deliberate,
        value: true,
      ),
    ],
  );
  return result ?? false;
}

/// Shows the licence text bundled with the app: the same text that ships as
/// `LICENSE-NVIDIA.txt` in every pack, readable before any download starts.
Future<void> showCudaEulaFullText(BuildContext context) async {
  final l10n = L10n.of(context);
  final text = await rootBundle.loadString(kCudaEulaAssetPath);
  if (!context.mounted) return;
  await showWpDialog<void>(
    context: context,
    title: l10n.cudaEulaDialogTitle,
    content: SizedBox(
      height: 360,
      child: Scrollbar(
        child: SingleChildScrollView(
          child: SelectableText(
            text,
            key: const Key('cuda-eula-fulltext'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ),
    ),
    actions: [
      WpDialogAction<void>(
        label: l10n.cudaEulaFullTextClose,
        testId: 'cuda-eula-fulltext-close',
        role: WpDialogActionRole.primary,
      ),
    ],
  );
}

class _CudaEulaContent extends StatelessWidget {
  const _CudaEulaContent({required this.l10n});

  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('cuda-eula-dialog'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.cudaEulaDialogBody(
            '$kCudaEulaVersion, SHA-256 ${kCudaEulaSha256.substring(0, 12)}…',
          ),
          key: const Key('cuda-eula-body'),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: WpSpacing.sm),
        Wrap(
          spacing: WpSpacing.md,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: WpLayout.minTouchTarget,
              ),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: WpTextLink(
                  key: const Key('cuda-eula-fulltext-open'),
                  label: l10n.cudaEulaFullTextOpen,
                  icon: LucideIcons.fileText,
                  onPressed: () => showCudaEulaFullText(context),
                ),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: WpLayout.minTouchTarget,
              ),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: WpTextLink(
                  key: const Key('cuda-eula-link'),
                  label: l10n.cudaEulaDialogLink,
                  icon: LucideIcons.externalLink,
                  onPressed: () => launchUrl(
                    Uri.parse(kCudaNvidiaEulaUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
