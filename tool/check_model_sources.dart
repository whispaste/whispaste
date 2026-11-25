// Source guard for runtime model downloads.
//
// Checks every source in tool/model_sources.json against the live servers:
//   1. HEAD without following redirects. On Hugging Face the 302 carries
//      `x-linked-size` and `x-linked-etag` (the LFS SHA-256), so size and hash
//      are checked without a download.
//   2. GET `Range: bytes=0-0` with redirects followed: the CDN must answer 206
//      with `Content-Range: bytes 0-0/<size>`, which proves resume works and
//      the served object has the registry size.
//   3. Files up to --hash-limit bytes (default 20 MB) are downloaded and
//      hashed; --full hashes every file (several GB).
//
// A failure means a download in the app would fail closed (size or hash
// mismatch) or not start at all: catch it before a release, not from user
// reports (2026-11-07). Exit code 1 on any failure, 0 otherwise.
//
// Usage: dart run tool/check_model_sources.dart [--catalog-only] [--full] [--hash-limit=N]
//        [--manifest=tool/model_sources.json]
//
// --catalog-only reads the bundled catalog directly and excludes CUDA packs.
// Dedicated opt-in job: .internal forge/workflows/model-sources.yml.
// Runs in the lab's full suite (.internal forge/workflows/lab-full.yml) and in
// scripts/premerge-main.sh before dev -> main. Needs `flutter pub get` (package:crypto).

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import 'package:whispaste/core/models/bundled_model_catalog.dart';

Future<void> main(List<String> args) async {
  var full = false;
  var catalogOnly = false;
  var hashLimit = 20 * 1024 * 1024;
  var manifestPath = 'tool/model_sources.json';
  for (final a in args) {
    if (a == '--catalog-only') {
      catalogOnly = true;
    } else if (a == '--full') {
      full = true;
    } else if (a.startsWith('--hash-limit=')) {
      hashLimit = int.parse(a.split('=').last);
    } else if (a.startsWith('--manifest=')) {
      manifestPath = a.split('=').last;
    } else {
      stderr.writeln('unknown argument: $a');
      exit(2);
    }
  }

  final manifest =
      jsonDecode(File(manifestPath).readAsStringSync()) as Map<String, Object?>;
  final files = catalogOnly
      ? [
          for (final f in bundledModelCatalog.allFiles)
            <String, Object?>{
              'name': f.filename,
              'size': f.sizeBytes,
              'sha256': f.sha256,
              'sources': f.sources,
            },
        ]
      : (manifest['files']! as List).cast<Map<String, Object?>>();
  final problems = bundledModelCatalog.validate();
  if (problems.isNotEmpty) {
    stderr.writeln(problems.join('\n'));
    exit(1);
  }
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    ..userAgent = 'whispaste-source-guard';

  var failures = 0;
  for (final f in files) {
    final name = f['name']! as String;
    final size = f['size']! as int;
    final sha = f['sha256']! as String;
    final sources = (f['sources']! as List).cast<String>();
    for (final (i, url) in sources.indexed) {
      final label = '$name [${i + 1}/${sources.length} ${Uri.parse(url).host}]';
      final problems = await _check(
        client,
        Uri.parse(url),
        size: size,
        sha256: sha,
        hash: full || size <= hashLimit,
      );
      if (problems.isEmpty) {
        stdout.writeln('OK    $label');
      } else {
        failures++;
        stdout.writeln('FAIL  $label');
        for (final p in problems) {
          stdout.writeln('        $p');
        }
      }
    }
  }
  client.close(force: true);
  stdout.writeln(
    failures == 0
        ? 'All ${files.length} files reachable with the pinned size/hash.'
        : '$failures source(s) failed.',
  );
  exit(failures == 0 ? 0 : 1);
}

Future<List<String>> _check(
  HttpClient client,
  Uri url, {
  required int size,
  required String sha256,
  required bool hash,
}) async {
  final problems = <String>[];
  try {
    // 1. Redirect metadata (Hugging Face LFS/Xet files).
    final head = await _send(client, 'HEAD', url, follow: false);
    await head.drain<void>();
    if (head.statusCode >= 400) {
      return ['HEAD ${head.statusCode} (repo deleted, gated or commit gone?)'];
    }
    final linkedSize = head.headers.value('x-linked-size');
    if (linkedSize != null && int.tryParse(linkedSize) != size) {
      problems.add('x-linked-size $linkedSize, registry $size');
    }
    final linkedEtag = head.headers
        .value('x-linked-etag')
        ?.replaceAll('"', '')
        .replaceFirst('W/', '');
    if (linkedEtag != null &&
        RegExp(r'^[0-9a-f]{64}$').hasMatch(linkedEtag) &&
        linkedEtag != sha256) {
      problems.add('x-linked-etag $linkedEtag, registry $sha256');
    }

    // 2. Ranged GET on the final host: resume support + object size.
    final ranged = await _send(
      client,
      'GET',
      url,
      headers: {'Range': 'bytes=0-0'},
    );
    await ranged.drain<void>();
    if (ranged.statusCode != 206) {
      problems.add('ranged GET answered ${ranged.statusCode}, expected 206');
    } else {
      final range = ranged.headers.value('content-range') ?? '';
      final total = int.tryParse(range.split('/').last);
      if (total != size) problems.add('Content-Range "$range", registry $size');
    }

    // 3. Full hash for small files or with --full.
    if (hash && problems.isEmpty) {
      final res = await _send(client, 'GET', url);
      if (res.statusCode != 200) {
        await res.drain<void>();
        problems.add('GET ${res.statusCode}');
      } else {
        var length = 0;
        final digest = await crypto.sha256
            .bind(
              res.map((chunk) {
                length += chunk.length;
                return chunk;
              }),
            )
            .first;
        if (length != size) {
          problems.add('downloaded $length bytes, registry $size');
        }
        if ('$digest' != sha256) {
          problems.add('sha256 $digest, registry $sha256');
        }
      }
    }
  } on Object catch (e) {
    problems.add('$e');
  }
  return problems;
}

/// One request; with [follow] the client follows up to 5 redirects.
Future<HttpClientResponse> _send(
  HttpClient client,
  String method,
  Uri url, {
  bool follow = true,
  Map<String, String> headers = const {},
}) async {
  final req = await client.openUrl(method, url);
  req.followRedirects = follow;
  req.maxRedirects = 5;
  headers.forEach(req.headers.set);
  return req.close().timeout(const Duration(seconds: 60));
}
