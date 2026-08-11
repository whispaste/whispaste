/// WhisPaste color palette — dark & light theme color definitions.
///
/// Quiet, chromatic material. **Two accents, two jobs**: `accent` and its
/// ladder mean "you can act on this", `recordingAccent` means "a recording or
/// its transcription is in flight" — nothing else is allowed a saturated voice.
/// The two are one cyan family separated by *weight*, not by hue; the older
/// "each job owns its own hue" clause is retracted (ADR 0013 — see *The Two
/// Accent, Two Jobs Rule* in `lib/DESIGN.md` for the retraction note).
///
/// **The ambient is not a third voice, it is the room** (ADR 0012,
/// 2026-08-11). Frame, content plane and the whole opaque surface stack live
/// in the brand's blue/navy family (~218–226°), the hue the app icon, the
/// websites and every pre-Ticket-04 build already carried. Ticket 04 had moved
/// the ambient onto a violet pole together with the accent; neither half of
/// that move survives (ADR 0012 returned the ground, ADR 0013 the accent).
/// Violet stays as the sparing "here and there", outside both accents: the
/// far, deepest end of both ambient arcs, where it is a flush rather than a
/// ground, and the lavender cast of the frost fills.
///
/// The blue is the *hue* of the pre-Ticket-04 palette but deliberately not its
/// *bytes*. Restoring those verbatim also restored the flat, pre-"coloured
/// glass" ground that Tickets 04–07 existed to leave behind, so every ambient
/// and surface value here is re-solved at raised chroma with its luminance held
/// constant: the numbers the gates measure are unchanged, the colour the eye
/// sees is roughly twice as saturated.
///
/// What keeps a blue ambient from reading as the cyan recording signal is
/// **weight, not hue distance**. The frame's first stop sits 28° from
/// `recordingAccent` — inside any hue radius one could name — and is in no
/// danger of being mistaken for it, because every ambient stop is ≥ 7:1 darker
/// than the signal and carries no edge, no motion and no shape. That is the
/// gate (`Ambient vs. the recording signal`, `wcag_contrast_test.dart`), and it
/// replaced *The Cool-Shadow Exception*, whose 45° clearance was retracted with
/// the violet ground it was invented to survive.
///
/// Depth is *precomposited frost*, not a compositor effect: tinted translucent
/// card fills (`cardFill`, `cardFillElevated`) painted over one chromatic
/// ambient gradient (`warmSurfaceGradient`), plus a static 1px top-edge
/// highlight. Every fill carries its hue in the token — a neutral white/black
/// alpha over a chromatic ground desaturates it, which is exactly how the
/// earlier painted-glass attempt read grey. There is no `BackdropFilter` in
/// the app outside the modal dialog-barrier family (`dialog.dart`,
/// `export_format_picker.dart`, `hotkey_recorder.dart` — three call sites of
/// the same transient full-screen effect, which already has a Windows
/// fallback).
///
/// Depth comes from **one source per theme**: on dark from the brightness
/// delta between fills (no card shadow token exists here at all), on light
/// from a single soft, wide, violet-tinted shadow (`cardShadowLight`). A glow
/// — a colored shadow at offset 0 — is not a depth source and stays out.
///
/// **Theme asymmetry, sanctioned here.** The light stack's chroma is capped
/// well below the dark stack's — not for taste, but because rotating a pearl
/// toward violet drains the green channel that carries 71.5 % of relative
/// luminance, and `textMuted` runs out of AA headroom before the dark side
/// notices anything. That is the *Increment–Decrement Rule*'s closing clause in
/// `lib/DESIGN.md` — "a new theme asymmetry is allowed, but it argues for
/// itself at the token" — and the argument sits at [WpColorsLight.background].
///
/// The two-accent and one-depth-source splits are stated in this file rather
/// than cited: `lib/DESIGN.md` still carries the superseded single-accent
/// doctrine and is rewritten in a follow-up ticket.
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Dark Theme Colors (Primary) — rich saturated blue-navy tones, unified
// ---------------------------------------------------------------------------
abstract final class WpColorsDark {
  /// Window frame — close to surface for unified monochrome feel.
  ///
  /// **Back in the brand's blue-navy (~222–226°)** — ADR 0012. Ticket 04 had
  /// rotated this whole stack to violet-navy (~253°) so the ambient would share
  /// the accent's hue family; the maintainer's course correction returns the
  /// *ground* to the hue the app icon and the websites carry (ADR 0013 then
  /// sent the accent back to cyan as well).
  ///
  /// **Chroma is deliberately not the pre-Ticket-04 value.** Rotating the hue
  /// back is only half the correction: restoring the old *bytes* would restore
  /// the flat, pre-"coloured glass" ground this palette spent Tickets 04–07
  /// getting away from, and it read as exactly that — a ground so grey the rail
  /// and the content plane beside it looked like two different materials. So
  /// the hue is the old one and the saturation is new: 58–61 % against the old
  /// 29–36 %, which roughly doubles the byte spread of every rung (17→31 on
  /// [background] through 41→83 on [active]).
  ///
  /// The lift costs nothing that is gated. Each rung was re-solved at its
  /// **luminance held constant** — saturation up, HSL lightness raised to
  /// compensate — so text AA (15.73:1 / 8.65:1 / 6.02:1), the category-slot
  /// ordering (5.83:1) and *Frame–content unity* (2.75 % gap, ceiling 4 %) all
  /// come out bit-for-bit unchanged. Only chroma moved, which is the one thing
  /// the correction was about. Same method as the frame arc below: hold what is
  /// measured, move what is seen.
  static const Color background = Color(0xFF0B122A);

  /// Content surfaces — minimal step up from frame (≈ 2% lightness delta)
  static const Color surface = Color(0xFF0D1936);

  /// Elevated panels, cards — richer navy tint
  static const Color surfaceElevated = Color(0xFF122247);

  /// Variant surface for alternate rows, secondary panels
  static const Color surfaceVariant = Color(0xFF162A57);

  /// Hover and press rungs of the same stack. Moved with the surfaces on
  /// purpose, in both directions: a hover left behind at the surfaces' old hue
  /// would introduce a hue shift *on interaction*, which is the one thing a
  /// hover state must not do.
  static const Color hover = Color(0xFF152856);

  /// Transparent version of hover for smooth AnimatedContainer transitions
  /// (prevents dark flash when interpolating from transparent to hover)
  static const Color hoverTransparent = Color(0x00152856);
  static const Color active = Color(0xFF1B306E);

  /// Hairline borders — white at 11.8 % / 18.8 %, both a step *above* their
  /// light twins (7.8 % / 14.1 %). Not an oversight: see
  /// [WpColorsLight.borderSubtle] for the increment/decrement reasoning.
  static const Color borderSubtle = Color(0x1EFFFFFF);
  static const Color borderDefault = Color(0x30FFFFFF);

  /// Hairline of an *active* card tile — see [WpColorsLight.cardActiveBorder]
  /// for why this pair carries the same alpha byte in both themes.
  static const Color cardActiveBorder = Color(0x24FFFFFF);

  /// Text — readable, not overly bright to avoid harshness
  static const Color textPrimary = Color(0xFFF0F4FA);
  static const Color textSecondary = Color(0xFFABB8CC);
  static const Color textMuted = Color(0xFF8A99B2);

  /// The one generic interaction color — the brand's cyan, 189°/81 %.
  ///
  /// Everything the user can act on carries this and only this: filled and
  /// outlined buttons, focus rings, selected rows, active toggles, links.
  ///
  /// **Back from violet** — ADR 0013. Ticket 04 had moved this to a vivid
  /// violet and made hue the discriminator against [recordingAccent]; the
  /// maintainer read a wall-to-wall violet as generic AI-generated SaaS rather
  /// than as this app's identity. The history settles it: before Ticket 04 the
  /// generic accent and the recording signal were the *same byte value*
  /// (`0xFF3CCBE6`) and shipped that way for the app's whole life without ever
  /// being confused. Hue exclusivity was a Ticket-04 artefact, not brand core.
  ///
  /// So the two tokens are one family again, and they separate by **weight,
  /// not hue** — the same mechanism the ambient uses against the same signal.
  /// This value sits 0.69° from [recordingAccent] in hue and 1.221:1 above it
  /// in contrast: unmistakably one family, still measurably two steps. The
  /// direction is functional rather than decorative. This token is consumed as
  /// thin alpha washes (5–30 %, the ladder below) and as label/icon text, where
  /// luminance *is* legibility and a darker cyan at 6 % over the ground would
  /// vanish; [recordingAccent] is painted opaque as a shape (waveform, dot),
  /// where the deeper, denser value reads as the more urgent of the two — which
  /// is the right way round for a status signal standing next to a button.
  ///
  /// The lightness is not a taste call either. `WpCategorySlot` tops out at
  /// 5.83:1 against [surface] and the accent has to stay *louder* than the
  /// loudest category; this value measures 10.98:1, comfortably above it.
  static const Color accent = Color(0xFF6FDDF0);
  static const Color accentHover = Color(0xFFA7EAF6);

  /// Flat accent surface tint, 16.5 % — deliberately *above* its light twin
  /// (11 %). See [WpColorsLight.accentSubtle] for the increment/decrement
  /// reasoning shared by every structural translucent in this file.
  static const Color accentSubtle = Color(0x2A6FDDF0);

  /// Instance-safe tint tokens: translucent fills/borders whose alpha lives in
  /// the *value*, used inside components that get reused as nested instances.
  /// Prefer them over inline `colour.withValues(...)` for component
  /// fills/borders.
  static const Color accentChipFill = Color(0x1A6FDDF0); // accent @ 10%
  static const Color accentChipFillHover = Color(0x2E6FDDF0); // accent @ 18%
  static const Color accentMiniTagFill = Color(0x1F6FDDF0); // accent @ 12%
  static const Color accentBorder30 = Color(0x4D6FDDF0); // accent @ 30%
  static const Color accentButtonFill = Color(0x146FDDF0); // accent @ 8%
  static const Color accentActiveFill = Color(0x1F6FDDF0); // accent @ 12%
  static const Color accentBadgeFill = Color(0x266FDDF0); // accent @ 15%
  static const Color accentBorder20 = Color(0x336FDDF0); // accent @ 20%
  static const Color accentRowHover = Color(0x0F6FDDF0); // accent @ 6%
  static const Color surfaceChipFill = Color(0x800D1936); // surface @ 50%
  static const Color surfaceMutedFill = Color(0x148A99B2); // textMuted @ 8%

