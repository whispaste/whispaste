/// Widget tests for the support page, one group per channel variant.
///
/// The Mac App Store variant must contain no external link of any kind
/// (App Review guideline 3.1.1); its test asserts that by key.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/app_urls.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/help/support_page.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/support/support_capabilities.dart';
import 'package:whispaste/services/support/support_state.dart';

import '../../fixtures/support_fakes.dart';
import '../../fixtures/test_helpers.dart';

const _externalKeys = [
  'support-sponsors-button',
  'support-kofi-button',
  'support-paypal-button',
  'support-share-x',
  'support-share-facebook',
  'support-share-whatsapp',
  'support-share-linkedin',
  'support-share-reddit',
  'support-share-telegram',
  'support-share-bluesky',
  'support-share-email',
  'support-star-button',
];

Future<FakeSupportStatusNotifier> _pump(
  WidgetTester tester, {
  required DeployChannel channel,
  required SupportPlatform platform,
  SupportStatus status = const SupportStatus(),
}) async {
  final notifier = FakeSupportStatusNotifier(status);
  await tester.pumpWidget(
    makeTestable(
      const SupportPage(),
      locale: const Locale('en'),
      overrides: supportOverrides(
        channel: channel,
        platform: platform,
        status: notifier,
      ),
    ),
  );
  await tester.pump();
  return notifier;
}

