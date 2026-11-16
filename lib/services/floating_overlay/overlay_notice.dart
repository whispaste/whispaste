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

/// The resolved card: localized texts and the actions, ready to render.
class OverlayNotice {
  const OverlayNotice({
    required this.kind,
    required this.tone,
    required this.title,
    required this.body,
    required this.actions,
    this.footer = '',
  });

  final OverlayNoticeKind kind;
  final OverlayNoticeTone tone;
  final String title;
  final String body;
  final List<OverlayNoticeAction> actions;

  /// The keys that are valid while the card stands, one line under the body
  /// (#781). Empty shows no line.
  final String footer;

  /// The same card with [footer] set.
  OverlayNotice withFooter(String footer) => OverlayNotice(
    kind: kind,
    tone: tone,
    title: title,
    body: body,
    actions: actions,
    footer: footer,
  );

  /// Title and body as one sentence for the screen-reader announcement.
  String get announcement => '$title. $body';

  Map<String, dynamic> toMap() => {
    'kind': kind.name,
    'tone': tone.name,
    'title': title,
    'body': body,
    'footer': footer,
    'actions': [for (final a in actions) a.toMap()],
  };

  /// Rebuilds a card from [toMap]; null for a missing or malformed payload,
  /// so a bad relay shows the plain pill instead of crashing the renderer.
  static OverlayNotice? fromMap(Object? map) {
    if (map is! Map) return null;
    final kind = OverlayNoticeKind.values.asNameMap()[map['kind']];
    if (kind == null) return null;
    final actions = map['actions'];
    return OverlayNotice(
      kind: kind,
      tone: map['tone'] == OverlayNoticeTone.error.name
          ? OverlayNoticeTone.error
          : OverlayNoticeTone.hint,
      title: map['title'] as String? ?? '',
      body: map['body'] as String? ?? '',
      footer: map['footer'] as String? ?? '',
      actions: [
        if (actions is List)
          for (final a in actions) ?OverlayNoticeAction.fromMap(a),
      ],
    );
  }
}
