/// Main-window preview for multiline automation inserts (WP-38 / 8.5).
///
/// [WpMultilinePastePreviewHost] watches [multilinePasteConfirmationProvider]
/// and opens a dialog while a request is pending. Confirm inserts, cancel,
/// dismissing the dialog, and the provider's timeout all resolve the request
/// with a decision; nothing is pasted here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/tokens.dart';
import '../services/automation_api/multiline_paste_confirmation.dart';
import '../services/window_activation.dart';
import 'dialog.dart';

/// Invisible host that lives in the main shell and shows the preview dialog.
class WpMultilinePastePreviewHost extends ConsumerStatefulWidget {
  const WpMultilinePastePreviewHost({super.key});

  @override
  ConsumerState<WpMultilinePastePreviewHost> createState() =>
      _WpMultilinePastePreviewHostState();
}

class _WpMultilinePastePreviewHostState
    extends ConsumerState<WpMultilinePastePreviewHost> {
  /// The dialog is on screen.
  bool _open = false;

  /// The window is being brought forward; the dialog opens once it is.
  bool _pending = false;

  @override
  Widget build(BuildContext context) {
    ref.listen<MultilinePasteRequest?>(multilinePasteConfirmationProvider, (
      _,
      next,
    ) {
      if (next == null) {
        // Confirm, cancel, or the timeout settled the request: close the
        // dialog if it is still up. A request still waiting for the window
        // has no dialog to close; `_show` sees the settled state and stops.
        if (_open) Navigator.of(context).maybePop();
        return;
      }
      if (_open || _pending) return;
      _pending = true;
      _show(next);
    });
    return const SizedBox.shrink();
  }

  /// Shows the main window first when it is hidden or minimized, so the
  /// preview is never invisible. Confirming pastes into the captured target,
  /// which the paste path restores; cancelling leaves focus here.
  Future<void> _show(MultilinePasteRequest request) async {
    final hidden = await ref.read(mainWindowHiddenProvider)();
    if (hidden) await ref.read(windowActivatorProvider)();
    _pending = false;
    if (!mounted) return;
    // The request may have settled while the window came up (timeout or an
    // automation-side cancel); then there is nothing left to preview.
    if (ref.read(multilinePasteConfirmationProvider) != request) return;
    _open = true;
    final l10n = L10n.of(context);
    final confirmation = ref.read(multilinePasteConfirmationProvider.notifier);

    showWpDialog<void>(
      context: context,
      title: l10n.automationPreviewTitle,
      content: _PreviewContent(request: request),
      // Insert is `deliberate`: Enter alone must never paste into another
      // app (A-M7).
      actions: [
        WpDialogAction(
          label: l10n.automationPreviewInsert,
          testId: 'multiline-paste-preview-confirm',
          role: WpDialogActionRole.deliberate,
          onPressed: confirmation.confirm,
        ),
        WpDialogAction(
          label: l10n.automationPreviewCancel,
          testId: 'multiline-paste-preview-cancel',
          role: WpDialogActionRole.cancel,
          onPressed: confirmation.cancel,
        ),
      ],
    ).then((_) {
      _open = false;
      // Barrier tap or Escape: resolve as cancelled. No-op when already
      // settled by a button or the timeout.
      confirmation.cancel();
    });
  }
}

class _PreviewContent extends StatelessWidget {
  const _PreviewContent({required this.request});

  final MultilinePasteRequest request;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('multiline-paste-preview'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.automationPreviewBody, style: theme.textTheme.bodyMedium),
        const SizedBox(height: WpSpacing.sm),
        Text(
          l10n.automationPreviewLineCount(request.lineCount),
          style: theme.textTheme.labelMedium,
        ),
        const SizedBox(height: WpSpacing.xs),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: SingleChildScrollView(
            child: SelectableText(
              request.text,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
      ],
    );
  }
}
