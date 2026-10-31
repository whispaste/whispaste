import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/services/audio/import/audio_import_providers.dart';
import 'package:whispaste/services/audio/import/audio_import_queue.dart';
import 'package:whispaste/widgets/wp_audio_drop_zone.dart';

/// Records what the drop zone hands to the import queue.
class _RecordingQueue extends AudioImportQueueNotifier {
  final handed = <List<String>>[];

  @override
  List<ImportJob> build() => const [];

  @override
  Future<ImportEnqueueResult> addFiles(
    List<String> paths, {
    String? sliceManifestPath,
  }) async {
    handed.add(List.of(paths));
    return const ImportEnqueueResult(rejections: [], jobIds: []);
  }
}

/// Sends a drop event through the same channel desktop_drop uses natively.
Future<void> _sendDrop(String method, Object? arguments) async {
  final data = const StandardMethodCodec().encodeMethodCall(
    MethodCall(method, arguments),
  );
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage('desktop_drop', data, (_) {});
}

/// Drops [files] onto the zone. The plugin only reports a drop after the
/// pointer has entered the zone, so the enter event comes first.
Future<void> _dropFiles(WidgetTester tester, List<String> files) async {
  await _sendDrop('entered', [10.0, 10.0]);
  await _sendDrop('performOperation', files);
  // The file checks are real asynchronous I/O, and each await in the drop
  // handler resumes only after the fake clock is pumped again. Alternate real
  // delays with pumps so every step of the handler gets to run.
  for (var i = 0; i < 60; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
}

/// Lets the rejection toast's timer and exit animation finish, so no ticker
/// is still active when the test tree is torn down.
Future<void> _settleToasts(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 10));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late _RecordingQueue queue;
  late ProviderContainer container;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('wp-drop-widget-');
    queue = _RecordingQueue();
    container = ProviderContainer(
      overrides: [audioImportQueueProvider.overrideWith(() => queue)],
    );
  });

  tearDown(() {
    container.dispose();
    dir.deleteSync(recursive: true);
  });

  String file(String name) {
    final f = File(p.join(dir.path, name))..writeAsBytesSync(const [0]);
    return f.path;
  }

  Future<void> pumpZone(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: wpDarkTheme(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: const Scaffold(
            body: WpAudioDropZone(
              child: Center(
                key: ValueKey('drop-test-content'),
                child: Text('page'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('shows the localized hint while audio hovers over the window', (
    tester,
  ) async {
    await pumpZone(tester);
    expect(find.byKey(const ValueKey('audio-drop-overlay')), findsNothing);

    await _sendDrop('entered', [0.0, 0.0]);
    await tester.pump();

    expect(find.byKey(const ValueKey('audio-drop-overlay')), findsOneWidget);
    expect(
      find.text(L10n.of(tester.element(find.byType(Scaffold))).audioDropHint),
      findsOneWidget,
    );

    await _sendDrop('exited', null);
    await tester.pump();
    expect(find.byKey(const ValueKey('audio-drop-overlay')), findsNothing);
  });

  testWidgets('hands several supported files to the queue and opens history', (
    tester,
  ) async {
    await pumpZone(tester);
    final a = file('memo.m4a');
    final b = file('call.opus');

    await _dropFiles(tester, [a, b]);
    await tester.pump();

    expect(queue.handed, [
      [a, b],
    ]);
    expect(container.read(activePageProvider), 'history');
    await _settleToasts(tester);
  });

  testWidgets('rejects folders and unsupported files without queueing them', (
    tester,
  ) async {
    await pumpZone(tester);
    container.read(activePageProvider.notifier).setPage('notes');
    final folder = Directory(p.join(dir.path, 'recordings.mp3'))..createSync();
    final text = file('notes.txt');

    await _dropFiles(tester, [folder.path, text]);
    await tester.pump();

    expect(queue.handed, isEmpty);
    expect(container.read(activePageProvider), 'notes');
    final l10n = L10n.of(tester.element(find.byType(Scaffold)));
    expect(
      find.text(l10n.audioDropRejectedFolder('recordings.mp3')),
      findsOneWidget,
    );
    expect(
      find.textContaining('notes.txt', findRichText: true),
      findsOneWidget,
    );
    await _settleToasts(tester);
  });

  testWidgets('mixed drop queues only the supported files', (tester) async {
    await pumpZone(tester);
    final ok = file('talk.mp3');
    final text = file('notes.txt');

    await _dropFiles(tester, [text, ok]);
    await tester.pump();

    expect(queue.handed, [
      [ok],
    ]);
    await _settleToasts(tester);
  });

  testWidgets('the window below keeps receiving taps under the overlay', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: wpDarkTheme(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: WpAudioDropZone(
              child: Center(
                child: TextButton(
                  key: const ValueKey('drop-test-button'),
                  onPressed: () => taps++,
                  child: const Text('tap'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await _sendDrop('entered', [0.0, 0.0]);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('drop-test-button')));
    expect(taps, 1);
  });
}