  /// Precomposited frost — the card material, base and elevated rung.
  ///
  /// A violet-lavender tint at 8 % / 14 %, painted over the ambient
  /// [warmSurfaceGradient] rather than blurred out of it. The tint hue lives
  /// in the token by design: a white alpha would wash the ambient's color out
  /// and the card would read grey, which is precisely the failure this
  /// material replaces.
  ///
  /// **The tint stayed lavender when the ambient went back to navy** (ADR
  /// 0012) — measured, not defaulted. At these alphas over the plane the
  /// composite rotates by only a couple of degrees and *loses* saturation, i.e.
  /// it does what *Tinted-Never-Grey* asks of a frost — carry the ground's hue
  /// forward instead of replacing it — and stays inside the 3° the seam gate
  /// calls "the same hue". A card here reads navy.
  ///
  /// **Re-derived, not inherited, when the accent went back to cyan** (ADR
  /// 0013). The old justification was that the lavender is "the whisper of the
  /// accent on the card"; with a cyan accent that reading is gone, and an
  /// inherited tint would have been a leftover. It is kept on a new argument:
  /// violet is now a sanctioned exception *outside* both accents, and a frost
  /// at 3–5 % effective alpha is exactly the "here and there" register that
  /// exception is for. It is also the palette's only counter-warmth — ground,
  /// accent and signal are all cool now, and a cool-tinted frost (tested at
  /// #9FC4E8) makes the cards recede into the plane instead of sitting on it.
  ///
  /// The alphas are solved, not chosen: composited over *both* extremes of the
  /// ambient gradient, body text still clears 4.5:1 and [accent] still clears
  /// 3:1 as a graphical object. Anything heavier eats the accent's headroom on
  /// the card.
  ///
  /// **Re-solved 2026-08-11 — 8 % / 14 % retracted, not merely re-tuned.** The
  /// seam fix lifted [warmSurfaceGradient]'s brightest stop from Y 0.01452 to
  /// 0.02312, and these alphas composite over exactly that stop. At the old
  /// values `textMuted` fell to 4.40:1 and 3.95:1 — under 4.5:1, so the ladder
  /// had to come down with the sheet it sits on, not the threshold. The margin
  /// before the lift was already thin (4.61:1), which is why *any* perceptible
  /// seam broke it; that thinness was the latent bug, the lift only exposed it.
  ///
  /// **The budget this leaves is the part to read before Ticket 08 spends it.**
  /// The two levels now lift 1.048:1 and 1.075:1 above the plane, where they
  /// once spanned to ≈1.25:1 — the plane rose, the 4.5:1 ceiling did not, and
  /// what got compressed is the *distance between the two levels*. Dark's
  /// second card level can therefore no longer be bought with fill brightness:
  /// there is roughly a quarter of the luminance room there used to be. Buy it
  /// with chroma and [cardEdgeHighlight] instead, or the elevated card will
  /// read as the same surface twice. Neither token is painted by any widget
  /// today, so this is a budget note for Ticket 08, not a visual change.
  static const Color cardFill = Color(0x08A190D5); // frost tint @ 3.1%
  static const Color cardFillElevated = Color(0x0CA190D5); // frost tint @ 4.7%

  /// The card's static 1px top edge — a lit rim, not a light source.
  ///
  /// It lifts the fill it sits on by ≈1.41:1, under the 1.5:1 threshold at
  /// which a surface treatment starts reading as a drawn object. Static: no
  /// animation, no hover response, no gradient. Dark carries no card *shadow*
  /// token at all — a shadow on near-black would only add mud. One depth
  /// source per theme — see the library header.
  ///
  /// *Retracted 2026-08-11:* this comment used to name "the brightness delta
  /// between [cardFill] and [cardFillElevated]" as where dark's depth comes
  /// from. After the seam fix raised the content plane, that delta is about a
  /// quarter of what it was and can no longer carry two card levels on its
  /// own. On dark this rim is now the *primary* separator between them, not a
  /// finishing touch on top of a brightness step.
  static const Color cardEdgeHighlight = Color(0x24D7C8F9);

  /// Wash for a large decorative background glyph — its own category, *below*
  /// the 6/12/30% tint ladder above. See [WpColorsLight.decorativeGlyphWash]
  /// for why the two themes carry different alphas.
  static const Color decorativeGlyphWash = Color(0x0D6FDDF0); // accent @ 5%

  /// Saturated status colors — rich and warm
  static const Color success = Color(0xFF36D98B);
  static const Color warning = Color(0xFFF5C842);
  static const Color error = Color(0xFFFF7B7B);

  /// Danger/off-brand-neutral tint ladder — the same 6/8/12/20/30% alpha steps
  /// as the accent ladder above, keyed to [error]/[textMuted] instead, so a
  /// destructive or neutral control's hover, press and outline carry exactly
  /// the weight of an accent one's, only the hue differs.
  static const Color errorRowHover = Color(0x0FFF7B7B); // error @ 6%
  static const Color errorButtonFill = Color(0x14FF7B7B); // error @ 8%
  static const Color errorActiveFill = Color(0x1FFF7B7B); // error @ 12%
  static const Color errorBorder20 = Color(0x33FF7B7B); // error @ 20%
  static const Color errorBorder30 = Color(0x4DFF7B7B); // error @ 30%
  static const Color mutedRowHover = Color(0x0F8A99B2); // textMuted @ 6%
  static const Color mutedActiveFill = Color(0x1F8A99B2); // textMuted @ 12%

  /// The 12 % rung for the two remaining status hues, so the Quiet Status
  /// Rule's "tinted 32 px icon badge (status color at 12 % fill)" can be
  /// written as a token everywhere instead of a `withValues(alpha: 0.12)` at
  /// each call site. [error] already had its rung above; these complete the
  /// set. No 6 %/30 % rungs: success and warning never carry a hover state or
  /// an outline of their own — they only ever appear as a badge.
  static const Color successActiveFill = Color(0x1F36D98B); // success @ 12%
  static const Color warningActiveFill = Color(0x1FF5C842); // warning @ 12%

  /// Ring that marks the settings section a search hit jumped to — accent at
  /// 55 %, 2 px, painted in the foreground and cleared again after 1.5 s.
  ///
  /// Deliberately *above* the tint ladder's 30 % ceiling and named as its own
  /// category rather than as a stretched top rung, mirroring how
  /// [decorativeGlyphWash] sits below it: 30 % is calibrated for a *resting*
  /// outline the user is already looking at, while this ring has one job in
  /// the opposite direction — be caught in peripheral vision, once, before it
  /// disappears on its own. Nothing else may reach for it; a resting border
  /// that wants to be louder than 30 % is a hierarchy problem, not an alpha
  /// problem.
  ///
  /// Carries the same alpha in both themes, unlike the structural tints above
  /// (see [WpColorsLight.accentSubtle]). Left unsplit on purpose: this value
  /// is calibrated for the peak of something transient, so a per-theme split
  /// would have to be judged against a moving target. If it ever reads heavy
  /// on light, that is a maintainer call with the ring on screen, not a
  /// derivation from the rule.
  static const Color accentLocatorRing = Color(0x8C6FDDF0); // accent @ 55%

  /// Recording/listening family — the one meaning cyan keeps.
  ///
  /// Split off from [accent] so the palette can say two different things:
  /// [accent] means "you can act on this", these mean "a recording or its
  /// transcription is in flight" (audio-level bars, the transcribing rung of
  /// the status chip, the onboarding sandbox's live border). The values below
  /// were copied byte-for-byte off the accent family while it was still cyan —
  /// deliberately *literals*, not aliases — and they have not moved since, which
  /// is what the literals were for.
  ///
  /// **The two jobs are no longer two hues** (ADR 0013). Ticket 04 briefly made
  /// hue the discriminator by sending [accent] to violet; that clause is
  /// retracted and both tokens are cyan again, as they were for the app's whole
  /// life before Ticket 04 — when they were in fact the *same byte value* and
  /// never once confused. What separates them now is weight (1.221:1, this the
  /// heavier of the two) plus context, form and motion: a waveform animates, an
  /// overlay frames, a button does neither. This token deliberately stayed put
  /// while [accent] moved, so the split's audit table below still holds.
  ///
  /// Every call site is classified in the split's audit table; anything that
  /// is merely tappable, selected, hovered or focused stays on [accent], and
  /// so does everything that reads a state other than the recording phase
  /// (microphone *permission*, STT subprocess boot, an idle mic affordance).
  /// The frozen floating overlay carries the same meaning in its own spec and
  /// is not wired through here.
  static const Color recordingAccent = Color(0xFF3CCBE6);

