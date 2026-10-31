import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_localized_locales/flutter_localized_locales.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/quality_tier.dart';
import '../../../core/config/settings_enums.dart' show OnDeviceEngine;
import '../../../core/config/settings_provider.dart';
import '../../../core/config/whisper_languages.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_native_name.dart';
import '../../../core/onboarding/onboarding_revision.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/engine_recommendation.dart'
    show recommendationLanguages;
import '../../../services/onboarding_telemetry.dart';
import '../../../services/speech_recommendation.dart'
    show systemLanguageCodesProvider;
import '../../../services/stt_parakeet/parakeet_model_registry.dart'
    show parakeetSupportedLanguages;
import '../../../services/welcome_sound_service.dart';
import '../../../widgets/brand_wordmark.dart';
import '../../../widgets/wp_button.dart';
import '../../../widgets/wp_hero_button.dart';
import '../../../widgets/wp_icon_button.dart';
import '../onboarding_speech_consent.dart';
import '../../../services/model_download_service.dart'
    show bestModelForTier, tierForModel;
import '../../../services/stt_parakeet/parakeet_download_service.dart'
    show parakeetDownloadBytes, parakeetGpuWantedForSetting;
import '../onboarding_select.dart';
import 'onboarding_headings.dart'
    show OnboardingHeadingFocus, onboardingCompactText;
import 'onboarding_page_fill.dart';

/// Test key for the update notice strip, shown on page 1 of a revision run
/// only (`internal-notes`).
@visibleForTesting
const kOnboardingRevisionNoticeKey = Key('onboarding-revision-notice');
const kOnboardingRevisionNoticeToggleKey = Key(
  'onboardingRevisionNoticeToggle',
);

/// Asset path of the pre-rendered still for beat [index] (0-based).
///
/// ## Convention (see `assets/onboarding/README.md`)
///
/// ```
/// assets/onboarding/beat_{1..5}_still_{hell,dunkel,marine}.webp  // single frame
/// ```
///
/// Maintainer decision 7b (2026-10-28): the beats are static frames. Animated
/// WebP is not shipped, so there is no motion path and no reduced-motion
/// variant to choose.
///
/// Every still is drawn at the 460:288 panel ratio of the step clip
/// ([kOnboardingMotionClipAspect]) and rendered with `BoxFit.cover`, so the
/// aspect ratio matters more than the exact pixel count. A missing file leaves
/// the calm surface behind it (see `OnboardingMotionClip`).

/// Theme slug of the colour set the app shows: `hell` (light), `dunkel`
/// (dark) or `marine` (navy, the first-start default and the fallback).
String onboardingBeatTheme() {
  final set = WpColors.current;
  if (identical(set, wpLightColors)) return 'hell';
  if (identical(set, wpDarkColors)) return 'dunkel';
  return 'marine';
}

/// Still for beat [index] (0-based) in [theme], defaulting to the active theme.
/// Every theme ships one still per beat under the same naming scheme.
String onboardingBeatAssetPath({required int index, String? theme}) =>
    'assets/onboarding/beat_${index + 1}_still_${theme ?? onboardingBeatTheme()}.webp';

// Start page (Onboarding v6): the slogan, the dictation language, model and
// app language as select lines, and one action that both confirms and starts
// the chosen speech model's download in the background (see
// onboarding_speech_consent.dart).

/// Width of the page's frame: the start page is the only one that runs wider.
const double kOnboardingWelcomeFrameWidth = 860;

/// Width of the copy column's content on screen 1 (wordmark, headline, the
/// language and model lines, the primary action).
const double _kWelcomeCopyWidth = 440;

/// Start inset of the copy column in the side-by-side layout: room to breathe
/// from the window edge (maintainer review 2026-10-30, "zu dicht").
const double _kWelcomeCopyInset = 64;

/// Headline size on screen 1: the page's only large type, sized to carry the
/// copy column's height like the website hero (maintainer review 2026-10-30).
const double _kWelcomeHeadlineSize = 38;

/// The marker behind the headline's second line is drawn on once, left to
/// right, after the page has settled — a highlighter stroke, as on the
/// website hero (`.hero-marker`).
const Duration _kWelcomeMarkerDelay = Duration(milliseconds: 620);
const Duration _kWelcomeMarkerSweep = Duration(milliseconds: 700);

/// The marker sits slightly off-axis like a hand-placed label.
const double _kWelcomeMarkerTilt = -1.5 * math.pi / 180;

/// Side of the static illustration, a vector pill with a waveform.
const double _kWelcomeIllustrationWidth = 240;
const double _kWelcomeIllustrationHeight = 96;

/// The illustration's height at the compact text scale, where the model link
/// below it would otherwise end under the footer (UX review round 2, UX-114).
const double _kWelcomeIllustrationCompactHeight = 48;

/// Width of the model card. Wider than the primary action below it on purpose:
/// at text scale 2.0 the recommendation and its link wrap inside 320 px, and
/// that line count pushed the link under the footer (UX-114).
const double _kWelcomeModelCardWidth = 440;

/// Width of the inline language selector once the language line is expanded.

/// Test key of the static illustration.
const kOnboardingWelcomeIllustrationKey = Key(
  'onboarding-welcome-illustration',
);

/// Key of the start page's title panel (wordmark and statement).
@visibleForTesting
const kOnboardingWelcomeTitlePanelKey = Key('onboarding-welcome-title-panel');

/// The product visual of screen 1 (the right column or the band above the copy).
const kOnboardingWelcomeVisualKey = Key('onboarding-welcome-visual');

