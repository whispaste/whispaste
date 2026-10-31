/// Coffee round 2026-10-25 (growth review GR-022, GR-024, GR-025):
///   - the `linkOpened` telemetry name carries the surface (`<stelle>.<ziel>`),
///   - the coffee pair order is drawn once per install and persisted,
///   - the automatic support prompt offers only the coffee pair plus
///     "Weitere Wege"; the recurring follow-up keeps its monthly route.
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/support/support_capabilities.dart';
import 'package:whispaste/services/support/support_state.dart';
import 'package:whispaste/services/support_prompt_service.dart';
import 'package:whispaste/widgets/support_prompt_dialog.dart';

/// Random source with a fixed answer for [nextBool].
class _FixedRandom implements Random {
  _FixedRandom(this.value);

  final bool value;

  @override
  bool nextBool() => value;

  @override
  int nextInt(int max) => throw UnimplementedError();

  @override
  double nextDouble() => throw UnimplementedError();
}

void main() {
  group('GR-022 linkOpened names the surface', () {
    test('wire names of the fixed surface list', () {
      expect(SupportLinkSurface.about.wireName, 'about');
      expect(SupportLinkSurface.supportTab.wireName, 'support_tab');
      expect(SupportLinkSurface.prompt.wireName, 'prompt');
      expect(SupportLinkSurface.tray.wireName, 'tray');
    });

    test('name is <stelle>.<ziel>', () {
      expect(linkOpenedName(SupportLinkSurface.about, 'kofi'), 'about.kofi');
      expect(
        linkOpenedName(SupportLinkSurface.prompt, 'buymeacoffee'),
        'prompt.buymeacoffee',
      );
      expect(
        linkOpenedName(SupportLinkSurface.supportTab, 'github'),
        'support_tab.github',
      );
    });
  });

  group('GR-025 coffee pair order is persisted once per install', () {
    test('a drawn order is kept on later calls', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final first = await coffeeBuyMeACoffeeFirst(
        prefs,
        random: _FixedRandom(true),
      );
      final second = await coffeeBuyMeACoffeeFirst(
        prefs,
        random: _FixedRandom(false),
      );

      expect(first, isTrue);
      expect(second, isTrue, reason: 'the persisted draw must win');
    });

    test('the other order is drawn when the random source says so', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      expect(
        await coffeeBuyMeACoffeeFirst(prefs, random: _FixedRandom(false)),
        isFalse,
      );
    });
  });

  group('GR-024 automatic prompt offers the coffee pair and Weitere Wege', () {
    test('direct installer build: Ko-fi, Buy Me a Coffee, Weitere Wege', () {
      final actions = offeredPromptActions(
        asks: supportCapabilities(
          DeployChannel.installer,
          SupportPlatform.windows,
        ),
        coffee: CoffeeSupportTarget.externalLinks,
        buyMeACoffeeFirst: false,
        kind: SupportPromptKind.initial,
      );

      expect(actions, [
        WpSupportPromptAction.kofi,
        WpSupportPromptAction.buyMeACoffee,
        WpSupportPromptAction.moreWays,
      ]);
    });

    test('the drawn order flips the coffee pair, Weitere Wege stays last', () {
      final actions = offeredPromptActions(
        asks: supportCapabilities(
          DeployChannel.portable,
          SupportPlatform.windows,
        ),
        coffee: CoffeeSupportTarget.externalLinks,
        buyMeACoffeeFirst: true,
        kind: SupportPromptKind.initial,
      );

      expect(actions, [
        WpSupportPromptAction.buyMeACoffee,
        WpSupportPromptAction.kofi,
        WpSupportPromptAction.moreWays,
      ]);
    });

    test(
      'Windows Store build with native coffee: store coffee, then more ways',
      () {
        final actions = offeredPromptActions(
          asks: supportCapabilities(
            DeployChannel.store,
            SupportPlatform.windows,
          ),
          coffee: CoffeeSupportTarget.storePurchase,
          buyMeACoffeeFirst: false,
          kind: SupportPromptKind.initial,
        );

        expect(actions, [
          WpSupportPromptAction.coffeeStore,
          WpSupportPromptAction.moreWays,
        ]);
      },
    );

    test('recurring follow-up keeps the monthly route (GitHub Sponsors)', () {
      final actions = offeredPromptActions(
        asks: supportCapabilities(
          DeployChannel.installer,
          SupportPlatform.windows,
        ),
        coffee: CoffeeSupportTarget.externalLinks,
        buyMeACoffeeFirst: false,
        kind: SupportPromptKind.recurringFollowUp,
      );

      expect(actions, contains(WpSupportPromptAction.gitHubSponsors));
      expect(actions, isNot(contains(WpSupportPromptAction.moreWays)));
    });
  });
}
