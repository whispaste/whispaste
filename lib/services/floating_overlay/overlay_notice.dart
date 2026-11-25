/// Notice card of the floating overlay (overlay F2).
///
/// A microphone problem or the duration limit used to reach the user only as
/// a line of text in the pill, without a way out. The notice card names the
/// problem and offers one or two actions, clickable without taking focus from
/// the target app.
///
/// This file is the wire model shared with the overlay render engine; the
/// rules that pick a card live in `overlay_notice_rules.dart`. No action ever
/// discards what was said: every way out either keeps recording, or stops and
/// transcribes. Only Esc discards, and over a card it asks first.
library;

import 'dart:async';

/// Which problem the card is about. Also decides the order when several are
/// true at once: a lost microphone first, then the duration limit, then a
/// quiet microphone.
enum OverlayNoticeKind {
  noMicrophone,
  startFailed,
  signalLost,
  timeRunningOut,
  quiet,

  /// A message of the dictation pipeline outside a recording: a failed paste,
  /// a missing model, a GPU fallback (#453). Texts and actions come from the
  /// caller, see `dictation_notice.dart`.
  message,
}

/// Colour of the card's glyph: amber for a hint, red for an error.
enum OverlayNoticeTone { hint, error }

/// What a card button does. The [id] is the wire name on the render channel.
enum OverlayNoticeActionId {
  /// Opens Settings at the microphone row. While a dictation runs it waits
  /// until that dictation is finished, so the paste still lands in the
  /// target app (the change applies from the next dictation).
  changeMicrophone('change_microphone'),

  /// Starts a new recording after a failed start.
  retry('retry'),

  /// Stops and transcribes what was captured so far.
  pasteSoFar('paste_so_far'),

  /// Throws away what was recorded so far (after the microphone dropped out);
  /// nothing is transcribed or pasted.
  discardRecording('discard_recording'),

  /// Extends the duration limit once by the configured duration.
  keepRecording('keep_recording'),

  /// Stops, transcribes and pastes now, before the limit.
  stopNow('stop_now'),

  /// Closes a card that has no running recording behind it.
  dismiss('dismiss'),

  /// The cross of a card over a running recording: hides the card for the
  /// rest of this recording and keeps recording. Never stops or discards.
  hideHint('hide_hint'),

  /// The first and second button of a [OverlayNoticeKind.message] card. The
  /// service looks the callback up in the open dictation notice.
  notice1('notice_1'),
  notice2('notice_2');

  const OverlayNoticeActionId(this.id);

  final String id;

  /// Whether the card draws this action as its close cross, not as a button.
  bool get isClose => this == dismiss || this == hideHint;

  /// The action for a wire [id]; null for an unknown one.
  static OverlayNoticeActionId? fromId(String? id) {
    for (final a in values) {
      if (a.id == id) return a;
    }
    return null;
  }
}

/// One button of the card.
class OverlayNoticeAction {
  const OverlayNoticeAction({
    required this.action,
    required this.label,
    this.primary = false,
    this.name,
    this.keyHint,
  });

  final OverlayNoticeActionId action;
  final String label;
  final bool primary;

  /// The key way that runs the button (`F12`, `2× F12`, #816), shown after
  /// the label and kept whole when the label has to be cut; null without one.
  final String? keyHint;

  /// The button's full name with its key way, for assistive technology and
  /// for sharing the row by width.
  String get fullLabel => keyHint == null ? label : '$label ($keyHint)';

  /// What a message button does (`use-microphone`), for its testID; null for
  /// the fixed actions, which are named by [action] itself.
  final String? name;

  /// The testID suffix of the button: by what it does, not where it sits.
  String get testName => name ?? action.id;

  Map<String, dynamic> toMap() => {
    'id': action.id,
    if (name != null) 'name': name,
    'label': label,
    'primary': primary,
    if (keyHint != null) 'keyHint': keyHint,
  };

  static OverlayNoticeAction? fromMap(Object? map) {
    if (map is! Map) return null;
    final action = OverlayNoticeActionId.fromId(map['id'] as String?);
    if (action == null) return null;
    return OverlayNoticeAction(
      action: action,
      label: map['label'] as String? ?? '',
      primary: map['primary'] as bool? ?? false,
      name: map['name'] as String?,
      keyHint: map['keyHint'] as String?,
    );
  }
}

