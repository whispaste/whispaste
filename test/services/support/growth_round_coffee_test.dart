/// Coffee round 2026-10-25 (growth review GR-022, GR-025):
///   - the `linkOpened` telemetry name carries the surface (`<stelle>.<ziel>`),
///   - the coffee pair order is drawn once per install and persisted.
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/services/support/support_state.dart';

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
      expect(SupportLinkSurface.tray.wireName, 'tray');
    });

    test('name is <stelle>.<ziel>', () {
      expect(linkOpenedName(SupportLinkSurface.about, 'kofi'), 'about.kofi');
      expect(
        linkOpenedName(SupportLinkSurface.tray, 'buymeacoffee'),
        'tray.buymeacoffee',
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
}
