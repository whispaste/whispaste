import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_info.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/navigation/page_state.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../services/deploy_channel_service.dart';
import '../../services/update_service.dart';
import '../../widgets/page_shell.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/wp_page_header.dart';
import '../help/help_target.dart';
import 'sections/about_section.dart';
import 'sections/automation_api_section.dart';
import 'sections/cloud_advanced_section.dart' show AdvancedSection;
import 'sections/feedback_section.dart';
import 'sections/history_section.dart';
import 'sections/interface_appearance_section.dart';
import 'sections/interface_section.dart';
import 'sections/overlay_button_section.dart';
import 'sections/privacy_section.dart';
import 'sections/recording_sections.dart';
import 'sections/settings_portability_section.dart';
import 'sections/shortcuts_section.dart';
import 'sections/smart_mode_section.dart';
import 'sections/stt_section.dart';
import 'sections/text_processing_section.dart';
import 'sections/updates_section.dart';
import 'search/settings_search_provider.dart';
import 'settings_areas.dart';
import 'settings_widgets.dart';
import 'widgets/settings_navigation.dart';
import 'widgets/wp_settings_group.dart';
import 'widgets/settings_scroll_affordance.dart';
import 'widgets/settings_search_field.dart';

/// Width below which the navigation collapses into an area dropdown above the
/// page (spec §2).
const double _kNavCollapseWidth = 760;

/// Text scale from which the navigation collapses too.
const double _kNavCollapseTextScale = 1.3;

/// Keeps the cards clear of the scrollbar thumb, which paints over the
/// trailing edge of the scroll view (UX-035). The gutter is directional, so it
/// moves to the left edge in RTL together with the thumb.
Widget _withScrollGutter(Widget child) {
  return Padding(
    padding: const EdgeInsetsDirectional.only(end: WpSpacing.md),
    child: child,
  );
}

