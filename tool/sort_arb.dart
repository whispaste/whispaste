/// Keeps every `lib/core/l10n/*.arb` sorted by message key.
///
/// Why: new keys used to be appended at the end of each ARB file, so any two
/// branches that added keys collided at the same spot (and on the trailing
/// comma). With the keys sorted, independent additions land at different
/// places and merge without a conflict (#1452).
///
/// Layout kept as is: one entry per top-level `  "key": ...` line (values may
/// span several lines), `"@key"` metadata stays right behind its key,
/// `@@locale` first. Only the order and the commas between entries change.
///
///   dart tool/sort_arb.dart           sort the files in place
///   dart tool/sort_arb.dart --check   exit 1 if a file is not sorted
library;

import 'dart:io';

const _arbDir = 'lib/core/l10n';

final _entryStart = RegExp(r'^  "([^"]+)"\s*:');

class _Entry {
  _Entry(this.name, this.lines);
  final String name;
  final List<String> lines;
}

/// Returns [source] with its entries sorted, or [source] itself if the
/// format is not the expected one (then nothing is touched).
String sortArb(String source) {
  final lines = source.replaceAll('\r\n', '\n').split('\n');
  if (lines.isEmpty || lines.first.trim() != '{') return source;
  var end = lines.length - 1;
  while (end > 0 && lines[end].trim().isEmpty) {
    end--;
  }
  if (lines[end].trim() != '}') return source;

  final entries = <_Entry>[];
  for (var i = 1; i < end; i++) {
    final match = _entryStart.firstMatch(lines[i]);
    if (match != null) {
      entries.add(_Entry(match.group(1)!, [lines[i]]));
    } else if (entries.isEmpty) {
      return source;
    } else {
      entries.last.lines.add(lines[i]);
    }
  }

  // Group "@key" metadata with its message key.
  final groups = <String, List<_Entry>>{};
  for (final entry in entries) {
    final base = entry.name.startsWith('@@')
        ? entry.name
        : entry.name.startsWith('@')
        ? entry.name.substring(1)
        : entry.name;
    groups.putIfAbsent(base, () => []).add(entry);
  }
  final keys = groups.keys.toList()
    ..sort((a, b) {
      final aMeta = a.startsWith('@@');
      final bMeta = b.startsWith('@@');
      if (aMeta != bMeta) return aMeta ? -1 : 1;
      return a.compareTo(b);
    });

  final ordered = <_Entry>[];
  for (final key in keys) {
    final group = groups[key]!
      ..sort(
        (a, b) => a.name.startsWith('@') == b.name.startsWith('@')
            ? 0
            : (a.name.startsWith('@') ? 1 : -1),
      );
    ordered.addAll(group);
  }

  final out = StringBuffer('{\n');
  for (var i = 0; i < ordered.length; i++) {
    final entryLines = List<String>.of(ordered[i].lines);
    while (entryLines.isNotEmpty && entryLines.last.trim().isEmpty) {
      entryLines.removeLast();
    }
    var last = entryLines.removeLast().trimRight();
    if (last.endsWith(',')) last = last.substring(0, last.length - 1);
    entryLines.add(i == ordered.length - 1 ? last : '$last,');
    out.writeln(entryLines.join('\n'));
  }
  out.write('}\n');
  return out.toString();
}

void main(List<String> args) {
  final check = args.contains('--check');
  final unsorted = <String>[];
  final files =
      Directory(_arbDir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.arb'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    final source = file.readAsStringSync();
    final sorted = sortArb(source);
    if (sorted == source) continue;
    unsorted.add(file.path.replaceAll(r'\', '/'));
    if (!check) file.writeAsStringSync(sorted);
  }
  if (check && unsorted.isNotEmpty) {
    stderr
      ..writeln('ARB files not sorted by key (merge-conflict guard, #1452):')
      ..writeln(unsorted.map((p) => '  - $p').join('\n'))
      ..writeln('  Fix: dart tool/sort_arb.dart && git add lib/core/l10n');
    exit(1);
  }
}
