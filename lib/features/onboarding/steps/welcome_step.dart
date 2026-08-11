import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/onboarding/onboarding_revision.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/brand_wordmark.dart';
import '../../../widgets/language_selector.dart';
import '../../../widgets/wp_focus_ring.dart';
import 'onboarding_page_fill.dart';

/// Test key for the update notice strip, shown on page 1 of a revision run
/// only (`.scratch/onboarding-revisions/issues/04`).
@visibleForTesting
const kOnboardingRevisionNoticeKey = Key('onboardingRevisionNotice');

/// Test key for the tappable beat list tile at [index] (0-based).
@visibleForTesting
Key onboardingBeatTileKey(int index) => Key('onboardingBeatTile$index');

/// Test key for the large media placeholder while beat [index] is active.
@visibleForTesting
Key onboardingBeatMediaKey(int index) => Key('onboardingBeatMedia$index');

/// Asset path of the pre-rendered demo clip for beat [index] (0-based).
///
/// ## Convention (assets do not exist yet — see `assets/onboarding/README.md`)
///
/// ```
/// assets/onboarding/beat_{1..3}_loop_{dark,light}.webp   // animated, ~2–3 s
/// assets/onboarding/beat_{1..3}_still_{dark,light}.webp  // single frame
/// ```
///
/// Two variants per beat, not one, because an **animated WebP cannot be
/// paused**: the reduced-motion path ([MediaQuery.disableAnimations]) must
/// load a genuinely static file, not the loop with its animation stopped.
/// The `_still_` file should be the loop's first frame so the two are
/// visually interchangeable.
///
/// Target size of the media surface at the fixed 1100×720 onboarding window:
/// **[kOnboardingBeatMediaWidth] × [kOnboardingBeatMediaHeight] logical px**.
/// Record/crop at 2× (Retina) for a crisp result; the surface renders with
/// `BoxFit.cover`, so the aspect ratio matters more than the exact pixel
/// count — deviating from it crops the recording's edges rather than
/// letterboxing it.
///
/// Every file is optional: [_BeatMediaPlaceholder] falls back to the icon
/// placeholder for any variant that is missing, so dark-only (or loop-only)
/// deliveries render correctly without a code change.
@visibleForTesting
/// The `_dark` suffix is now a fixed part of the name rather than a choice.
/// It took an `isDark` flag until 2026-08-11; no `_light` file was ever
/// delivered, so that branch only ever produced a path that missed and fell
/// through to the placeholder below. The suffix stays in the filename so the
/// assets already on disk keep their names.
String onboardingBeatAssetPath({required int index, required bool still}) =>
    'assets/onboarding/beat_${index + 1}'
    '_${still ? 'still' : 'loop'}'
    '_dark.webp';

/// Start inset that lines page-1 controls up with the beat *text* rather than
/// with the edge of the beat highlight, which bleeds outward by exactly this
/// much (the tile's horizontal padding).
const double kOnboardingContentInset = WpSpacing.md;

/// Width of the language dropdown. [WpLanguageSelector] runs `isExpanded:
/// true`, so it would otherwise stretch across the whole (deliberately wide)
/// page-1 frame — a full-width control for a three-item choice is exactly
/// the boxiness this page is trying to lose.
const double _kLanguageSelectorWidth = 240;

// ---------------------------------------------------------------------------
// Page-1 geometry — derived, not guessed.
//
// The Conductor reference (`reference-conductor/SCR-20260804-kans.png`) puts
// the media panel at 599 of 1468 px = 40.8 % of the window width and the text
// column at 558 px = 38 %, i.e. media is the *wider* of the two. Everything
// below reproduces that ratio against WhisPaste's fixed 1100×720 onboarding
// window, so all four numbers move together when one of them changes.
// ---------------------------------------------------------------------------

/// Content frame of page 1, wider than the 720 the settings-shaped pages use.
///
/// Lives here rather than in the shell because [kOnboardingBeatMediaWidth] is
/// derived from it — splitting the two invites silent drift in the asset
/// dimensions the maintainer records against.
const double kOnboardingWelcomeFrameWidth = 860;

/// Gap between the beat text column and the media panel.
const double _kBeatColumnGap = WpSpacing.xxl;

