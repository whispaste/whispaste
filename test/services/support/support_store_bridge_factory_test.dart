import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/support/mac_storekit_support_store_bridge.dart';
import 'package:whispaste/services/support/support_capabilities.dart';
import 'package:whispaste/services/support/support_store_bridge.dart';
import 'package:whispaste/services/support/support_store_bridge_factory.dart';
import 'package:whispaste/services/support/windows_support_store_bridge.dart';

void main() {
  group('resolveSupportStoreBridge', () {
    test('uses the Microsoft Store bridge in the Windows store channel', () {
      expect(
        resolveSupportStoreBridge(
          platform: SupportPlatform.windows,
          channel: DeployChannel.store,
        ),
        isA<WindowsSupportStoreBridge>(),
      );
    });

    test('uses StoreKit only in the Mac App Store build', () {
      expect(
        resolveSupportStoreBridge(
          platform: SupportPlatform.macos,
          channel: DeployChannel.store,
          isMasBuild: true,
        ),
        isA<MacStoreKitSupportStoreBridge>(),
      );
      expect(
        resolveSupportStoreBridge(
          platform: SupportPlatform.macos,
          channel: DeployChannel.store,
          isMasBuild: false,
        ),
        isA<UnavailableSupportStoreBridge>(),
      );
    });

    test('defaults to the compile-time MAS flag, false in unit tests', () {
      expect(
        resolveSupportStoreBridge(
          platform: SupportPlatform.macos,
          channel: DeployChannel.store,
        ),
        isA<UnavailableSupportStoreBridge>(),
      );
    });

    for (final platform in SupportPlatform.values) {
      for (final channel in DeployChannel.values.where(
        (c) => c != DeployChannel.store,
      )) {
        test('keeps the unavailable bridge on ${platform.name} '
            '${channel.name}', () {
          expect(
            resolveSupportStoreBridge(
              platform: platform,
              channel: channel,
              isMasBuild: true,
            ),
            isA<UnavailableSupportStoreBridge>(),
          );
        });
      }
    }

    test('Linux never gets a store bridge', () {
      expect(
        resolveSupportStoreBridge(
          platform: SupportPlatform.linux,
          channel: DeployChannel.store,
          isMasBuild: true,
        ),
        isA<UnavailableSupportStoreBridge>(),
      );
    });
  });
}
