/// API keys settings area (#208): the one place where provider keys are
/// entered. Speech recognition and Smart Mode keep the provider choice
/// (ADR 0010) and only show a status line that links here.
///
/// The storage stays as it was (`SecureKeyStore`, `wp_openai_api_key`,
/// `wp_deepgram_api_key`); this page writes through `settingsProvider`, so a
/// key saved here takes effect at once. The Automation API token is not a
/// provider key and stays in the Advanced area.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/linux_keyring_lock_probe.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/navigation/page_state.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/theme.dart' show kWpFontFallback, kWpUiFont;
import '../../../core/theme/tokens.dart';
import '../../../widgets/wp_button.dart';
import '../settings_widgets.dart';
import '../widgets/wp_settings_group.dart';

/// Cloud providers whose key this page holds.
enum ApiKeyProvider {
  openAi('openai', 'OpenAI', 'api-keys-openai'),
  deepgram('deepgram', 'Deepgram', 'api-keys-deepgram');

  const ApiKeyProvider(this.id, this.displayName, this.rowId);

  /// Suffix of the test ids (`settings-api-keys-<id>-field`).
  final String id;

  /// Brand name, never translated.
  final String displayName;

  /// Row id on this page, also the deep-link target of the status links.
  final String rowId;

  String valueIn(AppSettings settings) => switch (this) {
    ApiKeyProvider.openAi => settings.openAiApiKey,
    ApiKeyProvider.deepgram => settings.deepgramApiKey,
  };

  AppSettings write(AppSettings settings, String value) => switch (this) {
    ApiKeyProvider.openAi => settings.copyWith(openAiApiKey: value),
    ApiKeyProvider.deepgram => settings.copyWith(deepgramApiKey: value),
  };
}

/// What the status line says about one key.
enum ApiKeyStatus { stored, missing, keyringLocked }

/// An empty key on a locked (or unreachable) Linux keyring was not read, so
/// it must not show as missing: the user would type it in a second time.
ApiKeyStatus apiKeyStatus(String value, KeyringAvailability availability) {
  if (value.trim().isNotEmpty) return ApiKeyStatus.stored;
  return switch (availability) {
    KeyringAvailability.locked ||
    KeyringAvailability.unreachable => ApiKeyStatus.keyringLocked,
    KeyringAvailability.usable ||
    KeyringAvailability.missing => ApiKeyStatus.missing,
  };
}

/// Keyring state for the status lines. Non-prompting; `usable` off Linux.
/// Tests override it to simulate a locked keyring.
final apiKeysKeyringProvider = FutureProvider.autoDispose<KeyringAvailability>(
  (ref) => probeLinuxKeyring(),
);

String apiKeyStatusLabel(L10n l10n, ApiKeyStatus status) => switch (status) {
  ApiKeyStatus.stored => l10n.settingsApiKeyStatusStored,
  ApiKeyStatus.missing => l10n.settingsApiKeyStatusMissing,
  ApiKeyStatus.keyringLocked => l10n.settingsApiKeyStatusKeyringLocked,
};

ApiKeyStatus _watchStatus(WidgetRef ref, ApiKeyProvider provider) {
  final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
  final availability =
      ref.watch(apiKeysKeyringProvider).value ?? KeyringAvailability.usable;
  return apiKeyStatus(provider.valueIn(settings), availability);
}

class ApiKeysSection extends ConsumerStatefulWidget {
  const ApiKeysSection({super.key});

  @override
  ConsumerState<ApiKeysSection> createState() => _ApiKeysSectionState();
}

class _ApiKeysSectionState extends ConsumerState<ApiKeysSection> {
  final _controllers = {
    for (final p in ApiKeyProvider.values) p: TextEditingController(),
  };
  final _visible = {for (final p in ApiKeyProvider.values) p: false};

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;