/// Flex ratio of media : text. The reference sits at 1.07 : 1; 5 : 4 (1.25 : 1)
/// is deliberately a touch more asymmetric so the media panel reads as the
/// page's subject rather than as an equal partner of the text.
const int _kBeatMediaFlex = 5;
const int _kBeatTextFlex = 4;

/// Rendered width of the media surface: `(860 − 32) × 5/9 = 460` logical px,
/// i.e. 41.8 % of the 1100-px window — within a percentage point of the
/// reference's 40.8 %. The text column takes the remaining 368 px (33.5 %).
const double kOnboardingBeatMediaWidth =
    (kOnboardingWelcomeFrameWidth - _kBeatColumnGap) *
    _kBeatMediaFlex /
    (_kBeatMediaFlex + _kBeatTextFlex);

/// Rendered height of the media surface — the number that had to be *taken*
/// rather than derived.
///
/// Measured at the fixed 1100×720 window with real Inter metrics: the page
/// content viewport is 551 px, and everything around the showcase (wordmark
/// lockup, gaps, language selector, scroll padding) costs 241 px in both
/// German and Hebrew — so ~310 px is the ceiling. 288 takes all but 22 px of
/// that, and lands the panel on 460 × 288 = **16 : 10**, a ratio a screen
/// recording can be cropped to without arithmetic. The old
/// `AspectRatio(16/9)`-inside-`Expanded` construction measured ~191 px here:
/// it let the short text column dictate the row height and left the page's
/// lower third empty.
///
/// The row still sizes itself normally: if an accessibility text scale makes
/// the beat list taller than this, the row grows and the panel stays centred
/// — this is the panel's height, never a cap on the page.
const double kOnboardingBeatMediaHeight = 288;

/// Size of the decorative beat glyph on the empty media stage, and how far it
/// runs off the panel's bottom-end corner.
///
/// 256 is deliberately larger than anything in [WpIconSize]: those grades stop
/// at 48 because they describe icons the user *reads*, and this is not one —
/// it is a surface texture, the category DESIGN.md's Decorative Glyph Rule
/// calibrates its 3–5 % band for. At 256 px inside a 460×288 panel the glyph
/// covers a little under half the surface, and the 40-px bleed puts its corner
/// outside the [WpRadius.borderLg] clip so the shape reads as cropped rather
/// than as a large centred icon. Both numbers are geometry, not spacing —
/// putting them on the 4-px `WpSpacing` rhythm would say something the rhythm
/// does not mean.
const double _kBeatGlyphSize = 256;
const double _kBeatGlyphBleed = 40;

/// Welcome content of onboarding page 1 — wordmark, three demo beats and the
/// language selection.
///
/// Composition follows the Conductor reference (`.scratch/onboarding-redesign/
/// reference-conductor/SCR-20260804-kans.png`): a centred brand lockup on top,
/// then everything else start-aligned in a wide, airy frame — a vertical beat
/// list on one side, ONE large media area on the other, and the few controls
/// stacked underneath at the same start edge. The page carries no boxes it
/// doesn't need: the only filled surfaces are the active beat tile and the
/// media area, both borderless.
///
/// The language choice acts immediately on the whole UI and pre-seeds the
/// recognition language (and thus the engine recommendation on page 3) —
/// existing behaviour, unchanged. Two things deliberately do NOT live here:
/// the theme choice (page 4 — the pre-rendered demo clips cannot follow a
/// live theme switch) and any microphone affordance (page 6, where the
/// microphone is first used; the permission request itself still fires when
/// the user leaves this page). Content only — navigation (Back/Next) is
/// owned by the onboarding shell, so this widget renders no CTA of its own.
class WelcomeStep extends ConsumerWidget {
  const WelcomeStep({super.key, this.revisionRun = false});

  /// Whether this page is being shown as part of a revision run — an existing
  /// user pulled back into the flow because the onboarding content changed
  /// (`.scratch/onboarding-revisions/issues/04`).
  ///
  /// Passed in by the shell rather than read from
  /// `onboardingRevisionRunProvider`: that provider tracks whether *this
  /// process* started a run, while `OnboardingOverlay.revisionRun` is what
  /// actually decides which mode is on screen (a review, the first run, a
  /// revision). Deriving the notice from the shell's own answer is what keeps
  /// the two from ever disagreeing.
  final bool revisionRun;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final l10n = L10n.of(context);