  /// Gradient twin of [recordingAccent] — cyan to teal, copied from
  /// [accentWarmGradient]. No main-app surface paints a recording gradient
  /// today (the overlay owns that job and keeps its own spec), so this is the
  /// family's reserved home rather than a live call site.
  // loam-ignore: unused-public-exports – the recording family's reserved
  // gradient home; accentWarmGradient carries the lighter sibling of this
  // same cyan ramp (ADR 0013), so this stays the recording family's own copy.
  static const LinearGradient recordingAccentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3CCBE6), Color(0xFF14B8D4), Color(0xFF0A99B8)],
  );

  /// Preflight-screen palette — `WpInsufficientRamScreen` only.
  ///
  /// These three (plus the two badge tints below) are the sanctioned break of
  /// the Theme-Pair Rule and exist **without light counterparts on purpose**:
  /// the insufficient-RAM screen is shown *instead of* the app, never inside
  /// it, renders unconditionally in the dark identity theme and never reads
  /// `Theme` at all — so a light twin would have no code path that could ever
  /// resolve it. Off-limits everywhere else: in the app proper a warning is
  /// [warning] and a destructive action is [error], both theme-paired.
  /// Documented as *The Preflight-Screen Exception* in `lib/DESIGN.md`.
  ///
  /// Orange-600 — used for RAM/hardware preflight warnings.
  static const Color warningOrange = Color(0xFFEA580C);

  /// Fill and border of the preflight warning badge. Named rather than mixed
  /// at the call site, but *not* ladder rungs — the ladder is theme-paired and
  /// these are not, so they carry their own names at their own values.
  static const Color warningOrangeBadgeFill = Color(
    0x26EA580C,
  ); // warningOrange @ 15%
  static const Color warningOrangeBadgeBorder = Color(
    0x66EA580C,
  ); // warningOrange @ 40%

  /// Solid red shades for destructive action buttons (the preflight quit CTA).
  static const Color errorRed = Color(0xFFDC2626);
  static const Color errorRedHover = Color(0xFFB91C1C);

  /// Visible gradient for premium card/container backgrounds
  static const LinearGradient surfaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF14244F), Color(0xFF0D1936)],
  );

  /// The ambient the content plane is painted on, and the ground every card
  /// fill is gated against — brand navy top-left, a quiet indigo trough in the
  /// middle, and a violet pole bottom-right that keeps its tint as it turns.
  /// Opaque tonal steps (no alpha glow): neighbouring stops sit 1.07:1 / 1.09:1
  /// apart in relative luminance, so the panel reads as chromatic
  /// *temperature* under flat light, never as a lit edge.
  ///
  /// Measured: **220° / 234° / 255°, saturation 54 % → 33 % → 30 %** — the first
  /// stop answers to the frame beneath it (see below), the other two to the
  /// opaque tonal stack. ~~The middle stop *is* [surface] and moves with it.~~
  /// **Retracted 2026-08-11 (seam re-solve, below):** the middle stop no
  /// longer equals [surface]. That it did was a coincidence of tuning, not a
  /// derivation — the same coincidence the light twin already retracted. The
  /// plane is painted at three call sites only (`app.dart`,
  /// `snippet_picker_render_entrypoint.dart`, `screenshot_shell.dart`) and
  /// [surface] is the flat token for opaque panels; lifting the ambient does
  /// not lift the panel stack, and the two are free to disagree.
  /// What keeps the violet pole from
  /// reading as a second signal is its weight — 30 % saturation at Y 0.023,
  /// a third of the accent's chroma and a twentieth of its luminance — not hue
  /// distance; it deliberately reaches the arc the accent gradient walks,
  /// because one atmosphere is the point.
  ///
  /// **Hue arc re-derived for ADR 0012 (2026-08-11), luminance untouched.** The
  /// plane used to run 253° → 254° → 291°: a violet sheet ending on a warm
  /// magenta pole. Over the brand navy the ground returned to, that pole read
  /// as dirty brown-grey rather than as a warm counter-note, so the arc now
  /// runs **navy → indigo → violet** and the violet lands where it is
  /// *brightest* (the pole is the plane's most luminous stop) instead of where
  /// it is muddiest. That is ADR 0012's "violet here and there" made visible:
  /// blue carries the plane, violet finishes it.
  ///
  /// The rotation preserved **every stop's relative luminance to five decimals**
  /// (0.02113 / 0.01683 / 0.02312 → 0.02116 / 0.01679 / 0.02311, the residue
  /// being 8-bit quantisation). That is deliberate and it is what made this a
  /// hue change rather than a re-solve of the whole system: the seam's swept
  /// minimum, the card-fill ladder, [WpAvatarTint]'s disc clearance and every
  /// text-AA gate over this plane are luminance-only and did not move.
  ///
  /// The pole gained chroma in the turn — 15.6 % → 30.2 %. It had been pinned
  /// one tenth of a point above the 15 % ambient floor by the +12 lift
  /// (see below); at 255° that constraint simply stops binding, because the
  /// floor's `1 − |2L − 1|` divisor is no longer fighting a nearly-neutral
  /// magenta. The pole is now tinted with room to spare rather than by a
  /// hair's breadth.
  ///
  /// **The first stop is the seam** (Ticket 07). It is not a free color: it is
  /// painted at the plane's own top-left corner, at
  /// (`WpLayout.sidebarWidth`, `WpLayout.appBarHeight`) = (72, 64) of a
  /// [frameGradient] that spans the whole window, and it has to read there as
  /// the same light one step nearer — **identical hue, lower chroma, more
  /// light**. Against the frame under it (#05183F at the 1100 × 750 the app
  /// opens at, 220.11° / 84.4 % / Y 0.01066) this stop lands at 220.38° /
  /// 54.2 % / Y 0.02116: hue 0.27° off, chroma 5.7 8-bit steps down, luminance
  /// 1.173:1 up. *(Ticket 07 first shipped this stop at Y 0.01241 = 1.034:1;
  /// see the perceptibility re-solve below for why that number moved and the
  /// hue/chroma ones did not.)*
  ///
  /// **Re-solved with the frame's chroma, not merely re-measured.** It sat at
  /// 41.5 % while the frame beneath it sat at 46.8 % — a 5.4-point drop, about
  /// four 8-bit steps of channel spread. When the frame's chroma went up ~1.6×
  /// (2026-08-11) this stop had to follow, or the same four-step drop would
  /// have become a thirty-point chroma cliff at a corner that carries no
  /// border to explain it. It follows *only* at the seam: the plane's other
  /// two stops are untouched, and the chroma falls off inside the plane as a
  /// continuous ramp — which is a gradient, not an edge.
  ///
  /// **Why a constant and not a measurement.** The seam sits close enough to
  /// the frame gradient's origin (t ≈ 0.021–0.095 for every window from the
  /// enforced minimum to 4K) that the frame's color there moves by one to
  /// three 8-bit steps across that entire range — 1.8° of hue on dark. A
  /// `LayoutBuilder` would buy less than the quantisation of its own
  /// neighbourhood, so this stays a token like every other gradient here, and
  /// the `Frame → content-plane seam` group in `wcag_contrast_test.dart`
  /// walks the whole resize range to prove the constant holds at all of it.
  ///
  /// The seam lift is why end to end this now spans 1.027:1 rather than the
  /// 1.02:1 of Ticket 06 — the first stop rose toward the last. The plane's
  /// widest stop pair is the middle stop against the violet pole, 1.094:1.
  ///
  /// **Perceptibility re-solve (2026-08-11) — the whole plane moved, +12 8-bit
  /// steps on every channel of every stop.** Ticket 07's criteria gated the
  /// seam's *direction* (chroma falls, lightness rises) and its *continuity*
  /// (no chroma cliff) but never its *magnitude*, and the seam that satisfied
  /// them was invisible: the maintainer reported no perceivable transition at
  /// all. Measured, he was right — 1.034:1 at the corner is ΔL\* 0.47, at or
  /// under the just-noticeable difference, so the gate was passing on a step
  /// the eye cannot resolve.
  ///
  /// Worse, the corner was not the seam's worst point. The seam is an *edge
  /// with length*: along the top edge the plane's own gradient parameter
  /// sweeps toward its darkest middle stop while the frame above it brightens,
  /// and the step collapsed to **1.009:1** mid-edge. Sampling only the corner
  /// is what let that through, and the gate now sweeps both edges.
  ///
  /// Why a uniform additive offset rather than a re-pick: adding the same
  /// constant to all three channels leaves every pairwise channel difference
  /// intact, so hue and channel spread were preserved *exactly* while lightness
  /// rose and HSL saturation fell. Every one of Ticket 07's invariants was
  /// therefore not merely still satisfied but numerically unchanged. Only the
  /// thing that was broken moved. *(The stop values that lift produced were
  /// themselves rotated by ADR 0012, above; the technique is recorded because
  /// it is the reason the seam survived a lift, and the luminance-preserving
  /// rotation that followed is its counterpart in the other axis.)*
  ///
  /// Now: seam minimum **1.151:1 (ΔL\* 6.3)** along the whole edge at every
  /// window from the enforced minimum to 4K, 1.173:1 at the corner — thirteen
  /// times the ΔL\* of the step it replaces. The seam's hue gap runs
  /// 0.27–1.82° across the resize sweep and its chroma drop 5.2–5.9 steps,
  /// both inside the gate's 3° / 8-step bounds. For scale,
  /// the nav rail's approved icon chips read ≈1.24:1 (ΔL\* 8.7) at rest — but a
  /// chip is 38 px and this edge is the height of the window, and a luminance
  /// step over a long border is the easiest case there is to detect, so parity
  /// in ratio was never the target.
  ///
  /// ~~**What caps it: the magenta pole's saturation floor.** At +12 the third
  /// stop reads 15.6 % against the ambient floor of 15 %; +13 would fall
  /// under.~~ **Retracted 2026-08-11 (ADR 0012).** That cap was a property of
  /// the magenta pole, not of the lift: at 291° a nearly-neutral stop is
  /// measured against a `1 − |2L − 1|` divisor that grows as it lightens, so
  /// HSL saturation fell to the floor while the stop's channel spread — 14.0
  /// 8-bit steps — never moved. The pole is violet now, at 30.2 %, and the
  /// lift has no saturation cap left to argue with. What still holds from that
  /// analysis is the *other* bound it found: scaling the pole's chroma freely
  /// drives the plane's amplitude toward the frame's and breaks *The Two
  /// Ambients Rule*'s frame > 2 × plane gate. It is honoured here with margin
  /// (plane 0.027, frame 0.098).
  ///
  /// **What deliberately does not cap it: the card fills above.** An earlier
  /// pass stopped at +8 to preserve brightness headroom for [cardFill] /
  /// [cardFillElevated], which composite over this plane at a fixed 4.5:1
  /// floor. That was the wrong priority order — neither token is painted by
  /// any widget yet, so a defect the maintainer can see was being throttled to
  /// protect an unspent budget. The fills follow the plane instead; see their
  /// own doc comment for the ladder that cost.
  ///
  /// **The chroma is solved against the frame, not chosen.** The rail paints no
  /// ground of its own (see `WpSidebar`), so the window's most conspicuous edge
  /// is this plane meeting [frameGradient] down x = 72 and across y = 64. An
  /// earlier pass gated that seam at a single point and let the two arcs drift
  /// apart everywhere else: hue tracked to within 1.8° and luminance to within
  /// a steady 1.16:1, but the plane's chroma collapsed from 5.6 steps below the
  /// frame at the corner to **28 steps below** along the top edge. Same colour,
  /// same light, one surface vivid and its neighbour grey — which is precisely
  /// how the maintainer described it: the sidebar and the content did not look
  /// like one plane.
  ///
  /// These three stops are re-solved so the chroma *tracks* instead. Each keeps
  /// its hue and its luminance to the byte (saturation up, HSL lightness
  /// re-solved to hold Y), so every luminance-based seam gate is unchanged;
  /// what moves is the spread, from 52/29/32 steps to 60/60/50 — the middle
  /// stop, the plane's dead spot, doubles. Swept along the whole seam across
  /// all six gated window sizes the difference to the frame now stays inside
  /// **±4.0 steps**. The band is deliberately two-sided: the failure was
  /// divergence in *either* direction, and a one-sided "plane must be calmer"
  /// rule is what let a 28-step gap pass in the first place.
  ///
  /// The third stop is the one that looks under-solved and is not. On a 16:10
  /// window the seam only reaches t ≈ 0.70 and the stop could carry 63 steps;
  /// on an ultrawide it reaches far enough that the frame's own fourth stop
  /// (37 steps) is what the plane has to track, and a richer pole there
  /// re-opens the split at the far end of the top edge. It is solved for the
  /// widest gated window, not the default one.
  static const LinearGradient warmSurfaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF13274F), Color(0xFF171D53), Color(0xFF2E2153)],
    stops: [0.0, 0.5, 1.0],
  );

  /// The window frame — title bar, nav rail and status bar read as **one**
  /// light source falling from the top-left, not as a flat neutral hull.
  ///
  /// Diagonal on purpose, and on the *same* axis as
  /// [warmSurfaceGradient]: the frame and the content plane have to agree
  /// where the light comes from, or the seam between them reads as two rooms.
  /// The visible frame is an L of three strips, and this axis is what makes
  /// them one surface — the rail and the title bar both walk the first half of
  /// the ramp (bright at the top-left corner they share), the status bar walks
  /// the second (deepest at the far bottom-right, the corner furthest from the
  /// light).
  ///
  /// **Where it turned, and where it turned back.** It used to be a two-stop
  /// vertical ramp at 225°. Ticket 06 put it on a violet→magenta arc at
  /// 251° / 268° / 296° / 240° and re-solved its chroma upward at unchanged
  /// luminance (maintainer decision, 2026-08-11 — "the existing WhisPaste, seen
  /// through coloured glass"). **ADR 0012 then returned the hue family to the
  /// brand's blue/navy while keeping every bit of that material quality.**
  /// Measured now: **218° / 230° / 245° / 256°, saturation 85 % / 81 % / 76 % /
  /// 65 %** — a navy→violet arc, still roughly 1.6× the pre-Ticket-06 chroma,
  /// with the violet where the room is deepest.
  ///
  /// **Why the saturation numbers went *up* while the room got calmer.**
  /// Chroma is compared here in channel spread (max − min, in 8-bit steps), the
  /// metric this file uses wherever lightness differs; HSL points are not
  /// comparable across hues at a fixed luminance. The violet arc carried
  /// 72 / 52 / 31 / 28 steps. This one carries **57 / 61 / 56 / 37** at 10
  /// points more HSL saturation, because the blue corner of sRGB is simply
  /// darker per unit chroma: holding Ticket 06's luminance means a blue cannot
  /// reach a violet's byte count at any saturation. The higher percentages buy
  /// back most of the difference, they do not add loudness.
  ///
  /// **The fourth stop is no longer an exception.** ~~It is a cool shadow, held
  /// clear of [recordingAccent] by 50.5° of hue and a 52 % saturation
  /// ceiling.~~ *Retracted 2026-08-11 with ADR 0012* — that stop existed to
  /// smuggle the brand's blue into a violet room, and the room is the brand's
  /// blue now, so the carve-out has nothing left to carve. It keeps its place
  /// as the arc's deepest continuation and its only remaining obligations are
  /// the ones every ambient stop has: it must be the *deepest* stop (the
  /// amplitude gate measures first-against-last and would span the wrong pair
  /// otherwise) and it must stay under 1.5:1 against its neighbour, the
  /// threshold at which atmosphere becomes a drawn object. It sits at 1.018:1.
  /// Four stops rather than three because the visible frame is an L of three
  /// strips that between them walk the whole ramp, and the arc needs room to
  /// turn twice.
  ///
  /// **Why a blue ambient is not a second cyan signal.** The first stop sits
  /// 28.4° from [recordingAccent] — inside the 45° radius the retracted rule
  /// used. Hue distance was never what separated them: this is a large,
  /// borderless, motionless field at Y 0.011, and the signal is a small bright
  /// mark at Y 0.476. Every ambient stop clears it by ≥ 7.4:1 in luminance, and
  /// that ratio is the gate (`Ambient vs. the recording signal`). The app
  /// shipped navy-ambient with a cyan accent for its entire life before Ticket
  /// 04 and no one mistook one for the other.
  ///
  /// **Why it may be the louder of the two ambients.** End to end it spans
  /// 1.098:1 where the content plane spans 1.027:1 — the deliberate role
  /// reversal of Ticket 06. The frame is the room; the content plane is the
  /// sheet lying in it, and a sheet that patterned itself as strongly as the
  /// room would compete with what is printed on it. Both halves are gated in
  /// `wcag_contrast_test.dart`.
  ///
  /// **Why it stays darker than the content plane.** Mean relative luminance
  /// 0.0081 against the plane's 0.0204 — so the plane still reads as raised,
  /// which on dark is the *only* depth source there is (no card shadow token
  /// exists here). Livening the frame therefore happens by chroma alone, never
  /// by brightening it past the thing it carries: every stop keeps the
  /// luminance Ticket 06 solved for it. Opaque tonal steps, no alpha glow.
  static const LinearGradient frameGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF051A3E),
      Color(0xFF071144),
      Color(0xFF0E0941),
      Color(0xFF140A2F),
    ],
    stops: [0.0, 0.42, 0.74, 1.0],
  );

  /// Top accent line gradient — anchored at [accent], falling 1.247:1.
  ///
  /// That span is the pre-Ticket-04 ramp's, re-solved rather than lifted, for
  /// the reason spelled out on [accentWarmGradient].
  ///
  /// **Nothing paints it today.** No widget reads this token; the onboarding
  /// steps that look like they do build their own local ramps in local
  /// variables that happen to share the name. It is kept because it is public
  /// API and because a two-stop accent ramp is the obvious thing for the next
  /// caller to reach for — but it is carried forward on the same arithmetic as
  /// its used sibling rather than left to rot at a stale hue.
  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFF6FDDF0), Color(0xFF4AC7EA)],
  );

  /// The interactive gradient — cyan descending into teal, rich and saturated.
  ///
  /// Back on the brand arc with [accent] (ADR 0013). Ticket 04's violet→magenta
  /// ramp is retired and this is the pre-Ticket-04 cyan ramp — but re-solved,
  /// not lifted. A first pass raised all three stops by one constant lightness
  /// offset, which is what a hue rotation must *not* do: the bright end ran into
  /// the ceiling and the arc collapsed from 1.737:1 end to end to 1.207:1. In a
  /// palette being corrected for reading flat, on the token that paints primary
  /// buttons, that is the defect wearing the fix's clothes.
  ///
  /// So the *shape* is what carries over, and the numbers are re-derived under
  /// it. Stop 0 is [accent] exactly; stops 1–2 keep the old ramp's hue and
  /// saturation and have their lightness solved to reproduce the old ramp's
  /// internal contrasts (1.231:1, then 1.411:1 — 1.739:1 overall against the
  /// original 1.737:1). The pleasing part fell out rather than being aimed at:
  /// every stop lands 1.22:1 over the matching stop of
  /// [recordingAccentGradient], the same constant that separates the two flat
  /// tokens. The gradients are siblings by the identical margin their anchors
  /// are, without that having been imposed stop by stop.
  ///
  /// Anchoring at the flat accent rather than at a darker teal is deliberate and
  /// unchanged: this gradient also paints the 3 px sidebar and section indicator
  /// bars, and a dark first stop would drop those from ≈7:1 to ≈4:1 against
  /// their grounds app-wide.
  static const LinearGradient accentWarmGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6FDDF0), Color(0xFF1ACBE9), Color(0xFF0BAACC)],
  );

  /// Nav-rail icon chip, resting — the rail's icons stand on **material**, not
  /// on bare frame.
  ///
  /// Three stops on one vertical axis, and the first two are one idea: a
  /// *precomposited* top gloss (27 % of the [cardEdgeHighlight] tint over the
  /// first tenth of the tile) over a frost fill falling 17.6 % → 12.2 %. The
  /// gloss is what a 1px edge highlight would be if the tile were a card —
  /// baked into the gradient instead of drawn as a second border, because a
  /// non-uniform `Border` and a `borderRadius` cannot coexist in Flutter.
  ///
  /// **This is a glow the *Depth-Source Rule* allows.** No colored shadow at
  /// offset 0 is involved anywhere: the bloom is fill, chroma and a lit top
  /// edge, and on dark the tile's own brightness delta against the frame
  /// (≈1.24:1) is the whole depth source, exactly as it is between the card
  /// fills.
  ///
  /// **It marks nothing.** Every rail item wears one, resting or not, so the
  /// tile is material rather than a state — which is what keeps
  /// [navPillActiveGradient] the single marking of selection (*The One
  /// Highlight Per State Rule*).
  static const LinearGradient navChipGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x45A190D5), Color(0x2DA190D5), Color(0x1FA190D5)],
    stops: [0.0, 0.1, 1.0],
  );

  /// Nav-rail icon chip, hovered — the same tile one step brighter (25 % →
  /// 18 % frost under a 36 % [cardEdgeHighlight] gloss), ≈1.12:1 over
  /// [navChipGradient].
  ///
  /// Deliberately carries no accent: hover says "you can act on this", the
  /// accent-tinted tile says "you are here", and a hover that borrowed the
  /// accent would make the two states one.
  static const LinearGradient navChipGradientHover = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x5CD7C8F9), Color(0x40A190D5), Color(0x2EA190D5)],
    stops: [0.0, 0.1, 1.0],
  );

  /// Nav-rail active chip — the same tile in the accent's hue: 22 % accent at
  /// the top falling to 15 % at the bottom, under a 34 % [accentHover] gloss.
  ///
  /// **Re-solved upward with the chip (Ticket 07).** It used to be 20 % → 12 %
  /// (mean 16 %, matching the flat [accentSubtle] it replaced), calibrated
  /// against *bare frame*. Its ground is now [navChipGradient], so the same
  /// alphas would have bought a 1.09:1 step where the old one bought 1.5:1 —
  /// the state would have survived the audit and lost its voice. Ticket 07
  /// solved that at **1.40:1 over the resting tile**, and that ratio, not the
  /// alphas that produced it, is what this token owes.
  ///
  /// **Re-solved again for the cyan accent (ADR 0013), downward this time.**
  /// Cyan is far more luminous than the violet it replaces (Y 0.614 against
  /// 0.354), so carrying Ticket 07's 56/36/25 alphas across unchanged pushed
  /// the marker to 2.27:1 over its resting sibling — a 62 % overshoot of a
  /// deliberately solved value, arrived at by nobody's decision. All three
  /// alphas are therefore scaled by one factor (0.608), which preserves the
  /// gloss-to-fill structure while restoring the ratio: 1.40:1 over the resting
  /// tile, 1.90:1 over the frame. *The One Highlight Per State Rule* asks the
  /// marker to be unmistakable, not maximal.
  ///
  /// Still deliberately *not* [accentWarmGradient]: that one is opaque, and an
  /// opaque accent fill would swallow the tile's ground rather than tint it.
  static const LinearGradient navPillActiveGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x57A7EAF6), Color(0x386FDDF0), Color(0x276FDDF0)],
    stops: [0.0, 0.1, 1.0],
  );
}

