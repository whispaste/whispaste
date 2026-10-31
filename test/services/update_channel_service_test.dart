/// Tests for [UpdateChannelNotifier] persistence + [parseUpdateChannel].
///
/// Mirrors the SharedPreferences-mock + [ProviderContainer] convention used by
/// `store_thank_you_service_test.dart`.
///
/// Covers:
///   AC-6  Channel survives an app restart (stable → beta → restart → beta).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/services/update_channel_service.dart';

void main() {
  group('parseUpdateChannel', () {
    test('null/empty/unknown → stable default', () {
      expect(parseUpdateChannel(null), UpdateChannel.stable);
      expect(parseUpdateChannel(''), UpdateChannel.stable);
      expect(parseUpdateChannel('nightly'), UpdateChannel.stable);
      expect(
        parseUpdateChannel('BETA'),
        UpdateChannel.stable,
      ); // case-sensitive
    });

    test('beta token → beta', () {
      expect(parseUpdateChannel('beta'), UpdateChannel.beta);
    });

    test('stable token → stable', () {
      expect(parseUpdateChannel('stable'), UpdateChannel.stable);
    });
  });

  group('UpdateChannelNotifier', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('default channel is stable on a fresh install', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        await container.read(updateChannelProvider.future),
        UpdateChannel.stable,
      );
    });

    test(
      'setChannel(beta) updates state and persists to SharedPreferences',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await container
            .read(updateChannelProvider.notifier)
            .setChannel(UpdateChannel.beta);

        expect(container.read(updateChannelProvider).value, UpdateChannel.beta);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('update_channel'), 'beta');
      },
    );

    test('setChannel(stable) from beta flips it back', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(updateChannelProvider.notifier)
          .setChannel(UpdateChannel.beta);
      await container
          .read(updateChannelProvider.notifier)
          .setChannel(UpdateChannel.stable);

      expect(container.read(updateChannelProvider).value, UpdateChannel.stable);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('update_channel'), 'stable');
    });

    test(
      'AC-6: stable → beta → restart → still beta (persisted across restarts)',
      () async {
        // Session A: default stable, user opts into beta.
        final containerA = ProviderContainer();
        await containerA.read(updateChannelProvider.future);
        await containerA
            .read(updateChannelProvider.notifier)
            .setChannel(UpdateChannel.beta);
        expect(
          containerA.read(updateChannelProvider).value,
          UpdateChannel.beta,
        );
        containerA.dispose();

        // Restart: fresh container reads the SAME persisted prefs mock.
        final containerB = ProviderContainer();
        addTearDown(containerB.dispose);

        expect(
          await containerB.read(updateChannelProvider.future),
          UpdateChannel.beta,
        );
      },
    );

    test(
      'persisted beta is loaded on a new container without resetting prefs',
      () async {
        SharedPreferences.setMockInitialValues({'update_channel': 'beta'});

        final container = ProviderContainer();
        addTearDown(container.dispose);

        expect(
          await container.read(updateChannelProvider.future),
          UpdateChannel.beta,
        );
      },
    );

    test('unknown persisted value degrades to stable', () async {
      SharedPreferences.setMockInitialValues({'update_channel': 'canary'});

      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        await container.read(updateChannelProvider.future),
        UpdateChannel.stable,
      );
    });
  });
}
