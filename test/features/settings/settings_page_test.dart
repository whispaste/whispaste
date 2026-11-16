import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/settings/settings_areas.dart';
import 'package:whispaste/features/settings/sections/overlay_button_section.dart';
import 'package:whispaste/features/settings/sections/updates_section.dart';
import 'package:whispaste/features/settings/settings_page.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/floating_button/floating_button_support.dart';
import 'package:whispaste/services/floating_button/floating_button_support_provider.dart';

import '../../fixtures/test_helpers.dart';
import 'settings_area_fixture.dart';
import '../../fixtures/record_device_listing_stub.dart';

void main() {
  stubRecordDeviceListing();

  group('SettingsPage', () {
    testWidgets('renders without error', (tester) async {
      await tester.pumpWidget(
        makeTestable(const SettingsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    group('Floating Button section — platform gating', () {
      testWidgets('is present on Linux, so the Linux button is reachable '
          '(PAR-010)', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;

        await tester.pumpWidget(
          makeTestable(
            const SettingsPage(),
            locale: const Locale('en'),
            overrides: [
              settingsAreaAt(SettingsArea.appearance),
              floatingButtonSupportProvider.overrideWith(
                (ref) async => FloatingButtonSupport.full,
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(FloatingButtonSection), findsOneWidget);

        debugDefaultTargetPlatformOverride = null;
      });

      testWidgets('is present on Windows', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;

        await tester.pumpWidget(
          makeTestable(
            const SettingsPage(),
            locale: const Locale('en'),
            overrides: [settingsAreaAt(SettingsArea.appearance)],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(FloatingButtonSection), findsOneWidget);

        debugDefaultTargetPlatformOverride = null;
      });
    });

    group('Updates section — deploy-channel gating', () {
      // ticket: store builds keep the section with its rows disabled and the
      // reason shown (AR-19). Only package-managed installs drop it.
      testWidgets('stays on the store deploy channel, with disabled rows', (
        tester,
      ) async {
        await tester.pumpWidget(
          makeTestable(
            const SettingsPage(),
            locale: const Locale('en'),
            overrides: [
              deployChannelProvider.overrideWith((ref) => DeployChannel.store),
              settingsAreaAt(SettingsArea.general),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(UpdatesSection), findsOneWidget);
      });

      testWidgets('is absent on package-managed installs', (tester) async {
        await tester.pumpWidget(
          makeTestable(
            const SettingsPage(),
            locale: const Locale('en'),
            overrides: [
              deployChannelProvider.overrideWith(
                (ref) => DeployChannel.packageManaged,
              ),
              settingsAreaAt(SettingsArea.general),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(UpdatesSection), findsNothing);
      });

      testWidgets('is present on the portable deploy channel', (tester) async {
        await tester.pumpWidget(
          makeTestable(
            const SettingsPage(),
            locale: const Locale('en'),
            overrides: [
              deployChannelProvider.overrideWith(
                (ref) => DeployChannel.portable,
              ),
              settingsAreaAt(SettingsArea.general),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(UpdatesSection), findsOneWidget);
      });
    });
  });
}
