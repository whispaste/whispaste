/// Pure interface for the floating overlay controller.
///
/// The shared types, enums, and the abstract [FloatingOverlayController]
/// class live here so that platform implementations can import only this file
/// and avoid a circular dependency with the factory layer.
library;

import '../../core/theme/overlay_customization.dart';
import '../../core/theme/overlay_design_spec.dart'
    show OverlayBackground, OverlaySizeVariant, OverlayThemeColors, OverlayWave;
import 'floating_overlay_events.dart';
import 'overlay_key_hints.dart';
import 'overlay_notice.dart';

/// Visual state of the overlay (matches C++ OverlayVisualState).
enum OverlayVisualState { recording, transcribing, done, error }

/// Anchor position mode for the overlay window.
enum OverlayAnchorMode { topCenter, bottomCenter, topLeft }

/// Immutable snapshot of everything the overlay needs to render.
///
/// Dart owns ALL state — the native window is a dumb renderer.
/// Every field is pre-resolved (localized, formatted, themed) before sending.
/// The elapsed recording time shown on the overlay, as `m:ss` (minutes are not
/// padded). Shared by the live overlay and the settings preview.
String formatOverlayElapsed(Duration elapsed) {
  final minutes = elapsed.inMinutes;
  final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

class FloatingOverlaySnapshot {
  const FloatingOverlaySnapshot({
    required this.visible,
    required this.state,
    required this.label,
    this.size = OverlaySizeVariant.normal,
    this.background = OverlayBackground.marine,
    this.wave = OverlayWave.cyan,
    this.elapsed = '',
    this.hint = '',
    this.transcript,
    this.errorMessage,
    this.privacyMode = 'local',
    this.doneMessage,
    this.donePasteFailed = false,
    this.progress = 0.0,
    this.secondaryLabel,
    this.liveTranscript,
    this.languageChip,
    this.profileChip,
    this.appearance = OverlayAppearance.defaults,
    this.countdown = false,
    this.keyHints,
    this.reduceTransparency = false,
    this.nativeBackdrop = false,
    this.nativeBackdropEdge = false,
    this.notice,
    this.pillHintId,
    this.announced = false,
  });

  final bool visible;
  final OverlayVisualState state;

  /// The overlay size variant (normal / compact / mini). The native shells
  /// size their window from the serialised `size` name.
  final OverlaySizeVariant size;

  /// Background preset of the pill (ticket, ADR 0024), independent of [size].
  final OverlayBackground background;

  /// Wave colour preset of the pill (ticket, ADR 0024).
  final OverlayWave wave;

  final String label;
  final String elapsed;
  final String hint;
  final String? transcript;
  final String? errorMessage;
  final String privacyMode;
  final String? doneMessage;

  /// The run finished but its paste did not land. The done state then shows
  /// the error glyph in the warning colour instead of the green check
  /// (XP-5-07, UX-059).
  final bool donePasteFailed;

  /// Recording progress (0.0–1.0). 0 = unlimited/no limit set.
  final double progress;

  /// Smaller second text line under [label] in the text-forward
  /// (transcribing-style) composition — the guided-sequence frames use it
  /// for the Enter/Escape mechanics and the "get ready" beat. Null/empty
  /// keeps the classic single-line layout; the minimal (mini) composition
  /// never paints it.
  final String? secondaryLabel;

  /// Live/partial recognized text, only when the user has opted into the
  /// live-transcript overlay setting (ticket 11). While
  /// [OverlayVisualState.transcribing] it replaces the status label; while
  /// [OverlayVisualState.recording] the same text is already in [elapsed]
  /// and this field only marks it as live text, so the painter keeps the
  /// newest words on overflow. Null/empty keeps the classic composition —
  /// the default.
  final String? liveTranscript;

  /// Short label of the dictation language frozen at recording start (for
  /// example `DE`), painted as a small chip. Null hides the chip (auto or no
  /// language).
  final String? languageChip;

  /// Short name of the manually chosen profile, shown in the same top-centre
  /// chip as the language. Null while automatic or no profile is chosen.
  final String? profileChip;

  /// ticket appearance options (form, wave style, fluid outline, timer and
  /// cancel glyph, requested opacity step). Defaults to today's look.
  final OverlayAppearance appearance;

  /// The last 30 seconds before the duration limit: [elapsed] then carries the
  /// remaining time and the timer is drawn in the amber accent.
  final bool countdown;

  /// Stop and cancel key hints in the normal recording pill; null when they
  /// are not shown (other sizes, other states, or no live microphone).
  final OverlayKeyHints? keyHints;

  /// The system's "Reduce transparency" setting. Never sent by the main
  /// engine: the native shell injects it into the relayed map, and a glass
  /// look then paints an opaque neutral body instead.
  final bool reduceTransparency;

  /// True when the native shell draws the glass backdrop behind the Flutter
  /// view (NSGlassEffectView, DWM acrylic). The glass body then paints no
  /// fill of its own, only the rim and highlight. Injected by the shell.
  final bool nativeBackdrop;

  /// True when that native backdrop draws its own edge (NSGlassEffectView on
  /// macOS 26+). The body then adds no hairline of its own: a second line just
  /// inside the system edge read as an inner frame (#476). Injected by the
  /// shell.
  final bool nativeBackdropEdge;

  /// The notice card (overlay F2) that replaces the pill while a microphone
  /// problem or the duration limit needs a decision; null for the pill.
  /// The window then takes the size class `notice` instead of [size].
  final OverlayNotice? notice;

  /// Stable name of the short confirmation shown at the pill (#454), such as
  /// `profile-switched`; null for every other frame. Marks the pill as a hint
  /// for screen readers and UI tests (#633).
  final String? pillHintId;

  /// The main engine has already read this frame's text out. The overlay
  /// engine then stays quiet, so a profile or language switch is announced
  /// exactly once (#633).
  final bool announced;

  /// The opacity step actually rendered: the requested step lifted by the
  /// contrast gate for the active background and wave.
  OverlayOpacity get effectiveOpacity => OverlayOpacityGate.clamp(
    requested: appearance.opacity,
    fill: background.surfaceStart,
    accent: OverlayThemeColors.resolve(
      background: background,
      wave: wave,
    ).accent,
  );

  Map<String, dynamic> toMap() => {
    'visible': visible,
    'state': state.name,
    // The shells size their window from `size`; a notice card has its own
    // size class, the pill size travels on in `pillSize`.
    'size': notice != null ? 'notice' : size.name,
    'pillSize': size.name,
    'background': background.value,
    'wave': wave.value,
    // Legacy mirror of the old two-size contract, kept so any consumer that
    // still switches on the boolean (older shell binaries during a staged
    // rollout) degrades to compact instead of breaking. `mini` reports
    // compact=false; such a consumer falls back to the normal window.
    'compact': size == OverlaySizeVariant.compact,
    'label': label,
    'elapsed': elapsed,
    'countdown': countdown,
    'stopHint': keyHints?.stop,
    'cancelHint': keyHints?.cancel,
    'hint': hint,
    'transcript': transcript,
    'errorMessage': errorMessage,
    'privacyMode': privacyMode,
    'doneMessage': doneMessage,
    'donePasteFailed': donePasteFailed,
    'progress': progress,
    'secondaryLabel': secondaryLabel,
    'liveTranscript': liveTranscript,
    'languageChip': languageChip,
    'profileChip': profileChip,
    'notice': notice?.toMap(),
    'pillHintId': pillHintId,
    'announced': announced,
    ...appearance.toMap(),
  };

  /// Rebuilds a snapshot from its [toMap] form.
  ///
  /// Used by the in-process overlay render engine (ADR 0002 phase 2): the
  /// native shell relays the main engine's [toMap] payload to the dedicated
  /// overlay Flutter engine, which deserialises it here before feeding
  /// [WpFloatingOverlayView]. Unknown/absent `state` falls back to
  /// [OverlayVisualState.recording] so a malformed relay never crashes the
  /// render isolate.
  factory FloatingOverlaySnapshot.fromMap(Map<dynamic, dynamic> map) {
    final stateName = map['state'] as String?;
    final state = OverlayVisualState.values.firstWhere(
      (s) => s.name == stateName,
      orElse: () => OverlayVisualState.recording,
    );
    // `size` is the canonical key; a payload without it (older sender) falls
    // back to the legacy `compact` boolean.
    final sizeName = (map['pillSize'] ?? map['size']) as String?;
    final size = sizeName != null
        ? OverlaySizeVariant.fromName(sizeName)
        : ((map['compact'] as bool? ?? false)
              ? OverlaySizeVariant.compact
              : OverlaySizeVariant.normal);
    final background = OverlayBackground.fromValue(
      map['background'] as String?,
    );
    final wave = OverlayWave.fromValue(map['wave'] as String?);
    return FloatingOverlaySnapshot(
      visible: map['visible'] as bool? ?? false,
      state: state,
      size: size,
      background: background,
      wave: wave,
      reduceTransparency: map['reduceTransparency'] as bool? ?? false,
      nativeBackdrop: map['nativeBackdrop'] as bool? ?? false,
      nativeBackdropEdge: map['nativeBackdropEdge'] as bool? ?? false,
      label: map['label'] as String? ?? '',
      elapsed: map['elapsed'] as String? ?? '',
      hint: map['hint'] as String? ?? '',
      transcript: map['transcript'] as String?,
      errorMessage: map['errorMessage'] as String?,
      privacyMode: map['privacyMode'] as String? ?? 'local',
      doneMessage: map['doneMessage'] as String?,
      donePasteFailed: map['donePasteFailed'] as bool? ?? false,
      progress: (map['progress'] as num?)?.toDouble() ?? 0.0,
      secondaryLabel: map['secondaryLabel'] as String?,
      liveTranscript: map['liveTranscript'] as String?,
      languageChip: map['languageChip'] as String?,
      profileChip: map['profileChip'] as String?,
      appearance: OverlayAppearance.fromMap(map),
      countdown: map['countdown'] as bool? ?? false,
      keyHints: OverlayKeyHints.fromStrings(
        stop: map['stopHint'] as String?,
        cancel: map['cancelHint'] as String?,
      ),
      notice: OverlayNotice.fromMap(map['notice']),
      pillHintId: map['pillHintId'] as String?,
      announced: map['announced'] as bool? ?? false,
    );
  }
}

/// Optional capability: a shell whose render engine can be re-booted on
/// request (macOS, Windows, Linux; ticket phase 2). The service only runs the frame-heartbeat
/// recovery against controllers that implement it, so a platform without a
/// render engine never gets a re-boot request.
abstract interface class RenderEngineRecovery {
  /// Re-boots the render engine inside the existing shell. Fire-and-forget:
  /// the outcome is observed through the next [OverlayRenderFrame].
  Future<void> rebootRenderEngine();
}

/// Platform-agnostic interface for the native floating overlay window.
///
/// Layer 2 in the three-layer architecture. The overlay shows recording
/// status, waveform, transcription progress, and results in a native
/// always-on-top window. Future macOS/Linux implementations provide their
/// own controller behind this same interface.
abstract class FloatingOverlayController {
  /// Send the complete overlay state for rendering.
  ///
  /// This is the primary interface — one call carries everything. The native
  /// window lazy-creates on the first call with `visible: true`.
  Future<void> updateSnapshot(FloatingOverlaySnapshot snapshot);

  /// Push a pre-computed waveform bar array (length 30, values 0.0–1.0).
  ///
  /// Stateless render path: the native window draws bar `i` at height
  /// `minH + bars[i] × (maxH − minH)` with active/muted colour decided by
  /// `bars[i] >= 0.30`. This is the sole waveform input — the native side
  /// owns no smoothing or animation state of its own (cut-over: issue 06).
  Future<void> setWaveformBars(List<double> bars);

  /// Move the overlay to a specific position.
  Future<void> setPosition(double x, double y, OverlayAnchorMode anchor);

  /// Set the context menu for compact right-click, in the wire format of
  /// `nativeMenuItems`; [appearance] as `nativeMenuAppearance` returns it.
  Future<void> setContextMenuItems(
    List<Map<String, Object?>> items, {
    String appearance = 'system',
  });

  /// Stream of events from the native overlay window.
  Stream<FloatingOverlayEvent> get events;

  /// Destroy the native window and clean up resources.
  Future<void> dispose();
}