/// Key of the "Anderes Modell" link on the revision run's start page. It
/// opens the model cards, which stay changeable later.
const kWelcomeOtherModelLinkKey = Key('onboarding-welcome-other-model-link');

/// Key of the speech model select on the first run's start page.
const kWelcomeModelSelectKey = Key('onboarding-welcome-model-select');

/// The start page. Content only: navigation (Back, the consenting "Einrichten"
/// action) belongs to the onboarding shell.
class WelcomeStep extends ConsumerWidget {
  const WelcomeStep({
    super.key,
    this.revisionRun = false,
    this.onOpenModel,
    this.onPrimary,
    this.primaryLabel,
    this.primaryTestId,
    this.primaryKey,
  });

  /// The primary action of the full-bleed start page ("Einrichten"): it
  /// confirms the recommended model and starts its download. The shell owns
  /// the action; the page only places the button.
  final VoidCallback? onPrimary;
  final String? primaryLabel;
  final String? primaryTestId;
  final Key? primaryKey;

  /// Whether this page is being shown as part of a revision run — an existing
  /// user pulled back into the flow because the onboarding content changed
  /// (`internal-notes`).
  ///
  /// Passed in by the shell rather than read from
  /// `onboardingRevisionRunProvider`: that provider tracks whether *this
  /// process* started a run, while `OnboardingOverlay.revisionRun` is what
  /// actually decides which mode is on screen.
  final bool revisionRun;

  /// Opens the speech-model sub-view ("Anderes Modell"). It has no phase of its
  /// own and returns to this page. Null hides the link.
  final VoidCallback? onOpenModel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final l10n = L10n.of(context);
    // At the compact text scale the page gives up height, not the footer: the
    // model link must stay above it (UX-114).
    final compact = onboardingCompactText(context);

    // Only a revision run reads the registry at all.
    final revisionReasons = revisionRun
        ? pendingOnboardingRevisionReasons(
            registry: ref.watch(onboardingRevisionRegistryProvider),
            platform: currentOnboardingPlatform(),
            seenContentVersion: settings.onboarding.onboardingContentVersion,
            l10n: l10n,
          )
        : const <String>[];

    void selectLocale(String locale) {
      HapticFeedback.selectionClick();
      ref
          .read(settingsProvider.notifier)
          .updateSettings((s) => s.copyWith(locale: locale));
    }

    if (!revisionRun) {
      // Onboarding v6, screen 1 (review round 3): full bleed. The copy on the
      // navy stage on the left, the painted scene on the right over the whole
      // height. The primary action sits under the copy; the shell draws no
      // bottom bar on this page.
      return _WelcomeFullBleed(
        compact: compact,
        onPrimary: onPrimary,
        primaryLabel: primaryLabel,
        primaryTestId: primaryTestId,
        primaryKey: primaryKey,
        locale: settings.locale,
        onChangeLocale: selectLocale,
      );
    }

    return OnboardingPage(
      // The wordmark and the statement form the page's start. In a revision
      // run the update notice takes the statement's place, as before.
      headerGap: revisionRun ? WpSpacing.sm : kOnboardingHeaderGap,
      header: _WelcomeTitlePanel(
        // The revision notice keeps the plain header: its strip is the page's
        // own panel already.
        plain: revisionRun,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            WpBrandWordmark(height: compact ? 48 : 64, onDark: true),
            const SizedBox(height: WpSpacing.lg),
            if (revisionRun)
              _RevisionNotice(reasons: revisionReasons)
            else
              OnboardingHeadingFocus(
                child: Semantics(
                  header: true,
                  identifier: 'onboarding-welcome-heading',
                  child: Text(
                    l10n.onboardingWelcomeStatement,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: WpTypography.headline,
                      fontWeight: FontWeight.bold,
                      color: WpColors.textPrimary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _WelcomeIllustration(
            height: compact
                ? _kWelcomeIllustrationCompactHeight
                : _kWelcomeIllustrationHeight,
          ),
          SizedBox(height: compact ? WpSpacing.sm : WpSpacing.lg),
          _WelcomeModelLine(onOpenModel: onOpenModel),
          SizedBox(height: compact ? WpSpacing.xs : WpSpacing.md),
          _WelcomeAppLanguageSelect(
            locale: settings.locale,
            onChanged: selectLocale,
          ),
        ],
      ),
    );
  }
}

/// The title panel: the wordmark and the statement on one raised frost card of
/// the navy stage (V11-01). A revision run keeps its plain header, because its
/// update strip is already a panel of its own.
class _WelcomeTitlePanel extends StatelessWidget {
  const _WelcomeTitlePanel({required this.plain, required this.child});

  final bool plain;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (plain) return child;
    // The panel's top edge is the page's header line (every other page starts
    // its heading there), so its padding is the only thing that moves the
    // wordmark down. At the compact text scale it shrinks, because the model
    // card below must still end above the footer.
    final compact = onboardingCompactText(context);
    return Container(
      key: kOnboardingWelcomeTitlePanelKey,
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: WpSpacing.xl,
        vertical: compact ? WpSpacing.xxs : WpSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: WpColors.cardFillElevated,
        borderRadius: WpRadius.borderLg,
        border: Border.all(color: WpColors.cardEdgeHighlight),
      ),
      child: child,
    );
  }
}

/// Side by side from this width on (more than 800 px); at 800 px and below the
/// scene becomes a band above the copy.
const double _kWelcomeSplitWidth = 801;

/// Share of the window height the scene takes as a band in the stacked layout.
const double _kWelcomeBandShare = 0.35;

