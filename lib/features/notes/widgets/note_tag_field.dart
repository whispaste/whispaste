import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/database.dart';
import '../../../core/data/tag_suggestions.dart';
import '../../../core/logging/app_logger.dart';
import '../../../widgets/tag_input.dart';

// ---------------------------------------------------------------------------
// The tag field of the note editor: WpTagInput plus the existing tags as
// suggestions (#830). The most used tags show while the field is empty, tags
// starting with the typed text after that; arrow keys and Enter pick one
// (WpTagInput), so a tag is chosen instead of retyped.
// ---------------------------------------------------------------------------

final _log = AppLogger('NoteTagField');

class NoteTagField extends ConsumerStatefulWidget {
  const NoteTagField({
    super.key,
    required this.tags,
    required this.onAdd,
    required this.onRemove,
    required this.hintText,
    required this.searchHintText,
  });

  final List<Tag> tags;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;
  final String hintText;
  final String searchHintText;

  @override
  ConsumerState<NoteTagField> createState() => _NoteTagFieldState();
}

class _NoteTagFieldState extends ConsumerState<NoteTagField> {
  String _query = '';
  TagSuggestions _suggestions = (tags: const <Tag>[], counts: const {});

  // Newest request wins: a slow answer for an older query must not replace
  // the suggestions of the text now in the field.
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant NoteTagField old) {
    super.didUpdateWidget(old);
    // A tag that was just created (or removed) changes what is on offer.
    if (old.tags.length != widget.tags.length) _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    try {
      final result = await loadTagSuggestions(
        ref.read(historyDatabaseProvider),
        _query,
      );
      if (!mounted || request != _request) return;
      setState(() => _suggestions = result);
    } on Object catch (e, st) {
      // Suggestions are a convenience: typing and Enter work without them.
      _log.warning('Could not load the tag suggestions', e, st);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WpTagInput(
      tags: widget.tags,
      onAdd: widget.onAdd,
      onRemove: widget.onRemove,
      hintText: widget.hintText,
      searchHintText: widget.searchHintText,
      suggestions: _suggestions.tags,
      suggestionCounts: _suggestions.counts,
      onSearchChanged: (q) {
        _query = q;
        _load();
      },
    );
  }
}
