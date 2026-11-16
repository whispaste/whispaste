/// The running-app picker of the clipboard exclusion editor shows a loading
/// and an error state (issue #616); both are addressed by test id.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/features/settings/widgets/clipboard_exclusion_editor.dart';

import '../../../fixtures/test_helpers.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    state = AsyncData(updater(state.value ?? AppSettings.defaults));
  }
}

const _channel = MethodChannel('com.whispaste.clipboard_history');

Widget _pump() => makeTestable(
  const SingleChildScrollView(child: ClipboardExclusionEditor()),
  overrides: [settingsProvider.overrideWith(_FakeSettingsNotifier.new)],
);

void _mockChannel(Future<Object?>? Function(MethodCall) handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, handler);
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );
}

void _resetPlatform() => debugDefaultTargetPlatformOverride = null;

void _asMac() {
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
}

void main() {
  testWidgets('shows the loading state until the list arrives', (tester) async {
    _asMac();
    final gate = Completer<Object?>();
    _mockChannel((call) => gate.future);
    await tester.pumpWidget(_pump());
    await tester.pump();
    expect(
      find.byKey(const ValueKey('clipboard-exclusions-running-loading')),
      findsOneWidget,
    );
    gate.complete([
      {'id': 'org.example.app', 'name': 'Example'},
    ]);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('clipboard-exclusions-running-loading')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('clipboard-exclusions-pick-org-example-app')),
      findsOneWidget,
    );
    _resetPlatform();
  });

  testWidgets('shows the error state and retries', (tester) async {
    _asMac();
    var fail = true;
    _mockChannel((call) async {
      if (fail) throw PlatformException(code: 'boom');
      return [
        {'id': 'org.example.app', 'name': 'Example'},
      ];
    });
    await tester.pumpWidget(_pump());
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('clipboard-exclusions-running-error')),
      findsOneWidget,
    );
    fail = false;
    await tester.tap(
      find.byKey(const ValueKey('clipboard-exclusions-running-retry')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('clipboard-exclusions-running-error')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('clipboard-exclusions-pick-org-example-app')),
      findsOneWidget,
    );
    _resetPlatform();
  });
}
