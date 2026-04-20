import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/update_service.dart';

void main() {
  group('UpdateNotifier.parseSemver', () {
    test('parses standard X.Y.Z', () {
      expect(UpdateNotifier.parseSemver('1.2.3'), [1, 2, 3]);
    });

    test('strips leading v', () {
      expect(UpdateNotifier.parseSemver('v1.2.3'), [1, 2, 3]);
    });

    test('strips pre-release suffix', () {
      expect(UpdateNotifier.parseSemver('1.2.3-beta.1'), [1, 2, 3]);
    });

    test('strips build metadata', () {
      expect(UpdateNotifier.parseSemver('1.2.3+4'), [1, 2, 3]);
    });

    test('strips pre-release AND build metadata', () {
      expect(UpdateNotifier.parseSemver('v1.2.3-beta.1+42'), [1, 2, 3]);
    });

    test('returns null for too few segments', () {
      expect(UpdateNotifier.parseSemver('1.2'), isNull);
    });

    test('returns null for non-numeric', () {
      expect(UpdateNotifier.parseSemver('abc.def.ghi'), isNull);
    });

    test('returns null for empty string', () {
      expect(UpdateNotifier.parseSemver(''), isNull);
    });
  });

  group('UpdateNotifier.isNewer', () {
    test('higher major is newer', () {
      expect(UpdateNotifier.isNewer('2.0.0', '1.9.9'), isTrue);
    });

    test('higher minor is newer', () {
      expect(UpdateNotifier.isNewer('1.3.0', '1.2.9'), isTrue);
    });

    test('higher patch is newer', () {
      expect(UpdateNotifier.isNewer('1.2.4', '1.2.3'), isTrue);
    });

    test('equal versions are not newer', () {
      expect(UpdateNotifier.isNewer('1.2.3', '1.2.3'), isFalse);
    });

    test('lower version is not newer', () {
      expect(UpdateNotifier.isNewer('1.2.2', '1.2.3'), isFalse);
    });

    test('handles v prefix on candidate', () {
      expect(UpdateNotifier.isNewer('v1.3.0', '1.2.0'), isTrue);
    });

    test('handles v prefix on both', () {
      expect(UpdateNotifier.isNewer('v2.0.0', 'v1.0.0'), isTrue);
    });

    test('handles build metadata', () {
      expect(UpdateNotifier.isNewer('1.3.0+5', '1.2.0+3'), isTrue);
    });

    test('same version with different build metadata is NOT newer', () {
      expect(UpdateNotifier.isNewer('1.2.0+5', '1.2.0+3'), isFalse);
    });

    test('returns false for invalid candidate', () {
      expect(UpdateNotifier.isNewer('bad', '1.2.3'), isFalse);
    });

    test('returns false for invalid current', () {
      expect(UpdateNotifier.isNewer('1.2.3', 'bad'), isFalse);
    });
  });

  group('UpdateState', () {
    test('default state is idle', () {
      const state = UpdateState();
      expect(state.phase, UpdatePhase.idle);
      expect(state.latestVersion, isNull);
      expect(state.downloadUrl, isNull);
      expect(state.releaseNotesUrl, isNull);
      expect(state.downloadedPath, isNull);
      expect(state.progressPercent, 0);
      expect(state.errorMessage, isNull);
    });

    test('isBusy is true for checking', () {
      const state = UpdateState(phase: UpdatePhase.checking);
      expect(state.isBusy, isTrue);
    });

    test('isBusy is true for downloading', () {
      const state = UpdateState(phase: UpdatePhase.downloading);
      expect(state.isBusy, isTrue);
    });

    test('isBusy is false for idle', () {
      const state = UpdateState(phase: UpdatePhase.idle);
      expect(state.isBusy, isFalse);
    });

    test('isBusy is false for available', () {
      const state = UpdateState(phase: UpdatePhase.available);
      expect(state.isBusy, isFalse);
    });

    test('isBusy is false for error', () {
      const state = UpdateState(phase: UpdatePhase.error);
      expect(state.isBusy, isFalse);
    });

    test('copyWith preserves fields', () {
      const original = UpdateState(
        phase: UpdatePhase.available,
        latestVersion: '2.0.0',
        downloadUrl: 'https://example.com/setup.exe',
        releaseNotesUrl: 'https://github.com/whispaste/whispaste/releases/tag/v2.0.0',
      );
      final updated = original.copyWith(phase: UpdatePhase.downloading);
      expect(updated.phase, UpdatePhase.downloading);
      expect(updated.latestVersion, '2.0.0');
      expect(updated.downloadUrl, 'https://example.com/setup.exe');
    });
  });

  group('DeployChannel', () {
    test('deploy channel override works for testing', () {
      deployChannelOverride = DeployChannel.installer;
      expect(detectDeployChannel(), DeployChannel.installer);

      deployChannelOverride = DeployChannel.store;
      expect(detectDeployChannel(), DeployChannel.store);

      deployChannelOverride = DeployChannel.portable;
      expect(detectDeployChannel(), DeployChannel.portable);

      deployChannelOverride = null; // reset
    });
  });
}
