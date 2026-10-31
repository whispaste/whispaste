// transcription_eval.dart — measuring script for choosing the cloud
// transcription model (CLOUD-MODEL-EVAL). Standalone: imports dart: libraries
// only, so it runs without the app package's build hooks (like
// tool/headless_benchmark_check.dart).
//
// Run from a directory outside the repo, for example:
//   dart <repo>/tool/transcription_eval/transcription_eval.dart dry-run --plan full
//   OPENAI_API_KEY=… dart <repo>/tool/transcription_eval/transcription_eval.dart live \
//       --plan full --manifest <manifest.json> --out <internal-notes>/runs
//   dart <repo>/tool/transcription_eval/transcription_eval.dart score \
//       --manifest <manifest.json> --out <internal-notes>/runs
//
// Commands:
//   dry-run  Counts minutes and cost per model. Sends NOTHING, reads no key.
//   live     Sends the manifest's files to the API. Needs OPENAI_API_KEY
//            (environment only, never from the repo). Refuses output in the repo.
//   score    Computes WER/CER and latency p50/p95 from the raw answers in --out.
//
// Prices (USD per audio minute, source:
// https://developers.openai.com/api/docs/pricing, read 2026-10-26). The pricing
// page names no currency; $ is read as USD.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

const _endpoint = 'https://api.openai.com/v1/audio/transcriptions';
const _maxUploadBytes = 24 * 1000 * 1000; // Docs: 25 MB; headroom for multipart
const _reserve = 0.20; // Headroom for retries and failed attempts

class ModelSpec {
  const ModelSpec(this.id, this.usdPerMinute, this.languageField);
  final String id;
  final double usdPerMinute;

  /// Per the migration cookbook, gpt-transcribe takes the field `languages`
  /// instead of `language`. The exact format (array syntax) is still to be
  /// settled by a test run.
  final String languageField;
}

const _models = <ModelSpec>[
  ModelSpec('whisper-1', 0.006, 'language'),
  ModelSpec('gpt-4o-transcribe', 0.006, 'language'),
  ModelSpec('gpt-4o-mini-transcribe', 0.003, 'language'),
  ModelSpec('gpt-transcribe', 0.0045, 'languages'),
];

class Item {
  Item(
    this.id,
    this.lang,
    this.kind,
    this.seconds, {
    this.audio,
    this.reference,
  });
  final String id;
  final String lang;
  final String kind; // short | long | latency
  final double seconds;
  final String? audio;
  final String? reference;
}

/// Planned corpus without audio files (for the dry run and cost estimate).
List<Item> plannedItems(String plan) {
  final small = plan == 'small';
  const langs = ['de', 'en', 'es', 'ru', 'pt', 'ar'];
  final items = <Item>[];
  for (final lang in langs) {
    for (var i = 0; i < (small ? 20 : 50); i++) {
      items.add(Item('short-$lang-$i', lang, 'short', 12));
    }
    final longs = small
        ? [600, if (lang == 'de' || lang == 'en') 1800]
        : [600, 1800, 3600];
    for (final s in longs) {
      items.add(Item('long-$lang-${s ~/ 60}', lang, 'long', s.toDouble()));
    }
  }
  final reps = small ? 5 : 10;
  for (var i = 0; i < reps; i++) {
    items.add(Item('lat30-$i', 'de', 'latency', 30));
    items.add(Item('lat600-$i', 'de', 'latency', 600));
  }
  return items;
}

/// Manifest: JSON list of {id, lang, kind, seconds, audio, reference}.
List<Item> loadManifest(String path) {
  final list = jsonDecode(File(path).readAsStringSync()) as List<dynamic>;
  return [
    for (final e in list.cast<Map<String, dynamic>>())
      Item(
        e['id'] as String,
        e['lang'] as String,
        e['kind'] as String,
        (e['seconds'] as num).toDouble(),
        audio: e['audio'] as String?,
        reference: e['reference'] as String?,
      ),
  ];
}

String? _arg(List<String> args, String name) {
  final i = args.indexOf(name);
  return (i >= 0 && i + 1 < args.length) ? args[i + 1] : null;
}

Never _usage(String msg) {
  stderr.writeln(msg);
  stderr.writeln('Befehle: dry-run | live | score (siehe Kopf der Datei)');
  exit(2);
}

