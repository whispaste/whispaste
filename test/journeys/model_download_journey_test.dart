/// Download recovery journey: real transport, verification,
/// disk and error actions; only the public host and file manager are replaced.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/download_error_kind.dart';
import 'package:whispaste/services/http_model_fetcher.dart';
import 'package:whispaste/services/model_install_check.dart';
import 'package:whispaste/widgets/wp_model_download_error_notice.dart';

class _PublicHosts implements HttpClientAdapter {
  final requests = <String>[];
  final bytes = List<int>.generate(64, (i) => i);
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options.uri.host);
    if (options.uri.host == 'huggingface.co') {
      return ResponseBody.fromString('Unavailable', 503);
    }
    return ResponseBody(
      Stream.value(Uint8List.fromList(bytes)),
      200,
      headers: {
        'content-length': ['64'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  testWidgets(
    'retry survives first public source outage and opens model folder',
    (tester) async {
      // Real file I/O never completes inside the fake-async test zone.
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('download_journey_'),
      ))!;
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/model.bin';
      final hosts = _PublicHosts();
      final fetcher = HttpModelFetcher(
        dio: Dio()..httpClientAdapter = hosts,
        retryBackoff: const [],
      );
      final complete = Completer<void>();
      String? opened;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: WpModelDownloadErrorNotice(
              message: 'HTTP 503',
              kind: DownloadErrorKind.network,
              folder: () => dir.path,
              testIdPrefix: 'journey',
              openFolder: (folder) async {
                opened = folder;
                return true;
              },
              onRetry: () async {
                try {
                  await fetcher.fetchVerified(
                    sources: const [
                      'https://huggingface.co/model.bin',
                      'https://github.com/model.bin',
                    ],
                    destPath: path,
                    expectedSize: hosts.bytes.length,
                    expectedSha256: sha256.convert(hosts.bytes).toString(),
                  );
                  complete.complete();
                } catch (error, stack) {
                  complete.completeError(error, stack);
                }
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open model folder'));
      expect(opened, dir.path);
      await tester.runAsync(() async {
        // Tapped in the real zone so the download's I/O and timers run.
        await tester.tap(find.text('Try again'));
        // The completer belongs to the fake zone; poll it from the real one.
        // A zero wait yields to the event loop, so the download's I/O runs.
        while (!complete.isCompleted) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(await fileHasPinnedSize(path, 64), isTrue);
        expect(await File(path).readAsBytes(), hosts.bytes);
      });
      await complete.future;
      expect(hosts.requests, ['huggingface.co', 'github.com']);
      expect(
        (await tester.runAsync(() => File('$path.tmp').exists()))!,
        isFalse,
      );
      // A later session reuses the verified installation without a request.
      await tester.runAsync(() async {
        await HttpModelFetcher(
          dio: Dio()..httpClientAdapter = hosts,
        ).fetchVerified(
          sources: const ['https://huggingface.co/model.bin'],
          destPath: path,
          expectedSize: 64,
          expectedSha256: sha256.convert(hosts.bytes).toString(),
        );
      });
      expect(hosts.requests, hasLength(2));
    },
  );
}
