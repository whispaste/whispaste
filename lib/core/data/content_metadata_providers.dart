import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'content_metadata.dart';
import 'database.dart';

export 'content_metadata.dart';

/// Consumers receive cached metadata and request visible-document priority.
/// A missing/stale cache stays loading/empty until the worker publishes it.
final contentMetadataProvider = StreamProvider.autoDispose
    .family<ContentMetadata?, ContentKey>((ref, key) {
      return ref.watch(historyDatabaseProvider).contentIndex.watch(key);
    });

/// The editor submits an immutable snapshot on change; readers never inspect
/// its controller. Superseded keystrokes are discarded before worker startup.
final contentMetadataPreviewProvider = FutureProvider.autoDispose
    .family<ContentMetadata?, String>((ref, text) async {
      final index = ref.watch(historyDatabaseProvider).contentIndex;
      var cancelled = false;
      ref.onDispose(() => cancelled = true);
      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (cancelled) return null;
      return index.preview(text);
    });
