import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/stt/whisper/cuda_pack.dart'
    show kCudaEulaSha256, kCudaEulaVersion, kCudaNvidiaEulaUrl;
import '../../../widgets/dialog.dart';
import '../../../widgets/wp_button.dart';
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
      // Expanded: the two labels share the card's width instead of
      // overflowing the footer Row at dialog width.
      Expanded(
        flex: 2,
        child: WpButton(
          key: const Key('cuda-eula-cancel'),
          label: l10n.cudaEulaDialogCancel,
          variant: WpButtonVariant.ghost,
          expanded: true,
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      const SizedBox(width: WpSpacing.xs),
      Expanded(
        flex: 3,
        child: WpButton(
          key: const Key('cuda-eula-accept'),
          label: l10n.cudaEulaDialogAccept,
          variant: WpButtonVariant.primary,
          expanded: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ),
    ],
  );
  return result ?? false;
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
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: WpLayout.minTouchTarget),
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
    );
  }
}