/// Screen 1 without a bottom bar: the copy column on the stage, the scene
/// full bleed on the right (55 % of the width, the whole height).
class _WelcomeFullBleed extends ConsumerWidget {
  const _WelcomeFullBleed({
    required this.compact,
    required this.onPrimary,
    required this.primaryLabel,
    required this.primaryTestId,
    required this.primaryKey,
    required this.locale,
    required this.onChangeLocale,
  });

  final bool compact;
  final VoidCallback? onPrimary;
  final String? primaryLabel;
  final String? primaryTestId;
  final Key? primaryKey;
  final String locale;
  final ValueChanged<String> onChangeLocale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final offer = ref.watch(welcomeSpeechOfferProvider).value;

    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final localeNames = LocaleNames.of(context);
    // The first language the recommendation is made for names the model's
    // fit; with automatic detection that is the first system language.
    final dictationCode = recommendationLanguages(
      sttLanguageCode: settings.sttLanguageCode,
      systemLanguages: ref.watch(systemLanguageCodesProvider),
      uiLocale: settings.locale,
    ).first;
    final dictationName =
        localeNames?.nameOf(dictationCode) ??
        whisperLanguages[dictationCode] ??
        dictationCode;
    final secondary = TextStyle(
      fontSize: WpTypography.body,
      height: 1.45,
      color: WpColors.textSecondary,
    );

    final choice = ref.watch(welcomeModelChoiceProvider);
    final shown = choice ?? offer;

    Widget copyBlock(double minHeight, {required double insetStart}) {
      return SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                start: insetStart,
                end: WpSpacing.xl,
                top: WpSpacing.xl,
                bottom: WpSpacing.xl,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _kWelcomeCopyWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    WpBrandWordmark(height: compact ? 40 : 48, onDark: true),
                    SizedBox(height: compact ? WpSpacing.lg : WpSpacing.xxl),
                    OnboardingHeadingFocus(
                      child: Semantics(
                        header: true,
                        identifier: 'onboarding-welcome-heading',
                        child: _WelcomeHeadline(
                          text: l10n.onboardingWelcomeHeadline,
                          style: TextStyle(
                            fontSize: compact
                                ? WpTypography.headline
                                : _kWelcomeHeadlineSize,
                            height: 1.15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: compact ? 0 : -0.6,
                            color: WpColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: compact ? WpSpacing.lg : WpSpacing.xxl),
                    // What the button below is about to do: which language
                    // the model is picked for and which model. Both rows
                    // open the same list as the app language further down.
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _dictationLanguageSelect(
                          context,
                          ref,
                          settings,
                          dictationName,
                        ),
                        if (offer != null && shown != null)
                          _modelSelect(
                            context,
                            ref,
                            settings: settings,
                            recommended: offer,
                            shown: shown,
                            dictationCode: dictationCode,
                            dictationName: dictationName,
                          ),
                      ],
                    ),
                    SizedBox(height: compact ? WpSpacing.md : WpSpacing.xl),
                    SizedBox(
                      width: _kWelcomeCopyWidth,
                      child: WpHeroButton(
                        testId: primaryTestId ?? 'onboarding-welcome-start',
                        key: primaryKey,
                        label: shown != null
                            ? l10n.onboardingWelcomeStartSized(
                                shown.sizeLabelFor(settings.locale),
                              )
                            : primaryLabel ?? l10n.onboardingWelcomeStart,
                        onPressed: onPrimary,
                      ),
                    ),
                    const SizedBox(height: WpSpacing.sm),
                    Text(
                      l10n.onboardingWelcomeOnDevice,
                      style: secondary.copyWith(
                        fontSize: WpTypography.small,
                        color: WpColors.textMuted,
                      ),
                    ),
                    SizedBox(height: compact ? WpSpacing.lg : WpSpacing.xxxl),
                    // The app language changes the interface, not the
                    // dictation: its own card below the action, the same row.
                    _WelcomeAppLanguageSelect(
                      locale: locale,
                      onChanged: onChangeLocale,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _kWelcomeSplitWidth) {
          // The painting starts under the copy column and fades in through
          // its alpha; the copy keeps the left 46 %.
          final w = constraints.maxWidth;
          return Stack(
            children: [
              Positioned(
                left: w * 0.30,
                top: 0,
                right: 0,
                bottom: 0,
                child: _WelcomeScene(
                  horizontal: true,
                  contentInsetStart: w * 0.16,
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: math.max(
                  w * 0.46,
                  _kWelcomeCopyInset + _kWelcomeCopyWidth + WpSpacing.xl,
                ),
                child: copyBlock(
                  constraints.maxHeight,
                  insetStart: _kWelcomeCopyInset,
                ),
              ),
            ],
          );
        }
        return Column(
          children: [
            SizedBox(
              width: double.infinity,
              height: constraints.maxHeight * _kWelcomeBandShare,
              child: const _WelcomeScene(horizontal: false),
            ),
            Expanded(child: copyBlock(0, insetStart: WpSpacing.xl)),
          ],
        );
      },
    );
  }
}

