/// The tray panel and side panel engines are booted once per app session,
/// so a language change in the main window must reach them on their next
/// open, not only after a restart (#1682, same mechanism as the snippet
/// picker in #1680). Hand-off point: the locale mirror the main engine
/// writes → the locale each panel engine paints with when the native shell
/// relays the next open. Negative control: a relay that is not an open
/// (a content refresh, a close) leaves the language alone.
/// Behaviour only: checks the resolved locale, no UI texts.
library;

import 'dart:io';

import 'package:flutter/material.dart' show Localizations, MaterialApp;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/persisted_locale.dart';
import 'package:whispaste/core/theme/persisted_appearance.dart';
import 'package:whispaste/services/side_panel/side_panel_snapshot.dart';
import 'package:whispaste/services/tray_panel/tray_panel_protocol.dart';
import 'package:whispaste/side_panel_render_entrypoint.dart';
import 'package:whispaste/tray_panel_render_entrypoint.dart';

const _trayChannel = 'com.whispaste.tray_panel_render';
const _sideChannel = 'com.whispaste.side_panel_render';

/// Answers the engine's own outgoing calls (`ready`, `resize`, ...).
void _mockOutgoing(WidgetTester tester, String channel) {
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(MethodChannel(channel), (_) async => null);
  addTearDown(
    () => messenger.setMockMethodCallHandler(MethodChannel(channel), null),
  );
}

/// Delivers [method] from the native shell to the engine.
Future<void> _relay(
  WidgetTester tester,
  String channel,
  String method,
  Object? args,
) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    channel,
    const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
    (_) {},
  );
  await tester.pumpAndSettle();
}

Future<void> _trayContent(WidgetTester tester, {required bool shown}) =>
    _relay(tester, _trayChannel, 'setContent', {
      ...const TrayPanelContent(
        phase: TrayPanelPhase.ready,
        statusLabel: 'Ready',
        primaryLabel: 'Dictate',
        shortcut: '',
        openApp: TrayPanelEntry(id: 'open', label: 'Open'),
        settings: TrayPanelEntry(id: 'settings', label: 'Settings'),
      ).toMap(),
      'shown': shown,
    });

Future<void> _sideSnapshot(WidgetTester tester, {required bool visible}) =>
    _relay(
      tester,
      _sideChannel,
      'updateSnapshot',
      SidePanelSnapshot(visible: visible).toMap(),
    );

String? _trayLocale(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp)).locale?.languageCode;

String _sideLocale(WidgetTester tester) => tester
    .widget<Localizations>(find.byType(Localizations).first)
    .locale
    .languageCode;

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('wp_panel_locale');
    localeMirrorPathOverride = '${dir.path}/locale';
    appearanceMirrorPathOverride = '${dir.path}/appearance';
  });

  tearDown(() {
    localeMirrorPathOverride = null;
    appearanceMirrorPathOverride = null;
    dir.deleteSync(recursive: true);
  });

  testWidgets('tray panel: a language change reaches it on the next open', (
    tester,
  ) async {
    _mockOutgoing(tester, _trayChannel);
    writeLocaleMirror('en');
    await tester.pumpWidget(const TrayPanelRenderApp());
    await _trayContent(tester, shown: true);
    expect(_trayLocale(tester), 'en');

    // The user switches the app language; the engine stays alive.
    writeLocaleMirror('de');

    // Negative control: a content refresh of the panel already open is not
    // an open, so the language stays.
    await _trayContent(tester, shown: false);
    expect(_trayLocale(tester), 'en');

    await _trayContent(tester, shown: true);
    expect(_trayLocale(tester), 'de');
  });

  testWidgets('side panel: a language change reaches it on the next open', (
    tester,
  ) async {
    _mockOutgoing(tester, _sideChannel);
    writeLocaleMirror('en');
    await tester.pumpWidget(const SidePanelRenderApp());
    await _sideSnapshot(tester, visible: true);
    expect(_sideLocale(tester), 'en');

    writeLocaleMirror('de');

    // Negative control: the hidden snapshot a close sends is not an open.
    await _sideSnapshot(tester, visible: false);
    expect(_sideLocale(tester), 'en');

    await _sideSnapshot(tester, visible: true);
    expect(_sideLocale(tester), 'de');
  });
}