void main(List<String> args) async {
  if (args.isEmpty) _usage('Kein Befehl angegeben.');
  final cmd = args.first;
  final rest = args.sublist(1);
  final plan = _arg(rest, '--plan') ?? 'full';
  final manifest = _arg(rest, '--manifest');
  final out = _arg(rest, '--out');
  final modelsArg = _arg(rest, '--models');
  final rate = double.tryParse(_arg(rest, '--usd-per-eur') ?? '') ?? 1.1193;
  final chosen = modelsArg == null
      ? _models
      : _models.where((m) => modelsArg.split(',').contains(m.id)).toList();

  final items = manifest != null ? loadManifest(manifest) : plannedItems(plan);

  switch (cmd) {
    case 'dry-run':
      _printEstimate(items, chosen, rate);
    case 'live':
      await _runLive(items, chosen, out);
    case 'score':
      if (manifest == null || out == null) {
        _usage('score braucht --manifest und --out.');
      }
      _score(items, chosen, out);
    default:
      _usage('Unbekannter Befehl: $cmd');
  }
}

void _printEstimate(List<Item> items, List<ModelSpec> models, double rate) {
  double minutes(String? kind) => items
      .where((i) => kind == null || i.kind == kind)
      .fold(0.0, (a, i) => a + i.seconds / 60);
  final quality = minutes('short') + minutes('long');
  final latency = minutes('latency');
  stdout.writeln('Dry-Run — es wird nichts gesendet.');
  stdout.writeln(
    'Pro Modell: Qualität ${quality.toStringAsFixed(1)} min, '
    'Latenz ${latency.toStringAsFixed(1)} min.',
  );
  stdout.writeln('| Modell | Min | USD (+20 %) | EUR (+20 %) |');
  stdout.writeln('|---|---:|---:|---:|');
  var sumUsd = 0.0;
  for (final m in models) {
    final min = minutes(null);
    final usd = min * m.usdPerMinute * (1 + _reserve);
    sumUsd += usd;
    stdout.writeln(
      '| ${m.id} | ${min.toStringAsFixed(1)} | '
      '${usd.toStringAsFixed(2)} | ${(usd / rate).toStringAsFixed(2)} |',
    );
  }
  stdout.writeln(
    '| **Summe** | | **${sumUsd.toStringAsFixed(2)}** | '
    '**${(sumUsd / rate).toStringAsFixed(2)}** |',
  );
  stdout.writeln(
    'Kurs: 1 EUR = $rate USD (EZB-Referenzkurs, Abruf 2026-10-26).',
  );
}

Future<void> _runLive(
  List<Item> items,
  List<ModelSpec> models,
  String? out,
) async {
  final key = Platform.environment['OPENAI_API_KEY'];
  if (key == null || key.isEmpty) {
    _usage('OPENAI_API_KEY fehlt (nur Umgebungsvariable, nie aus dem Repo).');
  }
  if (out == null) {
    _usage('live braucht --out (außerhalb des Repos oder unter internal-notes).');
  }
  final outDir = Directory(out)..createSync(recursive: true);
  final outPath = outDir.absolute.path;
  if (outPath.contains('/whispaste/') && !outPath.contains('/internal-notes')) {
    _usage(
      '--out liegt im Repo; Rohdaten gehören nach internal-notes oder außerhalb.',
    );
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  for (final m in models) {
    final dir = Directory('$outPath/${m.id}')..createSync(recursive: true);
    for (final item in items.where((i) => i.audio != null)) {
      final file = File(item.audio!);
      if (file.lengthSync() > _maxUploadBytes) {
        stderr.writeln('${item.id}: > 24 MB, vorher komprimieren oder teilen.');
        continue;
      }
      final sw = Stopwatch()..start();
      final (status, body) = await _post(client, key, m, item, file);
      sw.stop();
      File('${dir.path}/${item.id}.json').writeAsStringSync(
        jsonEncode({
          'status': status,
          'latencyMs': sw.elapsedMilliseconds,
          'body': body,
        }),
      );
      stdout.writeln(
        '${m.id} ${item.id} HTTP $status ${sw.elapsedMilliseconds} ms',
      );
    }
  }
  client.close();
}

Future<(int, String)> _post(
  HttpClient client,
  String key,
  ModelSpec m,
  Item item,
  File file,
) async {
  final boundary = 'wpeval${DateTime.now().microsecondsSinceEpoch}';
  final bytes = <int>[];
  void text(String s) => bytes.addAll(utf8.encode(s));
  final fields = <String, String>{
    'model': m.id,
    'response_format': 'json',
    m.languageField: item.lang,
  };
  fields.forEach((k, v) {
    text(
      '--$boundary\r\nContent-Disposition: form-data; name="$k"\r\n\r\n$v\r\n',
    );
  });
  final name = file.uri.pathSegments.last;
  text(
    '--$boundary\r\nContent-Disposition: form-data; name="file"; '
    'filename="$name"\r\nContent-Type: application/octet-stream\r\n\r\n',
  );
  bytes.addAll(await file.readAsBytes());
  text('\r\n--$boundary--\r\n');

  final req = await client.postUrl(Uri.parse(_endpoint));
  req.headers
    ..set('Authorization', 'Bearer $key')
    ..set('Content-Type', 'multipart/form-data; boundary=$boundary');
  req.contentLength = bytes.length;
  req.add(bytes);
  final resp = await req.close();
  final body = await resp.transform(utf8.decoder).join();
  return (resp.statusCode, body);
}

// ---- Scoring --------------------------------------------------------------

/// Lowercases, drops diacritics (e.g. Arabic vowel marks), replaces
/// punctuation with spaces and collapses whitespace.
String normalize(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'\p{M}', unicode: true), '')
    .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

