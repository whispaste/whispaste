/// Route group: list, create and edit notes (ticket / 8.1, #671).
///
/// Creating a note never pastes or types anything; it only writes to the
/// Notizen store. The controller decides whether the write fires a hook.
library;

import 'package:shelf/shelf.dart';

import '../../core/logging/app_logger.dart';
import 'automation_api_responses.dart';
import 'automation_api_router.dart';

final _log = AppLogger('AutomationApiNotesRoutes');

/// Longest note body the API accepts, in characters.
const kAutomationApiNoteMaxChars = 100000;

const _defaultListLimit = 50;
const _maxListLimit = 200;

/// While [isHistoryLocked] reports a PIN-locked history, every notes route
/// answers 423 with `error: history_locked` and never reads or writes notes.
AutomationApiRouteGroup automationNotesRoutes({
  required Future<List<Map<String, Object?>>> Function(int limit) listNotes,
  required Future<Map<String, Object?>> Function(String content) createNote,
  Future<NoteEditOutcome> Function(NoteEdit edit)? editNote,
  bool Function()? isHistoryLocked,
}) {
  return (router) {
    if (editNote != null) _addEditRoutes(router, editNote, isHistoryLocked);

    router.add('GET', '/v1/notes', (Request request) async {
      if (isHistoryLocked?.call() ?? false) {
        return jsonResponse(423, {'error': 'history_locked'});
      }
      final raw = request.url.queryParameters['limit'];
      final int limit;
      if (raw == null) {
        limit = _defaultListLimit;
      } else {
        final parsed = int.tryParse(raw);
        if (parsed == null || parsed < 1 || parsed > _maxListLimit) {
          return jsonResponse(400, {'error': 'invalid_request'});
        }
        limit = parsed;
      }
      try {
        return jsonResponse(200, {'notes': await listNotes(limit)});
      } catch (e, st) {
        _log.warning('GET /v1/notes failed', e, st);
        return jsonResponse(500, {'error': 'notes_failed'});
      }
    });

    router.add('POST', '/v1/notes', (Request request) async {
      if (isHistoryLocked?.call() ?? false) {
        return jsonResponse(423, {'error': 'history_locked'});
      }
      final body = await readJsonObject(request.read());
      final content = body?['content'];
      if (content is! String || content.trim().isEmpty) {
        return jsonResponse(400, {'error': 'invalid_request'});
      }
      if (content.length > kAutomationApiNoteMaxChars) {
        return jsonResponse(400, {'error': 'content_too_long'});
      }
      try {
        final note = await createNote(content);
        return jsonResponse(201, note);
      } catch (e, st) {
        _log.warning('POST /v1/notes failed', e, st);
        return jsonResponse(500, {'error': 'notes_failed'});
      }
    });
  };
}

/// One edit of an existing note, addressed by its stable [id].
sealed class NoteEdit {
  const NoteEdit(this.id);
  final String id;

  /// Action name used in the log line and the response.
  String get action;
}

class NoteEditAppend extends NoteEdit {
  const NoteEditAppend(super.id, this.content);
  final String content;
  @override
  String get action => 'append';
}

/// Replaces the selection [find] by [replacement]; the first match only
/// unless [all] is set.
class NoteEditReplace extends NoteEdit {
  const NoteEditReplace(
    super.id,
    this.find,
    this.replacement, {
    this.all = false,
  });
  final String find;
  final String replacement;
  final bool all;
  @override
  String get action => 'replace';
}

class NoteEditTag extends NoteEdit {
  const NoteEditTag(super.id, this.tag);
  final String tag;
  @override
  String get action => 'tag';
}

class NoteEditPin extends NoteEdit {
  const NoteEditPin(super.id, {required this.pinned});
  final bool pinned;
  @override
  String get action => 'pin';
}

sealed class NoteEditOutcome {
  const NoteEditOutcome();
}

class NoteEdited extends NoteEditOutcome {
  const NoteEdited(this.note);
  final Map<String, Object?> note;
}

class NoteEditNotFound extends NoteEditOutcome {
  const NoteEditNotFound();
}

/// The text to replace does not occur in the note.
class NoteEditNoMatch extends NoteEditOutcome {
  const NoteEditNoMatch();
}

/// The edit would make the note longer than [kAutomationApiNoteMaxChars].
class NoteEditTooLong extends NoteEditOutcome {
  const NoteEditTooLong();
}

void _addEditRoutes(
  AutomationApiRouter router,
  Future<NoteEditOutcome> Function(NoteEdit edit) editNote,
  bool Function()? isHistoryLocked,
) {
  void register(
    String path,
    NoteEdit? Function(Map<String, Object?> body) parse,
  ) {
    router.add('POST', path, (Request request) async {
      if (isHistoryLocked?.call() ?? false) {
        return jsonResponse(423, {'error': 'history_locked'});
      }
      final body = await readJsonObject(request.read());
      final id = body?['id'];
      final edit = (body == null || id is! String || id.isEmpty)
          ? null
          : parse(body);
      if (edit == null) return jsonResponse(400, {'error': 'invalid_request'});
      try {
        final outcome = await editNote(edit);
        // Logged like every other automation call: action and note id only,
        // never note content.
        _log.info('POST $path: ${edit.action} note ${edit.id}');
        return switch (outcome) {
          NoteEdited(:final note) => jsonResponse(200, note),
          NoteEditNotFound() => jsonResponse(404, {'error': 'note_not_found'}),
          NoteEditNoMatch() => jsonResponse(404, {'error': 'no_match'}),
          NoteEditTooLong() => jsonResponse(400, {'error': 'content_too_long'}),
        };
      } catch (e, st) {
        _log.warning('POST $path failed', e, st);
        return jsonResponse(500, {'error': 'notes_failed'});
      }
    });
  }

  register('/v1/notes/append', (body) {
    final content = body['content'];
    if (content is! String || content.trim().isEmpty) return null;
    if (content.length > kAutomationApiNoteMaxChars) return null;
    return NoteEditAppend(body['id']! as String, content);
  });
  register('/v1/notes/replace', (body) {
    final find = body['find'];
    final replacement = body['replacement'];
    final all = body['all'] ?? false;
    if (find is! String || find.isEmpty) return null;
    if (replacement is! String || all is! bool) return null;
    if (replacement.length > kAutomationApiNoteMaxChars) return null;
    return NoteEditReplace(body['id']! as String, find, replacement, all: all);
  });
  register('/v1/notes/tag', (body) {
    final tag = body['tag'];
    if (tag is! String || tag.trim().isEmpty || tag.length > 64) return null;
    return NoteEditTag(body['id']! as String, tag);
  });
  register('/v1/notes/pin', (body) {
    final pinned = body['pinned'] ?? true;
    if (pinned is! bool) return null;
    return NoteEditPin(body['id']! as String, pinned: pinned);
  });
}