    // Only a revision run reads the registry at all — in a first run this
    // stays empty and nothing below it renders, so page 1 is byte-for-byte
    // the page it has always been.
    final revisionReasons = revisionRun
        ? pendingOnboardingRevisionReasons(
            registry: ref.watch(onboardingRevisionRegistryProvider),
            platform: currentOnboardingPlatform(),
            seenContentVersion: settings.onboarding.onboardingContentVersion,
            l10n: l10n,
          )
        : const <String>[];

    const textSecondary = WpColors.textSecondary;

    void selectLocale(String locale) {
      HapticFeedback.selectionClick();
      ref
          .read(settingsProvider.notifier)
          .updateSettings((s) => s.copyWith(locale: locale));
    }

    return OnboardingPage(
      // Brand lockup — this page's header, and the only horizontally
      // centred element on it, mirroring the reference's centred wordmark
      // over start-aligned content. The claim reads as a quiet second line
      // of the lockup instead of a second headline: the beat titles below
      // already carry that message, so shouting it here is what made the
      // page feel packed.
      //
      // Vertically it is fixed at the top of the page, exactly where every
      // other page's [OnboardingPageHeading] starts — the same
      // [OnboardingPage] header slot, so the two can never drift apart. It
      // used to float — the whole page was centred as one unit — which made
      // the logo's height depend on how tall the showcase happened to be and
      // put it visibly below page 2's title.
      //
      // In a revision run the claim line is replaced by the update notice
      // rather than joined by it: the returning user does not need the
      // product promise a second time, and page 1 has exactly 22 px of slack
      // at the fixed window (see [kOnboardingBeatMediaHeight]) — the claim's
      // own height is what pays for the strip. Swapping instead of stacking
      // also keeps the wordmark on the same line it sits on in every other
      // mode.
      headerGap: revisionRun ? WpSpacing.sm : kOnboardingHeaderGap,
      header: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 64 px is the wordmark's intrinsic logical height (the bundled
            // PNG is 199×64 at 1×, with 1.5×–4× variants). Rendering at
            // exactly that size is both the largest crisp option and a 45 %
            // step up from the 44 px this page used before, which read as
            // just another element rather than as the page's starting
            // point. Going further would upscale the 2× variant Flutter
            // picks on a Retina display and visibly soften the logo — that
            // needs a larger source export, not a larger `height`.
            const WpBrandWordmark(height: 64),
            // One gap for both variants, and the tighter of the two. The
            // claim is meant to read as a quiet second line *of the lockup*,
            // not as a separate headline under it — at 12 px it sat far
            // enough below the wordmark to read as its own block, which is
            // the opposite of the intent stated below. 8 px binds the two
            // into one mark, and it is also the last 4 px German at text
            // scale 1.3 needed to clear the fold on this page (see the
            // ledger in ticket 20's Phase-5 protocol). The revision variant
            // already used this value.
            const SizedBox(height: WpSpacing.xs),
            if (revisionRun)
              _RevisionNotice(reasons: revisionReasons)
            else
              Text(
                l10n.onboardingWelcome,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: WpTypography.heading,
                  fontWeight: FontWeight.w500,
                  color: textSecondary,
                  height: 1.3,
                ),
              ),
          ],
        ),
      ),

      // Showcase and language choice are this page's body: one block,
      // centred in whatever height is left under the lockup.
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Three demo beats in the Conductor-style asymmetric
          // composition: a start-aligned vertical list of titles +
          // captions on one side, ONE large media area for the active
          // beat on the other. Captions are rendered by Flutter (l10n,
          // incl. RTL) — never baked into the artwork.
          const _BeatShowcase(),
          // One gap, both runs. This used to be `xl` on a first run and `md`
          // on a revision run, which gave the page three different vertical
          // values (24 / 16 / 4) with the largest only 1.5× the middle one —
          // a rhythm too flat to group anything. The body now runs on two
          // values at 4:1 (`md` between blocks, `xxs` inside a tile), and the
          // language block below carries its own label, so the separation it
          // needs comes from being a labelled group rather than from a wider
          // gap.
          const SizedBox(height: WpSpacing.md),

          // Language selector — items derived from L10n.supportedLocales
          // so adding a new language is an ARB-only change. Rendered as a
          // compact dropdown without flag icons (see widget docs).
          //
          // Labelled, and labelled *beside* the control rather than above it:
          // this dropdown is the only decision the first page asks for, and
          // unlabelled under a 460-px media panel it read as a leftover
          // control rather than as the page's one question. A label above
          // would say the same thing, but it costs a full line of height on a
          // page that has none to spare — whereas the label-then-control row
          // is the shape every `SettingRow` in the app already uses, at zero
          // height. `settingsAppLanguage` is reused deliberately: this is the
          // same setting the settings page exposes, and it should be called
          // the same thing in both places.
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: kOnboardingContentInset,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.settingsAppLanguage,
                  style: const TextStyle(
                    fontSize: WpTypography.body,
                    fontWeight: FontWeight.w600,
                    color: textSecondary,
                  ),
                ),
                const SizedBox(width: WpSpacing.sm),
                SizedBox(
                  width: _kLanguageSelectorWidth,
                  child: WpLanguageSelector(
                    currentLocale: settings.locale,
                    onChanged: selectLocale,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Update notice — revision run only.
// =============================================================================

/// Separator between the reasons of several skipped versions.
///
/// Punctuation, not prose, and therefore not localized: a middle dot carries
/// the same "these are separate items" meaning in every script this app
/// ships, and it reads correctly under RTL because the bidi algorithm treats
/// it as neutral between two runs of the same direction.
const String _kRevisionReasonSeparator = '  ·  ';

/// The strip that tells a returning user why the flow reopened.
///
/// Accent palette and badge shape are lifted from
/// `WpPasteCapabilityRestartBanner` on purpose: nothing here went wrong —
/// an update landed and the app is telling the user about it. Error/warning
/// colours would turn a piece of good news into an alarm.
///
/// Two deliberate deviations from that banner, both bought by page 1's 22 px
/// of slack at the fixed 1100×720 window:
///
///  * **One paragraph instead of title + body.** The reassurance ("your
///    settings are unchanged") is the bold lead-in, the registry reasons run
///    on in secondary colour. That keeps the strip two lines tall *whatever*
///    the registry contains — the acceptance criterion "names the reasons of
///    every skipped version without becoming cluttered" is met by a bounded
///    box, not by hoping the reasons stay short.
///  * **[WpSpacing.xs] padding instead of [WpSpacing.md].** The 32-px badge
///    already sets the strip's height floor; the extra 16 px would have been
///    pure air the page cannot afford.
///
/// Truncation, when it happens, drops the *oldest* reason first
/// ([pendingOnboardingRevisionReasons] sorts newest first) — and the full
/// string still reaches assistive technology, because [Text]'s semantics
/// label is the complete text regardless of [TextOverflow.ellipsis].
class _RevisionNotice extends StatelessWidget {
  const _RevisionNotice({required this.reasons});

  /// Newest first; empty is legal (a registry override with no entry for this
  /// platform), and then the strip is the reassurance alone.
  final List<String> reasons;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    const accent = WpColors.accent;
    const fill = WpColors.accentButtonFill;
    const border = WpColors.accentBorder20;
    const badgeFill = WpColors.accentChipFill;
    const textPrimary = WpColors.textPrimary;
    const textSecondary = WpColors.textSecondary;

    return Container(
      key: kOnboardingRevisionNoticeKey,
      width: double.infinity,
      padding: const EdgeInsets.all(WpSpacing.xs),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: WpRadius.borderMd,
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Container(
            width: WpIconSize.xl,
            height: WpIconSize.xl,
            decoration: BoxDecoration(
              color: badgeFill,
              borderRadius: WpRadius.borderSm,
            ),
            child: const Center(
              child: Icon(
                LucideIcons.sparkles,
                size: WpIconSize.sm,
                color: accent,
              ),
            ),
          ),
          const SizedBox(width: WpSpacing.sm),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: l10n.onboardingRevisionNoticeTitle,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
                    ),
                  ),
                  if (reasons.isNotEmpty)
                    TextSpan(
                      text: ' ${reasons.join(_kRevisionReasonSeparator)}',
                    ),
                ],
              ),
              textAlign: TextAlign.start,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: WpTypography.small,
                color: textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Beat showcase — asymmetric two-column layout (Conductor reference).