// ---------------------------------------------------------------------------
// Light Theme Colors
// ---------------------------------------------------------------------------
abstract final class WpColorsLight {
  /// Window frame — pearl-violet tint for brand identity; the light twin of
  /// Dark's deep violet-navy.
  ///
  /// Same operation as [WpColorsDark.background]: hue turned from ~214° to
  /// ~260° at unchanged HSL lightness, so *Frame–content unity* (≤ 5 % gap on
  /// light) holds by construction rather than by re-tuning the gate.
  ///
  /// The chroma of the whole light stack is *capped*, not chosen: rotating a
  /// pearl from blue toward violet moves weight out of the green channel, and
  /// green carries 71.5 % of relative luminance. At the old saturations the
  /// violet pearls dropped [textMuted] below AA on three grounds. So every
  /// light surface sits as close to the ratified 15 % tint floor as the gates
  /// allow — the cap is [textMuted]'s AA headroom on pearl, not taste. Dark
  /// has no such cap and keeps its full chroma. That asymmetry is what *The
  /// Increment–Decrement Rule* in `lib/DESIGN.md` closes with — "a new theme
  /// asymmetry is allowed, but it argues for itself at the token" — and this
  /// paragraph is the argument.
  static const Color background = Color(0xFFEFEDF3);

  /// Content surfaces — cool pearl-white with a visible violet tint (not
  /// sterile white)
  static const Color surface = Color(0xFFF6F5F9);

  /// Elevated panels, cards — lighter than surface, still clearly tinted
  static const Color surfaceElevated = Color(0xFFFAF9FB);

  /// Variant surface for alternate rows, secondary panels
  static const Color surfaceVariant = Color(0xFFF1EFF4);

  /// Hover and press rungs — see [WpColorsDark.hover] for why they move with
  /// the surfaces instead of staying behind on the old hue.
  static const Color hover = Color(0xFFEBE8F0);

  /// Transparent version of hover for smooth AnimatedContainer transitions
  /// (prevents flash when interpolating from transparent to hover)
  static const Color hoverTransparent = Color(0x00EBE8F0);
  static const Color active = Color(0xFFE0DCE7);

  /// Hairline borders — navy-ink at 7.8 % / 14.1 %, a step *under* dark's
  /// 11.8 % / 18.8 %. Same reason as [accentSubtle] below, and the reason is
  /// independent of size: an ink hairline on pearl is a decrement on a bright
  /// ground and reads harder per unit alpha than a white hairline does as an
  /// increment on navy. Matching the bytes would leave the light theme visibly
  /// more ruled than the dark one.
  static const Color borderSubtle = Color(0x140F172A);
  static const Color borderDefault = Color(0x24131F32);

  /// Hairline of an *active* card tile — the one border pair that carries the
  /// same alpha byte (14.1 %) in both themes instead of stepping dark above
  /// light. An active card already sits on the lifted `hover` fill, so its
  /// hairline only has to separate two surfaces that already differ; the
  /// increment dark normally needs is bought by the fill underneath it.
  ///
  /// Replaces the former `glassBorder`, which survived the deleted glass
  /// family on dark only and left this call site pairing a glass token against
  /// an ink one. Values are unchanged in both themes — this is a rename into
  /// a proper theme pair, not a re-tune.
  static const Color cardActiveBorder = Color(0x24131F32);

  /// Strong text contrast for light theme
  static const Color textPrimary = Color(0xFF101828);
  static const Color textSecondary = Color(0xFF44556E);
  static const Color textMuted = Color(0xFF5B697E);

  /// Deep violet accent — the same 258° hue as Dark's #AF8EFA, darkened for
  /// WCAG AA on pearl (5.84:1 against `surface`, 5.46:1 against `background`).
  ///
  /// Solved for *relative-luminance parity* with the teal it replaces
  /// (Y ≈ 0.1157, byte-identical in effect): every light tint rung, the
  /// nav pill's 14/8 % pair and [decorativeGlyphWash] were calibrated against
  /// that luminance, so the whole light ladder keeps its optical weight
  /// without a single alpha being re-tuned. Dark cannot have that parity — the
  /// old cyan sat at Y ≈ 0.49 and matching it would have forced a near-white
  /// lavender — so the dark ladder resolves a little quieter than before. That
  /// is a deliberate consequence, not an oversight.
  static const Color accent = Color(0xFF6B35E9);

  /// Flat accent surface tint, 11 % — a step under dark's 16.5 %, and the
  /// canonical statement of why every *structural* translucent in this file
  /// runs lighter on light (*The Increment–Decrement Rule*, `lib/DESIGN.md`).
  ///
  /// A tint does not buy the same presence in both themes. On light it lands
  /// *darker* than its ground — a decrement, resolved at full contrast against
  /// a bright surface; on dark it lands *lighter* — an increment against a
  /// near-black surface, where the display's black floor and any reflected
  /// room light eat most of the difference. Equal alpha bytes therefore read
  /// visibly unequal, light heavier, so the light side is tuned down instead
  /// of copied across. Same argument, already applied: [navPillActiveGradient]
  /// (16 % → 11 % mean, pinned to exactly this token) and
  /// [decorativeGlyphWash] (5 % → 3 %).
  ///
  /// The tint ladder is the deliberate carve-out: its rungs stay byte-identical
  /// across themes because they are a cross-hue *semantic* scale — 6 % is
  /// "hover" and 30 % is "outline" whatever the hue, whatever the theme — and
  /// re-tuning them per theme would break the guarantee that a destructive
  /// control's states carry exactly the weight of an accent one's.
  static const Color accentSubtle = Color(0x1C6B35E9); // accent @ 11%