/// The dictation language row. The choice is saved at once, and the model
/// recommendation follows it; a picked Parakeet that cannot write the new
/// language falls back to the recommendation.
Widget _dictationLanguageSelect(
  BuildContext context,
  WidgetRef ref,
  AppSettings settings,
  String dictationName,
) {
  final l10n = L10n.of(context);
  final names = LocaleNames.of(context);
  final current = settings.sttLanguageCode;
  final languages = [
    for (final e in whisperLanguages.entries)
      (code: e.key, name: names?.nameOf(e.key) ?? e.value),
  ]..sort((a, b) => a.name.compareTo(b.name));
  return OnboardingSelect<String>(
    testId: 'onboarding-welcome-dictation-language',
    label: l10n.onboardingSelectDictationLanguage,
    valueText: current == 'auto'
        ? l10n.settingsLanguageAutoDetect
        : dictationName,
    selected: current,
    searchHint: l10n.onboardingSelectSearchLanguage,
    noResultsText: l10n.settingsLanguageNoResults,
    options: [
      OnboardingSelectOption(
        value: 'auto',
        id: 'auto',
        title: l10n.settingsLanguageAutoDetect,
      ),
      for (final lang in languages)
        OnboardingSelectOption(
          value: lang.code,
          id: lang.code,
          title: lang.name,
          subtitle: _endonymIfDifferent(lang.code, lang.name),
          searchTerms: [
            lang.code,
            ?LocaleNamesLocalizationsDelegate.nativeLocaleNames[lang.code],
          ],
        ),
    ],
    onSelected: (code) {
      final choice = ref.read(welcomeModelChoiceProvider);
      if (choice?.engine == OnDeviceEngine.parakeet &&
          !parakeetSupportedLanguages.contains(code)) {
        ref.read(welcomeModelChoiceProvider.notifier).choose(null);
      }
      ref
          .read(settingsProvider.notifier)
          .updateSettings((s) => s.copyWith(sttLanguage: code));
      ref.read(onboardingTelemetryProvider).dictationLanguageChanged(code);
    },
  );
}

/// The language's own name ("Français", "日本語") when it reads differently
/// from [name]; `null` when the locale data has none.
String? _endonymIfDifferent(String code, String name) {
  final endonym = LocaleNamesLocalizationsDelegate.nativeLocaleNames[code];
  if (endonym == null || endonym.isEmpty) return null;
  final shown = endonym[0].toUpperCase() + endonym.substring(1);
  return shown == name ? null : shown;
}

/// The speech model row: the recommendation, or the model picked in its list.
/// Parakeet is listed but not selectable when it cannot write the dictation
/// language.
Widget _modelSelect(
  BuildContext context,
  WidgetRef ref, {
  required AppSettings settings,
  required WelcomeSpeechOffer recommended,
  required WelcomeSpeechOffer shown,
  required String dictationCode,
  required String dictationName,
}) {
  final l10n = L10n.of(context);
  final locale = settings.locale;
  final parakeet = WelcomeSpeechOffer(
    engine: OnDeviceEngine.parakeet,
    sizeBytes: parakeetDownloadBytes(
      gpuWanted: parakeetGpuWantedForSetting(settings.behavior.gpuAcceleration),
    ),
  );
  final whisper = [
    for (final tier in QualityTier.values)
      (
        tier: tier,
        offer: WelcomeSpeechOffer(
          engine: OnDeviceEngine.whisper,
          whisperModelId: bestModelForTier(tier).id,
          sizeBytes: bestModelForTier(tier).sizeBytes,
        ),
      ),
  ];
  final byId = {
    parakeet.choiceId: parakeet,
    for (final w in whisper) w.offer.choiceId: w.offer,
  };
  final parakeetFits = parakeetSupportedLanguages.contains(dictationCode);
  String? badge(WelcomeSpeechOffer o) => o.choiceId == recommended.choiceId
      ? l10n.onboardingModelRecommended
      : null;
  String tierName(QualityTier tier) => switch (tier) {
    QualityTier.compact => l10n.qualityTierCompactLabel,
    QualityTier.balanced => l10n.qualityTierBalancedLabel,
    QualityTier.premium => l10n.qualityTierPremiumLabel,
  };
  final isRecommended = shown.choiceId == recommended.choiceId;
  return OnboardingSelect<String>(
    testId: 'onboarding-welcome-model',
    key: kWelcomeModelSelectKey,
    label: l10n.onboardingSelectSpeechModel,
    valueText: shown.engine == OnDeviceEngine.whisper
        ? '${shown.engineName(l10n)} · ${tierName(tierForModel(shown.whisperModelId ?? '') ?? QualityTier.balanced)}'
        : shown.engineName(l10n),
    // The size is on the button below; this line says why and how far.
    detail:
        '${isRecommended ? l10n.onboardingSelectRecommendedFor(dictationName) : l10n.onboardingSelectYourChoice} · '
        '${shown.engine == OnDeviceEngine.parakeet ? l10n.onboardingWelcomeReachParakeet(parakeetSupportedLanguages.length) : l10n.onboardingModelFactLanguagesWhisper}',
    selected: shown.choiceId,
    options: [
      OnboardingSelectOption(
        value: parakeet.choiceId,
        id: 'parakeet',
        title: parakeet.engineName(l10n),
        subtitle: parakeetFits
            ? '${l10n.onboardingWelcomeReachParakeet(parakeetSupportedLanguages.length)} · ${parakeet.sizeLabelFor(locale)}'
            : l10n.onboardingModelEngineUnsupportedLanguage,
        badge: badge(parakeet),
        enabled: parakeetFits,
      ),
      for (final w in whisper)
        OnboardingSelectOption(
          value: w.offer.choiceId,
          id: w.offer.choiceId,
          title: '${w.offer.engineName(l10n)} · ${tierName(w.tier)}',
          subtitle:
              '${l10n.onboardingModelFactLanguagesWhisper} · ${w.offer.sizeLabelFor(locale)}',
          badge: badge(w.offer),
        ),
    ],
    onSelected: (id) {
      final picked = byId[id];
      ref
          .read(welcomeModelChoiceProvider.notifier)
          .choose(picked == null || id == recommended.choiceId ? null : picked);
    },
  );
}

