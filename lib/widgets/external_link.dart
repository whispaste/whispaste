import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/l10n/generated/app_localizations.dart';
import 'toast.dart';

/// Opens [url] in the system browser or the store app.
///
/// Returns false and shows an error toast with a "copy address" action when
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
    WpToast.show(
      context,
      message: l10n.externalLinkOpenFailed,
      type: WpToastType.error,
      action: WpToastAction(
        label: l10n.externalLinkCopyAddress,
        onPressed: () => Clipboard.setData(ClipboardData(text: url)),
      ),
    );
  }
  return opened;
}
