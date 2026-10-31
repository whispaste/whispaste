// Onboarding v6, screen 2 "Über dich": first name and roles, then how the
// user found WhisPaste, as two short views of one page; every answer is
// optional. Same composition as screen 1: the questions and the one amber
// action on the navy stage on the left, a painted light glacier scene on the
// right with a preview field that writes the typed name.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/config/settings_sections.dart' show OnboardingSettings;
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/system_user_name.dart';
import '../../../widgets/wp_filter_chip.dart';
import '../../../widgets/wp_hero_button.dart';
import '../../../widgets/wp_text_field.dart';
import '../onboarding_scene.dart';
import '../onboarding_split_page.dart';
import 'onboarding_headings.dart' show onboardingCompactText;

/// Role ids of the "Wofür diktierst du?" chips, in display order. They match
/// `OnboardingRole` of the telemetry service.
const List<String> kOnboardingAboutRoles = [
  'writing',
  'dev',
  'legal',
  'education',
  'business',
  'other',
];

/// Ids of the "Wie hast du WhisPaste gefunden?" chips, in display order. They
/// match `OnboardingAttribution` of the telemetry service.
const List<String> kOnboardingAboutSources = [
  'search',
  'ai',
  'friend',
  'store',
  'social',
  'video',
  'github',
  'other',
];

/// Longest first name the field takes.
const int kOnboardingFirstNameMaxLength = 40;

/// One beat of the preview's waveform pulse.
const Duration _kAboutWavePeriod = Duration(milliseconds: 1400);

/// Screen 2. The shell owns the navigation; [onNext] and [onBack] are called
/// after the page has saved its answers. The page itself moves between its
/// two views: Back on the second view returns to the first. Every answer is
/// optional, so Next with nothing chosen is the way past a view.
class AboutStep extends ConsumerStatefulWidget {
  const AboutStep({
    super.key,
    required this.onNext,
    this.onBack,
    this.primaryKey,
  });

  final VoidCallback onNext;
  final VoidCallback? onBack;
  final Key? primaryKey;

  @override
  ConsumerState<AboutStep> createState() => _AboutStepState();
}

class _AboutStepState extends ConsumerState<AboutStep> {
  final _name = TextEditingController();

  /// 0 = name and roles, 1 = how the user found WhisPaste.
  int _view = 0;

  /// Whether the user typed into the field; then a late system name must not
  /// overwrite it.
  bool _nameTouched = false;