  /// Instance-safe tint tokens — see [WpColorsDark.accentChipFill] for rationale.
  static const Color accentChipFill = Color(0x1A6B35E9); // accent @ 10%
  static const Color accentChipFillHover = Color(0x2E6B35E9); // accent @ 18%
  static const Color accentMiniTagFill = Color(0x1F6B35E9); // accent @ 12%
  static const Color accentBorder30 = Color(0x4D6B35E9); // accent @ 30%
  static const Color accentButtonFill = Color(0x146B35E9); // accent @ 8%
  static const Color accentActiveFill = Color(0x1F6B35E9); // accent @ 12%
  static const Color accentBadgeFill = Color(0x266B35E9); // accent @ 15%
  static const Color accentBorder20 = Color(0x336B35E9); // accent @ 20%
  static const Color accentRowHover = Color(0x0F6B35E9); // accent @ 6%
  static const Color surfaceChipFill = Color(0x80F6F5F9); // surface @ 50%
  static const Color surfaceMutedFill = Color(0x145B697E); // textMuted @ 8%

  /// Precomposited frost — see [WpColorsDark.cardFill] for the material.
  ///
  /// The light twin runs the *other* direction, as the ground demands: on
  /// pearl a card is a lift toward white, not toward the accent, so the tint
  /// is a violet-white rather than a lavender. It still carries hue in the
  /// value (#FAF7FF / #FDFAFF, never `0x..FFFFFF`) — a plain white alpha here
  /// would bleach the ambient's violet out of the card and leave the same grey
  /// the dark theme was failing at.
  ///
  /// The alphas run *higher* than dark's 8/14 %, which is not a violation of
  /// *The Increment–Decrement Rule* but its consequence: these are not tints
  /// laid over a ground to tint it, they are the card's own body, and on pearl
  /// the card's body is nearly the ground's own value.
  static const Color cardFill = Color(0xCCFAF7FF); // frost tint @ 80%
  static const Color cardFillElevated = Color(0xE6FDFAFF); // frost tint @ 90%

  /// The card's static 1px top edge — see [WpColorsDark.cardEdgeHighlight].
  /// Lifts its fill by ≈1.02:1 here; on pearl there is barely any room above
  /// the card left, which is exactly why light gets a shadow and dark does not.
  static const Color cardEdgeHighlight = Color(0xCCFFFCFF);

  /// The light theme's one depth source: a soft, wide, violet-tinted shadow
  /// (≈`0 10px 35px rgba(40,20,70,0.08)`, wired up as
  /// `WpShadows.cardTintedLight`).
  ///
  /// Tinted, not neutral black — a black shadow under a violet card greys the
  /// pearl around it, which is the same failure mode as a white-alpha fill,
  /// one layer down. **Deliberately has no dark counterpart**: on near-black
  /// a shadow adds mud instead of depth, so dark reads its depth off the
  /// brightness delta between the card fills. A `WpColorsDark.cardShadow` is
  /// not missing here — it is refused. One depth source per theme; the split
  /// is stated in the library header, not yet named in `lib/DESIGN.md`.
  static const Color cardShadowLight = Color(0x14281446);

  /// Transient settings-search locator ring — see
  /// [WpColorsDark.accentLocatorRing], including why this one alpha is *not*
  /// tuned down for light the way the structural tints are.
  static const Color accentLocatorRing = Color(0x8C6B35E9); // accent @ 55%

  /// Recording/listening family — see [WpColorsDark.recordingAccent] for the
  /// split's rationale. Same deal on light: byte-for-byte copies of [accent]
  /// and [accentWarmGradient], written as literals so the recording signal
  /// stays put when the generic accent family changes hue.
  static const Color recordingAccent = Color(0xFF06678A);

  /// Gradient twin of [recordingAccent] — teal to deep teal, copied from
  /// [accentWarmGradient]. See [WpColorsDark.recordingAccentGradient] for why
  /// the family reserves a gradient it does not paint yet.
  // loam-ignore: unused-public-exports – see WpColorsDark.recordingAccentGradient.
  static const LinearGradient recordingAccentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF06678A), Color(0xFF0E7490), Color(0xFF155E75)],
  );

  /// Wash for a large decorative background glyph — its own category, *below*
  /// the 6/12/30% tint ladder above, because that ladder is defined for
  /// badges, chips and borders: small, bounded shapes the user is meant to
  /// read. A 140px glyph bleeding out of a card corner is neither, and the
  /// ladder's bottom rung is too loud once it covers that much area.
  ///
  /// The alpha is lower here than on dark, and deliberately so — the same
  /// alpha does not buy the same presence in both themes. On light the wash
  /// lands *darker* than its ground (a decrement, which the eye resolves at
  /// lower contrast); on dark it lands *lighter* (an increment), against a
  /// near-black surface where a display's black floor and any reflected room
  /// light eat most of the difference. Equal alphas therefore read unequal —
  /// light visibly stronger — which is exactly what the model step showed.
  /// Both values still sit clearly under the ladder's 6% floor.
  static const Color decorativeGlyphWash = Color(0x086B35E9); // accent @ 3%

  /// Danger/off-brand-neutral tint ladder — see [WpColorsDark.errorRowHover]
  /// for rationale.
  static const Color errorRowHover = Color(0x0FCC1C1C); // error @ 6%
  static const Color errorButtonFill = Color(0x14CC1C1C); // error @ 8%
  static const Color errorActiveFill = Color(0x1FCC1C1C); // error @ 12%
  static const Color errorBorder20 = Color(0x33CC1C1C); // error @ 20%
  static const Color errorBorder30 = Color(0x4DCC1C1C); // error @ 30%
  static const Color mutedRowHover = Color(0x0F5B697E); // textMuted @ 6%
  static const Color mutedActiveFill = Color(0x1F5B697E); // textMuted @ 12%

  static const Color success = Color(0xFF05875C);
  static const Color warning = Color(0xFFC97A06);
  static const Color error = Color(0xFFCC1C1C);

  /// 12 % status badge rungs — see [WpColorsDark.successActiveFill].
  static const Color successActiveFill = Color(0x1F05875C); // success @ 12%
  static const Color warningActiveFill = Color(0x1FC97A06); // warning @ 12%

  /// Premium pearl-violet card gradient — subtle diagonal wash
  static const LinearGradient surfaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF8F7FB), Color(0xFFF3F1F6)],
  );

  /// The light ambient — a pearl-violet cool pole top-left, a slightly deeper
  /// violet mid-stop, a pearl-magenta pole bottom-right. Mirrors
  /// [WpColorsDark.warmSurfaceGradient] in shape and in the direction of its
  /// hue arc — measured 260° → 255° → 285° — at a fraction of its amplitude:
  /// luminance stays within 1.04:1 across all three stops, so the drift reads
  /// as a temperature shift on pearl rather than a color cast. Opaque tonal
  /// steps, no alpha glow. This is the ground every light card fill is gated
  /// against.
  ///
  /// **The first stop is the seam** — see the dark twin for the full argument;
  /// this is its pearl solution. Against the frame at (72, 64) (#F5F1FC at
  /// the 1100 × 750 the app opens at, 259.92° / 61.2 % / Y 0.89504) it lands
  /// at 260.0° / Y 0.95481: hue 0.05° off, chroma 4.5 8-bit steps down,
  /// luminance 1.065:1 up. *(Ticket 07 first shipped this stop at Y 0.92044 =
  /// 1.029:1; see the perceptibility re-solve below.)* The residual hue gap is
  /// a *floor*, not a tolerance
  /// — at L ≈ 97 % a single 8-bit step is worth several degrees of hue, the
  /// same quantisation ceiling [frameGradient] argues for its own stops.
  ///
  /// **Re-solved with the frame's chroma (2026-08-11).** It sat at 20.0 % under
  /// a 39.5 % frame; both went up together when the frame's chroma did, so the
  /// drop across the seam stays the ~4½ 8-bit steps of channel spread Ticket 07
  /// ratified rather than doubling into a visible edge. Pearl flatters this:
  /// at L ≈ 97 % the divisor `1 − |2L − 1|` is ≈ 0.06, so eighteen *points* of
  /// HSL saturation are four bytes of actual color.
  ///
  /// **This stop no longer equals [surface].** Until Ticket 07 the two were
  /// the same value (#F6F5F9) and this comment read the plane as anchored on
  /// the surface token. That was a coincidence of tuning, not a derivation:
  /// the plane's first stop answers to the frame beneath it, [surface] answers
  /// to the opaque tonal stack, and the two have drifted apart accordingly —
  /// two 8-bit steps of blue and one of red since the frame's chroma rose. The
  /// dark twin still anchors on [surface] — at its *middle* stop, where
  /// nothing reads it against the frame. ~~*(dark anchor)*~~ **Retracted
  /// 2026-08-11:** the dark twin has since dropped that anchor too, for the
  /// same reason this one did. See [WpColorsDark.warmSurfaceGradient].
  ///
  /// **Perceptibility re-solve (2026-08-11) — +4 8-bit steps on every channel,
  /// and this plane is now at its physical ceiling.** The dark twin carries the
  /// full argument: Ticket 07 gated the seam's direction and continuity but
  /// never its magnitude, and the result was invisible — 1.029:1 is ΔL\* 0.94,
  /// under the just-noticeable difference. Same uniform additive offset, so
  /// hue (260.0° / 255.0° / 285.0°) and channel spread survive bit for bit and
  /// every Ticket 07 invariant is numerically unchanged.
  ///
  /// Unlike dark, pearl cannot be lifted to a comfortable value, and it is
  /// worth being exact about why rather than filing the shortfall as a weaker
  /// choice. The first stop is now **#FBF9FF, and its blue channel landed on
  /// 0xFF exactly** (0xFB + 4). That is what makes +4 the ceiling and not a
  /// taste call: one more step would clip that channel alone, and a *clipped*
  /// offset is no longer a uniform one — the moment blue stops moving with
  /// red and green, the pairwise channel differences change and this token
  /// loses the very hue-and-spread preservation the whole method rests on.
  /// The lift stops where the arithmetic stops being lossless. The seam reads
  /// **1.060:1 minimum (ΔL\* 2.3)** along the edge, 1.065:1 at the corner:
  /// 2.5 × the old step, and the most this plane can give while the frame
  /// stays where it is. Even a literally white plane would only reach 1.113:1,
  /// because the frame at the seam sits at Y ≈ 0.894 — the ceiling is the
  /// *frame's* brightness, and the frame's own deepest stop is pinned 0.007
  /// above the luminance at which [textMuted] loses AA on it. **Going past
  /// ≈1.06:1 on pearl is a decision about [frameGradient], not a tuning pass
  /// on this token**, and it is deliberately left open rather than taken here.
  ///
  /// Two things that do *not* work, tried and measured, so they are not
  /// re-tried: buying luminance by narrowing the plane's channel spread (at
  /// 4–6 bytes one LSB is worth ~10–15° of hue, so the seam's 3° hue tolerance
  /// blows out to 9°, 20°, 41°, and then to a fully achromatic stop), and
  /// reading the chroma direction in HSL saturation (see the seam group in
  /// `wcag_contrast_test.dart`: as these stops approach white the divisor
  /// `1 − |2L − 1|` collapses and HSL saturation *rises* to 100 % on a stop
  /// carrying six bytes of color, while the frame beneath it carries eleven).
  static const LinearGradient warmSurfaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFBF9FF), Color(0xFFF7F6FA), Color(0xFFF8F5F9)],
    stops: [0.0, 0.5, 1.0],
  );

  /// The light twin of [WpColorsDark.frameGradient] — same diagonal, same
  /// top-left light source, four stops on the same arc (measured 258° / 268° /
  /// 288° / 247°), at a fraction of its amplitude.
  ///
  /// **Left on the Ticket-04 violet arc on purpose.** ADR 0012 returned the
  /// *dark* ambient to the brand's blue/navy and is explicitly scoped to dark
  /// only, because the light theme is being removed wholesale by a parallel
  /// ticket. These stops therefore no longer twin their dark counterparts in
  /// hue, only in shape — a temporary, documented break of *The Theme-Pair
  /// Rule* that resolves when the theme goes.
  ///
  /// Same correction, too: the old stops sat at 212–215°, pearl-*blue*, left
  /// behind by the violet turn and 45° off the pearl everything else stands
  /// on.
  ///
  /// **Chroma is bought sideways here, not downward** (2026-08-11). Saturation
  /// went 41 / 33 / 26 % → **63 / 57 / 59 / 56 %** without spending the
  /// luminance budget, because on pearl chroma can be taken by pushing red and
  /// blue apart while green — 71.5 % of relative luminance — barely moves. The
  /// budget is real and it is [textMuted]'s: it needs a ground at relative
  /// luminance ≥ 0.798 to hold 4.5:1, and the frame is exactly where the
  /// status bar and the nav rail's resting icons put it. The deepest stop
  /// lands at 0.805 (4.54:1). The dark twin has no such cap and takes its
  /// chroma straight.
  ///
  /// **Amplitude.** 1.11:1 end to end against the content plane's 1.04:1, so
  /// the frame is still the livelier of the two ambients — that is *The
  /// Increment–Decrement Rule*'s sanctioned asymmetry arguing for itself at the
  /// token, exactly as [background] does.
  ///
  /// Mean relative luminance 0.847 against the content plane's 0.900: on
  /// pearl, raised means brighter, so the plane again sits above its room.
  ///
  /// ~~**The fourth stop is the cool shadow**, clearing this theme's
  /// [recordingAccent] (196°) by 50.8° at 56 % saturation.~~ *Retracted
  /// 2026-08-11 with ADR 0012* — see [WpColorsDark.frameGradient] for why the
  /// carve-out dissolved. The stop and its value stay exactly where they are;
  /// it is now simply the arc's deepest continuation, and it reads more plainly
  /// here than on dark, where the same corner sits near black.
  static const LinearGradient frameGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFF5F2FC),
      Color(0xFFF3EDFA),
      Color(0xFFF4E4F8),
      Color(0xFFE8E6F8),
    ],
    stops: [0.0, 0.42, 0.74, 1.0],
  );

  /// The interactive gradient — violet to magenta, the light twin of
  /// [WpColorsDark.accentWarmGradient]: same 258° → 271° → 285° arc, each stop
  /// solved back toward the relative luminance its teal predecessor carried
  /// (old 0.1157 / 0.1460 / 0.0945 → new 0.1156 / 0.1429 / 0.0968 — the first
  /// stop is parity, the other two land within ~2 %, which is where the hue
  /// arc and 8-bit quantisation leave them). Buttons and indicator bars
  /// therefore keep their weight on pearl.
  static const LinearGradient accentWarmGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6B35E9), Color(0xFF8F3CDD), Color(0xFF882AA7)],
  );

  /// Nav-rail icon chip, resting — see [WpColorsDark.navChipGradient].
  ///
  /// **Pearl has a ceiling the dark theme does not.** The frame under the rail
  /// already sits at relative luminance ≈0.90, so a tile can be at most
  /// ≈1.06:1 brighter than it no matter what it is filled with; at 80 % → 70 %
  /// of a violet-white this one reaches ≈1.03:1. The tile's objecthood is
  /// therefore carried by the other two channels the *Depth-Source Rule*
  /// gives the light theme: the offset shadow (`WpShadows.subtleLight`, which
  /// the dark theme deliberately does without) and a [borderDefault] hairline
  /// rather than the [borderSubtle] one dark can afford — the same argument
  /// the rail's own group divider already makes, that a subtle hairline on a
  /// 38 px shape reads as a rendering artifact.
  static const LinearGradient navChipGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xF2FFFCFF), Color(0xCCFAF7FF), Color(0xB3F7F3FE)],
    stops: [0.0, 0.1, 1.0],
  );

  /// Nav-rail icon chip, hovered — see [WpColorsDark.navChipGradientHover].
  ///
  /// Light hovers the tile *downward* into violet (90 % → 80 % of a pearl
  /// violet) where dark hovers it upward into light. That is not a stylistic
  /// mirror but the pearl ceiling again: there is ≈0.03 of luminance left
  /// above the resting tile and 1.07:1 available below it, so the perceptible
  /// step is the one that exists. *The Increment–Decrement Rule*, taken to its
  /// literal end.
  static const LinearGradient navChipGradientHover = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFAFFFCFF), Color(0xE6F3ECFE), Color(0xCCEFE7FD)],
    stops: [0.0, 0.1, 1.0],
  );

  /// Nav-rail active chip — see [WpColorsDark.navPillActiveGradient].
  ///
  /// Light keeps its own, lower alpha pair (20 % → 12 %, mean 16 %) rather than
  /// reusing the dark stops (36 → 25): the deep accent on a near-white pearl
  /// surface reads heavier per unit alpha than the light violet on violet-navy
  /// does. Both were re-solved together when the resting tile became their
  /// shared ground; the light pair lands 1.31:1 over it.
  static const LinearGradient navPillActiveGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xCCFDFAFF), Color(0x336B35E9), Color(0x1F6B35E9)],
    stops: [0.0, 0.1, 1.0],
  );
}

