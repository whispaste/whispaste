/// Plattformneutrale Gesten-Erkennung für einen einzelnen Hotkey.
///
/// Reine Dart-Logik ohne Flutter- oder Plattform-Abhängigkeit. Die nativen
/// Schichten liefern nur rohe Down/Up-Ereignisse der beobachteten Taste (und
/// für Modifier-only zusätzlich „andere Taste gedrückt“); diese Maschine
/// entscheidet daraus, welche Aktion der Aufnahme-Steuerung gilt.
///
/// Wichtig für die Latenz (Nordstern: schnellster Weg Hotkey → Text): Jede
/// Aktion, die eine Aufnahme startet, wird synchron im Down-Ereignis
/// ausgegeben. Die Maschine wartet nie auf ein Zeitfenster, bevor sie startet.
library;

/// Geste, mit der eine Hotkey-Zeile ausgelöst wird.
enum HotkeyGesture {
  /// Halten: Aufnahme läuft, solange die Taste gedrückt bleibt (Push-to-talk).
  hold,

  /// Tippen: jeder Druck startet bzw. stoppt die Aufnahme (Freihand-Toggle).
  tap,

  /// Automatisch: Halten ab der Schwelle = Push-to-talk, kürzerer Druck =
  /// Freihand (Hybrid).
  auto,

  /// Doppeltippen: zwei kurze Drücke in Folge lösen die Doppeltipp-Aktion aus.
  /// Einzel-Tippen hat keine Wirkung, damit kein Druck auf das Doppeltipp-
  /// Fenster warten muss.
  doubleTap,
}

/// Ausgabe der Maschine an die Aufnahme-Steuerung.
enum GestureOutput {
  /// Aufnahme starten (Halten, Beginn des Drucks, sofort).
  start,

  /// Aufnahme beenden (Loslassen nach dem Halten, nur wenn dieser Druck sie
  /// gestartet hat).
  stop,

  /// Aufnahme umschalten (Tippen bzw. Automatisch beim Drücken, sofort).
  toggle,

  /// Doppeltipp erkannt; die gewählte Doppeltipp-Aktion läuft.
  doubleTap,

  /// Modifier-only: eine andere Taste kam, während der Druck die Aufnahme
  /// gestartet hatte. Die Aufnahme wird verworfen, weil es keine Geste war.
  abort,
}

/// Erkennt Gesten aus Down/Up-Zeitstempeln.
///
/// Die Zeitquelle liefert der Aufrufer (`now`), damit Tests deterministisch
/// bleiben. Die Maschine ist nicht threadsicher; sie wird aus dem UI-Isolate
/// gespeist.
class HotkeyGestureMachine {
  HotkeyGestureMachine({
    required this.gesture,
    required this._onOutput,
    this.holdThreshold = const Duration(milliseconds: 250),
    this.doubleTapWindow = const Duration(milliseconds: 400),
    this.repeatWindow = const Duration(milliseconds: 1200),
    this.doubleTapEnabled = false,
  }) : assert(
         !doubleTapEnabled || gesture == HotkeyGesture.hold,
         'Double tap may only share a key with hold (never with tap or auto)',
       );

  /// Gewählte Geste dieser Hotkey-Zeile.
  final HotkeyGesture gesture;

  /// Ab dieser Haltedauer gilt ein Druck als Halten (Standard 250 ms).
  final Duration holdThreshold;

  /// Zwei kurze Drücke gelten als Doppeltipp, wenn der zweite Druck innerhalb
  /// dieser Zeit nach dem Loslassen des ersten beginnt.
  final Duration doubleTapWindow;

  /// Ein Down ohne vorheriges Up innerhalb dieses Fensters ist OS-Auto-Repeat.
  /// Liegt es länger zurück, ist das Up verloren gegangen und der Druck neu.
  final Duration repeatWindow;

  /// Hold key that also carries a double-tap action. A short release then
  /// discards the recording it started (silently, as a first tap), and a
  /// second press inside [doubleTapWindow] runs the action instead of
  /// starting a recording. Only allowed with [HotkeyGesture.hold].
  final bool doubleTapEnabled;

  final void Function(GestureOutput output) _onOutput;

