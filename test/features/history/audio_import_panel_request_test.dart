/// Wiring of the tray's "Transcribe file…" request into the import panel:
/// a request made before the panel is mounted is taken on mount, one made
/// while it is shown is taken by its listener, an expired request opens
/// nothing, a second request while the dialog is open opens no second
/// dialog (also after a remount), and a failed dialog releases the guard
/// and is reported in a toast.
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/history/widgets/audio_import_panel.dart';
import 'package:whispaste/services/audio/import/audio_import_providers.dart';
import 'package:whispaste/services/path_service.dart'
    show appDataDirOverride, retainedAudioDirOverride;

import '../../fixtures/test_helpers.dart';

const _fileSelectorChannel = MethodChannel('plugins.flutter.io/file_selector');

void main() {
  late Directory tmp;
  late DateTime now;
  late Completer<List<String>?> dialog;
  late int dialogCalls;
  late ValueNotifier<bool> shown;
  // Answers each dialog call; a test may swap it to fail the first one.
  late Future<Object?> Function() answerDialog;

  DateTime clock() => now;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('wp73-import-panel-');
    appDataDirOverride = '${tmp.path}/appdata';
    retainedAudioDirOverride = '${tmp.path}/retained';
    now = DateTime(2026, 10, 18, 12);
    dialog = Completer<List<String>?>();
    dialogCalls = 0;
    shown = ValueNotifier<bool>(false);
    answerDialog = () => dialog.future;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_fileSelectorChannel, (call) {
          if (call.method != 'openFile') return Future.value();
          dialogCalls++;
          // The dialog stays open until the test answers, as the real one does.
          return answerDialog();
        });
  });

  tearDown(() async {
    if (!dialog.isCompleted) dialog.complete(const []);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_fileSelectorChannel, null);
    appDataDirOverride = null;
    retainedAudioDirOverride = null;
    await tmp.delete(recursive: true);
  });

  /// Mounts the panel only once [shown] is set, inside one ProviderScope, so
  /// a request can be made before the panel exists and the state survives.
  Future<ProviderContainer> mountHost(WidgetTester tester) async {
    await tester.pumpWidget(
      makeTestable(
        ValueListenableBuilder<bool>(
          key: const ValueKey('wp73-host'),
          valueListenable: shown,
          builder: (_, on, _) =>
              on ? const AudioImportPanel() : const SizedBox.shrink(),
        ),
        db: HistoryDatabase.forTesting(NativeDatabase.memory()),
        locale: const Locale('en'),
        overrides: [audioImportClockProvider.overrideWithValue(clock)],
      ),
    );
    return ProviderScope.containerOf(
      tester.element(find.byKey(const ValueKey('wp73-host'))),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
  }

  /// Closes any open dialog first, so the picker releases its guard while the
  /// container is still alive. Then disposes the ProviderScope, which also
  /// cancels a pending request timer.
  Future<void> unmount(WidgetTester tester) async {
    if (!dialog.isCompleted) dialog.complete(const []);
    // The platform reply arrives on real event-loop turns, not fake ones.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await settle(tester);
    // Lets an error toast run out and finish its exit animation.
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
  }

  testWidgets('a request made before the panel is mounted opens the picker', (
    tester,
  ) async {
    final container = await mountHost(tester);
    container.read(audioImportPickRequestProvider.notifier).request();

    shown.value = true;
    await settle(tester);

    expect(dialogCalls, 1);
    await unmount(tester);
  });

  testWidgets('a request made while the panel is shown opens the picker', (
    tester,
  ) async {
    final container = await mountHost(tester);
    shown.value = true;
    await settle(tester);
    expect(dialogCalls, 0);

    container.read(audioImportPickRequestProvider.notifier).request();
    await settle(tester);

    expect(dialogCalls, 1);
    await unmount(tester);
  });

  testWidgets('a request older than 60 seconds opens nothing on mount', (
    tester,
  ) async {
    final container = await mountHost(tester);
    container.read(audioImportPickRequestProvider.notifier).request();
    now = now.add(const Duration(seconds: 61));

    shown.value = true;
    await settle(tester);

    expect(dialogCalls, 0);
    expect(container.read(audioImportPickRequestProvider), isNull);
    await unmount(tester);
  });

  testWidgets('a second request while the dialog is open opens no second '
      'dialog', (tester) async {
    final container = await mountHost(tester);
    shown.value = true;
    await settle(tester);
    final requests = container.read(audioImportPickRequestProvider.notifier);

    requests.request();
    await settle(tester);
    requests.request();
    await settle(tester);

    expect(dialogCalls, 1);
    await unmount(tester);
  });

  testWidgets('a remounted panel does not open a second dialog while one is '
      'open', (tester) async {
    final container = await mountHost(tester);
    shown.value = true;
    await settle(tester);
    container.read(audioImportPickRequestProvider.notifier).request();
    await settle(tester);
    expect(dialogCalls, 1);

    // The panel leaves and comes back while the dialog is still open.
    shown.value = false;
    await settle(tester);
    container.read(audioImportPickRequestProvider.notifier).request();
    shown.value = true;
    await settle(tester);

    expect(dialogCalls, 1);
    await unmount(tester);
  });

  testWidgets('a failing dialog says so instead of failing silently '
      '(UIA-HIS-30)', (tester) async {
    final container = await mountHost(tester);
    answerDialog = () async => throw PlatformException(code: 'dialog-failed');
    shown.value = true;
    await settle(tester);

    container.read(audioImportPickRequestProvider.notifier).request();
    await settle(tester);

    expect(
      find.text(
        'The file dialog could not be opened. Try again, or drag the files '
        'onto this page.',
      ),
      findsOneWidget,
    );
    await unmount(tester);
  });

  testWidgets('a failing dialog releases the guard, so the next request opens '
      'one again', (tester) async {
    final container = await mountHost(tester);
    answerDialog = () async => throw PlatformException(code: 'dialog-failed');
    shown.value = true;
    await settle(tester);
    final requests = container.read(audioImportPickRequestProvider.notifier);

    requests.request();
    await settle(tester);
    expect(dialogCalls, 1);

    answerDialog = () => dialog.future;
    requests.request();
    await settle(tester);

    expect(dialogCalls, 2);
    await unmount(tester);
  });
}