/// The painted scene (v2 "Klangbaender", whispaste-34) with the product overlay:
/// a text field where the dictated text lands, the caret at its end, and the
/// waveform pill below. On the first appearance the welcome sound plays, the
/// field and the waveform fly in and the sample sentence types in letter by
/// letter, as if it were being dictated. Then it loops: the sentence rests,
/// is erased like a held Backspace, and is dictated again — without the
/// sound and the fly-in. Reduced motion shows the full frame and stays still. The painting fades into the navy
/// stage: from the left in the side-by-side layout, from the bottom in the
/// band.
class _WelcomeScene extends ConsumerStatefulWidget {
  const _WelcomeScene({required this.horizontal, this.contentInsetStart = 0});

  final bool horizontal;

  /// Left inset of the product overlay: the painting reaches under the copy
  /// column's fade, the overlay stays in the visible part.
  final double contentInsetStart;

  @override
  ConsumerState<_WelcomeScene> createState() => _WelcomeSceneState();
}

/// Length of the one-shot intro (maintainer 2026-10-30: noticeable, not
/// hurried): a pause, the text field flies in, then the waveform, then the
/// sentence types in letter by letter and the bars settle.
const _kWelcomeIntroDuration = Duration(milliseconds: 5200);

/// Phases of the intro as shares of [_kWelcomeIntroDuration].
const _kWelcomeFieldIn = Interval(0.12, 0.30, curve: Curves.easeOutCubic);
const _kWelcomeWaveIn = Interval(0.22, 0.40, curve: Curves.easeOutCubic);
const _kWelcomeTypingStart = 0.40;
const _kWelcomeTypingEnd = 0.84;

/// The loop after the intro (maintainer 2026-10-30), in milliseconds: the
/// full sentence rests, Backspace erases it (speeding up like a held key),
/// a breath with the empty field, the sentence is dictated again, the bars
/// settle. Then it starts over.
const int _kWelcomeLoopHoldMs = 2800;
const int _kWelcomeLoopEraseMs = 1300;
const int _kWelcomeLoopBreathMs = 700;
const int _kWelcomeLoopTypeMs = 2300;
const int _kWelcomeLoopSettleMs = 400;
const int _kWelcomeLoopMs =
    _kWelcomeLoopHoldMs +
    _kWelcomeLoopEraseMs +
    _kWelcomeLoopBreathMs +
    _kWelcomeLoopTypeMs +
    _kWelcomeLoopSettleMs;

/// When the Bernstein-Auftakt starts: with the text field's arrival.
const _kWelcomeSoundDelay = Duration(milliseconds: 640);

/// Distance the field and the waveform travel while flying in.
const double _kWelcomeFlyDistance = 48;

/// The intro plays once per app run: going back to page 1 shows the rest frame.
bool _welcomeIntroPlayed = false;

/// Lets an onboarding opened from the start run the intro again.
void resetWelcomeIntro() => _welcomeIntroPlayed = false;

/// Whether screen 1's intro is at least halfway through (or skipped). The
/// shell shows the contact launcher from then on (maintainer 2026-10-30).
class OnboardingIntroHalfwayNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void reach() {
    if (!state) state = true;
  }
}

final onboardingIntroHalfwayProvider =
    NotifierProvider<OnboardingIntroHalfwayNotifier, bool>(
      OnboardingIntroHalfwayNotifier.new,
    );

/// One frame of the scene: how much of the sentence shows, how far the field
/// and the waveform have flown in, how lively the bars are and the bars'
/// clock in seconds.
typedef _WelcomeFrame = ({
  double cut,
  double fieldIn,
  double waveIn,
  double activity,
  double phase,
});

