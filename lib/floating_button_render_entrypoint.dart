/// Dedicated Flutter entrypoint for the macOS floating-button render engine.
///
/// ADR 0002 (Approach 1 / Variant B) makes the native button window a
/// lifecycle-only shell: it no longer draws with CoreGraphics, it hosts a
/// **second, headless-ish Flutter engine** whose only job is to paint the
/// shared [FloatingButtonView]. That engine is booted by the Swift
/// `FloatingButtonHost` with the `floatingButtonMain` entrypoint and pinned
/// into a transparent non-activating [FloatingButtonPanel].
///
/// ## The seam
///
/// The app's MAIN engine is untouched: `MacOSFloatingButtonController` still
/// pushes `show` / `setState` / `setTheme` / etc. over the
/// `com.whispaste.floating_button` channel to the native host. The host then
/// **relays** those payloads to THIS engine over a private render channel
/// (`com.whispaste.floating_button_render`). Interaction goes the other way:
/// this engine asks the host to start a native window drag, to show the native
/// context menu, or reports a tap — the host translates that into the existing
/// main-engine events. So the whole service/controller/event contract stays
/// exactly as it was; only the pixels move from native CoreGraphics to the
/// shared Dart painter.
library;

import 'package:flutter/widgets.dart';

import 'core/l10n/generated/app_localizations.dart';
import 'services/floating_button/floating_button_controller_interface.dart';
import 'services/floating_button/floating_button_render_channel.dart';
import 'shared_render_engine_helpers.dart';
import 'widgets/floating_button/floating_button_view.dart';

/// Private channel between the native button shell and this render engine.
///
/// Distinct from the public `com.whispaste.floating_button` channel the main
/// engine uses — the two engines never share a binary messenger, so the names
/// must not collide.
const String _renderChannelName = 'com.whispaste.floating_button_render';

/// Boots the button render engine.
///
/// The actual `@pragma('vm:entry-point') floatingButtonMain` lives in
/// `main.dart` (the root library) because macOS `runWithEntrypoint:` resolves
/// the entrypoint name only against the root library — it has no `libraryURI`
/// variant. That thin entrypoint delegates here so the real wiring stays in
/// this cohesive, unit-tested file.
void runFloatingButtonEngine() {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('[button-engine] runFloatingButtonEngine booted');
  runApp(const _ButtonRenderApp());
}

class _ButtonRenderApp extends StatefulWidget {
  const _ButtonRenderApp();

  @override
  State<_ButtonRenderApp> createState() => _ButtonRenderAppState();
}

class _ButtonRenderAppState
    extends RenderEngineState<_ButtonRenderApp, FloatingButtonRenderChannel> {
  _ButtonRenderAppState()
    : super(lookupL10n(const Locale('en')).a11yRecordingButton);

  FloatingButtonVisualState _state = FloatingButtonVisualState.idle;
  double _diameter = 56;

  @override
  FloatingButtonRenderChannel createChannel() => FloatingButtonRenderChannel(
    name: _renderChannelName,
    onState: _onState,
    onDiameter: (d) => setState(() => _diameter = d),
  );

  @override
  String labelOf(L10n l10n) => l10n.a11yRecordingButton;

  void _onState(FloatingButtonVisualState s) {
    final previous = _state;
    setState(() => _state = s);
    if (s == previous) return;
    final message = _announcementFor(s);
    if (message != null) announce(message);
  }

  /// Screen-reader text for a recording-workflow state transition, or null
  /// for states that don't warrant an announcement (idle/disabled are the
  /// button's resting states, not events).
  String? _announcementFor(FloatingButtonVisualState s) {
    final l10n = this.l10n;
    if (l10n == null) return null;
    return switch (s) {
      FloatingButtonVisualState.recording => l10n.statusBarRecording,
      FloatingButtonVisualState.transcribing => l10n.statusBarTranscribing,
      FloatingButtonVisualState.done => l10n.statusBarDone,
      FloatingButtonVisualState.error => l10n.sttStatusError,
      FloatingButtonVisualState.idle => null,
      FloatingButtonVisualState.disabled => null,
    };
  }

  /// The static role label plus the current state's announcement text (reuses
  /// [_announcementFor]), so a screen-reader user who explores this element
  /// on demand — not just one listening for the [announce] fired on state
  /// change — also hears the current state instead of only a generic
  /// "recording button".
  String get _composedSemanticsLabel {
    final stateText = _announcementFor(_state);
    return stateText == null ? semanticsLabel : '$semanticsLabel, $stateText';
  }

  @override
  Widget build(BuildContext context) => buildRenderEngineRoot(
    semanticsLabel: _composedSemanticsLabel,
    onTap: channel.clicked,
    onPanStart: channel.startDrag,
    onSecondaryOrLongPress: channel.showContextMenu,
    child: FloatingButtonView(state: _state, diameter: _diameter),
  );
}
