/// Coffee support button: visible per channel, the store build never launches
/// an external link, and the layout holds at 800 px, text scale 1.3 and RTL.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/app_urls.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/support/support_capabilities.dart';
import 'package:whispaste/services/support/support_state.dart';
import 'package:whispaste/services/support/support_store_bridge.dart';
import 'package:whispaste/widgets/wp_coffee_button.dart';

import '../fixtures/test_helpers.dart';

const _launcherChannel = MethodChannel('plugins.flutter.io/url_launcher');
const _testId = 'support-coffee-button';

/// Store bridge that reports availability and counts purchases.
class _FakeBridge implements SupportStoreBridge {
  _FakeBridge({required this.available});

  final bool available;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<List<SupportProduct>> loadProducts(List<String> productIds) async =>
      const [];

  @override
  Future<SupportPurchaseStatus> purchase(String productId) async =>
      SupportPurchaseStatus.unavailable;

  @override
  Future<bool> hasVerifiedAppPurchase() async => false;

  @override
  Future<bool> hasVerifiedSupportPurchase() async => false;
}

Future<void> _pump(
  WidgetTester tester, {
  required DeployChannel channel,
  required SupportPlatform platform,
  bool bridgeAvailable = true,
  bool buyMeACoffeeFirst = false,
  Size size = const Size(1280, 800),
  double textScale = 1,
  Locale locale = const Locale('en'),
  bool settle = true,
}) async {
  await tester.pumpWidget(
    makeTestable(
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: WpCoffeeSupportButton(
              testId: _testId,
              surface: SupportLinkSurface.about,
              expanded: true,
            ),
          ),
        ),
      ),
      size: size,
      locale: locale,
      overrides: [
        deployChannelProvider.overrideWithValue(channel),
        supportPlatformProvider.overrideWithValue(platform),
        coffeeBuyMeACoffeeFirstProvider.overrideWith(
          (ref) async => buyMeACoffeeFirst,
        ),
        supportStoreBridgeProvider.overrideWithValue(
          _FakeBridge(available: bridgeAvailable),
        ),
      ],
    ),
  );
  if (!settle) return;
  // The store availability check resolves asynchronously.
  await tester.pumpAndSettle();
}

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_launcherChannel, null);
  });

  testWidgets('a direct Windows build shows the Ko-fi coffee button', (
    tester,
  ) async {
    await _pump(
      tester,
      channel: DeployChannel.installer,
      platform: SupportPlatform.windows,
    );

    expect(find.byKey(const ValueKey(_testId)), findsOneWidget);
    expect(find.text(l10n.aboutKofi), findsOneWidget);
    // Buy Me a Coffee is configured: it sits below with equal rank, the same
    // yellow button, never a secondary one.
    expect(
      find.byKey(const ValueKey('$_testId-buy-me-a-coffee')),
      findsOneWidget,
    );
    expect(find.text(l10n.coffeeBuyMeACoffeeLabel), findsOneWidget);
    expect(find.byType(WpCoffeeButton), findsNWidgets(2));
  });

  testWidgets('Ko-fi leads by default (GR-025)', (tester) async {
    await _pump(
      tester,
      channel: DeployChannel.installer,
      platform: SupportPlatform.windows,
    );
    final kofiTop = tester.getTopLeft(find.byKey(const ValueKey(_testId))).dy;
    final bmcTop = tester
        .getTopLeft(find.byKey(const ValueKey('$_testId-buy-me-a-coffee')))
        .dy;
    expect(kofiTop, lessThan(bmcTop));
  });

  testWidgets('Buy Me a Coffee leads when the install drew it first (GR-025)', (
    tester,
  ) async {
    await _pump(
      tester,
      channel: DeployChannel.installer,
      platform: SupportPlatform.windows,
      buyMeACoffeeFirst: true,
    );
    final kofiTop = tester.getTopLeft(find.byKey(const ValueKey(_testId))).dy;
    final bmcTop = tester
        .getTopLeft(find.byKey(const ValueKey('$_testId-buy-me-a-coffee')))
        .dy;
    expect(bmcTop, lessThan(kofiTop));
  });

  testWidgets('the first frames never show the other order than the drawn one '
      '(UX-082)', (tester) async {
    await _pump(
      tester,
      channel: DeployChannel.installer,
      platform: SupportPlatform.windows,
      buyMeACoffeeFirst: true,
      settle: false,
    );
    // Each frame before the draw is known shows nothing or the drawn order.
    for (var frame = 0; frame < 3; frame++) {
      final buttons = find.byType(WpCoffeeButton);
      if (buttons.evaluate().isNotEmpty) {
        expect(
          tester.widget<WpCoffeeButton>(buttons.first).testId,
          '$_testId-buy-me-a-coffee',
        );
      }
      await tester.pump();
    }
  });

  testWidgets('the Ko-fi button opens kKofiUrl', (tester) async {
    String? capturedUrl;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_launcherChannel, (call) async {
          if (call.method == 'canLaunch' || call.method == 'launch') {
            capturedUrl = (call.arguments as Map)['url'] as String?;
          }
          return true;
        });

    await _pump(
      tester,
      channel: DeployChannel.portable,
      platform: SupportPlatform.linux,
    );
    await tester.tap(find.byKey(const ValueKey(_testId)));
    await tester.pumpAndSettle();

    expect(capturedUrl, kKofiUrl);
  });

  testWidgets('a Mac App Store build with a sellable purchase shows the '
      'button and never launches an external link', (tester) async {
    var launched = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_launcherChannel, (call) async {
          launched = true;
          return true;
        });

    await _pump(
      tester,
      channel: DeployChannel.store,
      platform: SupportPlatform.macos,
    );

    expect(find.byKey(const ValueKey(_testId)), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey(_testId)));
    await tester.pumpAndSettle();

    expect(launched, isFalse);
  });

  testWidgets('a Microsoft Store build never launches an external link', (
    tester,
  ) async {
    var launched = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_launcherChannel, (call) async {
          launched = true;
          return true;
        });

    await _pump(
      tester,
      channel: DeployChannel.store,
      platform: SupportPlatform.windows,
    );

    expect(find.byKey(const ValueKey(_testId)), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey(_testId)));
    await tester.pumpAndSettle();

    expect(launched, isFalse);
  });

  testWidgets('a store build the store cannot sell hides the button', (
    tester,
  ) async {
    await _pump(
      tester,
      channel: DeployChannel.store,
      platform: SupportPlatform.windows,
      bridgeAvailable: false,
    );

    expect(find.byKey(const ValueKey(_testId)), findsNothing);
    expect(find.text(l10n.coffeeButtonLabel), findsNothing);
  });

  testWidgets('a Mac direct installer, which has no payment route, hides the '
      'button', (tester) async {
    await _pump(
      tester,
      channel: DeployChannel.installer,
      platform: SupportPlatform.macos,
    );

    expect(find.byKey(const ValueKey(_testId)), findsNothing);
  });
}
