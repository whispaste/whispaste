/// UX screenshot harness for the onboarding Auto-Paste step, which the screen
/// harness in `ux_screens_test.dart` cannot reach (it is an onboarding page,
/// not a settings page). Renders the step per platform and capability state,
/// window size, text scale and locale, on the dark golden palette. It asserts
/// nothing; it is a survey tool for the UX reviewer.
///
/// Tagged `ux-screens`, so the normal suite and CI skip it. Run on the Mac:
///
///   UX_SCREENS_DIR=OUT_DIR flutter test --tags=ux-screens generators/ux/ux_autopaste_test.dart
@Tags(<String>['ux-screens'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart' show loadAppFonts;
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/features/onboarding/steps/auto_paste_step.dart';
import 'package:whispaste/services/paste/paste_capability_notifier.dart';
import 'package:whispaste/services/paste/paster.dart';

import '../../test/features/settings/widgets/settings_golden_board.dart'
    show kSettingsGoldenSets;
import '../../test/fixtures/test_helpers.dart';
import '../../test/ux_audit/ux_fixtures.dart' show kUxCaptureKey;

/// Serves one fixed capability state and never polls.
class _FixedPasteCapabilityNotifier extends PasteCapabilityNotifier {
  _FixedPasteCapabilityNotifier(this._state);

  final PasteCapabilityState _state;

  @override
  PasteCapabilityState build() => _state;

  @override
  void startPolling({
    Duration interval = const Duration(seconds: 1),
    Duration timeout = const Duration(seconds: 30),
  }) {}

  @override
  void stopPolling() {}
}

class _StaticSettings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;
}

/// Capability states that reach distinct branches of the step.
const _states = <String, (TargetPlatform, PasteCapabilityState)>{
  'mac-grant': (
    TargetPlatform.macOS,
    PasteCapabilityState(
      capability: PasteCapability(
        status: PasteCapabilityStatus.permissionMissing,
        canPrompt: true,
      ),
    ),
  ),
  'win-ready': (
    TargetPlatform.windows,
    PasteCapabilityState(
      capability: PasteCapability(status: PasteCapabilityStatus.ready),
    ),
  ),
  'linux-uinput-setup': (
    TargetPlatform.linux,
    PasteCapabilityState(
      capability: PasteCapability(
        status: PasteCapabilityStatus.permissionMissing,
      ),
    ),
  ),
  'linux-unavailable': (
    TargetPlatform.linux,
    PasteCapabilityState(
      capability: PasteCapability(status: PasteCapabilityStatus.unsupported),
    ),
  ),
};

void main() {
  setUpAll(() async => loadAppFonts());

  final outDir =
      Platform.environment['UX_SCREENS_DIR'] ?? 'internal-notes';
  const sizes = <Size>[Size(800, 716), Size(1100, 720)];
  const scales = <double>[1.0, 2.0];
  const locales = <String>['de', 'he'];

  for (final entry in _states.entries) {
    final (platform, state) = entry.value;
    for (final size in sizes) {
      for (final scale in scales) {
        for (final locale in locales) {
          final name =
              'autopaste-${entry.key}__${size.width.toInt()}x'
              '${size.height.toInt()}__s${scale.toString()}__dark_$locale';
          testWidgets('ux-autopaste: $name', (tester) async {
            final set = kSettingsGoldenSets['dark']!;
            WpColors.activate(set);
            debugDefaultTargetPlatformOverride = platform;
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            await tester.pumpWidget(
              makeTestable(
                Theme(
                  data: wpThemeFor(set),
                  child: Builder(
                    builder: (context) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.linear(scale)),
                      child: RepaintBoundary(
                        key: const ValueKey(kUxCaptureKey),
                        child: ColoredBox(
                          color: set.background,
                          child: SizedBox.expand(
                            child: SingleChildScrollView(
                              child: SizedBox(
                                width: size.width,
                                child: const AutoPasteStep(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                size: size,
                locale: Locale(locale),
                overrides: [
                  pasteCapabilityNotifierProvider.overrideWith(
                    () => _FixedPasteCapabilityNotifier(state),
                  ),
                  settingsProvider.overrideWith(_StaticSettings.new),
                ],
              ),
            );
            await tester.pump(const Duration(milliseconds: 300));

            final error = tester.takeException();
            debugDefaultTargetPlatformOverride = null;
            if (error != null) {
              Directory(outDir).createSync(recursive: true);
              File(
                '$outDir/exceptions.log',
              ).writeAsStringSync('$name: $error\n', mode: FileMode.append);
            }

            await tester.runAsync(() async {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(const ValueKey(kUxCaptureKey)),
              );
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              Directory(outDir).createSync(recursive: true);
              File(
                '$outDir/$name.png',
              ).writeAsBytesSync(bytes!.buffer.asUint8List());
            });

            await tester.pumpWidget(const SizedBox());
            await tester.pump(const Duration(seconds: 5));
          });
        }
      }
    }
  }
}