/// A quiet hint line under a card's body with its own testID [id], such as
/// the local model's quality hint (#251) or the refine hint (#250) of the
/// write preview.
class OverlayNoticeNote {
  const OverlayNoticeNote({required this.id, required this.text});

  final String id;
  final String text;

  Map<String, dynamic> toMap() => {'id': id, 'text': text};

  static OverlayNoticeNote? fromMap(Object? map) {
    if (map is! Map) return null;
    final id = map['id'];
    final text = map['text'];
    if (id is! String || text is! String || text.isEmpty) return null;
    return OverlayNoticeNote(id: id, text: text);
  }

  @override
  bool operator ==(Object other) =>
      other is OverlayNoticeNote && other.id == id && other.text == text;

  @override
  int get hashCode => Object.hash(id, text);
}

/// testIDs of the write preview's edit field (#254).
const kNoticeEditFieldId = 'smart-write-preview-edit-field';
const kNoticeEditToggleId = 'smart-write-preview-edit-toggle';
const kNoticeEditInsertHintId = 'smart-write-preview-edit-insert-hint';

/// Lines the edit field shows before it scrolls. Fixed, so the card height
/// the main engine measures does not change while the user types.
const int kNoticeEditFieldLines = 5;

/// An editable text on the card (#254): [text] with a toggle while not
/// [open], then a multi-line field with the [insertHint] line under it.
class OverlayNoticeEdit {
  const OverlayNoticeEdit({
    required this.key,
    required this.text,
    required this.open,
    required this.toggleLabel,
    required this.fieldLabel,
    required this.insertHint,
  });

  /// Changes when the text was replaced from outside; while it stays, the
  /// field keeps what the user typed and the caret.
  final int key;
  final String text;
  final bool open;
  final String toggleLabel;
  final String fieldLabel;
  final String insertHint;

  Map<String, dynamic> toMap() => {
    'key': key,
    'text': text,
    'open': open,
    'toggleLabel': toggleLabel,
    'fieldLabel': fieldLabel,
    'insertHint': insertHint,
  };