  bool _held = false;
  DateTime? _lastDownAt;
  DateTime? _downAt;

  /// Ob der aktuelle Druck die Aufnahme gestartet hat (nur dann darf er sie
  /// beim Loslassen wieder stoppen).
  bool _pressStarted = false;

  /// Gesetzt, wenn eine andere Taste den Druck als Geste entwertet hat.
  bool _aborted = false;

  /// Ende des letzten kurzen Drucks, der noch auf einen zweiten warten kann.
  DateTime? _pendingTapReleaseAt;

  /// Ein Doppeltipp hat dieses Paar bereits verbraucht.
  bool _pairConsumed = false;

  /// Taste wurde gedrückt.
  ///
  /// [isRecording] sagt, ob gerade eine Aufnahme läuft. Der Aufrufer muss es
  /// im selben Moment liefern, damit Tippen und Automatisch wissen, ob der
  /// Druck startet oder stoppt.
  void down(DateTime now, {required bool isRecording}) {
    final last = _lastDownAt;
    _lastDownAt = now;
    if (_held && last != null && now.difference(last) < repeatWindow) {
      return; // OS auto-repeat of the press already being handled.
    }
    _held = true;
    _aborted = false;
    _downAt = now;

    switch (gesture) {
      case HotkeyGesture.hold:
        final lastRelease = _pendingTapReleaseAt;
        _pendingTapReleaseAt = null;
        if (doubleTapEnabled &&
            !_pairConsumed &&
            lastRelease != null &&
            now.difference(lastRelease) < doubleTapWindow) {
          // Second tap of a pair: the action runs, nothing is recorded.
          _pairConsumed = true;
          _pressStarted = false;
          _onOutput(GestureOutput.doubleTap);
        } else {
          _pairConsumed = false;
          _pressStarted = true;
          _onOutput(GestureOutput.start);
        }
      case HotkeyGesture.tap:
        _pressStarted = !isRecording;
        _onOutput(GestureOutput.toggle);
      case HotkeyGesture.auto:
        _pressStarted = !isRecording;
        _onOutput(GestureOutput.toggle);
      case HotkeyGesture.doubleTap:
        _pressStarted = false;
        final lastRelease = _pendingTapReleaseAt;
        _pendingTapReleaseAt = null;
        if (!_pairConsumed &&
            lastRelease != null &&
            now.difference(lastRelease) < doubleTapWindow) {
          _pairConsumed = true;
          _onOutput(GestureOutput.doubleTap);
        } else {
          _pairConsumed = false;
        }
    }
  }

  /// Taste wurde losgelassen.
  void up(DateTime now) {
    if (!_held) return;
    _held = false;
    final downAt = _downAt;
    _downAt = null;
    final started = _pressStarted;
    _pressStarted = false;
    final aborted = _aborted;
    _aborted = false;
    final held = downAt == null ? Duration.zero : now.difference(downAt);
    final isShort = held < holdThreshold;

    switch (gesture) {
      case HotkeyGesture.hold:
        if (!started || aborted) {
          // Second tap of a pair (or an aborted press): nothing to stop.
          _pendingTapReleaseAt = null;
        } else if (doubleTapEnabled && isShort) {
          // First tap of a possible pair: drop the recording silently and
          // keep the release as a candidate for the second tap.
          _onOutput(GestureOutput.abort);
          _pendingTapReleaseAt = now;
        } else {
          _pendingTapReleaseAt = null;
          _onOutput(GestureOutput.stop);
        }
      case HotkeyGesture.tap:
        break;
      case HotkeyGesture.auto:
        if (started && !aborted && !isShort) _onOutput(GestureOutput.stop);
      case HotkeyGesture.doubleTap:
        if (isShort && !_pairConsumed) {
          _pendingTapReleaseAt = now;
        } else {
          _pendingTapReleaseAt = null;
        }
    }
  }

  /// Eine andere Taste wurde gedrückt, während die beobachtete Taste gehalten
  /// wird. Für Modifier-only zählt damit der Druck nicht mehr als Geste
  /// (⌘+C bleibt ⌘+C).
  void otherKey(DateTime now) {
    if (!_held || !_pressStarted || _aborted) return;
    _aborted = true;
    _onOutput(GestureOutput.abort);
  }
}
