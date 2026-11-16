import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/l10n/generated/app_localizations.dart';
import 'dialog.dart';
import 'wp_page_notice.dart';

/// Opens [url] in the system browser or the store app.
///
/// Returns false and shows an error notice with a "copy address" action when
/// no handler accepted the link, so the user is never left with a click that
/// silently did nothing (UIA-HLP-01, UIA-FBK-08, UIA-SET-09).
Future<bool> openExternalUrl(BuildContext context, String url) async {
  final uri = Uri.parse(url);
  var opened = false;
  try {
    opened =
        await canLaunchUrl(uri) &&
        await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on Exception {
    opened = false;
  }
  if (!opened && context.mounted) {
    final l10n = L10n.of(context);
    showWpAppError(
      context,
      id: 'external-link-failed',
      message: l10n.externalLinkOpenFailed,
      actionLabel: l10n.externalLinkCopyAddress,
      actionTestId: 'external-link-copy-address',
      onAction: () => Clipboard.setData(ClipboardData(text: url)),
    );
  }
  return opened;
}

/// Asks before leaving the app, then opens [url] like [openExternalUrl].
///
/// For targets the user does not expect to be a plain link (a voting board, a
/// third-party site): the dialog names the [destination] (a noun phrase, e.g.
/// "the ideas board") and only "Continue" opens the browser. Cancel, Esc and a
/// tap outside open nothing and return false.
Future<bool> openExternalUrlConfirmed(
  BuildContext context,
  String url, {
  required String destination,
}) async {
  final l10n = L10n.of(context);
  final ok = await showWpConfirmDialog(
    context: context,
    title: l10n.externalLeaveTitle,
    message: l10n.externalLeaveMessage(destination),
    confirmLabel: l10n.externalLeaveContinue,
    cancelLabel: l10n.actionCancel,
  );
  if (!ok || !context.mounted) return false;
  return openExternalUrl(context, url);
}
