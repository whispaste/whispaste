/// Progress of a long recording that is transcribed in upload slices, shown to
/// the user while it runs (dock status chip, dictation overlay).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// [done] of [total] slices have finished. Only a split upload (total above 1)
/// has slices worth showing.
class SliceProgress {
  const SliceProgress({required this.done, required this.total});

  final int done;
  final int total;

  bool get isSliced => total > 1;

  /// The slice being transcribed now, counted from 1 and never above [total].
  int get current => done < total ? done + 1 : total;
}

/// Holds the progress of the dictation that is transcribing now, or null.
class SliceProgressNotifier extends Notifier<SliceProgress?> {
  @override
  SliceProgress? build() => null;

  void report({required int done, required int total}) =>
      state = SliceProgress(done: done, total: total);

  void clear() => state = null;
}

final transcriptionSliceProgressProvider =
    NotifierProvider<SliceProgressNotifier, SliceProgress?>(
      SliceProgressNotifier.new,
    );
