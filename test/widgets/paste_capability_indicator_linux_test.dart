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
  _FakeCapability(this._status);
  final PasteCapabilityStatus _status;

  @override
  PasteCapabilityState build() =>
      PasteCapabilityState(capability: PasteCapability(status: _status));

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
  exists: (_) => deb,
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
  }) async {
    await tester.pumpWidget(
      makeTestable(
        const SingleChildScrollView(child: WpPasteCapabilityIndicator()),
        overrides: [
          pasteCapabilityNotifierProvider.overrideWith(
            () => capability = _FakeCapability(status),
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
    await tester.pump(const Duration(seconds: 10));
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
    expect(find.text(en.linuxUinputRevokeDone), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  }, variant: linux);

  testWidgets('no remove button when the access is not from our rule', (
    tester,
  ) async {
    await pump(tester, PasteCapabilityStatus.ready, access: _access(deb: true));

    expect(find.byKey(revokeButton), findsNothing);
  }, variant: linux);

  testWidgets('other formats show no removal card when ready', (tester) async {
    debugLinuxPackageFormatOverride = LinuxPackageFormat.snap;
    await pump(tester, PasteCapabilityStatus.ready);

    // Only a .deb's own rule is offered back; a ready card would otherwise
    // show on every Linux install.
    expect(find.byKey(revokeButton), findsNothing);
    expect(find.text(en.pasteCapabilityReady), findsNothing);
  }, variant: linux);
}