class _WelcomeSceneState extends ConsumerState<_WelcomeScene>
    with TickerProviderStateMixin {
  late final AnimationController _intro =
      AnimationController(vsync: this, duration: _kWelcomeIntroDuration)
        ..addListener(_reportHalfway)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) _startLoop();
        });

  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _kWelcomeLoopMs),
  );

  void _startLoop() {
    if (!mounted || _loop.isAnimating) return;
    if (MediaQuery.disableAnimationsOf(context)) return;
    _loop.repeat();
  }

  /// The intro's frame while it runs, the loop's afterwards. [length] is the
  /// sample sentence's length in letters.
  _WelcomeFrame _frame(int length) {
    final t = _intro.value;
    if (t < 1 || !_loop.isAnimating) {
      final typing =
          ((t - _kWelcomeTypingStart) /
                  (_kWelcomeTypingEnd - _kWelcomeTypingStart))
              .clamp(0.0, 1.0);
      final waveIn = _kWelcomeWaveIn.transform(t);
      return (
        cut: typing * length,
        fieldIn: _kWelcomeFieldIn.transform(t),
        waveIn: waveIn,
        // Speaking while words still arrive, then the bars settle back to
        // the rest shape.
        activity: t >= 1
            ? 0.0
            : waveIn *
                  Curves.easeOut.transform(
                    (1 - (typing - 0.9) / 0.1).clamp(0.0, 1.0),
                  ),
        phase: t * _kWelcomeIntroDuration.inMilliseconds / 1000,
      );
    }
    final ms = _loop.value * _kWelcomeLoopMs;
    double share(int start, int span) => ((ms - start) / span).clamp(0.0, 1.0);
    const eraseAt = _kWelcomeLoopHoldMs;
    const breathAt = eraseAt + _kWelcomeLoopEraseMs;
    const typeAt = breathAt + _kWelcomeLoopBreathMs;
    const settleAt = typeAt + _kWelcomeLoopTypeMs;
    final erased = Curves.easeIn.transform(
      share(eraseAt, _kWelcomeLoopEraseMs),
    );
    final typed = share(typeAt, _kWelcomeLoopTypeMs);
    final double cut = ms < typeAt ? (1 - erased) * length : typed * length;
    // The bars wake up in the breath before the first word and settle once
    // the sentence stands.
    final double activity = ms < breathAt
        ? 0.0
        : ms < settleAt
        ? Curves.easeOut.transform(share(breathAt, _kWelcomeLoopBreathMs))
        : 1 - Curves.easeOut.transform(share(settleAt, _kWelcomeLoopSettleMs));
    return (
      cut: cut,
      fieldIn: 1,
      waveIn: 1,
      activity: activity,
      phase: ms / 1000,
    );
  }

  void _reportHalfway() {
    if (_intro.value < 0.5) return;
    _intro.removeListener(_reportHalfway);
    // After the frame: the provider must not change while the tree builds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(onboardingIntroHalfwayProvider.notifier).reach();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_intro.isAnimating || _intro.isCompleted) return;
    if (_welcomeIntroPlayed) {
      _intro.value = 1;
      // Back on page 1 the loop runs on from the rest frame, quietly.
      WidgetsBinding.instance.addPostFrameCallback((_) => _startLoop());
      return;
    }
    _welcomeIntroPlayed = true;
    // Engine and asset load now, so the play after the delay finds a running
    // audio device (a cold device swallowed the one-shot).
    ref.read(welcomeSoundProvider).prewarmIntro().ignore();
    // The sound belongs to the screen, not to the motion: reduced motion
    // shows the rest frame but still plays the intro (maintainer 2026-10-31:
    // the onboarding always has its sound).
    _soundTimer = Timer(_kWelcomeSoundDelay, _playSound);
    if (MediaQuery.disableAnimationsOf(context)) {
      _intro.value = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) => _startLoop());
      return;
    }
    _intro.forward();
  }

  Timer? _soundTimer;

  void _playSound() {
    if (!mounted) return;
    // One sound only: the Bernstein-Auftakt, no logo under it (maintainer
    // 2026-10-30; the logo belongs to the main window). Fire and forget: the
    // service decides whether it may play (volume, cues off, busy) and never
    // throws into the UI.
    ref.read(welcomeSoundProvider).playIntro().ignore();
  }

  @override
  void dispose() {
    _soundTimer?.cancel();
    _intro.dispose();
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final compact = onboardingCompactText(context);
    final horizontal = widget.horizontal;
    final sample = l10n.onboardingWelcomeSampleDictation;
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The painting fades out through its own alpha instead of a colour
          // scrim, so it melts into whatever the stage gradient is at that
          // point: no seam between the copy column and the scene.
          ExcludeSemantics(
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) => LinearGradient(
                begin: horizontal
                    ? Alignment.centerLeft
                    : Alignment.bottomCenter,
                end: horizontal ? Alignment.centerRight : Alignment.topCenter,
                colors: const [Color(0x00000000), Color(0xFF000000)],
                stops: horizontal ? const [0.0, 0.5] : const [0.0, 0.6],
              ).createShader(rect),
              child: Image.asset(
                'assets/onboarding/welcome-klangbaender.webp',
                fit: BoxFit.cover,
                alignment: Alignment.centerRight,
                excludeFromSemantics: true,
                gaplessPlayback: true,
              ),
            ),
          ),
          // Scrolls when the band is short (large text in the stacked layout),
          // so the product overlay never overflows the scene.
          LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(
                      WpSpacing.lg,
                    ).copyWith(left: WpSpacing.lg + widget.contentInsetStart),
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_intro, _loop]),
                      builder: (context, _) {
                        final frame = _frame(sample.length);
                        // Letter by letter, like typing.
                        final cut = frame.cut.round().clamp(0, sample.length);
                        final fieldIn = frame.fieldIn;
                        final waveIn = frame.waveIn;
                        final activity = frame.activity;
                        // The field flies in from the right, the waveform
                        // rises from below: one after the other.
                        Widget flyIn(double v, Offset from, Widget child) =>
                            Opacity(
                              opacity: v,
                              child: Transform.translate(
                                offset: from * (1 - v) * _kWelcomeFlyDistance,
                                child: child,
                              ),
                            );
                        return Column(
                          key: kOnboardingWelcomeVisualKey,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            flyIn(
                              fieldIn,
                              const Offset(1, 0),
                              Container(
                                constraints: const BoxConstraints(
                                  maxWidth: 380,
                                ),
                                padding: const EdgeInsets.all(WpSpacing.md),
                                decoration: BoxDecoration(
                                  // Same floating material as the preview
                                  // card of screen 2 and the contact panel.
                                  color: WpColors.floatingSurface,
                                  borderRadius: WpRadius.borderMd,
                                  border: Border.all(
                                    color: WpColors.cardEdgeHighlight,
                                  ),
                                ),
                                child: Text.rich(
                                  TextSpan(
                                    style: TextStyle(
                                      fontSize: WpTypography.body,
                                      color: WpColors.textPrimary,
                                    ),
                                    children: [
                                      TextSpan(text: sample.substring(0, cut)),
                                      WidgetSpan(
                                        alignment: PlaceholderAlignment.middle,
                                        child: Container(
                                          width: 2,
                                          height: WpTypography.body + 4,
                                          margin: const EdgeInsets.only(
                                            left: 2,
                                          ),
                                          color: WpColors.accent,
                                        ),
                                      ),
                                      // The words still to come keep their
                                      // room, so the field never grows.
                                      TextSpan(
                                        text: sample.substring(cut),
                                        style: const TextStyle(
                                          color: Color(0x00000000),
                                        ),
                                      ),
                                    ],
                                  ),
                                  semanticsLabel: sample,
                                ),
                              ),
                            ),
                            SizedBox(
                              height: compact ? WpSpacing.xs : WpSpacing.md,
                            ),
                            flyIn(
                              waveIn,
                              const Offset(0, 1),
                              _WelcomeIllustration(
                                height: compact ? 40 : 56,
                                phase: frame.phase,
                                activity: activity,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The waveform pill. [activity] 0 is the rest shape; up to 1 the bars move
/// like a live level meter, driven by [phase] (seconds into the intro).
class _WelcomeIllustration extends StatelessWidget {
  const _WelcomeIllustration({
    required this.height,
    this.phase = 0,
    this.activity = 0,
  });

  final double height;
  final double phase;
  final double activity;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        key: kOnboardingWelcomeIllustrationKey,
        width: _kWelcomeIllustrationWidth,
        height: height,
        child: CustomPaint(
          painter: _WelcomeWavePainter(
            pill: WpColors.accentSubtle,
            bar: WpColors.accent,
            phase: phase,
            activity: activity,
          ),
        ),
      ),
    );
  }
}

class _WelcomeWavePainter extends CustomPainter {
  const _WelcomeWavePainter({
    required this.pill,
    required this.bar,
    this.phase = 0,
    this.activity = 0,
  });

  final Color pill;
  final Color bar;
  final double phase;
  final double activity;

  /// Relative bar heights of the rest shape, left to right.
  static const _levels = [
    0.28,
    0.46,
    0.7,
    0.9,
    1.0,
    0.78,
    0.55,
    0.82,
    0.6,
    0.36,
    0.22,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(size.height / 2),
      ),
      Paint()..color = pill,
    );
    final slot = size.width / _levels.length;
    final barWidth = slot * 0.46;
    final paint = Paint()..color = bar;
    for (var i = 0; i < _levels.length; i++) {
      // Two detuned sines per bar read as speech rather than a metronome.
      final live =
          0.25 +
          0.75 *
              (0.5 +
                      0.3 * math.sin(phase * 9.0 + i * 1.7) +
                      0.2 * math.sin(phase * 5.3 + i * 0.9))
                  .clamp(0.0, 1.0);
      final level = _levels[i] + (live - _levels[i]) * activity;
      final height = math.max(barWidth, size.height * 0.62 * level);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(slot * (i + 0.5), size.height / 2),
            width: barWidth,
            height: height,
          ),
          Radius.circular(barWidth / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WelcomeWavePainter oldDelegate) =>
      oldDelegate.pill != pill ||
      oldDelegate.bar != bar ||
      oldDelegate.phase != phase ||
      oldDelegate.activity != activity;
}

