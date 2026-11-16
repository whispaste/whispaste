/// Checklists inside the Markdown a recording or note carries (issue #643).
///
/// The text stays the one source of truth (ADR 0035): ticking a box rewrites
/// `- [ ]` to `- [x]` in the line itself, nothing is stored beside it. Every
/// function here is pure and keeps every other character, including Windows
/// line endings, exactly where it was.
library;

/// One task line: `- [ ] text`, `* [x] text`, `1. [X] text`, indented or not.
/// Group 1 is everything before the box, group 2 the box's mark.
final RegExp _task = RegExp(
  r'^(\s*(?:[-*+]|\d{1,9}[.)])[ \t]+)\[([ xX])\](?=\s|$)',
);
final RegExp _fence = RegExp(r'^\s{0,3}(`{3,}|~{3,})');
final RegExp _listLine = RegExp(r'^(\s*)(?:[-*+]|\d{1,9}[.)])[ \t]');

/// A task line of the text: its line index and whether it is ticked.
class ChecklistItem {
  const ChecklistItem({required this.line, required this.checked});

  /// Zero-based line index in the source (split at `\n`).
  final int line;
  final bool checked;

  @override
  bool operator ==(Object other) =>
      other is ChecklistItem && other.line == line && other.checked == checked;

  @override
  int get hashCode => Object.hash(line, checked);

  @override
  String toString() => 'ChecklistItem($line, $checked)';
}

/// Every task line outside code fences, in text order.
List<ChecklistItem> checklistItems(String source) {
  if (!source.contains('[')) return const [];
  final items = <ChecklistItem>[];
  final lines = source.split('\n');
  final fences = _fencedLines(lines);
  for (var i = 0; i < lines.length; i++) {
    if (fences[i]) continue;
    final m = _task.firstMatch(lines[i]);
    if (m != null) {
      items.add(ChecklistItem(line: i, checked: m.group(2) != ' '));
    }
  }
  return items;
}

/// Whether the line at [line] is a task line that is ticked; null when the
/// line is no task line.
bool? isChecklistLineChecked(String line) {
  final m = _task.firstMatch(line);
  return m == null ? null : m.group(2) != ' ';
}

/// Flips the box in line [line]. Any other line index, or a line that is no
/// task, returns [source] unchanged.
String toggleChecklistItem(String source, int line) {
  final lines = source.split('\n');
  if (line < 0 || line >= lines.length) return source;
  if (_fencedLines(lines)[line]) return source;
  final m = _task.firstMatch(lines[line]);
  if (m == null) return source;
  final mark = m.group(2) == ' ' ? 'x' : ' ';
  lines[line] = _withMark(lines[line], m, mark);
  return lines.join('\n');
}

/// Ticks ([checked] true) or clears every box. Lines already in that state,
/// and every other line, stay byte for byte.
String setAllChecklistItems(String source, {required bool checked}) {
  final items = checklistItems(source);
  if (items.isEmpty) return source;
  final lines = source.split('\n');
  for (final item in items) {
    if (item.checked == checked) continue;
    final m = _task.firstMatch(lines[item.line])!;
    lines[item.line] = _withMark(lines[item.line], m, checked ? 'x' : ' ');
  }
  return lines.join('\n');
}

/// Moves the ticked items of each checklist below its open ones, keeping the
/// order within both groups. A checklist is a run of consecutive list lines;
/// an item carries the deeper-indented lines below it (sub-items, wrapped
/// text) along. A run that mixes tasks and plain bullets at its top level is
/// left alone — reordering it would tear a list the user wrote on purpose.
String moveCheckedToBottom(String source) {
  if (checklistItems(source).isEmpty) return source;
  final lines = source.split('\n');
  final fences = _fencedLines(lines);
  final out = <String>[];
  var i = 0;
  while (i < lines.length) {
    final start = _listLine.firstMatch(lines[i]);
    if (fences[i] || start == null) {
      out.add(lines[i]);
      i++;
      continue;
    }
    final base = _indentWidth(start.group(1)!);
    // Collect the run as units: a top-level line plus its deeper lines.
    final units = <List<String>>[];
    while (i < lines.length && !fences[i]) {
      final line = lines[i];
      final lm = _listLine.firstMatch(line);
      final trimmed = line.trim();
      if (lm != null && _indentWidth(lm.group(1)!) <= base) {
        units.add([line]);
      } else if (trimmed.isNotEmpty &&
          _indentWidth(_leading(line)) > base &&
          units.isNotEmpty) {
        units.last.add(line);
      } else {
        break;
      }
      i++;
    }
    final allTasks = units.every((u) => _task.hasMatch(u.first));
    if (!allTasks) {
      for (final u in units) {
        out.addAll(u);
      }
      continue;
    }
    final open = units.where((u) => !_isChecked(u.first));
    final done = units.where((u) => _isChecked(u.first));
    for (final u in [...open, ...done]) {
      out.addAll(u);
    }
  }
  return out.join('\n');
}

bool _isChecked(String line) => _task.firstMatch(line)!.group(2) != ' ';

String _withMark(String line, RegExpMatch m, String mark) {
  final boxStart = m.group(1)!.length;
  return '${line.substring(0, boxStart + 1)}$mark'
      '${line.substring(boxStart + 2)}';
}

String _leading(String line) => RegExp(r'^\s*').firstMatch(line)!.group(0)!;

int _indentWidth(String whitespace) {
  var width = 0;
  for (final c in whitespace.codeUnits) {
    width += c == 0x09 ? 4 : 1;
  }
  return width;
}

/// True for every line inside a code fence, the fence lines included.
List<bool> _fencedLines(List<String> lines) {
  final result = List<bool>.filled(lines.length, false);
  String? marker;
  for (var i = 0; i < lines.length; i++) {
    final m = _fence.firstMatch(lines[i]);
    if (marker != null) {
      result[i] = true;
      if (m != null &&
          m.group(1)!.startsWith(marker) &&
          lines[i].trim().length == m.group(1)!.length) {
        marker = null;
      }
    } else if (m != null) {
      result[i] = true;
      marker = m.group(1);
    }
  }
  return result;
}
