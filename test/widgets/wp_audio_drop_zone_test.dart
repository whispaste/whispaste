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
import 'package:whispaste/widgets/wp_banner.dart';

import '../test_helpers/pump_until.dart';

/// Records what the drop zone hands to the import queue.
class _RecordingQueue extends AudioImportQueueNotifier {
  final handed = <List<String>>[];

  @override
  List<ImportJob> build() => const [];

  @override
  Future<ImportEnqueueResult> addFiles(
    List<String> paths, {
    String? sliceManifestPath,
    ImportStartSource? source,
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
///
/// The file checks are real asynchronous I/O off the UI isolate; everything
/// after them is synchronous. Real event-loop turns alternate with pumps
/// until [handled] shows the drop's result, no fixed wait (#1491).
Future<void> _dropFiles(
  WidgetTester tester,
  List<String> files, {
  required bool Function() handled,
}) async {
  await _sendDrop('entered', [10.0, 10.0]);
  await _sendDrop('performOperation', files);
  await pumpUntil(tester, handled, what: 'the drop to be handled');
}

bool _rejectionShown() =>
    find.byKey(const ValueKey('audio-drop-rejected')).evaluate().isNotEmpty;

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

    await _dropFiles(tester, [a, b], handled: () => queue.handed.isNotEmpty);
    await tester.pump();

    expect(queue.handed, [
      [a, b],
    ]);
    expect(container.read(activePageProvider), 'history');
  });

  testWidgets('rejects folders and unsupported files without queueing them', (
    tester,
  ) async {
    await pumpZone(tester);
    container.read(activePageProvider.notifier).setPage('notes');
    final folder = Directory(p.join(dir.path, 'recordings.mp3'))..createSync();
    final text = file('notes.txt');

    await _dropFiles(tester, [folder.path, text], handled: _rejectionShown);
    await tester.pump();

    expect(queue.handed, isEmpty);
    expect(container.read(activePageProvider), 'notes');
    final notice = find.byKey(const ValueKey('audio-drop-rejected'));
    expect(notice, findsOneWidget);
    final message = tester.widget<WpBanner>(notice).message;
    expect(message, contains('recordings.mp3'));
    expect(message, contains('notes.txt'));
  });

  testWidgets('a rejection stays until closed or a clean drop follows', (
    tester,
  ) async {
    const notice = ValueKey('audio-drop-rejected');
    await pumpZone(tester);
    final text = file('notes.txt');

    await _dropFiles(tester, [text], handled: _rejectionShown);
    await tester.pump(const Duration(minutes: 5));
    expect(find.byKey(notice), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('audio-drop-rejected-dismiss')));
    await tester.pump();
    expect(find.byKey(notice), findsNothing);

    await _dropFiles(tester, [text], handled: _rejectionShown);
    await tester.pump();
    expect(find.byKey(notice), findsOneWidget);

    await _dropFiles(tester, [
      file('talk.mp3'),
    ], handled: () => queue.handed.isNotEmpty);
    await tester.pump();
    expect(find.byKey(notice), findsNothing);
  });

  testWidgets('mixed drop queues only the supported files', (tester) async {
    await pumpZone(tester);
    final ok = file('talk.mp3');
    final text = file('notes.txt');

    await _dropFiles(tester, [
      text,
      ok,
    ], handled: () => queue.handed.isNotEmpty);
    await tester.pump();

    expect(queue.handed, [
      [ok],
    ]);
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
