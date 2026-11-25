import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/update_actions.dart';
import 'package:whispaste/services/update_service.dart';

void main() {
  group('updatesInstalledByHand (PAR-004)', () {
    test(
      'a portable install without self-updater ends at the release page',
      () {
        expect(
          updatesInstalledByHand(DeployChannel.portable, autoUpdater: false),
          isTrue,
        );
      },
    );

    test('a self-updater installs on its own', () {
      expect(
        updatesInstalledByHand(DeployChannel.portable, autoUpdater: true),
        isFalse,
      );
    });

    test('store, package manager and installer are not manual', () {
      for (final channel in [
        DeployChannel.store,
        DeployChannel.packageManaged,
        DeployChannel.installer,
      ]) {
        expect(updatesInstalledByHand(channel, autoUpdater: false), isFalse);
      }
    });
  });

  group('presentsNativeUpdateDialog (#1881)', () {
    test('a plain check keeps the result in the app', () {
      for (final phase in [
        UpdatePhase.idle,
        UpdatePhase.checking,
        UpdatePhase.upToDate,
        UpdatePhase.error,
      ]) {
        expect(presentsNativeUpdateDialog(phase), isFalse, reason: '$phase');
      }
    });

    test('a known update opens the native install dialog', () {
      expect(presentsNativeUpdateDialog(UpdatePhase.available), isTrue);
      expect(presentsNativeUpdateDialog(UpdatePhase.readyToInstall), isTrue);
    });
  });
}