  @override
  void initState() {
    super.initState();
    final onboarding =
        (ref.read(settingsProvider).value ?? AppSettings.defaults).onboarding;
    if (onboarding.userFirstNameSet) {
      _name.text = onboarding.userFirstName;
      _nameTouched = true;
    } else {
      final system = ref.read(systemFirstNameProvider).value;
      if (system != null) _name.text = system;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String get _trimmedName => _name.text.trim();

  void _update(OnboardingSettings Function(OnboardingSettings) change) {
    ref
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWithSections(onboarding: change(s.onboarding)),
        );
  }

  void _saveName({required bool keep}) => _update(
    (o) => o.copyWith(
      userFirstName: keep ? _trimmedName : '',
      userFirstNameSet: true,
    ),
  );

  void _toggleRole(Set<String> roles, String id) {
    final next = {...roles};
    if (!next.remove(id)) next.add(id);
    _update(
      (o) => o.copyWith(
        userRoles: [
          for (final r in kOnboardingAboutRoles)
            if (next.contains(r)) r,
        ].join(','),
      ),
    );
  }

  void _chooseSource(String current, String id) =>
      _update((o) => o.copyWith(userAttribution: current == id ? '' : id));

  void _next() {
    if (_view == 0) {
      _saveName(keep: true);
      setState(() => _view = 1);
    } else {
      widget.onNext();
    }
  }

  void _back() {
    if (_view == 1) {
      setState(() => _view = 0);
      return;
    }
    _saveName(keep: true);
    widget.onBack?.call();
  }

  @override
  Widget build(BuildContext context) {
    // The system name can arrive after the first frame (it is read off the
    // UI isolate); it fills the field only while the user has not typed.
    ref.listen(systemFirstNameProvider, (_, next) {
      final system = next.value;
      if (system == null || _nameTouched) return;
      final onboarding =
          (ref.read(settingsProvider).value ?? AppSettings.defaults).onboarding;
      if (onboarding.userFirstNameSet) return;
      setState(() => _name.text = system);
    });

    final l10n = L10n.of(context);
    final compact = onboardingCompactText(context);
    final onboarding =
        (ref.watch(settingsProvider).value ?? AppSettings.defaults).onboarding;
    final roles = onboarding.userRoles.isEmpty
        ? const <String>{}
        : onboarding.userRoles.split(',').toSet();
    final source = onboarding.userAttribution;

    final labelStyle = TextStyle(
      fontSize: WpTypography.rowTitle,
      height: 1.3,
      fontWeight: FontWeight.w600,
      color: WpColors.textPrimary,
    );
    final hintStyle = TextStyle(
      fontSize: WpTypography.small,
      color: WpColors.textMuted,
    );

    Widget label(String text, {String? hint}) => Padding(
      padding: const EdgeInsets.only(bottom: WpSpacing.xs),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.end,
        spacing: WpSpacing.xs,
        children: [
          Text(text, style: labelStyle),
          if (hint != null) Text(hint, style: hintStyle),
        ],
      ),
    );

    // Each chip keeps its 48-px tap surface, but the rows overlap by the
    // part of it that is empty air, so the pills sit as close as one cloud.
    Widget chips(List<Widget> children) => Wrap(
      spacing: WpSpacing.xs,
      runSpacing: -WpSpacing.sm,
      children: children,
    );

    final sectionGap = compact ? WpSpacing.lg : WpSpacing.xxl;

    final List<Widget> questions = _view == 0
        ? [
            OnboardingSplitHeading(
              l10n.onboardingAboutTitle,
              testId: 'onboarding-about-heading',
            ),
            const SizedBox(height: WpSpacing.sm),
            Text(
              l10n.onboardingAboutSubtitle,
              style: TextStyle(
                fontSize: WpTypography.body,
                height: 1.45,
                color: WpColors.textSecondary,
              ),
            ),
            SizedBox(height: sectionGap),
            label(l10n.onboardingAboutNameLabel),
            Semantics(
              identifier: 'onboarding-about-name',
              child: WpTextField(
                controller: _name,
                variant: WpTextFieldVariant.form,
                semanticsLabel: l10n.onboardingAboutNameLabel,
                hintText: l10n.onboardingAboutNameHint,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(
                    kOnboardingFirstNameMaxLength,
                  ),
                ],
                autocorrect: false,
                onChanged: (_) => setState(() => _nameTouched = true),
                onSubmitted: (_) => _next(),
              ),
            ),
            SizedBox(height: compact ? WpSpacing.lg : WpSpacing.xl),
            label(
              l10n.onboardingAboutRolesLabel,
              hint: l10n.onboardingAboutRolesHint,
            ),
            chips([
              for (final id in kOnboardingAboutRoles)
                WpFilterChip(
                  testId: 'onboarding-about-role-$id',
                  label: _roleLabel(l10n, id),
                  icon: roles.contains(id) ? LucideIcons.check : null,
                  isActive: roles.contains(id),
                  onTap: () => _toggleRole(roles, id),
                ),
            ]),
          ]
        : [
            OnboardingSplitHeading(
              l10n.onboardingAboutFoundLabel,
              testId: 'onboarding-about-found',
            ),
            SizedBox(height: sectionGap),
            chips([
              for (final id in kOnboardingAboutSources)
                WpFilterChip(
                  testId: 'onboarding-about-source-$id',
                  label: _sourceLabel(l10n, id),
                  icon: source == id ? LucideIcons.check : null,
                  isActive: source == id,
                  onTap: () => _chooseSource(source, id),
                ),
            ]),
          ];