// ---------------------------------------------------------------------------
// Reusable glass decoration builder
// ---------------------------------------------------------------------------

/// Theme-independent accents used identically in light and dark — a sanctioned
/// exception to the per-theme token split above, for colors chosen for
/// user-facing variety/recognition rather than surface hierarchy.
abstract final class WpSharedColors {
  /// Pinned/favorited-item accent (star icon, toggle). Amber reads as
  /// "favorite" cross-platform regardless of theme, like a star rating.
  static const Color pinnedAccent = Color(0xFFFFB300); // Colors.amber.shade600
}

// ---------------------------------------------------------------------------
// Category slots — the nominal color layer
// ---------------------------------------------------------------------------

/// The nine category slots, in palette order — eight interchangeable *category*
/// hues plus one dedicated [neutral] fallback.
///
/// **The contract.** A category color is never picked at a call site. A widget
/// asks [categorySlotForModel] or [categorySlotForTag] for a slot, or reaches
/// for [neutral] when the thing it paints has no category at all — and only
/// then resolves the slot to a [Color] through [color]. The indirection *is*
/// the feature: it makes a hue a statement about the data rather than
/// decoration, and it is the thing a later reader can grep to find out what a
/// color means. Painting one of the constants below directly is the same defect
/// as hand-rolling an alpha.
///
/// **The one sanctioned decorative user** is the history-entry avatar, which
/// indexes [categories] with the slot persisted on the entry. It is bounded the
/// same way: no call site picks the hue there either, and the hue claims no
/// meaning at all — see `historyAvatarSlot` and *The Categorical vs. Sequential
/// Rule* in `lib/DESIGN.md`.
///
/// **Why a slot and not a [Color].** The slot is theme-independent, the color
/// is not. Anything that caches an identity's color must cache the *slot* and
/// resolve it inside `build()`; caching the resolved color leaves the old
/// theme's hue on screen after a runtime theme switch.
///
/// **[neutral] is not a ninth category.** Untitled/uncategorised is the *normal*
/// case in a dictation app, not an edge case, and it must not disguise itself
/// as a category — so it gets its own near-achromatic slot and is deliberately
/// excluded from [categories], i.e. from every hash. Nothing ever lands on
/// neutral by accident; a call site asks for it explicitly.
enum WpCategorySlot {
  iris,
  ember,
  fern,
  orchid,
  brass,
  azure,
  plum,
  moss,
  neutral;

  /// The eight hashable category slots — [neutral] excluded on purpose.
  static const List<WpCategorySlot> categories = [
    iris,
    ember,
    fern,
    orchid,
    brass,
    azure,
    plum,
    moss,
  ];

  /// Resolves this slot against the active theme. The only sanctioned way from
  /// a slot to a paintable color.
  Color color(bool isDark) => (isDark
      ? WpCategoryColorsDark.slots
      : WpCategoryColorsLight.slots)[index];

  /// *The Tint Ladder Rule*'s 12 % fill rung, in this slot's hue.
  ///
  /// A rung rather than a call-site alpha, but computed rather than declared:
  /// the ladder's other hues are one token family each because they are one
  /// hue each — nine slots × two rungs × two themes would be 36 constants
  /// restating one number. The ladder's guarantee is that the *weight* is
  /// shared across hues, and that is exactly what these two methods carry.
  Color chipFill(bool isDark) => color(isDark).withValues(alpha: 0.12);

  /// *The Tint Ladder Rule*'s 30 % outline rung, in this slot's hue. See
  /// [chipFill].
  Color chipBorder(bool isDark) => color(isDark).withValues(alpha: 0.30);

  /// A [steps]-step **sequential** ramp in this slot's hue — the ordinal half
  /// of *The Categorical vs. Sequential Rule*.
  ///
  /// Ordered data (a duration distribution, a ranked tier) gets one hue at
  /// several weights, never several hues: a reader who sees eight hues on a
  /// ranked axis has to learn an arbitrary order, where one hue at rising
  /// weight already carries it. `steps` is capped at the rule's own 3–5 so the
  /// cap is executable rather than advisory.
  ///
  /// **Step 0 is the slot itself, and the ramp climbs *away* from the ground.**
  /// On dark it lightens, on light it darkens — which means every rung clears
  /// the surfaces by at least as much as the base slot does, and the 3:1 floor
  /// for a graphical object is inherited rather than re-argued per rung. A ramp
  /// laid symmetrically around the slot would sink its low end under that floor
  /// on light.
  ///
  /// **The axis is luminance, not HSL lightness**, because the palette itself is
  /// built on equal relative luminance (see [WpCategoryColorsDark]). Each rung
  /// sits a fixed [_rampStepContrast] contrast ratio from the one before it, so
  /// the rungs are exactly as separable in `moss` as in `plum` — equal steps of
  /// HSL lightness are not, and collapse into each other on the slots that
  /// already sit low. Solving in linear light also makes the step a closed form
  /// instead of a search.
  ///
  /// The two themes mirror rather than share, as everywhere else in this file:
  /// lightening on dark blends toward white and therefore desaturates a little,
  /// while darkening on light is a pure luminance scale that leaves the
  /// chromaticity — and so the hue's identity — untouched.
  ///
  /// Verified per slot, per theme and per step count in
  /// `test/core/theme/wcag_contrast_test.dart`: neighbouring rungs stay ≥ 1.2:1
  /// apart and every rung clears every surface by ≥ 3:1.
  List<Color> ramp(int steps, bool isDark) {
    assert(
      steps >= 3 && steps <= 5,
      'a sequential ramp carries 3–5 steps (The Categorical vs. Sequential '
      'Rule); $steps rungs is a scale the eye can no longer order',
    );
    final base = color(isDark);
    final baseLuminance = base.computeLuminance();
    final r = _srgbToLinear(base.r);
    final g = _srgbToLinear(base.g);
    final b = _srgbToLinear(base.b);

    final rungs = <Color>[base];
    var offsetLuminance = baseLuminance + 0.05;
    for (var i = 1; i < steps; i++) {
      offsetLuminance = isDark
          ? offsetLuminance * _rampStepContrast
          : offsetLuminance / _rampStepContrast;
      final target = offsetLuminance - 0.05;
      if (isDark) {
        // Blend toward white in linear light: Y rises linearly with the blend
        // factor, so the factor that hits `target` is a division, not a search.
        final t = ((target - baseLuminance) / (1 - baseLuminance)).clamp(
          0.0,
          1.0,
        );
        rungs.add(
          Color.from(
            alpha: 1,
            red: _linearToSrgb(r + t * (1 - r)),
            green: _linearToSrgb(g + t * (1 - g)),
            blue: _linearToSrgb(b + t * (1 - b)),
          ),
        );
      } else {
        // Scaling every linear channel by the same factor scales Y by it too.
        final k = (target / baseLuminance).clamp(0.0, 1.0);
        rungs.add(
          Color.from(
            alpha: 1,
            red: _linearToSrgb(r * k),
            green: _linearToSrgb(g * k),
            blue: _linearToSrgb(b * k),
          ),
        );
      }
    }
    return rungs;
  }
}