/// The one model line: the recommendation with its size, and the quiet link to
/// the model cards.
class _WelcomeModelLine extends ConsumerWidget {
  const _WelcomeModelLine({required this.onOpenModel});

  final VoidCallback? onOpenModel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final offer = ref.watch(welcomeSpeechOfferProvider).value;
    // A model card on the stage: the recommendation with its size and the
    // quiet link to the cards. The "Empfohlen" marker is part of the line.
    final compact = onboardingCompactText(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: _kWelcomeModelCardWidth),
      padding: EdgeInsets.symmetric(
        horizontal: WpSpacing.md,
        vertical: compact ? WpSpacing.xxs : WpSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: WpColors.cardFillElevated,
        borderRadius: WpRadius.borderMd,
        border: Border.all(color: WpColors.cardEdgeHighlight),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: WpSpacing.sm,
        runSpacing: WpSpacing.xxs,
        children: [
          if (offer != null)
            Text(
              l10n.onboardingWelcomeRecommended(offer.engineName(l10n)),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: WpTypography.body,
                color: WpColors.textPrimary,
              ),
            ),
          if (onOpenModel != null)
            WpButton(
              testId: 'onboarding-welcome-model-link',
              key: kWelcomeOtherModelLinkKey,
              label: l10n.onboardingOtherModel,
              variant: WpButtonVariant.ghost,
              tone: WpButtonTone.neutral,
              size: WpButtonSize.dense,
              onPressed: onOpenModel,
            ),
        ],
      ),
    );
  }
}