  static OverlayNoticeEdit? fromMap(Object? map) {
    if (map is! Map) return null;
    final key = map['key'];
    final text = map['text'];
    if (key is! int || text is! String) return null;
    return OverlayNoticeEdit(
      key: key,
      text: text,
      open: map['open'] as bool? ?? false,
      toggleLabel: map['toggleLabel'] as String? ?? '',
      fieldLabel: map['fieldLabel'] as String? ?? '',
      insertHint: map['insertHint'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is OverlayNoticeEdit &&
      other.key == key &&
      other.text == text &&
      other.open == open &&
      other.toggleLabel == toggleLabel &&
      other.fieldLabel == fieldLabel &&
      other.insertHint == insertHint;

  @override
  int get hashCode =>
      Object.hash(key, text, open, toggleLabel, fieldLabel, insertHint);
}

/// What the card's edit field reports to the main engine. It travels as a
/// `noticeAction` with its arguments, which every shell relays unchanged.
enum OverlayNoticeEditKind {
  /// The toggle was pressed: show the field.
  open('edit_open'),

  /// The field's text changed (`text`).
  text('edit_text'),

  /// The field gained or lost the keyboard focus (`focused`).
  focus('edit_focus'),

  /// Enter in the field: insert `text`.
  submit('edit_submit'),

  /// Esc in the field: discard.
  cancel('edit_cancel');

  const OverlayNoticeEditKind(this.id);

  final String id;
}

/// A key the native shell caught for the open edit field (#254): the macOS
/// shell takes Return, Shift+Return and Escape before the embedder's text
/// input, which does not reliably pass them on, and sends them as `editKey`.
/// It reads Shift from the key event itself; the engine's pressed-key state
/// can miss a Shift that came only as a flag.
enum OverlayNoticeEditKey {
  /// Return: insert the text.
  enter,

  /// Shift+Return: break the line.
  newline,

  /// Escape: discard.
  escape;

  /// The key for a wire value (`enter`, `escape`); null for anything else.
  static OverlayNoticeEditKey? fromWire(Object? value) {
    for (final key in values) {
      if (key.name == value) return key;
    }
    return null;
  }
}

/// Keys from [OverlayNoticeEditKey]'s native source, for the edit field of
/// the card in this render engine. One card at a time carries a field.
class OverlayNoticeEditKeys {
  OverlayNoticeEditKeys._();

  static final StreamController<OverlayNoticeEditKey> _keys =
      StreamController<OverlayNoticeEditKey>.broadcast(sync: true);

  static Stream<OverlayNoticeEditKey> get stream => _keys.stream;

  static void dispatch(OverlayNoticeEditKey key) => _keys.add(key);
}

class OverlayNoticeEditEvent {
  const OverlayNoticeEditEvent(this.kind, {this.text, this.focused});

  final OverlayNoticeEditKind kind;
  final String? text;
  final bool? focused;

  String get id => kind.id;

  /// The arguments next to `id` on the wire.
  Map<String, dynamic> get args => {'text': ?text, 'focused': ?focused};

  /// The event for a wire [id] and its [args]; null for any other id.
  static OverlayNoticeEditEvent? fromWire(String id, Object? args) {
    for (final kind in OverlayNoticeEditKind.values) {
      if (kind.id != id) continue;
      final map = args is Map ? args : const {};
      final text = map['text'];
      final focused = map['focused'];
      return OverlayNoticeEditEvent(
        kind,
        text: text is String ? text : null,
        focused: focused is bool ? focused : null,
      );
    }
    return null;
  }
}

/// The resolved card: localized texts and the actions, ready to render.
class OverlayNotice {
  const OverlayNotice({
    required this.kind,
    required this.tone,
    required this.title,
    required this.body,
    required this.actions,
    this.footer = '',
    this.notes = const [],
    this.edit,
  });

  final OverlayNoticeKind kind;
  final OverlayNoticeTone tone;
  final String title;
  final String body;
  final List<OverlayNoticeAction> actions;

  /// The keys that are valid while the card stands, one line under the body
  /// (#781). Empty shows no line.
  final String footer;

  /// Quiet hint lines under the body, each with its own testID. Empty shows
  /// no line.
  final List<OverlayNoticeNote> notes;

  /// An editable text (#254); null for a card without a field.
  final OverlayNoticeEdit? edit;

  /// The same card with [footer] set.
  OverlayNotice withFooter(String footer) => OverlayNotice(
    kind: kind,
    tone: tone,
    title: title,
    body: body,
    actions: actions,
    footer: footer,
    notes: notes,
    edit: edit,
  );

  /// Title and body as one sentence for the screen-reader announcement.
  String get announcement => '$title. $body';

  Map<String, dynamic> toMap() => {
    'kind': kind.name,
    'tone': tone.name,
    'title': title,
    'body': body,
    'footer': footer,
    if (notes.isNotEmpty) 'notes': [for (final n in notes) n.toMap()],
    'actions': [for (final a in actions) a.toMap()],
    if (edit != null) 'edit': edit!.toMap(),
  };

  /// Rebuilds a card from [toMap]; null for a missing or malformed payload,
  /// so a bad relay shows the plain pill instead of crashing the renderer.
  static OverlayNotice? fromMap(Object? map) {
    if (map is! Map) return null;
    final kind = OverlayNoticeKind.values.asNameMap()[map['kind']];
    if (kind == null) return null;
    final actions = map['actions'];
    final notes = map['notes'];
    return OverlayNotice(
      kind: kind,
      tone: map['tone'] == OverlayNoticeTone.error.name
          ? OverlayNoticeTone.error
          : OverlayNoticeTone.hint,
      title: map['title'] as String? ?? '',
      body: map['body'] as String? ?? '',
      footer: map['footer'] as String? ?? '',
      notes: [
        if (notes is List)
          for (final n in notes) ?OverlayNoticeNote.fromMap(n),
      ],
      actions: [
        if (actions is List)
          for (final a in actions) ?OverlayNoticeAction.fromMap(a),
      ],
      edit: OverlayNoticeEdit.fromMap(map['edit']),
    );
  }
}
