import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_sections.dart';

/// Anchors that `SttProviderType.onDevice` is not gated or excluded in Mac
/// App Store (MAS) builds.
///
/// Context: after the FFI-engine migration (see
/// `.scratch/whisper-ffi-engine/`), the onDevice provider no longer shells
/// out to a subprocess/HTTP server, so nothing about it is
/// sandbox-unclean anymore. `kIsMasBuild` (`lib/core/config/build_config.dart`)
/// legitimately gates three unrelated concerns — simulated-keystroke
/// Auto-Paste, deploy-channel/self-updater detection
/// (`deploy_channel_service.dart`, since a MAS build is definitionally
/// store-distributed), and the `shellCommand` automation action type
/// (dictation-automations ticket 03: shell execution is impossible inside
/// the App Sandbox) — but it must never grow a branch that excludes or
/// defaults away from the onDevice STT provider. These tests fail loudly if
/// that changes.
void main() {
  group('MAS build gating — onDevice STT provider', () {
    test('onDevice is the default persisted provider', () {
      expect(SttSettings.defaults.provider, SttProviderType.onDevice.value);
      expect(
        SttProviderType.fromValue(SttSettings.defaults.provider),
        SttProviderType.onDevice,
      );
    });

    test('onDevice remains a selectable SttProviderType value', () {
      expect(SttProviderType.values, contains(SttProviderType.onDevice));
    });

    test('unknown/empty persisted provider values fall back to onDevice', () {
      // fromValue's documented fallback — exercised here so a future
      // change that special-cases MAS builds away from onDevice would
      // break this expectation.
      expect(SttProviderType.fromValue(null), SttProviderType.onDevice);
      expect(SttProviderType.fromValue(''), SttProviderType.onDevice);
      expect(
        SttProviderType.fromValue('does-not-exist'),
        SttProviderType.onDevice,
      );
    });

    test('no source file outside the Auto-Paste allowlist references the '
        'MAS build flag (kIsMasBuild/MAS_BUILD/WHISPASTE_MAS)', () {
      // These files legitimately branch on the MAS flag — for
      // simulated-keystroke Auto-Paste (App Review Guideline 2.4.5 /
      // App Sandbox) or deploy-channel/self-updater detection — never for
      // STT provider selection.
      const allowedFiles = <String>{
        'lib/core/config/build_config.dart',
        'lib/features/settings/sections/feedback_section.dart',
        'lib/features/onboarding/onboarding_overlay.dart',
        'lib/services/paste/paste_policy.dart',
        'lib/services/desktop_paste/desktop_paste_controller.dart',
        'lib/services/deploy_channel_service.dart',
        'lib/widgets/status_bar.dart',
        'lib/services/automation_dispatch_service.dart',
        'lib/features/automations/automations_page.dart',
      };

      final flagPattern = RegExp(r'\b(kIsMasBuild|MAS_BUILD|WHISPASTE_MAS)\b');

      final offenders = <String>[];
      final libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue, reason: 'lib/ must exist');

      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final relPath = entity.path.replaceAll(r'\', '/');
        final content = entity.readAsStringSync();
        if (!flagPattern.hasMatch(content)) continue;
        if (allowedFiles.contains(relPath)) continue;
        offenders.add(relPath);
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'Unexpected MAS-build-flag reference outside the Auto-Paste '
            'allowlist (possible new onDevice STT gating): '
            '${offenders.join(', ')}',
      );
    });
  });
}