int _editDistance(List<Object> a, List<Object> b) {
  var prev = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, i);
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      cur[j] = math.min(
        math.min(cur[j - 1] + 1, prev[j] + 1),
        prev[j - 1] + cost,
      );
    }
    prev = cur;
  }
  return prev[b.length];
}

/// WER over words; CER over characters without spaces.
(double, double) errorRates(String ref, String hyp) {
  final r = normalize(ref);
  final h = normalize(hyp);
  final rw = r.isEmpty ? <String>[] : r.split(' ');
  final hw = h.isEmpty ? <String>[] : h.split(' ');
  final rc = r.replaceAll(' ', '').split('');
  final hc = h.replaceAll(' ', '').split('');
  final wer = rw.isEmpty
      ? (hw.isEmpty ? 0.0 : 1.0)
      : _editDistance(rw, hw) / rw.length;
  final cer = rc.isEmpty
      ? (hc.isEmpty ? 0.0 : 1.0)
      : _editDistance(rc, hc) / rc.length;
  return (wer, cer);
}

/// Loop suspicion: a 4-word pattern occurs at least 4 times.
bool hasLoop(String hyp) {
  final w = normalize(hyp).split(' ');
  final counts = <String, int>{};
  for (var i = 0; i + 4 <= w.length; i++) {
    final g = w.sublist(i, i + 4).join(' ');
    counts[g] = (counts[g] ?? 0) + 1;
    if (counts[g]! >= 4) return true;
  }
  return false;
}

double _percentile(List<double> v, double q) {
  if (v.isEmpty) return double.nan;
  final s = [...v]..sort();
  return s[(q * (s.length - 1)).round()];
}

void _score(List<Item> items, List<ModelSpec> models, String out) {
  stdout.writeln(
    '| Modell | Kind | Lang | n | WER | CER | Schleife | p50 ms | p95 ms |',
  );
  stdout.writeln('|---|---|---|---:|---:|---:|---:|---:|---:|');
  for (final m in models) {
    final groups = <String, List<Map<String, dynamic>>>{};
    final lat = <String, List<double>>{};
    for (final item in items.where((i) => i.reference != null)) {
      final f = File('$out/${m.id}/${item.id}.json');
      if (!f.existsSync()) continue;
      final rec = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      if (rec['status'] != 200) continue;
      final body = jsonDecode(rec['body'] as String) as Map<String, dynamic>;
      final hyp = (body['text'] as String? ?? '');
      final (wer, cer) = errorRates(
        File(item.reference!).readAsStringSync(),
        hyp,
      );
      final key = '${item.kind}|${item.lang}';
      groups.putIfAbsent(key, () => []).add({
        'wer': wer,
        'cer': cer,
        'loop': hasLoop(hyp),
      });
      lat.putIfAbsent(key, () => []).add((rec['latencyMs'] as num).toDouble());
    }
    for (final key in groups.keys) {
      final g = groups[key]!;
      double mean(String k) =>
          g.map((e) => e[k] as num).fold(0.0, (a, b) => a + b) / g.length;
      final loops = g.where((e) => e['loop'] == true).length;
      final l = lat[key]!;
      final parts = key.split('|');
      stdout.writeln(
        '| ${m.id} | ${parts[0]} | ${parts[1]} | ${g.length} | '
        '${mean('wer').toStringAsFixed(3)} | ${mean('cer').toStringAsFixed(3)} | '
        '$loops | ${_percentile(l, 0.5).toStringAsFixed(0)} | '
        '${_percentile(l, 0.95).toStringAsFixed(0)} |',
      );
    }
  }
}
