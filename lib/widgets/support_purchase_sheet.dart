/// One-time native support purchase (Microsoft Store add-ons on Windows,
/// StoreKit consumables on the Mac App Store).
///
/// The dialog only ever starts from an explicit tap on the support page. Each
/// store outcome has its own view: a cancelled purchase returns silently to
/// the amounts, a pending one says so, and failures offer a retry. Prices are
/// the store's own `formattedPrice`, shown verbatim.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import '../services/support/support_state.dart';
import '../services/support/support_store_bridge.dart';
import 'dialog.dart';
import 'wp_button.dart';

/// Opens the native support purchase dialog.
Future<void> showWpSupportPurchaseDialog(BuildContext context) {
  final l10n = L10n.of(context);
  return showWpDialog<void>(
    context: context,
    title: l10n.supportNativeCta,
    content: const WpSupportPurchaseContent(),
    // The one footer action is the acknowledgement that closes the sheet;
    // the purchase itself lives in the content.
    actions: [
      WpDialogAction(
        label: l10n.supportSheetClose,
        testId: 'support-purchase-close',
        role: WpDialogActionRole.primary,
      ),
    ],
  );
}

/// What the dialog shows. The store catalogue drives [loading], [products],
/// [pricesError] and [unavailable]; a purchase drives the rest.
enum _SheetView {
  loading,
  products,
  pricesError,
  unavailable,
  purchasing,
  succeeded,
  pending,
  purchaseError,
}

/// Body of [showWpSupportPurchaseDialog]. Public for widget tests only.
class WpSupportPurchaseContent extends ConsumerStatefulWidget {
  const WpSupportPurchaseContent({super.key});

  @override
  ConsumerState<WpSupportPurchaseContent> createState() =>
      _SupportPurchaseContentState();
}

class _SupportPurchaseContentState
    extends ConsumerState<WpSupportPurchaseContent> {
  String _selected = kDefaultSupportProductId;

  /// Set once a purchase has started; `null` means "show the catalogue".
  _SheetView? _purchaseView;

  Future<void> _buy(String productId) async {
    setState(() => _purchaseView = _SheetView.purchasing);
    final status = await ref
        .read(supportStatusProvider.notifier)
        .purchase(productId);
    if (!mounted) return;
    setState(() {
      _purchaseView = switch (status) {
        SupportPurchaseStatus.succeeded => _SheetView.succeeded,
        SupportPurchaseStatus.pending => _SheetView.pending,
        // The user closed the store dialog: back to the amounts, silently.
        SupportPurchaseStatus.cancelled => null,
        SupportPurchaseStatus.unavailable => _SheetView.unavailable,
        SupportPurchaseStatus.networkError ||
        SupportPurchaseStatus.serverError => _SheetView.purchaseError,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final catalogue = ref.watch(supportTipProductsProvider);

    final view = _purchaseView ?? _catalogueView(catalogue);
    final body = switch (view) {
      _SheetView.loading => _StatusText(
        text: l10n.supportSheetLoading,
        showSpinner: true,
      ),
      _SheetView.pricesError => _RetryText(
        text: l10n.supportSheetPricesError,
        onRetry: () => ref.invalidate(supportTipProductsProvider),
      ),
      _SheetView.unavailable => _StatusText(text: l10n.supportSheetUnavailable),
      _SheetView.purchasing => _StatusText(
        text: l10n.supportSheetPurchasing,
        showSpinner: true,
      ),
      _SheetView.pending => _StatusText(text: l10n.supportSheetPending),
      _SheetView.purchaseError => _RetryText(
        text: l10n.supportSheetPurchaseError,
        // Retry repeats the purchase of the chosen amount (UIA-FBK-07).
        onRetry: () => _buy(_selected),
      ),
      _SheetView.succeeded => _ThankYou(l10n: l10n),
      _SheetView.products => _ProductList(
        products: catalogue.value ?? const [],
        selected: _selected,
        onSelected: (id) => setState(() => _selected = id),
        onBuy: _buy,
      ),
    };

    return Column(
      key: const ValueKey('support-purchase-sheet'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.supportNativeDescription,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: WpColors.textSecondary,
          ),
        ),
        const SizedBox(height: WpSpacing.md),
        body,
      ],
    );
  }

  static _SheetView _catalogueView(AsyncValue<List<SupportProduct>> catalogue) {
    if (catalogue.isLoading) return _SheetView.loading;
    if (catalogue.hasError) return _SheetView.pricesError;
    final products = catalogue.value ?? const <SupportProduct>[];
    return products.isEmpty ? _SheetView.unavailable : _SheetView.products;
  }
}

class _ProductList extends StatelessWidget {
  const _ProductList({
    required this.products,
    required this.selected,
    required this.onSelected,
    required this.onBuy,
  });

  final List<SupportProduct> products;
  final String selected;
  final ValueChanged<String> onSelected;
  final ValueChanged<String> onBuy;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final picked = products.firstWhere(
      (p) => p.productId == selected,
      orElse: () => products.first,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.supportSheetChoose,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: WpSpacing.xs),
        Wrap(
          spacing: WpSpacing.xs,
          runSpacing: WpSpacing.xs,
          children: [
            for (final product in products)
              Semantics(
                label: product.formattedPrice,
                button: true,
                selected: product.productId == picked.productId,
                excludeSemantics: true,
                child: _AmountTile(
                  productId: product.productId,
                  price: product.formattedPrice,
                  selected: product.productId == picked.productId,
                  onTap: () => onSelected(product.productId),
                ),
              ),
          ],
        ),
        const SizedBox(height: WpSpacing.md),
        WpButton(
          key: const ValueKey('support-purchase-button'),
          label: l10n.supportSheetBuy(picked.formattedPrice),
          variant: WpButtonVariant.primary,
          expanded: true,
          onPressed: () => onBuy(picked.productId),
        ),
      ],
    );
  }
}