/// Contrast ratio between two neighbouring rungs of [WpCategorySlot.ramp].
///
/// Chosen as the largest step a five-rung ramp can afford without its far end
/// running out of room: from the palette's Y ≈ 0.30 (dark) / 0.19 (light) base,
/// four steps of 1.22 land at Y ≈ 0.72 and Y ≈ 0.05 — pale and deep, but still
/// hue-bearing rather than white or black.
const double _rampStepContrast = 1.22;

/// The sRGB transfer function and its inverse — the same one
/// [Color.computeLuminance] applies, restated here because [WpCategorySlot.ramp]
/// has to leave linear light again after doing its arithmetic there.
double _srgbToLinear(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _linearToSrgb(double c) =>
    c <= 0.0031308 ? c * 12.92 : 1.055 * math.pow(c, 1 / 2.4) - 0.055;

/// Dark-theme category slots — one recipe, nine outcomes.
///
/// Every slot is a **solid tone**, not a translucent fill: hue spaced around
/// the wheel, HSL saturation held at ≈52 %, and lightness solved *per hue* so
/// all nine land on the same relative luminance (Y ≈ 0.30). Equal luminance is
/// what makes the set read as one categorical scale — no slot volunteers
/// itself as "the important one", which is exactly what a nominal scale must
/// not do. It also puts every slot at ≈5.8:1 against `surface`, comfortably
/// over the 3:1 floor for a graphical object and comfortably *under* the
/// accent's 9.0:1 — the palette is quieter than the brand voice by
/// construction, not by luck. Gated in `test/core/theme/wcag_contrast_test.dart`.
///
/// Because these are opaque tones, *The Increment–Decrement Rule* does not
/// apply — there is no alpha to tune down. The theme pair still mirrors its
/// direction for the same optical reason: on navy a slot resolves *lighter*
/// than its ground, on pearl its light twin resolves *toward ink*, same hue,
/// same saturation, luminance re-solved against the other ground.
///
/// **Excluded hue bands, on purpose.** Cyan/teal 165–215° belongs to the
/// recording family alone; ~30–55° is Pin Amber and
/// `warning`; ~350–15° is `error`; ~145–165° is `success`. A category may not
/// borrow a hue that already means something else in this app.
abstract final class WpCategoryColorsDark {
  static const Color iris = Color(0xFFA486D9); // 262° violet
  static const Color ember = Color(0xFFCB855B); // 22° terracotta
  static const Color fern = Color(0xFF36AA53); // 135° leaf green
  static const Color orchid = Color(0xFFCD74D3); // 296° purple-magenta
  static const Color brass = Color(0xFF979B31); // 62° olive-gold
  static const Color azure = Color(0xFF8092D7); // 228° blue
  static const Color plum = Color(0xFFD477A3); // 332° rose-plum
  static const Color moss = Color(0xFF5EA735); // 98° yellow-green

  /// The dedicated fallback for "no category" — same luminance as the eight,
  /// chroma dropped to ≈20 % so it reads as *absence of a category* rather than
  /// as a ninth one. Never returned by a hash.
  static const Color neutral = Color(0xFF8A95B1);

  /// Indexed by [WpCategorySlot.index] — same order as the enum, neutral last.
  static const List<Color> slots = [
    iris,
    ember,
    fern,
    orchid,
    brass,
    azure,
    plum,
    moss,
    neutral,
  ];
}

/// Light-theme category slots — the pearl-ground twins of
/// [WpCategoryColorsDark], same hues and saturation (≈58 %), lightness
/// re-solved against the light stack so all nine sit at Y ≈ 0.19: ≈4.0:1
/// against `surface`, over the 3:1 floor and under the light accent's 5.8:1.
abstract final class WpCategoryColorsLight {
  static const Color iris = Color(0xFF8C62D5); // 262° violet
  static const Color ember = Color(0xFFB76231); // 22° terracotta
  static const Color fern = Color(0xFF258A3E); // 135° leaf green
  static const Color orchid = Color(0xFFC23CCB); // 296° purple-magenta
  static const Color brass = Color(0xFF7A7D21); // 62° olive-gold
  static const Color azure = Color(0xFF5A72D3); // 228° blue
  static const Color plum = Color(0xFFCE4585); // 332° rose-plum
  static const Color moss = Color(0xFF488824); // 98° yellow-green

  /// See [WpCategoryColorsDark.neutral].
  static const Color neutral = Color(0xFF68789F);

  /// Indexed by [WpCategorySlot.index] — same order as the enum, neutral last.
  static const List<Color> slots = [
    iris,
    ember,
    fern,
    orchid,
    brass,
    azure,
    plum,
    moss,
    neutral,
  ];
}

/// Deterministic slot for an STT model, keyed by its `SttModelInfo.id`.
///
/// Stable across restarts and across model-list edits: the identity is the id,
/// never the list position, so adding a model never re-colors the others.
///
/// **A table, not a hash**, because the domain is closed and small enough that a
/// bijection is both possible and owed:
/// the shipped ids are a small closed set, and the sum-of-code-units hash is not
/// injective over it — `whisper-small` and `whisper-medium` both sum onto slot 0
/// and would paint the two most-used models the same hue. An id the table does
/// not know still hashes, so an unreleased model keeps working; a test pins that
/// every id the app actually ships is tabled.
WpCategorySlot categorySlotForModel(String modelId) =>
    _modelSlots[modelId] ?? _categorySlotForIdentity(modelId);

/// The STT model ids the app can show, one slot each.
///
/// The four selectable models take the four most widely separated hues on the
/// wheel; the three legacy ids — `_migrateModelId` rewrites the *setting*, so
/// history rows written before it still carry them — take what remains. Which
/// key gets which hue means nothing, the scale is nominal.
///
/// [WpCategorySlot.iris] is deliberately absent: it is the source of the
/// analytics duration ramp (see [WpCategorySlot.ramp]), which sits one panel
/// away from the model bars, and one hue should not mean two things on a screen.
const Map<String, WpCategorySlot> _modelSlots = {
  'whisper-small': WpCategorySlot.fern,
  'whisper-medium': WpCategorySlot.azure,
  'whisper-large-v3-turbo': WpCategorySlot.orchid,
  'parakeet-tdt-0.6b-v3': WpCategorySlot.ember,
  'whisper-tiny': WpCategorySlot.moss,
  'whisper-base': WpCategorySlot.brass,
  'whisper-large-v3': WpCategorySlot.plum,
};

/// Deterministic slot for a tag, keyed by its name.
///
/// The name is case- and whitespace-normalised first — tags are user-typed, and
/// "Meeting" and "meeting " must not land on two different hues.
WpCategorySlot categorySlotForTag(String tagName) =>
    _categorySlotForIdentity(tagName.trim().toLowerCase());

/// The one hash behind the mappers — sum of code units, modulo the slot count —
/// so the repo keeps a single, recognisable "identity → slot" idiom. Sound for
/// user-typed tags, whose domain is genuinely open; the closed set of shipped
/// model ids is tabled instead, because over a small domain the hash collides
/// and a bijection is both possible and owed. See [categorySlotForModel] —
/// there the hash is only the fallback for an id the table has not met.
///
/// Distributes over [WpCategorySlot.categories] only; [WpCategorySlot.neutral]
/// is unreachable from here by design. An empty identity is a caller bug, not a
/// fallback: it hashes to 0 like any other string. Callers that mean "no
/// category" say so with [WpCategorySlot.neutral].
WpCategorySlot _categorySlotForIdentity(String identity) {
  final hash = identity.codeUnits.fold<int>(0, (a, b) => a + b);
  return WpCategorySlot.categories[hash % WpCategorySlot.categories.length];
}

/// Theme-paired rendering recipe for the history-entry avatar disc.
///
/// The base is a [WpCategorySlot] color, so it already darkens per theme — but
/// the disc is a *translucent* tint over its ground, and a theme pair solved for
/// equal luminance is not the same thing as a pair solved for equal presence
/// through 20–36 % alpha. Every value below is therefore still mirrored rather
/// than merely scaled: on dark the hue is pushed **toward light** and the fill
/// kept thin; on light it is pushed **toward ink** and the fill made *denser*.
/// The denser light fill is the opposite of the usual "light theme needs less
/// ink" compensation, and it is what the measurement asks for: a light slot
/// clears its pearl ground by ≈4.0:1 where a dark one clears navy by ≈5.8:1, so
/// equal alpha would leave the light disc the weaker of the two.
///
/// The lightness shifts are clamped into a legibility band. The band is what
/// keeps the recipe hue-agnostic: a pure shift drives already-dark hues to
/// near-black glyphs on light and washes pale hues out on dark, so the band
/// caps both ends without flattening the hues that sit in between. On today's
/// slots the light bands hold `fern`, `brass`, `moss` and `ember` — the four
/// whose light twins already sit low — while the dark bands never bind at all.
///
/// Calibrated against two contrast targets, verified per slot and per theme in
/// `test/core/theme/wcag_contrast_test.dart`:
/// * disc vs. `surface`/`surfaceElevated` ≥ 1.5:1 (WCAG 1.4.11, graphical
///   object) — the disc has to be *seen*;
/// * glyph vs. disc ≥ 3:1 — the icon has to be *read*.
///
/// Both targets pull against each other on light (a denser disc drags the glyph
/// further toward ink), which is why they are calibrated together.
///
/// **The disc is the nav rail's chip material, on a circle (2026-08-11).** The
/// maintainer asked for the rail's icon chips on the entry avatars, so the
/// recipe grew the one thing it was missing: a *precomposited* crown on the
/// first [glossStop] of a vertical ramp ([gloss], [discGradient]) instead of a
/// flat two-stop diagonal fill. Nothing about the calibration above moved —
/// [fillTop], [fillBottom], [edge] and [glyph] are the same colors at the same
/// alphas, the crown sits above them, and the disc's own numbers are therefore
/// unchanged by construction. What did change is *where they are measured*:
/// the row the avatar sits in paints no fill of its own, so the ground is the
/// content plane ([WpColorsDark.warmSurfaceGradient]), not the flat `surface`
/// token the gate used to stand in for it. On dark that plane is the brighter
/// and therefore tighter ground, and the disc clears it with margin (worst
/// slot `fern`, 1.62:1 against the plane's brightest stop vs. 1.68:1 against
/// flat `surface`).
final class WpAvatarTint {
  const WpAvatarTint._({
    required this.fillTopAlpha,
    required this.fillBottomAlpha,
    required this.edgeAlpha,
    required this.glyphAlpha,
    required this.fillLightnessShift,
    required this.fillLightnessMin,
    required this.fillLightnessMax,
    required this.topStopLightnessDelta,
    required this.glyphLightnessShift,
    required this.glyphLightnessMin,
    required this.glyphLightnessMax,
    required this.glossLightness,
    required this.glossAlpha,
  });

  /// Alpha of the lit (top-left) gradient stop.
  final double fillTopAlpha;

  /// Alpha of the shaded (bottom-right) gradient stop.
  final double fillBottomAlpha;

  /// Alpha of the 1px hue-tinted rim.
  final double edgeAlpha;

  /// Alpha of the icon glyph.
  final double glyphAlpha;

  /// Lightness shift applied to the palette hue before it fills the disc.
  /// Positive on dark, negative on light — the mirror that makes the fill
  /// separate from its ground instead of dissolving into it.
  final double fillLightnessShift;

  /// Legibility band for the shifted fill lightness.
  final double fillLightnessMin;
  final double fillLightnessMax;

  /// Extra lightness delta of the lit stop over the shaded one. Carries the
  /// same sign as [fillLightnessShift]: "lit" means away from the ground.
  final double topStopLightnessDelta;

  /// Lightness shift applied to the palette hue for the glyph. Same sign as
  /// [fillLightnessShift] but larger, so the icon separates from the disc it
  /// sits on. Keep it clear of `fillLightnessShift + topStopLightnessDelta` —
  /// at equality the glyph and the lit stop collapse onto the same color and
  /// only their alphas still tell them apart.
  final double glyphLightnessShift;

  /// Legibility band for the shifted glyph lightness.
  final double glyphLightnessMin;
  final double glyphLightnessMax;

  /// HSL lightness of the crown's source hue — **absolute, not a delta**.
  ///
  /// Deliberately not another shift stacked on [topStopLightnessDelta]: the
  /// fill's shifts run through a legibility band, and a third delta would
  /// simply be clamped away for the slots that already sit at the band edge.
  /// The crown would then exist on some hues and not on others, which is a
  /// per-slot difference in a material whose hue is supposed to mean nothing.
  /// An absolute lightness is clamp-proof — every slot gets the same crown,
  /// only in its own hue.
  ///
  /// It carries the slot's hue rather than being white for the reason this
  /// file's header states about every other fill: a neutral alpha over a
  /// chromatic ground desaturates it, which is exactly how the abandoned
  /// painted-glass prototype came out grey.
  final double glossLightness;

  /// Alpha at which the crown is laid over the lit stop before the two are
  /// composited into [gloss]. The single dial for how wet the disc looks.
  final double glossAlpha;

  /// Where the crown ends, as a fraction of the disc's height — the same first
  /// tenth the nav-rail chips give their gloss, so the two materials catch the
  /// light at the same place.
  static const double glossStop = 0.1;

  /// Dark theme: thin fill, hue pushed lighter, glyph lighter still.
  static const WpAvatarTint dark = WpAvatarTint._(
    fillTopAlpha: 0.28,
    fillBottomAlpha: 0.20,
    edgeAlpha: 0.30,
    glyphAlpha: 0.95,
    fillLightnessShift: 0.12,
    fillLightnessMin: 0.45,
    fillLightnessMax: 0.86,
    topStopLightnessDelta: 0.12,
    glyphLightnessShift: 0.20,
    glyphLightnessMin: 0.55,
    glyphLightnessMax: 0.92,
    glossLightness: 0.90,
    glossAlpha: 0.20,
  );

  /// Light theme: denser fill (not thinner), hue pushed toward ink, glyph
  /// darker still — every sign mirrored against [dark].
  ///
  /// The crown is the one value that is **not** mirrored, and that is the
  /// point rather than an oversight: "lit" means lit in both themes. Pearl's
  /// disc is ink *under* its ground, so a crown mirrored into a shadow would
  /// light the disc from below — the exact failure the nav chip's own gloss
  /// gate names. Light pays for it with a paler source (0.97 vs. 0.90) and
  /// slightly more of it (24 % vs. 20 %), because the crown has to climb from
  /// an inked fill toward pearl rather than from a thin tint toward navy.
  static const WpAvatarTint light = WpAvatarTint._(
    fillTopAlpha: 0.36,
    fillBottomAlpha: 0.26,
    edgeAlpha: 0.44,
    glyphAlpha: 0.95,
    fillLightnessShift: -0.20,
    fillLightnessMin: 0.22,
    fillLightnessMax: 0.56,
    topStopLightnessDelta: -0.12,
    glyphLightnessShift: -0.36,
    glyphLightnessMin: 0.14,
    glyphLightnessMax: 0.34,
    glossLightness: 0.97,
    glossAlpha: 0.24,
  );

  static WpAvatarTint of(bool isDark) => isDark ? dark : light;

  /// Lit (top-left) gradient stop for [base], alpha included.
  Color fillTop(Color base) => _shift(
    base,
    fillLightnessShift + topStopLightnessDelta,
    fillLightnessMin + topStopLightnessDelta,
    fillLightnessMax + topStopLightnessDelta,
  ).withValues(alpha: fillTopAlpha);

  /// Shaded (bottom-right) gradient stop for [base], alpha included.
  Color fillBottom(Color base) =>
      _fillBase(base).withValues(alpha: fillBottomAlpha);

  /// Hue-tinted rim for [base], alpha included.
  Color edge(Color base) => _fillBase(base).withValues(alpha: edgeAlpha);

  /// Icon color for [base], alpha included.
  Color glyph(Color base) => _shift(
    base,
    glyphLightnessShift,
    glyphLightnessMin,
    glyphLightnessMax,
  ).withValues(alpha: glyphAlpha);

  /// The lit crown — [fillTop] with the highlight **already composited in**,
  /// so it can be a gradient stop rather than a second layer painted over the
  /// disc.
  ///
  /// Source-over in premultiplied alpha, which is what makes this a
  /// precomposite and not a lerp: the result is always *denser* than the fill
  /// it covers (`α_out = α_gloss + α_fill·(1 − α_gloss)`), the way a real
  /// second coat of anything is. A `Color.lerp` toward the highlight would
  /// have kept the fill's alpha and only shifted its hue, which is a thinner
  /// paint pretending to be a thicker one.
  ///
  /// Same trick, same reason as [WpColorsDark.navChipGradient]'s first stop:
  /// Flutter cannot pair a non-uniform `Border` with a shape, so a lit top
  /// edge has to be baked into the fill.
  Color gloss(Color base) {
    final fill = fillTop(base);
    final crown = HSLColor.fromColor(
      base,
    ).withLightness(glossLightness).toColor();
    final outAlpha = glossAlpha + fill.a * (1 - glossAlpha);
    double channel(double c, double f) =>
        (c * glossAlpha + f * fill.a * (1 - glossAlpha)) / outAlpha;
    return Color.from(
      alpha: outAlpha,
      red: channel(crown.r, fill.r),
      green: channel(crown.g, fill.g),
      blue: channel(crown.b, fill.b),
    );
  }

  /// The whole disc as one gradient — crown, lit stop, shaded stop.
  ///
  /// Vertical rather than the diagonal this used to be, because the crown only
  /// works on the axis it is lit from: over a circle, the first tenth of a
  /// top-left→bottom-right ramp is a corner the shape barely occupies, while
  /// the first tenth of a vertical one is the cap the light would actually
  /// catch. The nav chips are lit on the same axis for the same reason.
  LinearGradient discGradient(Color base) => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [gloss(base), fillTop(base), fillBottom(base)],
    stops: const [0.0, glossStop, 1.0],
  );

  Color _fillBase(Color base) =>
      _shift(base, fillLightnessShift, fillLightnessMin, fillLightnessMax);

  static Color _shift(Color base, double delta, double min, double max) {
    final hsl = HSLColor.fromColor(base);
    return hsl
        .withLightness((hsl.lightness + delta).clamp(min, max).clamp(0.0, 1.0))
        .toColor();
  }
}

