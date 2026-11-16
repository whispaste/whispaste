/// The role packs of [roleTermSuggestion], offered once under the empty term
/// list: every term preselected, deselect what is not needed, then "Übernehmen"
/// appends the rest to the custom vocabulary. "Ausblenden" adds nothing. Either
/// ends the suggestion for good.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/wp_banner.dart';
import '../../../widgets/wp_page_notice.dart';
import '../../../widgets/wp_button.dart';
import '../../../widgets/wp_filter_chip.dart';
import '../../onboarding/steps/about_step.dart' show aboutRoleLabel;
import '../dictionary_notice.dart';
import '../role_terms.dart';

/// The suggestion, or nothing when none is due.
class RoleTermsCard extends ConsumerWidget {
  const RoleTermsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value;
    if (settings == null) return const SizedBox.shrink();
    final groups = roleTermSuggestion(
      onboarding: settings.onboarding,
      vocabulary: settings.stt.customVocabulary,
      languageCode: Localizations.localeOf(context).languageCode,
    );
    if (groups.isEmpty) return const SizedBox.shrink();
    return _RoleTermsCard(groups: groups);
  }
}

class _RoleTermsCard extends ConsumerStatefulWidget {
  const _RoleTermsCard({required this.groups});

  final List<RoleTermGroup> groups;

  @override
  ConsumerState<_RoleTermsCard> createState() => _RoleTermsCardState();
}

class _RoleTermsCardState extends ConsumerState<_RoleTermsCard> {
  // Deselected terms; everything else is taken over.
  final _off = <String>{};

  List<String> get _chosen => [
    for (final g in widget.groups)
      for (final t in g.terms)
        if (!_off.contains(t)) t,
  ];

  Future<void> _finish(List<String> add) => ref
      .read(settingsProvider.notifier)
      .updateSettings(
        (s) => s
            .copyWith(
              customVocabulary: mergeVocabulary(s.stt.customVocabulary, add),
            )
            .copyWithSections(
              onboarding: s.onboarding.copyWith(roleTermsDone: true),
            ),
      );

  Future<void> _accept() async {
    final add = _chosen;
    if (add.isEmpty) return;
    final l10n = L10n.of(context);
    await _finish(add);
    if (!mounted) return;
    showWpPageNotice(
      context,
      page: dictionaryNoticePage,
      notice: WpPageNotice(
        id: 'role-terms-added',
        message: l10n.dictionaryRoleTermsAdded(add.length),
        tone: WpBannerTone.info,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final chosen = _chosen;
    return Semantics(
      identifier: 'dictionary-role-terms',
      container: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: WpSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.dictionaryRoleTermsBody, style: WpTextStyles.rowNote),
            const SizedBox(height: WpSpacing.sm),
            for (final group in widget.groups) ...[
              Semantics(
                header: true,
                child: Text(
                  aboutRoleLabel(l10n, group.role),
                  style: WpTextStyles.rowTitle,
                ),
              ),
              const SizedBox(height: WpSpacing.xs),
              Wrap(
                spacing: WpSpacing.xs,
                runSpacing: WpSpacing.xs,
                children: [
                  for (final (i, term) in group.terms.indexed)
                    WpFilterChip(
                      testId: 'dictionary-role-terms-${group.role}-$i',
                      label: term,
                      icon: _off.contains(term) ? null : LucideIcons.check,
                      isActive: !_off.contains(term),
                      onTap: () => setState(() {
                        if (!_off.remove(term)) _off.add(term);
                      }),
                    ),
                ],
              ),
              const SizedBox(height: WpSpacing.md),
            ],
            Wrap(
              spacing: WpSpacing.xs,
              runSpacing: WpSpacing.xs,
              children: [
                Semantics(
                  hint: chosen.isEmpty
                      ? l10n.dictionaryRoleTermsNoneHint
                      : null,
                  child: WpButton(
                    testId: 'dictionary-role-terms-accept',
                    label: l10n.dictionaryRoleTermsAccept,
                    variant: WpButtonVariant.secondary,
                    size: WpButtonSize.dense,
                    onPressed: chosen.isEmpty ? null : _accept,
                  ),
                ),
                WpButton(
                  testId: 'dictionary-role-terms-dismiss',
                  label: l10n.dictionaryRoleTermsDismiss,
                  variant: WpButtonVariant.ghost,
                  size: WpButtonSize.dense,
                  onPressed: () => _finish(const []),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