/// Settings page (WP-23b): navigation with eight areas on the left, the
/// selected area's sections on the right.
///
/// Deep links hand over a row id ([settingsScrollTargetProvider]). The page
/// switches to that row's area first, then scrolls to its section and marks it
/// with a transient tint ([settingsHighlightTargetProvider]). Legacy
/// section keys still resolve, so older callers keep working.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _searchFocusNode = FocusNode();

  final _sectionKeys = <String, GlobalKey>{
    'interface': GlobalKey(),
    'appearance': GlobalKey(),
    'stt': GlobalKey(),
    'smartMode': GlobalKey(),
    'audio': GlobalKey(),
    'afterTranscription': GlobalKey(),
    'textProcessing': GlobalKey(),
    'overlay': GlobalKey(),
    'floatingButton': GlobalKey(),
    'hotkey': GlobalKey(),
    'sound': GlobalKey(),
    'recordingSafety': GlobalKey(),
    'history': GlobalKey(),
    'settingsPortability': GlobalKey(),
    'advanced': GlobalKey(),
    'automationApi': GlobalKey(),
    'updates': GlobalKey(),
    'betaChannel': GlobalKey(),
    'privacy': GlobalKey(),
    'about': GlobalKey(),
  };

  /// Row to scroll to once the area that contains it has been built.
  String? _pendingScrollRowId;

  Timer? _highlightClearTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyScrollTarget();
    });
  }

  @override
  void dispose() {
    _highlightClearTimer?.cancel();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// Consumes a pending deep link: switches the area if needed, then scrolls
  /// after the frame that builds it.
  void _applyScrollTarget() {
    if (!mounted) return;
    final target = ref.read(settingsScrollTargetProvider);
    if (target == null) return;
    ref.read(settingsScrollTargetProvider.notifier).set(null);

    final entry = settingsRowAnchorFor(target);
    if (entry == null) return;
    final host = entry.hostArea;
    if (host == null) {
      // Moved to the Help page (Hilfe): leave Settings for its tab.
      ref
          .read(helpTargetProvider.notifier)
          .set(HelpTarget(tab: helpTabForRow(target)));
      ref.read(activePageProvider.notifier).setPage('help');
      return;
    }
    ref.read(settingsHighlightTargetProvider.notifier).set(entry.rowId);
    if (host != ref.read(settingsAreaProvider)) {
      _pendingScrollRowId = entry.rowId;
      ref.read(settingsAreaProvider.notifier).select(host);
      return;
    }
    _scrollTo(entry.rowId);
  }

  void _scrollTo(String rowId) {
    final targetContext = settingsRowKey(rowId).currentContext;
    if (targetContext == null) return;
    Scrollable.ensureVisible(
      targetContext,
      duration: WpMotion.durationFor(targetContext, WpMotion.smooth),
      curve: Curves.easeInOut,
      // Not glued to the top edge: the row lands about a fifth of the way down
      // the viewport, with room for the page header above the area.
      alignment: 0.2,
    );
  }

  void _startHighlightClearTimer() {
    _highlightClearTimer?.cancel();
    _highlightClearTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        ref.read(settingsHighlightTargetProvider.notifier).set(null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    // A deep link may arrive while the page is open (search, quick-note hint).
    ref.listen(settingsScrollTargetProvider, (_, target) {
      if (target != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _applyScrollTarget();
        });
      }
    });

    // Watch highlight target: cleared automatically after 1.5 s.
    ref.listen(settingsHighlightTargetProvider, (_, target) {
      if (target != null) {
        _startHighlightClearTimer();
      }
    });

    final highlightTarget = ref.watch(settingsHighlightTargetProvider);
    final area = ref.watch(settingsAreaProvider);

    final deployChannel = ref.watch(deployChannelProvider);

    final updatePhase = ref.watch(updateProvider).phase;

    // A deep link to an area switched the area in the previous frame; scroll
    // to its section once that frame has been built.
    final pending = _pendingScrollRowId;
    if (pending != null) {
      _pendingScrollRowId = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollTo(pending);
      });
    }

    final builders = <String, Widget Function()>{
      'interface': () =>
          InterfaceGeneralSection(key: _sectionKeys['interface']),
      'appearance': () =>
          InterfaceAppearanceSection(key: _sectionKeys['appearance']),
      'stt': () => SpeechRecognitionSection(key: _sectionKeys['stt']),
      'smartMode': () => SmartModeSection(key: _sectionKeys['smartMode']),
      'audio': () => AudioSection(key: _sectionKeys['audio']),
      'afterTranscription': () =>
          AfterTranscriptionSection(key: _sectionKeys['afterTranscription']),
      'textProcessing': () =>
          TextProcessingSection(key: _sectionKeys['textProcessing']),
      'overlay': () => OverlaySection(key: _sectionKeys['overlay']),
      'floatingButton': () =>
          FloatingButtonSection(key: _sectionKeys['floatingButton']),
      'hotkey': () => KeyboardShortcutSection(key: _sectionKeys['hotkey']),
      'sound': () => SoundFeedbackSection(key: _sectionKeys['sound']),
      'recordingSafety': () =>
          RecordingSafetySection(key: _sectionKeys['recordingSafety']),
      'history': () => HistorySection(key: _sectionKeys['history']),
      'settingsPortability': () =>
          SettingsPortabilitySection(key: _sectionKeys['settingsPortability']),
      'advanced': () => AdvancedSection(key: _sectionKeys['advanced']),
      'automationApi': () =>
          AutomationApiSection(key: _sectionKeys['automationApi']),
      'updates': () => UpdatesSection(key: _sectionKeys['updates']),
      'betaChannel': () => BetaChannelSection(key: _sectionKeys['betaChannel']),
      'privacy': () => PrivacySection(key: _sectionKeys['privacy']),
      'about': () => AboutSection(key: _sectionKeys['about']),
    };

    // Sections of the selected area, minus the ones this platform or channel
    // cannot show at all. Store-restricted rows stay visible (disabled, with
    // their reason), see WP-23g.
    final sectionKeys = kSettingsAreaSections[area] ?? const <String>[];
    final visible = sectionKeys.where((key) {
      if (key == 'floatingButton' &&
          !FloatingButtonSection.isSupportedPlatform) {
        return false;
      }
      // Package-managed installs: no self-updater, so no card at all.
      if (key == 'updates' && deployChannel == DeployChannel.packageManaged) {
        return false;
      }
      return true;
    }).toList();

    final children = <Widget>[];
    for (var i = 0; i < visible.length; i++) {
      final key = visible[i];
      // No card around a section: each [WpSettingsGroup] inside it is the one
      // card level of the area (spec §5), so dark and navy read like light.
      children.add(builders[key]!());
      if (i < visible.length - 1) children.add(settingsSectionBreak);
    }

    // A query that matches no row replaces the area with an empty state that
    // offers the one loud action of the page (WP-23c, spec §4).
    final query = ref.watch(settingsSearchQueryProvider).trim();
    final noMatch =
        query.isNotEmpty && ref.watch(settingsSearchMatchesProvider).isEmpty;

    final content = noMatch
        ? _SettingsSearchEmpty(l10n: l10n, query: query)
        : SettingsRowHighlight(
            rowId: highlightTarget,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WpPageHeader(title: settingsAreaLabel(l10n, area)),
                const SizedBox(height: WpSpacing.lg),
                ...children,
              ],
            ),
          );

    final footer = _SettingsFooter(
      storeChannel: deployChannel == DeployChannel.store,
      updatePhase: updatePhase,
    );

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        // Ctrl+F / Cmd+F: focus the settings search field.
        SingleActivator(
          LogicalKeyboardKey.keyF,
          control: !Platform.isMacOS,
          meta: Platform.isMacOS,
        ): () {
          _searchFocusNode.requestFocus();
        },
      },
      child: Focus(
        autofocus: true,
        skipTraversal: true,
        child: WpPageShell(
          // Fixed height: the navigation column and the area each scroll
          // on their own, so the shell must not scroll the whole page.
          scrollable: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final narrow =
                  constraints.maxWidth < _kNavCollapseWidth ||
                  MediaQuery.textScalerOf(context).scale(1) >=
                      _kNavCollapseTextScale;
              final searchField = SettingsSearchField(
                focusNode: _searchFocusNode,
              );
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    searchField,
                    const SizedBox(height: WpSpacing.md),
                    settingsDropdown(
                      context: context,
                      value: area.id,
                      items: [for (final a in SettingsArea.values) a.id],
                      labels: [
                        for (final a in SettingsArea.values)
                          settingsAreaLabel(l10n, a),
                      ],
                      onChanged: (v) => ref
                          .read(settingsAreaProvider.notifier)
                          .select(
                            SettingsArea.values.firstWhere((a) => a.id == v),
                          ),
                    ),
                    const SizedBox(height: WpSpacing.lg),
                    Expanded(
                      child: SettingsScrollAffordance(
                        child: _withScrollGutter(content),
                      ),
                    ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SettingsNavigation(
                    selected: area,
                    onSelect: (a) =>
                        ref.read(settingsAreaProvider.notifier).select(a),
                    header: searchField,
                    footer: footer,
                  ),
                  const SizedBox(width: WpSpacing.xl),
                  Expanded(
                    child: SettingsScrollAffordance(
                      child: _withScrollGutter(content),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Empty state of a search without a match (spec §4). Help is the only loud
/// action on the page: it opens the handbook on the Help page with the same
/// query (UIA-SET-11).
class _SettingsSearchEmpty extends ConsumerWidget {
  const _SettingsSearchEmpty({required this.l10n, required this.query});

  final L10n l10n;
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      key: const ValueKey('settings-search-empty'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.settingsSearchNoResults,
          style: TextStyle(
            fontSize: WpTypography.heading,
            fontWeight: FontWeight.w600,
            color: WpColors.textPrimary,
          ),
        ),
        const SizedBox(height: WpSpacing.xs),
        Text(
          l10n.settingsSearchNoResultsHint,
          style: TextStyle(
            fontSize: WpTypography.body,
            color: WpColors.textMuted,
          ),
        ),
        const SizedBox(height: WpSpacing.lg),
        WpButton(
          key: const ValueKey('settings-search-empty-help'),
          label: l10n.settingsSearchEmptyHelp,
          variant: WpButtonVariant.primary,
          onPressed: () {
            ref
                .read(helpTargetProvider.notifier)
                .set(HelpTarget(tab: HelpTab.manual, query: query));
            ref.read(activePageProvider.notifier).setPage('help');
          },
        ),
      ],
    );
  }
}

/// Version and update status under the navigation (spec §2). Store builds show
/// that the store owns updates instead of a status.
class _SettingsFooter extends StatelessWidget {
  const _SettingsFooter({
    required this.storeChannel,
    required this.updatePhase,
  });

  final bool storeChannel;
  final UpdatePhase updatePhase;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final status = storeChannel
        ? l10n.settingsNavStoreUpdates
        : updatePhase == UpdatePhase.available
        ? l10n.settingsNavUpdateAvailable
        : l10n.settingsNavUpToDate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.settingsNavVersion(appVersion),
          style: TextStyle(
            fontSize: WpTypography.body,
            color: WpColors.textMuted,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          status,
          style: TextStyle(
            fontSize: WpTypography.body,
            color: WpColors.textMuted,
          ),
        ),
      ],
    );
  }
}
