/// The dark palette (ADR 0023: the `dark` appearance and the navy frame of
/// `brand`). Split out of `colors.dart` so the runtime sets in
/// `theme_colors.dart` can build on it without an import cycle.
library;

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

  /// Hairline borders — white at 11.8 % / 18.8 %.
  ///
  /// These used to be described as "a step *above* their light twins (7.8 % /
  /// 14.1 %)", the increment half of the *Increment–Decrement Rule*: a
  /// translucent structural token needs more alpha over navy than its
  /// counterpart needs over pearl to read at the same weight. The twins are
  /// gone with the light stack; the values here are unchanged, and what
  /// justifies them now is simply what they measure against this ground.
  static const Color borderSubtle = Color(0x1EFFFFFF);
  static const Color borderDefault = Color(0x30FFFFFF);

  // Removed with Ticket 08: `cardActiveBorder` (0x24FFFFFF), the hairline of
  // an *active* card tile. Its one call site — `wp_list_tile_surface.dart` —
  // now draws [cardEdgeHighlight] there instead. Same alpha byte, but tinted:
  // on a translucent frost fill the rim is the card's shape, and a neutral
  // white rim over a chromatic fill desaturates it toward grey, which is the
  // failure the frost material was introduced to fix. Recorded rather than
  // deleted silently, because "a neutral hairline on an active card" was a
  // deliberate choice once and has to be visibly overruled.

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

  /// Filled primary surface and its content colour. On the stage the fill
  /// is the accent itself; the light palette splits the two roles.
  static const Color action = accent;
  static const Color onAction = background;

  /// Flat accent surface tint, 16.5 % — formerly "deliberately *above* its
  /// light twin (11 %)", the increment/decrement reasoning shared by every
  /// structural translucent in this file. The twin is gone; the value is not.
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

  /// Rim of a dock keycap: frost tint @ 30 % (spec §2). Dock-only, so it lives
  /// in the dark set alone; the dock stays on the navy stage in every theme.
  static const Color frostBorder30 = Color(0x4DA190D5);

  /// Hairline between dock groups: frost tint @ 15 % (spec §2). Dock-only.
  static const Color frostBorder15 = Color(0x26A190D5);

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

  /// The same frost, **pre-composited** for surfaces that float over content
  /// the material cannot see through.
  ///
  /// [cardFill]/[cardFillElevated] are translucent by definition: they only
  /// read as frost because the one ambient gradient runs underneath them. A
  /// dialog does not sit on that ambient — it sits on a 92 %-opaque barrier of
  /// [background] — and a toast or a dropdown popup sits on whatever the user
  /// happens to have scrolled underneath it. A 4.7 % tint over an unknown or
  /// near-opaque ground is not a material, it is a rounding error, and it would
  /// leave those three the only surfaces in the app still reading as raw
  /// [surfaceElevated].
  ///
  /// So the composite is done once, here, instead of at paint time:
  /// `Color.alphaBlend(cardFillElevated, surfaceElevated)` = #18274D. Same
  /// recipe, same hue, same rim ([cardEdgeHighlight]) — a floating surface is
  /// the *result* of the card material rather than a second material.
  ///
  /// This is also the one place in the app where a shadow is still spent
  /// (Ticket 08): an element that floats above arbitrary content has no
  /// brightness reference to be read against, so it gets exactly one neutral
  /// drop shadow and never a second, never a tinted one.
  ///
  /// Now the website's `surface.floating` (navy 600, #171D53) instead of that
  /// composite (Onboarding v6, 2026-10-30): the composite's grey blue read as
  /// a different navy beside the indigo frame gradient. Text contrast rises
  /// (textPrimary 14.23:1, textSecondary 7.82:1, textMuted 5.44:1).
  static const Color floatingSurface = Color(0xFF171D53);

  /// Wash for a large decorative background glyph — its own category, *below*
  /// the 6/12/30% tint ladder above. The two themes used to carry different
  /// alphas here; only this one is left.
  static const Color decorativeGlyphWash = Color(0x0D6FDDF0); // accent @ 5%

  /// Ring that marks the element a jump landed on (onboarding locator),
  /// accent at 55 %: caught once in peripheral vision, then gone.
  static const Color accentLocatorRing = Color(0x8C6FDDF0); // accent @ 55%

  /// Saturated status colors — rich and warm
  static const Color success = Color(0xFF36D98B);
  static const Color warning = Color(0xFFF5C842);
  static const Color error = Color(0xFFFF7B7B);
  static const Color onError = background;

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
  static const Color warningActiveFill = Color(0x1FF5C842); // warning @ 12%

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
  /// the removed warm accent ramp. No main-app surface paints a recording
  /// gradient today (the overlay owns that job and keeps its own spec), so
  /// this is the family's reserved home rather than a live call site.
  // loam-ignore: unused-public-exports – the recording family's reserved
  // gradient home; the removed warm accent ramp carried the lighter
  // sibling of this same cyan ramp (ADR 0013), so this stays the recording family's own copy.
  static const LinearGradient recordingAccentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3CCBE6), Color(0xFF14B8D4), Color(0xFF0A99B8)],
  );

  /// Preflight-screen palette. Its only consumer, the blocking low-RAM screen,
  /// was removed (low RAM no longer blocks start-up), so this is a removal
  /// candidate, not a live exception.
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
  /// Opaque tonal steps (no translucent light): neighbouring stops sit 1.07:1 / 1.09:1
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
  /// (`WpLayout.sidebarWidth`, `WpLayout.appBarHeight`) = (232, 40) of a
  /// [frameGradient] that spans the whole window, and it has to read there as
  /// the same light one step nearer — **the same hue, the same chroma within a
  /// few steps, more light**.
  ///
  /// The frame's hue at that corner is not one number: the corner slides along
  /// the ambient as the window changes, so the frame reads 219.5° at 4K and
  /// 223.5° at the minimum window. The stop is solved to the middle of that run
  /// (#152750, 221.7°). Against the frame at the 1100 × 750 the app opens at
  /// (#061740, 222.8°) it lands 1.1° off in hue, 2 steps wider in spread and
  /// 1.19:1 lighter. It had been solved for the pre-ticket corner (72, 64) at
  /// 220.0°; widening the rail to 232 px moved the corner along the frame, and
  /// at the minimum window the hue fell 3.5° out of step. *(Ticket 07 first
  /// shipped this stop at Y 0.01241 = 1.034:1; see the perceptibility re-solve
  /// below for why the luminance moved.)*
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
    colors: [Color(0xFF152750), Color(0xFF171D53), Color(0xFF2E2153)],
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
  /// luminance Ticket 06 solved for it. Opaque tonal steps, no translucent light.
  static const LinearGradient frameGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF051A3E),
      // One green step (0x11 -> 0x12) below the seam gate's 3.5 deg at the
      // minimum window (was 3.53 deg; wcag_contrast_test seam group).
      Color(0xFF071244),
      Color(0xFF0E0941),
      Color(0xFF140A2F),
    ],
    stops: [0.0, 0.42, 0.74, 1.0],
  );

  /// Top accent line gradient — anchored at [accent], falling 1.247:1.
  ///
  /// That span is the pre-Ticket-04 ramp's, re-solved rather than lifted, for
  /// the reason recorded with ADR 0013.
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

  /// Nav-rail icon chip, resting — the rail's icons stand on **material**, not
  /// on bare frame.
  ///
  /// Two stops on one vertical axis: a frost fill falling 17.6 % → 12.2 %.
  /// The tile carries no light source of its own (UIA-VIS-12). On dark, the
  /// tile's own brightness delta against the frame (≈1.24:1) is the whole depth
  /// source, exactly as it is between the card fills.
  ///
  /// **It marks nothing.** Every rail item wears one, resting or not, so the
  /// tile is material rather than a state — which is what keeps
  /// [navPillActiveGradient] the single marking of selection (*The One
  /// Highlight Per State Rule*).
  static const LinearGradient navChipGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x2DA190D5), Color(0x1FA190D5)],
    stops: [0.0, 1.0],
  );

  /// Nav-rail icon chip, hovered — the same tile one step brighter (25 % →
  /// 18 % frost under a 36 % [cardEdgeHighlight] tint), ≈1.12:1 over
  /// [navChipGradient].
  ///
  /// Deliberately carries no accent: hover says "you can act on this", the
  /// accent-tinted tile says "you are here", and a hover that borrowed the
  /// accent would make the two states one.
  static const LinearGradient navChipGradientHover = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x40A190D5), Color(0x2EA190D5)],
    stops: [0.0, 1.0],
  );

  /// Nav-rail active chip — the same tile in the accent's hue: 22 % accent at
  /// the top falling to 15 % at the bottom, under a 34 % [accentHover] tint.
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
  /// top-to-bottom structure while restoring the ratio: 1.40:1 over the resting
  /// tile, 1.90:1 over the frame. *The One Highlight Per State Rule* asks the
  /// marker to be unmistakable, not maximal.
  ///
  /// Still deliberately *not* the opaque warm accent ramp: an
  /// opaque accent fill would swallow the tile's ground rather than tint it.
  static const LinearGradient navPillActiveGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x386FDDF0), Color(0x276FDDF0)],
    stops: [0.0, 1.0],
  );
}
