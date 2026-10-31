import '../../core/config/build_config.dart';
import '../deploy_channel_service.dart';
import 'mac_storekit_support_store_bridge.dart';
import 'support_capabilities.dart';
import 'support_store_bridge.dart';
import 'windows_support_store_bridge.dart';

/// The store bridge for this process. Only store builds talk to a store:
/// the MSIX package on Windows and the Mac App Store build on macOS. Every
/// other build keeps [UnavailableSupportStoreBridge].
SupportStoreBridge resolveSupportStoreBridge({
  required SupportPlatform platform,
  required DeployChannel channel,
  bool isMasBuild = kIsMasBuild,
}) {
  if (channel != DeployChannel.store) {
    return const UnavailableSupportStoreBridge();
  }
  return switch (platform) {
    SupportPlatform.windows => const WindowsSupportStoreBridge(),
    SupportPlatform.macos when isMasBuild => MacStoreKitSupportStoreBridge(),
    _ => const UnavailableSupportStoreBridge(),
  };
}