    return OnboardingSplitPage(
      panelAsset: 'assets/onboarding/about-glacier.webp',
      panel: _AboutScene(name: _trimmedName),
      copy: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_view == 1 || widget.onBack != null)
            OnboardingBackLink(
              testId: 'onboarding-about-back',
              label: l10n.onboardingBack,
              onPressed: _back,
            ),
          // The two views differ in height; the column glides to the new one
          // while the views cross-fade.
          // WpAnimatedSize: a raw AnimatedSize asserts under reduced motion
          // (zero duration), WpAnimatedSize swaps in a plain child there.
          WpAnimatedSize(
            duration: WpMotion.durationFor(context, WpMotion.dramatic),
            curve: WpMotion.spring,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: WpMotion.durationFor(context, WpMotion.smooth),
              layoutBuilder: (current, previous) => Stack(
                alignment: AlignmentDirectional.topStart,
                children: [...previous, ?current],
              ),
              child: Column(
                key: ValueKey(_view),
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: questions,
              ),
            ),
          ),
          SizedBox(height: sectionGap),
          SizedBox(
            width: kOnboardingCopyWidth,
            child: WpHeroButton(
              testId: 'onboarding-about-next',
              key: widget.primaryKey,
              label: l10n.onboardingNext,
              onPressed: _next,
            ),
          ),
        ],
      ),
    );
  }
}

// loam-ignore: code-duplicates – an id→label switch like the one in recording_behavior.dart; different ids and labels
String _roleLabel(L10n l10n, String id) => switch (id) {
  'writing' => l10n.onboardingAboutRoleWriting,
  'dev' => l10n.onboardingAboutRoleDev,
  'legal' => l10n.onboardingAboutRoleLegal,
  'education' => l10n.onboardingAboutRoleEducation,
  'business' => l10n.onboardingAboutRoleBusiness,
  _ => l10n.onboardingAboutOther,
};

String _sourceLabel(L10n l10n, String id) => switch (id) {
  'search' => l10n.onboardingAboutFoundSearch,
  'ai' => l10n.onboardingAboutFoundAi,
  'friend' => l10n.onboardingAboutFoundFriend,
  'store' => l10n.onboardingAboutFoundStore,
  'social' => l10n.onboardingAboutFoundSocial,
  'video' => l10n.onboardingAboutFoundVideo,
  'github' => l10n.onboardingAboutFoundGithub,
  _ => l10n.onboardingAboutOther,
};

/// The painted light glacier scene (a light sibling of screen 1's
/// "Klangbänder") as one rounded panel that rises on the navy stage, like the
/// light bands of the website, with one dark preview field that writes the
/// typed name and a pulsing waveform below it. Decorative for assistive
/// technology: it repeats the field on the left.
class _AboutScene extends StatefulWidget {
  const _AboutScene({required this.name});

  final String name;

  @override
  State<_AboutScene> createState() => _AboutSceneState();
}

class _AboutSceneState extends State<_AboutScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: _kAboutWavePeriod,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return OnboardingScene(
      // The local promise stuck on the card's corner, as on the website's
      // hero card: what you share here stays on this computer.
      card: Stack(
        clipBehavior: Clip.none,
        children: [
          OnboardingSceneCard(
            label: l10n.onboardingAboutPreviewLabel,
            text: widget.name.isEmpty
                ? l10n.onboardingAboutPreviewSampleAnonymous
                : l10n.onboardingAboutPreviewSample(widget.name),
          ),
          PositionedDirectional(
            bottom: -WpSpacing.md,
            end: -WpSpacing.md,
            child: OnboardingSticker(
              icon: LucideIcons.shieldCheck,
              text: l10n.onboardingStickerLocal,
              angle: 0.1,
            ),
          ),
        ],
      ),
      pill: OnboardingWavePill(pulse: _pulse),
    );
  }
}
