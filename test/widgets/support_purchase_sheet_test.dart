/// Widget tests for the native support purchase dialog: each store outcome
/// has its own view, and a cancelled purchase returns silently to the amounts.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/support/support_capabilities.dart';
import 'package:whispaste/services/support/support_store_bridge.dart';
import 'package:whispaste/widgets/support_purchase_sheet.dart';

import '../fixtures/support_fakes.dart';
import '../fixtures/test_helpers.dart';

const _products = [
  SupportProduct(
    productId: 'whispaste.support.once.1',
    title: 'Small',
    formattedPrice: '1,99 €',
  ),
  SupportProduct(
    productId: 'whispaste.support.once.2',
    title: 'Medium',
    formattedPrice: '4,99 €',
  ),
];

Future<FakeSupportStatusNotifier> _open(
  WidgetTester tester, {
  List<SupportProduct> products = _products,
  Object? productsError,
  SupportPurchaseStatus purchaseResult = SupportPurchaseStatus.succeeded,
}) async {
  final notifier = FakeSupportStatusNotifier()..purchaseResult = purchaseResult;
  await tester.pumpWidget(
    makeTestable(
      Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            key: const ValueKey('open'),
            onPressed: () => showWpSupportPurchaseDialog(context),
            child: const Text('open'),
          ),
        ),
      ),
      locale: const Locale('en'),
      overrides: supportOverrides(
        channel: DeployChannel.store,
        platform: SupportPlatform.windows,
        status: notifier,
        products: products,
        productsError: productsError,
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('open')));
  await tester.pumpAndSettle();
  return notifier;
}

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  testWidgets('shows the catalogue with the default amount preselected', (
    tester,
  ) async {
    await _open(tester);

    expect(
      find.byKey(const ValueKey('support-purchase-sheet')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('support-purchase-tier-whispaste.support.once.1'),
      ),
      findsOneWidget,
    );
    expect(
      find.text(l10n.supportSheetBuy('4,99 €')),
      findsOneWidget,
      reason: 'the default amount is the second tier',
    );
    expect(
      find.byKey(const ValueKey('support-purchase-button')),
      findsOneWidget,
    );
  });

  testWidgets('selecting another amount changes the buy label', (tester) async {
    await _open(tester);

    await tester.tap(
      find.byKey(
        const ValueKey('support-purchase-tier-whispaste.support.once.1'),
      ),
    );
    await tester.pump();
    expect(find.text(l10n.supportSheetBuy('1,99 €')), findsOneWidget);
  });

  testWidgets('successful purchase shows the thank-you state', (tester) async {
    final notifier = await _open(tester);

    await tester.tap(find.byKey(const ValueKey('support-purchase-button')));
    await tester.pumpAndSettle();

    expect(notifier.calls, ['purchase:whispaste.support.once.2']);
    expect(
      find.byKey(const ValueKey('support-purchase-thank-you')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('support-purchase-button')), findsNothing);
  });

  testWidgets('cancelled purchase returns to the amounts silently', (
    tester,
  ) async {
    await _open(tester, purchaseResult: SupportPurchaseStatus.cancelled);

    await tester.tap(find.byKey(const ValueKey('support-purchase-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('support-purchase-button')),
      findsOneWidget,
    );
    expect(find.text(l10n.supportSheetPurchaseError), findsNothing);
    expect(
      find.byKey(const ValueKey('support-purchase-thank-you')),
      findsNothing,
    );
  });

  testWidgets('pending purchase says it awaits confirmation', (tester) async {
    await _open(tester, purchaseResult: SupportPurchaseStatus.pending);

    await tester.tap(find.byKey(const ValueKey('support-purchase-button')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.supportSheetPending), findsOneWidget);
  });

  testWidgets('server error offers a retry that returns to the amounts', (
    tester,
  ) async {
    await _open(tester, purchaseResult: SupportPurchaseStatus.serverError);

    await tester.tap(find.byKey(const ValueKey('support-purchase-button')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.supportSheetPurchaseError), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('support-purchase-retry')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('support-purchase-button')),
      findsOneWidget,
    );
  });

  testWidgets('empty catalogue shows the unavailable state without buy', (
    tester,
  ) async {
    await _open(tester, products: const []);

    expect(find.text(l10n.supportSheetUnavailable), findsOneWidget);
    expect(find.byKey(const ValueKey('support-purchase-button')), findsNothing);
  });

  testWidgets('catalogue error offers a retry', (tester) async {
    await _open(tester, productsError: StateError('store down'));

    expect(find.text(l10n.supportSheetPricesError), findsOneWidget);
    expect(
      find.byKey(const ValueKey('support-purchase-retry')),
      findsOneWidget,
    );
  });

  testWidgets('loading state shows while the catalogue is pending', (
    tester,
  ) async {
    final completer = Completer<List<SupportProduct>>();
    final notifier = FakeSupportStatusNotifier();
    await tester.pumpWidget(
      makeTestable(
        Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              key: const ValueKey('open'),
              onPressed: () => showWpSupportPurchaseDialog(context),
              child: const Text('open'),
            ),
          ),
        ),
        locale: const Locale('en'),
        overrides: supportOverrides(
          channel: DeployChannel.store,
          platform: SupportPlatform.windows,
          status: notifier,
          pendingCatalogue: completer.future,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pump();
    await tester.pump();

    expect(find.text(l10n.supportSheetLoading), findsOneWidget);
    completer.complete(const []);
    await tester.pumpAndSettle();
  });
}
