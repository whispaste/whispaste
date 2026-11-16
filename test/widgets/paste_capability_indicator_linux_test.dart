// XP-5-06: the failed-paste notification on Linux leads to the Auto-Paste
// settings, so the capability card there has to show the one-time uinput
// setup instead of the macOS permission flow.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/onboarding/steps/auto_paste_step.dart'
    show debugLinuxPackageFormatOverride;
import 'package:whispaste/services/desktop_paste/linux_desktop_paste_controller.dart';
import 'package:whispaste/services/desktop_paste/linux_package_format.dart';
import 'package:whispaste/services/desktop_paste/linux_uinput_access.dart';
import 'package:whispaste/services/paste/paste_capability_notifier.dart';
import 'package:whispaste/services/paste/paster.dart';
import 'package:whispaste/widgets/paste_capability_indicator.dart';

import '../fixtures/test_helpers.dart';

class _FakeCapability extends PasteCapabilityNotifier {
  _FakeCapability(this._status, [this._detail]);
  final PasteCapabilityStatus _status;
  final String? _detail;

  @override
  PasteCapabilityState build() => PasteCapabilityState(
    capability: PasteCapability(status: _status, detail: _detail),
  );

  int checks = 0;

  @override
  Future<void> check({bool prompt = false}) async => checks++;
}

/// A .deb install (helper and pkexec present) or, with [deb] false, any
/// other format. [ruleInstalled] answers `status`; every call is recorded.
LinuxUinputAccess _access({
  bool deb = false,
  bool ruleInstalled = false,
  int pkexecExit = 0,
  List<List<String>>? calls,
}) => LinuxUinputAccess(
  exists: (path) =>
      deb || (path == LinuxUinputAccess.rulePath && ruleInstalled),
  run: (exe, args) async {
    calls?.add([exe, ...args]);
    final status = args.last == 'status';
    return ProcessResult(
      0,
      status ? (ruleInstalled ? 0 : 1) : pkexecExit,
      '',
      '',
    );
  },
);

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

  late _FakeCapability capability;

  Future<void> pump(
    WidgetTester tester,
    PasteCapabilityStatus status, {
    LinuxUinputAccess? access,
    String? detail,
  }) async {
    await tester.pumpWidget(
      makeTestable(
        const SingleChildScrollView(child: WpPasteCapabilityIndicator()),
        overrides: [
          pasteCapabilityNotifierProvider.overrideWith(
            () => capability = _FakeCapability(status, detail),
          ),
          linuxUinputAccessProvider.overrideWithValue(access ?? _access()),
        ],
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
  }

  const copyButton = ValueKey('settings-paste-linux-copy-command');
  final linux = TargetPlatformVariant.only(TargetPlatform.linux);

  const removeCopyButton = ValueKey('settings-paste-linux-revoke-copy-command');

  testWidgets('an AppImage with the rule copies the remove command', (
    tester,
  ) async {
    debugLinuxPackageFormatOverride = LinuxPackageFormat.appimage;
    await pump(
      tester,
      PasteCapabilityStatus.ready,
      access: _access(ruleInstalled: true),
    );

    await tester.tap(find.byKey(removeCopyButton));
    await tester.pump();
    expect(copied, [kLinuxUinputRemoveCommand]);
    await tester.pumpAndSettle(const Duration(seconds: 3));
  }, variant: linux);

  testWidgets('no remove command where the app takes the access back itself', (
    tester,
  ) async {
    debugLinuxPackageFormatOverride = LinuxPackageFormat.native;
    await pump(
      tester,
      PasteCapabilityStatus.ready,
      access: _access(deb: true, ruleInstalled: true),
    );
    expect(find.byKey(removeCopyButton), findsNothing);
  }, variant: linux);

  testWidgets('no remove command for a portal grant', (tester) async {
    debugLinuxPackageFormatOverride = LinuxPackageFormat.flatpak;
    await pump(
      tester,
      PasteCapabilityStatus.ready,
      detail: kLinuxPortalCapabilityDetail,
    );
    expect(find.byKey(removeCopyButton), findsNothing);
  }, variant: linux);

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
    await tester.pump();
    await tester.pump();
    expect(copied, [kLinuxUinputUdevCommand]);
    expect(find.text(en.copyDone), findsOneWidget);
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

  const grantButton = ValueKey('settings-paste-linux-grant-button');
  const revokeButton = ValueKey('settings-paste-linux-revoke-button');

  testWidgets(
    'a .deb explains the access and grants it through pkexec (R-02)',
    (tester) async {
      final calls = <List<String>>[];
      await pump(
        tester,
        PasteCapabilityStatus.permissionMissing,
        access: _access(deb: true, calls: calls),
      );

      expect(find.text(en.linuxUinputConsentDetail), findsOneWidget);
      expect(find.byKey(copyButton), findsNothing);

      await tester.tap(find.byKey(grantButton));
      await tester.pumpAndSettle();

      expect(calls.last, [
        LinuxUinputAccess.pkexecPath,
        LinuxUinputAccess.helperPath,
        'enable',
      ]);
      expect(capability.checks, greaterThanOrEqualTo(2));
      expect(copied, isEmpty, reason: 'granting never touches the clipboard');
    },
    variant: linux,
  );

  testWidgets('a failed grant says so, a dismissed prompt stays quiet', (
    tester,
  ) async {
    await pump(
      tester,
      PasteCapabilityStatus.permissionMissing,
      access: _access(deb: true, pkexecExit: 1),
    );
    await tester.tap(find.byKey(grantButton));
    await tester.pumpAndSettle();
    expect(find.text(en.linuxUinputGrantFailed), findsOneWidget);
    // An error stays until it is closed.
    await tester.pump(const Duration(seconds: 10));
    expect(find.text(en.linuxUinputGrantFailed), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('page-notice-dismiss-settings')),
    );
    await tester.pumpAndSettle();

    await pump(
      tester,
      PasteCapabilityStatus.permissionMissing,
      access: _access(deb: true, pkexecExit: 126),
    );
    await tester.tap(find.byKey(grantButton));
    await tester.pumpAndSettle();
    expect(find.text(en.linuxUinputGrantFailed), findsNothing);
  }, variant: linux);

  testWidgets('a .deb with its rule installed offers to remove it', (
    tester,
  ) async {
    final calls = <List<String>>[];
    await pump(
      tester,
      PasteCapabilityStatus.ready,
      access: _access(deb: true, ruleInstalled: true, calls: calls),
    );

    await tester.tap(find.byKey(revokeButton));
    await tester.pumpAndSettle();

    expect(calls.last.last, 'disable');
    // The card shows the access is gone; no message repeats it.
    expect(find.byKey(revokeButton), findsNothing);
    expect(find.text(en.linuxUinputRevokeDone), findsNothing);
  }, variant: linux);

  testWidgets('no remove button when the access is not from our rule', (
    tester,
  ) async {
    await pump(tester, PasteCapabilityStatus.ready, access: _access(deb: true));

    expect(find.byKey(revokeButton), findsNothing);
  }, variant: linux);

  testWidgets('no removal card when ready without our rule', (tester) async {
    debugLinuxPackageFormatOverride = LinuxPackageFormat.appimage;
    await pump(tester, PasteCapabilityStatus.ready);

    // Access that is not ours (say the input group) has nothing to take
    // back; a ready card would otherwise show on every Linux install.
    expect(find.byKey(revokeButton), findsNothing);
    expect(find.text(en.pasteCapabilityReady), findsNothing);
  }, variant: linux);
}
