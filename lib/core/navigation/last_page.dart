/// Start-up restore and remember-on-visit for the last top-level page.
///
/// The pure rules live in `page_state.dart`; this file wires them to the
/// settings and the `app_settings` row.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/settings_provider.dart';
import '../data/database.dart';
import '../logging/app_logger.dart';
import '../onboarding/onboarding_surface.dart';
import 'page_state.dart';

final _log = AppLogger('LastPage');

/// Keeps the last visited restorable page in the database.
///
/// Read once by the app shell's entry point (see `restoreLastPage`) so the
/// listener is registered before the first navigation.
final lastPagePersistenceProvider = Provider<void>((ref) {
  ref.keepAlive();
  ref.listen<String>(activePageProvider, (_, next) {
    final pageId = persistablePage(
      next,
      surfaceActive: ref.read(onboardingSurfaceActiveProvider),
    );
    if (pageId == null) return;
    // Best effort: losing one remembered page is not worth an error.
    unawaited(
      ref
          .read(historyDatabaseProvider)
          .writeLastPage(pageId)
          .then<void>(
            (_) {},
            onError: (Object e) {
              _log.debug('Could not remember page $pageId (${e.runtimeType})');
            },
          ),
    );
  });
});

/// Shows the page the user left last session. Call once after settings have
/// resolved. A failed read keeps the default start page instead of blocking
/// start-up.
Future<void> restoreLastPage(ProviderContainer container) async {
  container.read(lastPagePersistenceProvider);
  try {
    final settings = await container.read(settingsProvider.future);
    final stored = await container.read(historyDatabaseProvider).readLastPage();
    final start = resolveStartPage(
      stored,
      onboardingCompleted: settings.onboarding.onboardingCompleted,
    );
    // Pass the stored id itself when it is a retired one that resolves to the
    // start page, so its target (Support tab, About section) still applies.
    final restoreId = stored != null && canonicalPageId(stored) == start
        ? stored
        : start;
    container.read(activePageProvider.notifier).restore(restoreId);
  } on Object catch (e) {
    _log.warning('Restoring the last page failed, starting on history: $e');
  }
}
