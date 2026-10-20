// XP-5-06: the failed-paste notification on Linux leads to the Auto-Paste
// settings, so the capability card there has to show the one-time uinput
// setup instead of the macOS permission flow.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/onboarding/steps/auto_paste_step.dart'
    show debugLinuxPackageFormatOverride;
import 'package:whispaste/services/desktop_paste/linux_desktop_paste_controller.dart';
import 'package:whispaste/services/desktop_paste/linux_package_format.dart';
import 'package:whispaste/services/paste/paste_capability_notifier.dart';
import 'package:whispaste/services/paste/paster.dart';
import 'package:whispaste/widgets/paste_capability_indicator.dart';

import '../fixtures/test_helpers.dart';

class _FakeCapability extends PasteCapabilityNotifier {
  _FakeCapability(this._status);
  final PasteCapabilityStatus _status;

  @override
  PasteCapabilityState build() =>
      PasteCapabilityState(capability: PasteCapability(status: _status));

  @override
  Future<void> check({bool prompt = false}) async {}
}

void main() {
  final en = lookupL10n(const Locale('en'));
  final copied = <String>[];

  setUp(() {
    copied.clear();
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
  });

  tearDown(() {
    debugLinuxPackageFormatOverride = null;
  });

  Future<void> pump(WidgetTester tester, PasteCapabilityStatus status) async {
    await tester.pumpWidget(
      makeTestable(
        const SingleChildScrollView(child: WpPasteCapabilityIndicator()),
        overrides: [
          pasteCapabilityNotifierProvider.overrideWith(
            () => _FakeCapability(status),
          ),
        ],
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
  }

  const copyButton = ValueKey('settings-paste-linux-copy-command');
  final linux = TargetPlatformVariant.only(TargetPlatform.linux);

  testWidgets('missing uinput access shows the hint and copies the command', (
    tester,
  ) async {
    debugLinuxPackageFormatOverride = LinuxPackageFormat.native;
    await pump(tester, PasteCapabilityStatus.permissionMissing);

    expect(find.text(en.pasteFailureLinuxUinputHint), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-paste-grant-button')),
      findsNothing,
    );
    // The sudo command is shown before it is copied (XP-6-04).
    final command = tester.widget<SelectableText>(
      find.byKey(const ValueKey('settings-paste-linux-command')),
    );
    expect(command.data, kLinuxUinputUdevCommand);

    await tester.tap(find.byKey(copyButton));
    await tester.pumpAndSettle();
    expect(copied, [kLinuxUinputUdevCommand]);
    expect(find.text(en.historyCopiedToClipboard), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }, variant: linux);

  testWidgets('the snap build copies the interface connect command', (
    tester,
  ) async {
    debugLinuxPackageFormatOverride = LinuxPackageFormat.snap;
    await pump(tester, PasteCapabilityStatus.permissionMissing);

    expect(
      tester
          .widget<SelectableText>(
            find.byKey(const ValueKey('settings-paste-linux-command')),
          )
          .data,
      kSnapUinputConnectCommand,
    );
    await tester.tap(find.byKey(copyButton));
    await tester.pumpAndSettle();
    expect(copied, [kSnapUinputConnectCommand]);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }, variant: linux);

  testWidgets('no setup offered once Auto-Paste works', (tester) async {
    await pump(tester, PasteCapabilityStatus.ready);

    expect(find.byKey(copyButton), findsNothing);
    expect(find.text(en.pasteFailureLinuxUinputHint), findsNothing);
  }, variant: linux);
}
