/// Regression test for the "rate button always opens GitHub, even on the
/// Mac App Store build" bug: the "Bewerten" button used to hardcode
/// `Platform.isWindows ? Windows-Store-URL : GitHub`, so a macOS Mac App
/// Store install fell into the GitHub branch instead of opening the Mac App
/// Store review sheet.
///
/// These tests run on the real host platform (macOS in this repo's CI/dev
/// environment, matching the reported bug) — there is no platform-override
/// test seam in [ReviewSupportSection] itself, so the `DeployChannel.store`
/// case here exercises the actual `Platform.isMacOS` branch.
library;

import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/app_urls.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/sections/review_support_section.dart';
import 'package:whispaste/services/deploy_channel_service.dart';

import '../../../fixtures/test_helpers.dart';

const _launcherChannel = MethodChannel('plugins.flutter.io/url_launcher');

void main() {
  late L10n l10n;
  late String? capturedUrl;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  setUp(() {
    capturedUrl = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_launcherChannel, (call) async {
          if (call.method == 'canLaunch' || call.method == 'launch') {
            capturedUrl = (call.arguments as Map)['url'] as String?;
          }
          return true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_launcherChannel, null);
  });

  testWidgets(
    'store channel opens the Mac App Store review URL on macOS, not GitHub',
    skip: !io.Platform.isMacOS,
    (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const ReviewSupportSection(),
          locale: const Locale('en'),
          overrides: [
            deployChannelProvider.overrideWith((ref) => DeployChannel.store),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.reviewSupportAction));
      await tester.pumpAndSettle();

      expect(capturedUrl, kMacAppStoreReviewUrl);
      expect(capturedUrl, isNot(kGitHubRepoUrl));
    },
  );

  testWidgets('portable channel falls back to GitHub (no store listing)', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(
        const ReviewSupportSection(),
        locale: const Locale('en'),
        overrides: [
          deployChannelProvider.overrideWith((ref) => DeployChannel.portable),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.reviewSupportAction));
    await tester.pumpAndSettle();

    expect(capturedUrl, kGitHubRepoUrl);
  });
}