Key _key(String id) => ValueKey(id);

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  testWidgets('macOS direct build shows the Mac App Store card', (
    tester,
  ) async {
    await _pump(
      tester,
      channel: DeployChannel.portable,
      platform: SupportPlatform.macos,
    );

    expect(find.text(l10n.supportStoreTitleMac), findsOneWidget);
    expect(find.byKey(_key('support-store-cta')), findsOneWidget);
    expect(find.byKey(_key('support-sponsors-button')), findsOneWidget);
    expect(find.byKey(_key('support-native-tip-button')), findsNothing);
  });

  testWidgets('Linux build offers sponsoring only, no store card', (
    tester,
  ) async {
    await _pump(
      tester,
      channel: DeployChannel.portable,
      platform: SupportPlatform.linux,
    );

    expect(find.byKey(_key('support-store-card')), findsNothing);
    expect(find.byKey(_key('support-sponsors-button')), findsOneWidget);
    expect(find.byKey(_key('support-kofi-button')), findsOneWidget);
    expect(find.byKey(_key('support-paypal-button')), findsOneWidget);
    expect(find.byKey(_key('support-self-declare-button')), findsOneWidget);
  });

  testWidgets('Windows Store build offers native tip and GitHub only', (
    tester,
  ) async {
    await _pump(
      tester,
      channel: DeployChannel.store,
      platform: SupportPlatform.windows,
    );

    expect(find.text(l10n.supportStoreThankYouLine), findsOneWidget);
    expect(find.byKey(_key('support-native-tip-button')), findsOneWidget);
    expect(find.byKey(_key('support-sponsors-button')), findsOneWidget);
    expect(find.byKey(_key('support-kofi-button')), findsNothing);
    expect(find.byKey(_key('support-paypal-button')), findsNothing);
    expect(find.byKey(_key('support-store-card')), findsNothing);
    expect(find.byKey(_key('support-self-declare-button')), findsNothing);
    expect(find.byKey(_key('support-rate-button')), findsOneWidget);
  });

  testWidgets(
    'Mac App Store build contains no external link, only native tip and copy',
    (tester) async {
      await _pump(
        tester,
        channel: DeployChannel.store,
        platform: SupportPlatform.macos,
      );

      expect(find.byKey(_key('support-native-tip-button')), findsOneWidget);
      expect(find.byKey(_key('support-share-link')), findsOneWidget);
      expect(find.byKey(_key('support-rate-button')), findsOneWidget);
      for (final id in _externalKeys) {
        expect(
          find.byKey(_key(id)),
          findsNothing,
          reason: '$id must not exist in the MAS build',
        );
      }
      expect(find.byKey(_key('support-store-card')), findsNothing);
      expect(find.byKey(_key('support-self-declare-button')), findsNothing);
    },
  );

  testWidgets('dismissing the store card hides it and restore brings it back', (
    tester,
  ) async {
    final notifier = await _pump(
      tester,
      channel: DeployChannel.installer,
      platform: SupportPlatform.windows,
    );

    await tester.tap(find.byKey(_key('support-store-offer-dismiss')));
    await tester.pump();
    expect(notifier.calls, contains('dismissStoreOffer'));
    expect(find.byKey(_key('support-store-card')), findsNothing);
    expect(find.byKey(_key('support-store-offer-restore')), findsOneWidget);

    await tester.tap(find.byKey(_key('support-store-offer-restore')));
    await tester.pump();
    expect(notifier.calls, contains('restoreStoreOffer'));
    expect(find.byKey(_key('support-store-card')), findsOneWidget);
  });

  testWidgets('supporter sees the thank-you line and the badge when verified', (
    tester,
  ) async {
    await _pump(
      tester,
      channel: DeployChannel.installer,
      platform: SupportPlatform.windows,
      status: const SupportStatus(verifiedSupporter: true),
    );

    expect(find.text(l10n.supportSupporterLine), findsOneWidget);
    expect(find.byKey(_key('support-supporter-badge')), findsOneWidget);
    expect(find.byKey(_key('support-self-declare-button')), findsNothing);
  });

  testWidgets('verified store buyer can still tip natively', (tester) async {
    await _pump(
      tester,
      channel: DeployChannel.store,
      platform: SupportPlatform.windows,
      status: const SupportStatus(verifiedSupporter: true),
    );

    expect(find.byKey(_key('support-supporter-badge')), findsOneWidget);
    expect(find.byKey(_key('support-native-card')), findsOneWidget);
    expect(find.byKey(_key('support-native-tip-button')), findsOneWidget);
  });

  testWidgets('self-declared supporter gets the line but no badge', (
    tester,
  ) async {
    await _pump(
      tester,
      channel: DeployChannel.portable,
      platform: SupportPlatform.linux,
      status: const SupportStatus(selfDeclaredSupporter: true),
    );

    expect(find.text(l10n.supportSupporterLine), findsOneWidget);
    expect(find.byKey(_key('support-supporter-badge')), findsNothing);
  });

  testWidgets('before declaring: neutral hint and CTA, no confirmation', (
    tester,
  ) async {
    await _pump(
      tester,
      channel: DeployChannel.portable,
      platform: SupportPlatform.linux,
    );

    expect(find.text(l10n.supportSelfDeclareHint), findsOneWidget);
    expect(find.byKey(_key('support-self-declare-button')), findsOneWidget);
    expect(find.text(l10n.supportSelfDeclareNote), findsNothing);
  });

  testWidgets('after declaring: confirmation replaces the CTA', (tester) async {
    await _pump(
      tester,
      channel: DeployChannel.portable,
      platform: SupportPlatform.linux,
      status: const SupportStatus(selfDeclaredSupporter: true),
    );

    expect(find.text(l10n.supportSelfDeclareNote), findsOneWidget);
    expect(find.text(l10n.supportSelfDeclareHint), findsNothing);
    expect(find.byKey(_key('support-self-declare-button')), findsNothing);
  });

  group('supportRateUrl', () {
    test('macOS uses the Mac App Store review link, never a Windows URL', () {
      final url = supportRateUrl(SupportPlatform.macos);
      expect(url, kMacAppStoreReviewUrl);
      expect(url, isNot(contains('ms-windows-store')));
    });

    test('Windows uses the Microsoft Store review link', () {
      expect(supportRateUrl(SupportPlatform.windows), kWindowsStoreReviewUrl);
    });

    test('Linux has no rate target', () {
      expect(supportRateUrl(SupportPlatform.linux), isNull);
    });
  });
}
