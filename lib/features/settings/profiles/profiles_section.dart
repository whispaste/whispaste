import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/app_profiles/app_profile.dart';
import '../../../services/app_profiles/app_profile_choice.dart';
import '../../../services/app_profiles/app_profile_editing.dart';
import '../../../services/app_profiles/app_profile_repository.dart';
import '../../../services/app_profiles/app_profile_resolver.dart';
import '../../../widgets/dialog.dart';
import '../../../widgets/wp_button.dart';
import '../../../widgets/wp_icon_button.dart';
import '../settings_widgets.dart';
import '../widgets/wp_settings_group.dart';
import 'profile_detail.dart';

/// The Profiles area of Settings: the list of profiles (create, rename through
/// the detail, delete, reorder) and the detail of the selected one.
class ProfilesSection extends ConsumerStatefulWidget {
  const ProfilesSection({super.key});

  @override
  ConsumerState<ProfilesSection> createState() => _ProfilesSectionState();
}

class _ProfilesSectionState extends ConsumerState<ProfilesSection> {
  String? _selectedId;

  Future<void> _add() async {
    final name = await showWpFormDialog<String>(
      context: context,
      builder: (ctx, animation) => _NewProfileDialog(animation: animation),
    );
    if (name == null) return;
    final id = newAppProfileId(DateTime.now());
    await ref
        .read(appProfilesProvider.notifier)
        .save(AppProfile(id: id, name: name));
    if (mounted) setState(() => _selectedId = id);
  }

  Future<void> _reorder(List<String> orderedIds) =>
      ref.read(appProfilesProvider.notifier).reorder(orderedIds);

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final profiles = ref.watch(appProfilesProvider).value ?? const [];
    final choice = ref.watch(profileChoiceProvider);
    final activeId = choice is ProfileChoiceProfile ? choice.profileId : null;
    final canAdd = canAddAppProfile(profiles);
    // Without a pick the first profile shows its detail, so the fields are
    // there at once.
    final selected =
        profiles.where((p) => p.id == _selectedId).firstOrNull ??
        profiles.firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WpSettingsGroup(
          heading: l10n.profilesSectionHeading,
          children: [
            if (profiles.isEmpty)
              SettingsRowFrame(
                rowId: 'profiles-empty',
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.profilesEmptyBody),
                      const SizedBox(height: 12),
                      WpButton(
                        label: l10n.profilesAddFirst,
                        variant: WpButtonVariant.primary,
                        testId: 'profiles-add-first',
                        onPressed: _add,
                      ),
                    ],
                  ),
                ),
              )
            else
              SettingsRowFrame(
                rowId: 'profiles-list',
                child: ReorderableListView(
                  shrinkWrap: true,
                  buildDefaultDragHandles: false,
                  physics: const NeverScrollableScrollPhysics(),
                  onReorderItem: (oldIndex, newIndex) {
                    final ids = [for (final p in profiles) p.id];
                    ids.insert(newIndex, ids.removeAt(oldIndex));
                    _reorder(ids);
                  },
                  children: [
                    for (var i = 0; i < profiles.length; i++)
                      _ProfileListItem(
                        key: ValueKey('profiles-row-${profiles[i].id}'),
                        index: i,
                        profile: profiles[i],
                        count: profiles.length,
                        active: profiles[i].id == activeId,
                        selected: profiles[i].id == _selectedId,
                        onSelect: () =>
                            setState(() => _selectedId = profiles[i].id),
                        onUp: () => _reorder(
                          movedAppProfileIds(profiles, profiles[i].id, -1),
                        ),
                        onDown: () => _reorder(
                          movedAppProfileIds(profiles, profiles[i].id, 1),
                        ),
                      ),
                  ],
                ),
              ),
            WpSettingsRow(
              rowId: 'profiles-add',
              title: l10n.profilesAdd,
              trailing: WpButton(
                label: l10n.profilesAdd,
                variant: WpButtonVariant.secondary,
                testId: 'profiles-add',
                onPressed: canAdd ? _add : null,
              ),
            ),
            if (!canAdd)
              Padding(
                key: const ValueKey('profiles-limit-note'),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  l10n.profilesLimitReached,
                  style: TextStyle(color: WpColors.textMuted),
                ),
              ),
          ],
        ),
        if (selected != null) ...[
          const SizedBox(height: 16),
          ProfileDetailGroup(
            key: ValueKey('profile-detail-${selected.id}'),
            profile: selected,
            profiles: profiles,
            onDeleted: () => setState(() => _selectedId = null),
          ),
        ],
      ],
    );
  }
}

/// One profile in the list: drag handle, name, active marker, move buttons.
class _ProfileListItem extends StatelessWidget {
  const _ProfileListItem({
    super.key,
    required this.index,
    required this.profile,
    required this.count,
    required this.active,
    required this.selected,
    required this.onSelect,
    required this.onUp,
    required this.onDown,
  });

  final int index;
  final AppProfile profile;
  final int count;
  final bool active;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onUp;
  final VoidCallback onDown;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final id = profile.id;
    return Material(
      color: selected ? WpColors.surfaceMutedFill : Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: KeyedSubtree(
                key: ValueKey('profiles-drag-$id'),
                child: Tooltip(
                  message: l10n.profilesDragHandle,
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(
                      LucideIcons.gripVertical,
                      size: WpIconSize.smMd,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: InkWell(
                key: ValueKey('profiles-select-$id'),
                onTap: onSelect,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          profile.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (active) ...[
                        const SizedBox(width: 8),
                        Text(
                          l10n.profilesActiveBadge,
                          style: TextStyle(color: WpColors.textMuted),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            KeyedSubtree(
              key: ValueKey('profiles-move-up-$id'),
              child: WpIconButton(
                icon: LucideIcons.arrowUp,
                tooltip: l10n.profilesMoveUp,
                onPressed: index > 0 ? onUp : null,
              ),
            ),
            KeyedSubtree(
              key: ValueKey('profiles-move-down-$id'),
              child: WpIconButton(
                icon: LucideIcons.arrowDown,
                tooltip: l10n.profilesMoveDown,
                onPressed: index < count - 1 ? onDown : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks for the name of a new profile. A blank name is refused here, the same
/// rule the detail applies.
class _NewProfileDialog extends StatefulWidget {
  const _NewProfileDialog({required this.animation});

  final Animation<double> animation;

  @override
  State<_NewProfileDialog> createState() => _NewProfileDialogState();
}

class _NewProfileDialogState extends State<_NewProfileDialog> {
  final TextEditingController _name = TextEditingController();
  bool _blank = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _create() {
    final name = cleanAppProfileName(_name.text);
    if (name == null) {
      setState(() => _blank = true);
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return WpFormDialogShell(
      animation: widget.animation,
      title: l10n.profilesNewTitle,
      subtitle: _blank ? l10n.profilesNameEmpty : '',
      fields: [
        settingsTextField(
          context: context,
          controller: _name,
          hintText: l10n.profilesNameLabel,
          semanticLabel: l10n.profilesNameLabel,
          onChanged: (_) {
            if (_blank) setState(() => _blank = false);
          },
        ),
      ],
      actions: [
        WpDialogAction<Object?>(
          label: l10n.actionCancel,
          testId: 'profiles-create-cancel',
          role: WpDialogActionRole.cancel,
        ),
        WpDialogAction<Object?>(
          label: l10n.profilesCreate,
          testId: 'profiles-create-confirm',
          role: WpDialogActionRole.primary,
          onPressed: _create,
        ),
      ],
    );
  }
}
