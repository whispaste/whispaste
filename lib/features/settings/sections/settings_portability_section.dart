/// Settings portability (dateibasierter Export/Import) as its own top-level
/// settings section — the full portable settings state (deny-list-filtered
/// `AppSettings.toStorageMap()`), Text Replacements, and Snippets. See
/// `services/settings_portability_service.dart` for the deny list and the
/// `mergeImportedSettings` merge seam, and
/// `services/settings_portability_controller.dart` for the path/toast
/// contract; this section only wires the two buttons + the destructive-ish
/// import confirm.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/tokens.dart' show WpSpacing;
import '../../../features/replacements/replacements_page.dart'
    show replacementsProvider;
import '../../../features/snippets/snippets_page.dart' show snippetsProvider;
import '../../../services/settings_portability_controller.dart';
import '../../../services/settings_portability_service.dart';
import '../../../widgets/dialog.dart';
import '../../../widgets/section.dart';
import '../settings_widgets.dart';

class SettingsPortabilitySection extends ConsumerWidget {
  const SettingsPortabilitySection({super.key});

  SettingsPortabilityController _controller(WidgetRef ref) {
    return SettingsPortabilityController(
      gather: () async {
        final settings =
            ref.read(settingsProvider).value ?? AppSettings.defaults;
        final replacements = ref.read(replacementsProvider).value ?? const [];
        final snippets = ref.read(snippetsProvider).value ?? const [];
        // Filtered here at the source *and* again in
        // `SettingsPortabilityService.encode` (the file-writing boundary,
        // which cannot assume its caller filtered) — deliberate, not
        // accidental duplication. This matters for the machine-bound keys
        // (window geometry, onboarding progress, microphone) that carry
        // real values here; the two API-key entries are moot either way,
        // since `CloudProviderSettings.toMap()` always writes them as ''
        // regardless of filtering (secure storage is the real API-key
        // guard — see `mergeImportedSettings`).
        final filteredSettings = <String, String>{
          for (final entry in settings.toStorageMap().entries)
            if (!settingsPortabilityDenyList.contains(entry.key))
              entry.key: entry.value,
        };
        return SettingsExportBundle(
          settings: filteredSettings,
          replacements: replacements,
          snippets: snippets,
        );
      },
      apply: (bundle) async {
        await ref
            .read(settingsProvider.notifier)
            .updateSettings((s) => mergeImportedSettings(s, bundle.settings));
        await ref
            .read(replacementsProvider.notifier)
            .replaceAll(bundle.replacements);
        // `bundle.snippets` is `null` when the import file predates the
        // Snippets feature (no "snippets" key) — leave the user's existing
        // snippets untouched rather than silently clearing them.
        if (bundle.snippets case final snippets?) {
          await ref.read(snippetsProvider.notifier).replaceAll(snippets);
        }
      },
    );
  }

  Future<void> _confirmImport(BuildContext context, WidgetRef ref) async {
    final l10n = L10n.of(context);
    final controller = _controller(ref);
    final path = await controller.resolvePath();
    if (!context.mounted) return;
    final confirmed = await showWpConfirmDialog(
      context: context,
      title: l10n.settingsPortabilityImportConfirmTitle,
      message: l10n.settingsPortabilityImportConfirmMessage(path),
      confirmLabel: l10n.settingsPortabilityImportAction,
      cancelLabel: l10n.actionCancel,
      destructive: true,
    );
    if (!confirmed) return;
    if (!context.mounted) return;
    await controller.import(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    return WpSection(
      title: l10n.settingsPortabilitySectionTitle,
      subtitle: l10n.settingsPortabilitySectionSubtitle,
      padding: EdgeInsets.zero,
      child: SettingRow(
        icon: LucideIcons.arrowUpDown,
        label: l10n.settingsPortabilityLabel,
        subtitle: l10n.settingsPortabilitySubtitle,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton(
              onPressed: () => _controller(ref).export(context),
              child: Text(l10n.settingsPortabilityExportAction),
            ),
            const SizedBox(width: WpSpacing.sm),
            OutlinedButton(
              onPressed: () => _confirmImport(context, ref),
              child: Text(l10n.settingsPortabilityImportAction),
            ),
          ],
        ),
      ),
    );
  }
}