class _AmountTile extends StatelessWidget {
  const _AmountTile({
    required this.productId,
    required this.price,
    required this.selected,
    required this.onTap,
  });

  final String productId;
  final String price;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: ValueKey('support-purchase-tier-$productId'),
      onTap: onTap,
      borderRadius: WpRadius.borderMd,
      child: Container(
        constraints: const BoxConstraints(minWidth: 96, minHeight: 48),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.md,
          vertical: WpSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: selected ? WpColors.surfaceChipFill : null,
          borderRadius: WpRadius.borderMd,
          border: Border.all(
            color: selected ? WpColors.accent : WpColors.borderSubtle,
          ),
        ),
        child: Text(
          price,
          style: TextStyle(
            color: selected ? WpColors.accent : WpColors.textPrimary,
            fontSize: WpTypography.body,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _StatusText extends StatelessWidget {
  const _StatusText({required this.text, this.showSpinner = false});

  final String text;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Row(
        children: [
          if (showSpinner) ...[
            const SizedBox(
              width: WpIconSize.sm,
              height: WpIconSize.sm,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: WpSpacing.sm),
          ],
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: WpColors.textSecondary,
                fontSize: WpTypography.body,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RetryText extends StatelessWidget {
  const _RetryText({required this.text, required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatusText(text: text),
        const SizedBox(height: WpSpacing.md),
        WpButton(
          key: const ValueKey('support-purchase-retry'),
          label: l10n.supportSheetRetry,
          variant: WpButtonVariant.secondary,
          onPressed: onRetry,
        ),
      ],
    );
  }
}

class _ThankYou extends StatelessWidget {
  const _ThankYou({required this.l10n});

  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('support-purchase-thank-you'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              LucideIcons.heart,
              size: WpIconSize.sm,
              color: WpSharedColors.supportHeart,
            ),
            const SizedBox(width: WpSpacing.sm),
            Expanded(
              child: Text(
                l10n.supportSheetThanks,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: WpSpacing.xs),
        Text(
          l10n.supportSheetThanksDetail,
          style: TextStyle(
            color: WpColors.textSecondary,
            fontSize: WpTypography.body,
          ),
        ),
      ],
    );
  }
}
