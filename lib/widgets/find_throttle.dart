/// Throttled, abortable find for long texts (#640).
///
/// Interim measure until the block architecture of #627: short texts are
/// searched synchronously exactly as before; long texts wait [delay] after the
/// last input and are scanned in time slices, so typing never blocks on the
/// scan. New input aborts a running scan.
library;

import 'dart:async';

import 'find_replace.dart';

class WpFindThrottle {
  WpFindThrottle({
    this.longTextChars = 20000,
    this.delay = const Duration(milliseconds: 150),
    this.slice = const Duration(milliseconds: 4),
  });

  /// Texts shorter than this are searched synchronously.
  final int longTextChars;
  final Duration delay;

  /// Time budget per scan slice before yielding to the event loop.
  final Duration slice;

  Timer? _timer;
  int _generation = 0;

  /// Looks for [query] in [text] and reports through [onResult]. Aborts any
  /// earlier pending or running search; an aborted search never reports.
  void run(
    String text,
    String query,
    void Function(WpFindMatches) onResult, {
    bool caseSensitive = false,
  }) {
    cancel();
    if (text.length < longTextChars || query.isEmpty) {
      onResult(WpFindReplace.locate(text, query, caseSensitive: caseSensitive));
      return;
    }
    final generation = _generation;
    _timer = Timer(delay, () {
      _timer = null;
      unawaited(_scan(text, query, caseSensitive, generation, onResult));
    });
  }

  Future<void> _scan(
    String text,
    String query,
    bool caseSensitive,
    int generation,
    void Function(WpFindMatches) onResult,
  ) async {
    final pattern = RegExp(RegExp.escape(query), caseSensitive: caseSensitive);
    final starts = <int>[];
    final watch = Stopwatch()..start();
    for (final match in pattern.allMatches(text)) {
      starts.add(match.start);
      if (watch.elapsed >= slice) {
        await Future<void>.delayed(Duration.zero);
        if (generation != _generation) return;
        watch.reset();
      }
    }
    if (generation != _generation) return;
    onResult(
      starts.isEmpty
          ? WpFindMatches.none
          : WpFindMatches(
              starts: List<int>.unmodifiable(starts),
              length: query.length,
            ),
    );
  }

  /// Aborts a pending or running search without reporting.
  void cancel() {
    _generation++;
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => cancel();
}