    return Semantics(
      identifier: 'settings-api-keys-page',
      container: true,
      child: WpSettingsGroup(
        children: [
          for (final (i, p) in ApiKeyProvider.values.indexed) ...[
            if (i > 0) settingsInlineBreak,
            _keyRow(context, l10n, settings, p),
          ],
        ],
      ),
    );
  }

  Widget _keyRow(
    BuildContext context,
    L10n l10n,
    AppSettings settings,
    ApiKeyProvider p,
  ) {
    final controller = _controllers[p]!;
    syncController(controller, p.valueIn(settings));
    final title = switch (p) {
      ApiKeyProvider.openAi => l10n.settingsOpenAiApiKey,
      ApiKeyProvider.deepgram => l10n.settingsDeepgramApiKey,
    };
    final (usedBy, explanation) = switch (p) {
      ApiKeyProvider.openAi => (
        l10n.settingsApiKeysOpenAiUsedBy,
        l10n.settingsOpenAiApiKeySubtitle,
      ),
      ApiKeyProvider.deepgram => (
        l10n.settingsApiKeysDeepgramUsedBy,
        l10n.settingsDeepgramApiKeySubtitle,
      ),
    };
    return WpSettingsRow(
      rowId: p.rowId,
      title: title,
      subtitle: '$usedBy\n$explanation',
      // The field goes under the explanation: beside it, the field and its
      // status took up to 420 px and left the explanation a narrow column.
      controlBelow: true,
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          settingsApiKeyField(
            context: context,
            controller: controller,
            obscure: !_visible[p]!,
            onToggle: () => setState(() => _visible[p] = !_visible[p]!),
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .updateSettings((s) => p.write(s, v)),
            semanticLabel: title,
            fieldTestId: 'settings-api-keys-${p.id}-field',
            visibilityTestId: 'settings-api-keys-${p.id}-visibility',
          ),
          const SizedBox(height: WpSpacing.xs),
          _ApiKeyStatusText(
            testId: 'settings-api-keys-${p.id}-status',
            status: _watchStatus(ref, p),
          ),
        ],
      ),
    );
  }
}

class _ApiKeyStatusText extends StatelessWidget {
  const _ApiKeyStatusText({required this.testId, required this.status});

  final String testId;
  final ApiKeyStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final (icon, color) = switch (status) {
      ApiKeyStatus.stored => (LucideIcons.circleCheck, WpColors.success),
      ApiKeyStatus.missing => (LucideIcons.circleDashed, WpColors.textMuted),
      ApiKeyStatus.keyringLocked => (LucideIcons.lock, WpColors.warning),
    };
    final label = apiKeyStatusLabel(l10n, status);
    return Semantics(
      identifier: testId,
      key: ValueKey(testId),
      container: true,
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: WpIconSize.sm, color: color),
            const SizedBox(width: WpSpacing.xs),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: kWpUiFont,
                  fontFamilyFallback: kWpFontFallback,
                  fontSize: WpTypography.body,
                ).copyWith(color: WpColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Status line in Speech recognition and Smart Mode: which key the chosen
/// provider needs, whether it is there, and a button to the API keys area.
class ApiKeyStatusLinkRow extends ConsumerWidget {
  const ApiKeyStatusLinkRow({
    super.key,
    required this.rowId,
    required this.provider,
    required this.linkTestId,
    this.indent = false,
  });

  final String rowId;
  final ApiKeyProvider provider;
  final String linkTestId;
  final bool indent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final status = _watchStatus(ref, provider);
    return WpSettingsRow(
      rowId: rowId,
      indent: indent,
      title: l10n.settingsAreaApiKeys,
      subtitle: '${provider.displayName} · ${apiKeyStatusLabel(l10n, status)}',
      trailing: WpButton(
        key: ValueKey(linkTestId),
        testId: linkTestId,
        label: l10n.settingsApiKeysManage,
        variant: WpButtonVariant.secondary,
        onPressed: () {
          ref.read(settingsScrollTargetProvider.notifier).set(provider.rowId);
          ref.read(activePageProvider.notifier).setPage('settings');
        },
      ),
    );
  }
}
