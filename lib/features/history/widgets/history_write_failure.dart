/// The storage error of every write on the recordings page, with its
/// diagnostics. It uses the shared page notice ([WpPageNotice]).
library;

import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../../core/app_info.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/logging/crash_fingerprints.dart';
import '../../../widgets/wp_button.dart';
import '../../../widgets/wp_copy_feedback.dart';
import '../../../widgets/wp_page_notice.dart';

/// The storage error of every write on this page, with its diagnostics.
void showHistoryWriteFailed(BuildContext context, {String? entryId}) {
  showWpPageNotice(
    context,
    page: WpNoticePage.history,
    notice: historyWriteFailedNotice(
      L10n.of(context).historyWriteFailed,
      entryId: entryId,
    ),
  );
}

/// The write-failure notice for callers that no longer have a context (a panel
/// that is closing): they build it earlier and show it through the notice
/// notifier.
WpPageNotice historyWriteFailedNotice(String message, {String? entryId}) =>
    WpPageNotice(
      id: 'write-failed',
      message: message,
      area: entryId,
      action: (_) => const HistoryDiagnosticsButton(),
    );

/// Copies [historyWriteDiagnostics]; every storage error offers it.
class HistoryDiagnosticsButton extends StatelessWidget {
  const HistoryDiagnosticsButton({
    super.key,
    this.testId = 'page-notice-diagnostics',
  });

  final String testId;

  @override
  Widget build(BuildContext context) => WpCopyButton(
    testId: testId,
    label: L10n.of(context).historyWriteFailedAction,
    variant: WpButtonVariant.ghost,
    icon: null,
    text: historyWriteDiagnostics,
  );
}

/// A compact block for a bug report: app version, platform and the canonical
/// fingerprint. Sentry's own event ID is not available here, because the
/// capture happens inside the write coordinator; the fingerprint plus a
/// timestamp is enough for the maintainer to correlate.
String historyWriteDiagnostics() {
  final timestamp = DateTime.now().toUtc().toIso8601String();
  final diag = StringBuffer()
    ..writeln('WhisPaste diagnostics')
    ..writeln('fingerprint: $historyWriteFailed')
    ..writeln('app: $appName $appVersion')
    ..writeln(
      'platform: ${Platform.operatingSystem} '
      '${Platform.operatingSystemVersion}',
    )
    ..writeln('locale: ${Platform.localeName}')
    ..writeln('timestamp: $timestamp');
  return diag.toString();
}