/// The slogan: its first line plain, its second on the amber marker block of
/// the website hero. Without a line break the whole slogan stays plain.
class _WelcomeHeadline extends StatefulWidget {
  const _WelcomeHeadline({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  State<_WelcomeHeadline> createState() => _WelcomeHeadlineState();
}

class _WelcomeHeadlineState extends State<_WelcomeHeadline>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: _kWelcomeMarkerSweep,
  );
  Timer? _delay;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sweep.isAnimating || _sweep.isCompleted || _delay != null) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _sweep.value = 1;
    } else {
      _delay = Timer(_kWelcomeMarkerDelay, () {
        if (mounted) _sweep.forward();
      });
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final split = widget.text.indexOf('\n');
    if (split < 0) return Text(widget.text, style: widget.style);
    final first = widget.text.substring(0, split);
    final second = widget.text.substring(split + 1);
    final size = widget.style.fontSize ?? _kWelcomeHeadlineSize;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(first, style: widget.style),
        SizedBox(height: size * 0.12),
        AnimatedBuilder(
          animation: _sweep,
          builder: (context, _) {
            final t = WpMotion.defaultCurve.transform(_sweep.value);
            // The ink turns navy once the stroke has passed most of the line.
            final ink = _sweep.value < 0.6
                ? WpColors.textPrimary
                : WpColors.onCta;
            return Transform.rotate(
              angle: rtl ? -_kWelcomeMarkerTilt : _kWelcomeMarkerTilt,
              alignment: AlignmentDirectional.centerStart.resolve(
                Directionality.of(context),
              ),
              child: CustomPaint(
                painter: _MarkerStrokePainter(
                  progress: t,
                  color: WpColors.highlight,
                  rtl: rtl,
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    size * 0.14,
                    0,
                    size * 0.14,
                    size * 0.06,
                  ),
                  child: Text(second, style: widget.style.copyWith(color: ink)),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _MarkerStrokePainter extends CustomPainter {
  const _MarkerStrokePainter({
    required this.progress,
    required this.color,
    required this.rtl,
  });

  final double progress;
  final Color color;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final width = size.width * progress;
    final left = rtl ? size.width - width : 0.0;
    canvas.drawRect(
      Rect.fromLTWH(left, 0, width, size.height),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_MarkerStrokePainter old) =>
      old.progress != progress || old.color != color || old.rtl != rtl;
}

/// The app language, taken from the system on first start, in the same select
/// row as the dictation language and the model.
class _WelcomeAppLanguageSelect extends StatelessWidget {
  const _WelcomeAppLanguageSelect({
    required this.locale,
    required this.onChanged,
  });

  final String locale;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    const locales = L10n.supportedLocales;
    final current = locales
        .firstWhere(
          (l) => l.languageCode == locale,
          orElse: () => locales.first,
        )
        .languageCode;
    return OnboardingSelect<String>(
      testId: 'onboarding-welcome-app-language',
      label: l10n.onboardingSelectAppLanguage,
      valueText: localeNativeName(Locale(current)),
      selected: current,
      options: [
        for (final l in locales)
          OnboardingSelectOption(
            value: l.languageCode,
            id: l.languageCode,
            title: localeNativeName(l),
          ),
      ],
      onSelected: onChanged,
    );
  }
}

// Update notice — revision run only.

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
/// ([pendingOnboardingRevisionReasons] sorts newest first) and adds a chevron
/// that unfolds the full text in place (UIA-ONB-12). The full string also
/// reaches assistive technology, because [Text]'s semantics label is the
/// complete text regardless of [TextOverflow.ellipsis].
class _RevisionNotice extends StatefulWidget {
  const _RevisionNotice({required this.reasons});

  /// Newest first; empty is legal (a registry override with no entry for this
  /// platform), and then the strip is the reassurance alone.
  final List<String> reasons;

  @override
  State<_RevisionNotice> createState() => _RevisionNoticeState();
}

class _RevisionNoticeState extends State<_RevisionNotice> {
  /// The strip stays two lines by default (page 1's slack, see the class doc
  /// above); a chevron lets the user unfold the reasons that did not fit.
  /// Unfolded, the page scrolls — the user asked for the text.
  bool _expanded = false;

  /// Read back from the laid-out paragraph after each frame: the page lays
  /// this strip out in the fill column, which rules out measuring it up front
  /// with a LayoutBuilder.
  bool _truncated = false;
  final _textKey = GlobalKey();

  void _syncTruncation(Duration _) {
    if (!mounted || _expanded) return;
    final paragraph = _textKey.currentContext?.findRenderObject();
    if (paragraph is! RenderParagraph) return;
    final truncated = paragraph.didExceedMaxLines;
    if (truncated != _truncated) setState(() => _truncated = truncated);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final reasons = widget.reasons;
    WidgetsBinding.instance.addPostFrameCallback(_syncTruncation);

    final accent = WpColors.accent;
    final fill = WpColors.accentButtonFill;
    final border = WpColors.accentBorder20;
    final badgeFill = WpColors.accentChipFill;
    final textPrimary = WpColors.textPrimary;
    final textSecondary = WpColors.textSecondary;

    final span = TextSpan(
      children: [
        TextSpan(
          text: l10n.onboardingRevisionNoticeTitle,
          style: TextStyle(fontWeight: FontWeight.w600, color: textPrimary),
        ),
        if (reasons.isNotEmpty)
          TextSpan(text: ' ${reasons.join(_kRevisionReasonSeparator)}'),
      ],
    );
    final style = TextStyle(
      fontSize: WpTypography.small,
      color: textSecondary,
      height: 1.4,
    );

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
            child: Center(
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
              span,
              key: _textKey,
              textAlign: TextAlign.start,
              maxLines: _expanded ? null : 2,
              overflow: _expanded ? null : TextOverflow.ellipsis,
              style: style,
            ),
          ),
          if (_truncated || _expanded) ...[
            const SizedBox(width: WpSpacing.xs),
            WpIconButton(
              testId: 'onboarding-welcome-revision-notice-toggle',
              key: kOnboardingRevisionNoticeToggleKey,
              icon: _expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
              tooltip: _expanded
                  ? l10n.onboardingRevisionNoticeCollapse
                  : l10n.onboardingRevisionNoticeExpand,
              onPressed: () => setState(() => _expanded = !_expanded),
            ),
          ],
        ],
      ),
    );
  }
}
