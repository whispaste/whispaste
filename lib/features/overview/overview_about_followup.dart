/// The one-time follow-up of the "Über dich" questions, at the top of the
/// Übersicht's "Mitmachen" block: whoever answered "Keine Angabe" in the
/// onboarding is asked once more after [kAboutFollowUpDictations] dictations,
/// with the same chips, "Keine Angabe" included. Saving or "Nicht mehr
/// fragen" ends it for good ([aboutFollowUpQuestions] holds the rule).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/config/settings_provider.dart';
import '../../core/config/settings_sections.dart' show OnboardingSettings;
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../services/onboarding_telemetry.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/wp_card.dart';
import '../../widgets/wp_filter_chip.dart';
import '../onboarding/about_answers.dart';
import '../onboarding/steps/about_step.dart'
    show aboutRoleLabel, aboutSourceLabel;
import 'overview_providers.dart';

/// The questions the card asks on this visit; empty while none is due or
/// the dictation count is still loading.
final aboutFollowUpProvider = Provider.autoDispose<List<AboutQuestion>>((ref) {
  final onboarding =
      (ref.watch(settingsProvider).value ?? AppSettings.defaults).onboarding;
  // Most visits have nothing to ask: settle that from the settings alone and
  // only then count dictations in the history database.
  final due = aboutFollowUpQuestions(
    onboarding,
    dictations: kAboutFollowUpDictations,
  );
  if (due.isEmpty) return const [];
  final dictations = ref.watch(overviewDictationTotalProvider).value;
  if (dictations == null) return const [];
  return aboutFollowUpQuestions(onboarding, dictations: dictations);
});

/// The card, or nothing when no question is due.
class OverviewAboutFollowUp extends ConsumerWidget {
  const OverviewAboutFollowUp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final questions = ref.watch(aboutFollowUpProvider);
    if (questions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: WpSpacing.lg),
      child: _FollowUpCard(questions: questions),
    );
  }
}

class _FollowUpCard extends ConsumerStatefulWidget {
  const _FollowUpCard({required this.questions});

  final List<AboutQuestion> questions;

  @override
  ConsumerState<_FollowUpCard> createState() => _FollowUpCardState();
}

class _FollowUpCardState extends ConsumerState<_FollowUpCard> {
  // Held here until "Speichern": a half-answered card changes nothing.
  Set<String> _roles = const {};
  String _source = '';

  bool get _complete =>
      (!widget.questions.contains(AboutQuestion.role) || _roles.isNotEmpty) &&
      (!widget.questions.contains(AboutQuestion.source) || _source.isNotEmpty);

  void _finish(OnboardingSettings Function(OnboardingSettings) change) => ref
      .read(settingsProvider.notifier)
      .updateSettings(
        (s) => s.copyWithSections(
          onboarding: change(s.onboarding).copyWith(aboutFollowUpDone: true),
        ),
      );

  void _save() {
    if (!_complete) return;
    final askRole = widget.questions.contains(AboutQuestion.role);
    final askSource = widget.questions.contains(AboutQuestion.source);
    _finish(
      (o) => o.copyWith(
        userRoles: askRole ? storeAboutRoles(_roles) : null,
        userAttribution: askSource ? _source : null,
      ),
    );
    final telemetry = ref.read(onboardingTelemetryProvider);
    final roleIds = OnboardingRole.values.asNameMap();
    if (askRole) {
      telemetry.rolesLater({for (final id in _roles) ?roleIds[id]});
    }
    if (askSource) {
      telemetry.attributionLater(
        OnboardingAttribution.values.asNameMap()[_source] ??
            OnboardingAttribution.other,
      );
    }
  }

  void _dismiss() {
    _finish((o) => o);
    ref.read(onboardingTelemetryProvider).aboutFollowUpDismissed();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    Widget chips(List<Widget> children) => Wrap(
      spacing: WpSpacing.xs,
      runSpacing: WpSpacing.xs,
      children: children,
    );
    Widget question(String label, String why) => Padding(
      padding: const EdgeInsets.only(bottom: WpSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(label, style: WpTextStyles.rowTitle),
          ),
          Text(why, style: WpTextStyles.rowNote),
        ],
      ),
    );
    return Semantics(
      identifier: 'overview-about-followup',
      container: true,
      child: WpCard(
        title: l10n.overviewAboutFollowUpTitle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.questions.contains(AboutQuestion.role)) ...[
              question(
                l10n.onboardingAboutRolesLabel,
                l10n.overviewAboutFollowUpRolesWhy,
              ),
              chips([
                for (final id in [...kOnboardingAboutRoles, kAboutDeclined])
                  WpFilterChip(
                    testId: 'overview-about-followup-role-$id',
                    label: aboutRoleLabel(l10n, id),
                    icon: _roles.contains(id) ? LucideIcons.check : null,
                    isActive: _roles.contains(id),
                    onTap: () =>
                        setState(() => _roles = toggleAboutRole(_roles, id)),
                  ),
              ]),
              const SizedBox(height: WpSpacing.md),
            ],
            if (widget.questions.contains(AboutQuestion.source)) ...[
              question(
                l10n.onboardingAboutFoundLabel,
                l10n.overviewAboutFollowUpFoundWhy,
              ),
              chips([
                for (final id in [...kOnboardingAboutSources, kAboutDeclined])
                  WpFilterChip(
                    testId: 'overview-about-followup-source-$id',
                    label: aboutSourceLabel(l10n, id),
                    icon: _source == id ? LucideIcons.check : null,
                    isActive: _source == id,
                    onTap: () => setState(
                      () => _source = chooseAboutSource(_source, id),
                    ),
                  ),
              ]),
              const SizedBox(height: WpSpacing.md),
            ],
            Wrap(
              spacing: WpSpacing.xs,
              runSpacing: WpSpacing.xs,
              children: [
                Semantics(
                  hint: _complete ? null : l10n.onboardingAboutChooseHint,
                  child: WpButton(
                    testId: 'overview-about-followup-save',
                    label: l10n.overviewAboutFollowUpSave,
                    variant: WpButtonVariant.secondary,
                    size: WpButtonSize.dense,
                    onPressed: _complete ? _save : null,
                  ),
                ),
                WpButton(
                  testId: 'overview-about-followup-dismiss',
                  label: l10n.overviewAboutFollowUpDismiss,
                  variant: WpButtonVariant.ghost,
                  size: WpButtonSize.dense,
                  onPressed: _dismiss,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
