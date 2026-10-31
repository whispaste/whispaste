import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/overview/storage_usage.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../services/storage_usage_service.dart';
import '../../widgets/dialog.dart' show showWpConfirmDialog;
import '../../widgets/wp_button.dart';
import '../../widgets/wp_card.dart';
import '../../widgets/wp_row_divider.dart';
import '../../widgets/wp_text_link.dart';
import 'overview_navigation.dart';

/// The sizes measured for the storage block. Auto-disposed: the walk runs
/// only while the block is on screen, and the cache keeps the result briefly.
final overviewStorageProvider = FutureProvider.autoDispose<StorageSizes>(
  (ref) => ref.watch(storageUsageCacheProvider).read(),
);

/// "Speicher von WhisPaste": speech models, recordings and cache, with
/// "Aufräumen…" for the cache only. Models and recordings are never removed
/// here; recordings have their own retention setting.
class OverviewStorage extends ConsumerStatefulWidget {
  const OverviewStorage({super.key});

  @override
  ConsumerState<OverviewStorage> createState() => _OverviewStorageState();
}

class _OverviewStorageState extends ConsumerState<OverviewStorage> {
  bool _busy = false;
  bool _cleanupFailed = false;

  Future<void> _cleanUp(StorageSizes sizes) async {
    final l10n = L10n.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final confirmed = await showWpConfirmDialog(
      context: context,
      title: l10n.overviewStorageCleanupTitle,
      message: l10n.overviewStorageCleanupMessage(
        formatStorageBytes(sizes.cache ?? 0, lang),
      ),
      confirmLabel: l10n.overviewStorageCleanupConfirm,
      cancelLabel: l10n.actionCancel,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _busy = true;
      _cleanupFailed = false;
    });
    var failed = false;
    try {
      await clearStorageCache();
    } on Object {
      failed = true;
    }
    ref.read(storageUsageCacheProvider).invalidate();
    ref.invalidate(overviewStorageProvider);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _cleanupFailed = failed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final measured = ref.watch(overviewStorageProvider);
    final sizes = measured.value;

    String value(int? bytes) {
      if (measured.hasError) return l10n.overviewStorageUnreadable;
      if (sizes == null) return '…';
      return bytes == null
          ? l10n.overviewStorageUnreadable
          : formatStorageBytes(bytes, lang);
    }

    Widget row(String id, String label, int? bytes) => Row(
      key: ValueKey('overview-storage-$id'),
      children: [
        Expanded(child: Text(label, style: WpTextStyles.rowTitle)),
        Text(
          value(bytes),
          key: ValueKey('overview-storage-$id-value'),
          style: WpTextStyles.rowNote,
        ),
      ],
    );

    final cacheBytes = sizes?.cache;
    return WpCard(
      key: const ValueKey('overview-storage'),
      title: l10n.overviewStorageTitle,
      titleTestId: 'overview-storage-title',
      trailing: WpTextLink(
        testID: 'overview-storage-manage',
        label: l10n.overviewStorageManage,
        icon: LucideIcons.arrowRight,
        iconAfter: true,
        onPressed: () =>
            overviewOpenTarget(ref, 'settings:privacy-history-retention'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row('models', l10n.overviewStorageModels, sizes?.models),
          const WpRowDivider(),
          row('recordings', l10n.overviewStorageRecordings, sizes?.recordings),
          const WpRowDivider(),
          row('cache', l10n.overviewStorageCache, cacheBytes),
          const SizedBox(height: WpSpacing.md),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: WpButton(
              testId: 'overview-storage-cleanup',
              label: l10n.overviewStorageCleanup,
              variant: WpButtonVariant.secondary,
              onPressed: _busy || sizes == null || (cacheBytes ?? 0) == 0
                  ? null
                  : () => _cleanUp(sizes),
            ),
          ),
          if (_cleanupFailed) ...[
            const SizedBox(height: WpSpacing.xs),
            Text(
              key: const ValueKey('overview-storage-cleanup-failed'),
              l10n.overviewStorageCleanupFailed,
              style: WpTextStyles.rowNote.copyWith(color: WpColors.error),
            ),
          ],
        ],
      ),
    );
  }
}