// =============================================================================

/// The three demo beats: a vertical, start-aligned list of title + caption
/// blocks on the start side and ONE large media area on the end side that
/// shows the active beat's placeholder.
///
/// Activation is click/tap-driven (first beat active on appear) rather than
/// timer-driven: deterministic, testable, and inherently reduce-motion-safe
/// — the only motion is the media cross-fade, which collapses to an instant
/// swap via [WpMotion.durationFor]. All three titles + captions stay in the
/// widget/semantics tree at all times — inactive beats are only visually
/// de-emphasised (muted text colors), never hidden, so screen readers and
/// keyboard users always reach the full content. Each tile is a focusable
/// button (InkWell), so keyboard users can also switch the media area.
///
/// Under RTL the plain [Row] mirrors via ambient [Directionality]: the text
/// list moves to the right, the media area to the left — no hard-coded
/// left/right anywhere.
class _BeatShowcase extends StatefulWidget {
  const _BeatShowcase();

  @override
  State<_BeatShowcase> createState() => _BeatShowcaseState();
}

class _BeatShowcaseState extends State<_BeatShowcase> {
  int _activeIndex = 0;

  void _activate(int index) {
    if (index == _activeIndex) return;
    HapticFeedback.selectionClick();
    setState(() => _activeIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    final beats = [
      (
        icon: LucideIcons.audioLines,
        title: l10n.onboardingBeat1Title,
        caption: l10n.onboardingBeat1Caption,
      ),
      (
        icon: LucideIcons.cpu,
        title: l10n.onboardingBeat2Title,
        caption: l10n.onboardingBeat2Caption,
      ),
      (
        icon: LucideIcons.appWindow,
        title: l10n.onboardingBeat3Title,
        caption: l10n.onboardingBeat3Caption,
      ),
    ];

    // Gentle fade-in instead of a hard pop. With "Reduce Motion" active,
    // WpMotion.durationFor collapses the duration to zero — the showcase
    // appears instantly, exactly like the future loop will fall back to a
    // still.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: WpMotion.durationFor(context, WpMotion.smooth),
      curve: WpMotion.smooth_,
      builder: (context, opacity, child) =>
          Opacity(opacity: opacity, child: child),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Text list — start-aligned, one tile per beat. The highlight box
          // bleeds outward past the text (like the reference): the tile's own
          // horizontal padding is what [kOnboardingContentInset] adds back to
          // the controls below, so beat text and controls share one start
          // edge while the highlight reads as a surface behind them.
          Expanded(
            flex: _kBeatTextFlex,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < beats.length; i++) ...[
                  if (i > 0) const SizedBox(height: WpSpacing.md),
                  // loam-ignore: a11y-interactive-semantics – semantics provided in _BeatListTile.build
                  _BeatListTile(
                    key: onboardingBeatTileKey(i),
                    title: beats[i].title,
                    caption: beats[i].caption,
                    active: i == _activeIndex,
                    onTap: () => _activate(i),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: _kBeatColumnGap),
          // ONE large media area for the active beat. The explicit height is
          // what makes the panel the taller of the two columns — sizing it
          // from an AspectRatio inside the Expanded handed the decision to
          // whichever column happened to be taller, which was always the
          // text. AnimatedSwitcher cross-fades between beats; with "Reduce
          // Motion" the duration collapses to zero (instant swap).
          Expanded(
            flex: _kBeatMediaFlex,
            child: SizedBox(
              height: kOnboardingBeatMediaHeight,
              child: AnimatedSwitcher(
                duration: WpMotion.durationFor(context, WpMotion.smooth),
                switchInCurve: WpMotion.smooth_,
                switchOutCurve: WpMotion.smooth_,
                child: _BeatMediaPlaceholder(
                  key: onboardingBeatMediaKey(_activeIndex),
                  index: _activeIndex,
                  icon: beats[_activeIndex].icon,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One entry of the beat text list: title + caption, start-aligned.
///
/// The active tile gets a subtle card background — no border: in the
/// reference the highlighted feature block is a fill alone, and stacking a
/// border on top of it is what turned three quiet text blocks into three
/// competing boxes. Inactive tiles keep muted text colors but remain fully
/// rendered and tappable — they are never removed from the semantics tree.
///
/// Keyboard focus is marked by [WpFocusRing] in external-node mode (one node
/// shared with the [InkWell], so Enter/Space keeps working), the same
/// affordance the engine cards and the theme swatches carry. The tile's own
/// active state is a fill of the very surface colour InkWell's default focus
/// highlight would paint, so without an explicit ring a keyboard user could
/// not tell focus from selection here.
class _BeatListTile extends StatefulWidget {
  const _BeatListTile({
    super.key,
    required this.title,
    required this.caption,
    required this.active,
    required this.onTap,
  });

  final String title;
  final String caption;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_BeatListTile> createState() => _BeatListTileState();
}

class _BeatListTileState extends State<_BeatListTile> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const textPrimary = WpColors.textPrimary;
    const textSecondary = WpColors.textSecondary;
    const textMuted = WpColors.textMuted;
    final surface = (WpColors.surfaceVariant).withValues(alpha: 0.5);

    // MergeSemantics + a plain Semantics wrapper, not
    // `Semantics(excludeSemantics: true)`: excluding the subtree also discards
    // the InkWell's tap and focus actions, which would leave a screen reader
    // announcing a selectable button it has no way to activate. The two Texts
    // below supply the label instead of a hand-assembled string.
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: widget.active,
        child: WpFocusRing(
          focusNode: _focusNode,
          radius: WpRadius.lg,
          child: InkWell(
            focusNode: _focusNode,
            onTap: widget.onTap,
            borderRadius: WpRadius.borderLg,
            // WpFocusRing owns the focus visual, and here it must be the
            // *only* one: InkWell's default focus fill is the same surface
            // colour this tile uses for `active`, so leaving it on would
            // still make a focused inactive tile read as selected — the very
            // confusion the ring was added to end. Only focusColor: this
            // tile draws no hover of its own, so hoverColor has to stay.
            focusColor: Colors.transparent,
            child: AnimatedContainer(
              duration: WpMotion.durationFor(context, WpMotion.fast),
              curve: WpMotion.defaultCurve,
              // Vertical padding is deliberately *half* the gap between two
              // tiles (8 against 16). At the old 12 the two numbers were 1.5:1
              // apart, which is close enough that the three tiles read as one
              // running block of text with faint boxes drawn over it — the
              // separation between two entries has to beat the air inside one
              // entry, or the grouping is invisible. Horizontal padding stays
              // at [kOnboardingContentInset]: it is the value the controls
              // below add back as a start inset, and shrinking it would move
              // the beat text off the page's one shared start edge.
              padding: const EdgeInsets.symmetric(
                horizontal: kOnboardingContentInset,
                vertical: WpSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: widget.active ? surface : Colors.transparent,
                borderRadius: WpRadius.borderLg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    textAlign: TextAlign.start,
                    style: TextStyle(
                      fontSize: WpTypography.subheading,
                      fontWeight: FontWeight.w600,
                      color: widget.active ? textPrimary : textSecondary,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: WpSpacing.xxs),
                  // Body, not caption. `WpTypography.small` (12) is the grade
                  // DESIGN.md reserves for captions and metadata, and this is
                  // neither: these three lines are the only place on the first
                  // page that says what the product actually does. Rendering
                  // the page's message-carrying text one grade *below* its
                  // body baseline — in the narrower of the two columns, at
                  // that — is what made the showcase read as a caption strip
                  // beside a picture. 13 is the 13px Baseline Rule's body
                  // size; the 1.4 leading is kept from the caption grade
                  // rather than taking body's 1.5, because at three wrapped
                  // German lines the extra leading costs more height than the
                  // page has.
                  Text(
                    widget.caption,
                    textAlign: TextAlign.start,
                    style: TextStyle(
                      fontSize: WpTypography.body,
                      color: widget.active ? textSecondary : textMuted,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Media surface of the active beat: the pre-rendered demo clip if it has
/// been produced, the icon placeholder until then.
///
/// The switch between the two is [Image.errorBuilder], not a feature flag —
/// dropping `beat_1_loop_dark.webp` into `assets/onboarding/` is the entire
/// activation step for that one variant, and every variant that is still
/// missing keeps showing the placeholder independently. See
/// [onboardingBeatAssetPath] for the naming convention and the target pixel
/// dimensions.
///
/// Reduced motion is honoured by loading a *different file* rather than by
/// pausing playback: animated WebP has no pause control, so
/// [MediaQuery.disableAnimations] selects the `_still_` variant. This is the
/// same accessibility flag [WpMotion.durationFor] already consults for the
/// fade-in and the cross-fade, so the whole page respects one switch.
class _BeatMediaPlaceholder extends StatelessWidget {
  const _BeatMediaPlaceholder({
    super.key,
    required this.index,
    required this.icon,
  });

  final int index;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final surface = (WpColors.surfaceVariant).withValues(alpha: 0.5);
    const glyphWash = WpColors.decorativeGlyphWash;

    // The empty stage, designed as one.
    //
    // This used to be a 48-px accent icon at 55 % alpha in the dead centre of
    // a 460×288 surface, which is — line for line — the composition every
    // browser draws for an image that failed to load: one small high-contrast
    // mark centred in a large void. Five of the six theme×beat variants
    // render it, so for most users that broken-image reading *is* page 1.
    //
    // The fix inverts the two properties that produce the reading rather than
    // adding anything: the mark stops being small and stops being
    // high-contrast. At [_kBeatGlyphSize] the beat's own icon is no longer an
    // icon sitting *on* the surface, it is the surface's texture, and
    // [WpColors*.decorativeGlyphWash] is the one alpha band DESIGN.md defines
    // for exactly that — a glyph washed into a panel, dark 5 % / light 3 %,
    // flat, no glow. It also retires a hand-rolled `withValues(alpha: 0.55)`,
    // which the ladder's Don't-list forbids at a call site.
    //
    // Cropped at the bottom-end corner, not centred: a centred mark re-invites
    // the "missing content" reading no matter how quiet it is, while a shape
    // running off the edge can only be read as composition. The bleed is
    // direction-aware — [PositionedDirectional] puts it bottom-left in Hebrew,
    // so the panel does not point off the wrong edge in RTL.
    //
    // Deliberately nothing else. No copy: a line of text here would either
    // advertise the missing clip or repeat the caption sitting 32 px to its
    // side, and it would cost new strings in three ARB files for a surface
    // that exists to be replaced. And no ornament: `beat_1_*_dark.webp` is
    // already produced, so in dark mode the very same [AnimatedSwitcher] slot
    // cross-fades between this stage and a real screen recording. Whatever
    // stands here has to survive that swap without looking like it lost an
    // argument.
    final placeholder = Stack(
      children: [
        PositionedDirectional(
          bottom: -_kBeatGlyphBleed,
          end: -_kBeatGlyphBleed,
          child: Icon(icon, size: _kBeatGlyphSize, color: glyphWash),
        ),
      ],
    );

    return DecoratedBox(
      // Borderless, like the reference's screenshot panel: the clip brings
      // its own edges, and an outline around a still-empty surface only makes
      // the page read as boxes.
      decoration: BoxDecoration(
        color: surface,
        borderRadius: WpRadius.borderLg,
      ),
      child: ClipRRect(
        borderRadius: WpRadius.borderLg,
        child: Image.asset(
          onboardingBeatAssetPath(
            index: index,
            still: MediaQuery.of(context).disableAnimations,
          ),
          // The clip is recorded to the panel's exact aspect ratio (see
          // [onboardingBeatAssetPath]); `cover` keeps a slightly-off crop
          // filling the surface instead of letterboxing it against the fill.
          fit: BoxFit.cover,
          excludeFromSemantics: true,
          errorBuilder: (context, error, stackTrace) => placeholder,
        ),
      ),
    );
  }
}