// ---------------------------------------------------------------------------
// Decorative layer — chrome surfaces, no meaning
// ---------------------------------------------------------------------------

/// Dark-theme decorative source — *Quartz*, a 314° mauve at ≈52 % saturation.
///
/// **Its own layer, and the third hue family outside the accent** (after Pin
/// Amber and the category slots). It exists to make the settings page read as
/// its own plate rather than the same flat field as every other page, and it
/// carries no information whatsoever. See *The Decorative Color Rule* in
/// `lib/DESIGN.md`, which is what sanctions it (maintainer decision ④ = b,
/// 2026-08-11).
///
/// **Narrowed in Ticket 06 (2026-08-11): the nav rail no longer carries it.**
/// The rail was the layer's first surface, and the wash's job there was to
/// make the chrome its own plate — a job [WpColorsDark.frameGradient] now does
/// itself, chromatically and across all three bars at once. What settles it is
/// not that the wash became invisible (it would still lift the rail by
/// ≈1.07:1 on dark) but that it became *wrong*: a flat veil on one strip of a
/// diagonal ambient cuts a seam down the frame at x = 72 dp, and the frame
/// has to read as one light source across title bar, rail and status bar.
/// The prohibition that no bar paints a ground of its own is the same rule
/// seen from the other side, and it is gated in
/// `test/widgets/frame_single_paint_test.dart`.
/// Recorded rather than deleted, per this file's audit convention.
///
/// **Never cyan.** Cyan/teal stays the brand accent alone (decision ② = b), so
/// the decorative layer may not borrow from it — otherwise the one voice the
/// app has would also be its wallpaper.
///
/// **Why hue proximity is not the guarantee.** 314° sits 18° from `orchid`
/// (296°) and 18° from `plum` (332°), stated rather than argued away: every
/// gap left on the wheel by the accent band, the status hues and the eight
/// slots is about that wide. What keeps this layer apart from the nominal one
/// is *form*, and form is testable — a category slot is an opaque, bounded
/// mark you are meant to read, while this hue only ever appears as a ≤5 %
/// field over a whole surface, at a contrast under the 1.5:1 a graphical
/// object has to clear to register as an object at all. The same argument the
/// [WpColorsDark.warmSurfaceGradient] comment already makes: what keeps a
/// large low-chroma field from reading as a second signal is its weight, not
/// its hue distance.
abstract final class WpDecorativeColorsDark {
  /// The single decorative hue. Never painted at full strength — the app only
  /// ever sees it through [chromeWash].
  static const Color source = Color(0xFFDA8BC8);

  /// The one decorative fill: [source] at 5 %, flat, over a whole surface.
  ///
  /// Below the tint ladder, where *The Decorative Glyph Rule* already puts the
  /// large-area washes, and per theme like everything down there (*The
  /// Increment–Decrement Rule*) — but the light value is **measured, not
  /// inherited**; see [WpDecorativeColorsLight.chromeWash].
  static const Color chromeWash = Color(0x0DDA8BC8); // source @ 5%
}

/// Light-theme decorative source — the pearl-ground twin of
/// [WpDecorativeColorsDark], same 314° hue at ≈58 % saturation with its
/// lightness re-solved toward ink so the wash lands *darker* than its ground.
abstract final class WpDecorativeColorsLight {
  static const Color source = Color(0xFFA12B86);

  /// [source] at 2 % — a third of the dark twin's presence, and the one value
  /// in this file that a *legibility* budget sets rather than an optical one.
  ///
  /// The chrome wash lies under the page ground, which is where a settings row
  /// puts its `textMuted` subtitle. The pairing starts at 4.98:1 on the
  /// content plane — 0.48 over AA — and every point the wash darkens the
  /// ground comes straight out of that margin; 2 % holds 4.83:1. On dark the
  /// same text has room to spare and is optically tuned as usual.
  ///
  /// **The margin used to be 0.19, not 0.48** (4.69:1 on the pearl *frame*,
  /// where 3 % already cost AA and settled this number). Ticket 06 moved the
  /// wash's only remaining ground from the frame to the content plane by
  /// dropping the nav rail's use of it, which is why the numbers above are
  /// larger than the argument that first chose 2 %. The value is left where it
  /// stands rather than re-opened: that ticket narrows *where* the decoration
  /// applies, not how loud it is, and 2 % is the value the layer was ratified
  /// at.
  ///
  /// The per-theme direction is still *The Increment–Decrement Rule*'s — light
  /// under dark — the size of the step is simply not free here.
  static const Color chromeWash = Color(0x05A12B86); // source @ 2%
}

/// The only sanctioned way to a decorative color.
///
/// It takes `isDark` and **nothing else** — no id, no index, no identity —
/// which is the executable half of the rule: a call site physically cannot
/// vary the decorative hue per nav item or per settings section, so the layer
/// cannot grow into a category scale. That is the mirror image of
/// [categorySlotForModel] and friends, whose *parameter* is the evidence that
/// a category color means something.
Color wpDecorativeChromeWash(bool isDark) => isDark
    ? WpDecorativeColorsDark.chromeWash
    : WpDecorativeColorsLight.chromeWash;

/// The translucent scrim behind a [BackdropFilter]-blurred dialog barrier.
///
/// Needs true black/white rather than a themed surface token — the blur
/// already carries the surface tint, this only needs to darken/lighten what
/// shows through it. Was duplicated verbatim across five dialog widgets.
Color wpDialogBarrierColor(bool isDark) {
  return (isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF))
      .withValues(alpha: isDark ? 0.45 : 0.35);
}
