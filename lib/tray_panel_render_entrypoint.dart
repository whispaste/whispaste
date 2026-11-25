/// Dedicated Flutter entrypoint of the tray / menu bar panel (#920).
///
/// The native `TrayPanelHost` hosts this second engine in a non-activating
/// panel at the tray icon (same shell pattern as the snippet picker, ADR
/// 0002). The engine only paints a [TrayPanelContent] snapshot and reports
/// presses; recording, hotkeys and paste stay in the main engine.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show Bidi;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'core/accessibility/accessibility_reply_binding.dart';
import 'core/accessibility/system_motion.dart';
import 'core/l10n/generated/app_localizations.dart';
import 'core/theme/colors.dart';
import 'core/theme/persisted_appearance.dart';
import 'core/theme/theme.dart';
import 'core/theme/tokens.dart';
import 'services/tray_panel/tray_panel_protocol.dart';
import 'services/tray_panel/tray_panel_render_channel.dart';
import 'shared_render_engine_helpers.dart'
    show RenderEngineState, detachFromEmbedderAppLifecycle;
import 'widgets/wp_focus_ring.dart';
import 'widgets/wp_keycap.dart';
import 'widgets/wp_row_divider.dart';

const String _renderChannelName = 'com.whispaste.tray_panel_render';

/// Transparent margin around the card that carries the floating shadow; the
/// native shell sizes the window as card + 2 * this inset.
const double kTrayPanelShadowInset = 20;

/// Card width in logical px (the window adds the shadow inset).
const double kTrayPanelCardWidth = 320;

/// Tallest card; a longer picker list scrolls inside it.
const double kTrayPanelMaxCardHeight = 520;

void runTrayPanelEngine() {
  WpRenderEngineBinding.ensureInitialized();
  // Same reason as the snippet picker: a bogus embedder `hidden` would wedge
  // this late-booted engine; visibility is relayed in-band instead.
  detachFromEmbedderAppLifecycle();
  runApp(const SystemMotionScope(child: TrayPanelRenderApp()));
}

/// The tray panel engine's root widget. Public only so a test can pump it
/// with a mocked render channel; [runTrayPanelEngine] is its one real caller.
@visibleForTesting
class TrayPanelRenderApp extends StatefulWidget {
  const TrayPanelRenderApp({super.key});

  @override
  State<TrayPanelRenderApp> createState() => _TrayPanelRenderAppState();
}

class _TrayPanelRenderAppState
    extends RenderEngineState<TrayPanelRenderApp, TrayPanelRenderChannel> {
  _TrayPanelRenderAppState()
    : super(lookupL10n(const Locale('en')).trayPanelSemanticsLabel);

  TrayPanelContent? _content;
  late WpThemeColors _colors;

  /// Bumped on every show, so the panel opens on its main view again.
  int _showCount = 0;

  @override
  void initState() {
    super.initState();
    _colors = _resolveAppearance();
  }

  WpThemeColors _resolveAppearance() => resolvePersistedAppearance(
    WidgetsBinding.instance.platformDispatcher.platformBrightness,
  );

  @override
  TrayPanelRenderChannel createChannel() => TrayPanelRenderChannel(
    name: _renderChannelName,
    onContent: (content, {required shown}) => setState(() {
      _content = content;
      if (shown) {
        _colors = _resolveAppearance();
        _showCount++;
        // The engine lives for the whole app session; a language changed in
        // the meantime reaches the panel's own texts (back row, screen
        // reader label, text direction) on the next open instead of after a
        // restart (#1682, same mechanism as the snippet picker in #1680).
        refreshL10n();
      }
    }),
    onPanelHidden: () {},
  );

  @override
  String labelOf(L10n l10n) => l10n.trayPanelSemanticsLabel;

  @override
  Widget build(BuildContext context) {
    final l = l10n ?? lookupL10n(const Locale('en'));
    final content = _content;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: wpThemeFor(_colors),
      locale: Locale(l.localeName),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: Directionality(
          textDirection: Bidi.isRtlLanguage(l.localeName)
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: Semantics(
            container: true,
            label: semanticsLabel,
            identifier: 'tray-panel-root',
            child: content == null
                ? const SizedBox.shrink()
                : TrayPanelBody(
                    key: ValueKey(_showCount),
                    content: content,
                    backLabel: l.trayPanelBack,
                    onAction: channel.action,
                    onCancel: channel.cancel,
                    onResize: channel.resize,
                  ),
          ),
        ),
      ),
    );
  }
}

/// Which page of the panel is showing: the main page, the picker of one
/// switch, or the overflow ("More") list.
sealed class _View {
  const _View();
}

class _MainView extends _View {
  const _MainView();
}

class _PickerView extends _View {
  const _PickerView(this.switchId);
  final String switchId;
}

class _OverflowView extends _View {
  const _OverflowView();
}

/// The painted panel. Public so a hand-over test can pump it.
class TrayPanelBody extends StatefulWidget {
  const TrayPanelBody({
    super.key,
    required this.content,
    required this.backLabel,
    required this.onAction,
    required this.onCancel,
    this.onResize,
  });

  final TrayPanelContent content;
  final String backLabel;
  final ValueChanged<String> onAction;
  final VoidCallback onCancel;

  /// Window height (card + shadow inset) whenever the painted card changes.
  final ValueChanged<double>? onResize;

  @override
  State<TrayPanelBody> createState() => _TrayPanelBodyState();
}

class _TrayPanelBodyState extends State<TrayPanelBody> {
  final _cardKey = GlobalKey();
  _View _view = const _MainView();
  double? _reported;

  /// True once a key was pressed in this showing of the panel, false again
  /// after a pointer press: the focus ring is for keyboard users only. The
  /// panel autofocuses Diktieren on open, and a ring around a button the user
  /// just clicked the tray icon for read as a second border (#1498).
  final _keyboardUsed = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _keyboardUsed.dispose();
    super.dispose();
  }

  TrayPanelSwitch? _switchOf(String id) {
    for (final s in widget.content.switches) {
      if (s.id == id && s.enabled) return s;
    }
    return null;
  }

  /// Escape steps back from a picker first, then closes the panel.
  void _escape() {
    if (_view is _MainView) {
      widget.onCancel();
    } else {
      setState(() => _view = const _MainView());
    }
  }

  void _choose(String id) {
    widget.onAction(id);
    if (_view is! _MainView) setState(() => _view = const _MainView());
  }

  void _reportSize() {
    final onResize = widget.onResize;
    final size = _cardKey.currentContext?.size;
    if (onResize == null || size == null) return;
    final height = size.height + 2 * kTrayPanelShadowInset;
    if (height == _reported) return;
    _reported = height;
    onResize(height);
  }

  @override
  Widget build(BuildContext context) {
    // A picker whose switch vanished or got locked (recording started) falls
    // back to the main page.
    final view = _view;
    final pickerSwitch = view is _PickerView ? _switchOf(view.switchId) : null;
    final page = switch (view) {
      _PickerView() when pickerSwitch != null => _PickerPage(
        sw: pickerSwitch,
        backLabel: widget.backLabel,
        onBack: _escape,
        onChoose: _choose,
      ),
      _OverflowView() => _OverflowPage(
        content: widget.content,
        backLabel: widget.backLabel,
        onBack: _escape,
        onChoose: _choose,
      ),
      _ => _MainPage(
        content: widget.content,
        onAction: widget.onAction,
        onOpenPicker: (id) => setState(() => _view = _PickerView(id)),
        onOpenOverflow: () => setState(() => _view = const _OverflowView()),
      ),
    };
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportSize());
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowDown): NextFocusIntent(),
        SingleActivator(LogicalKeyboardKey.arrowUp): PreviousFocusIntent(),
      },
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): _escape},
        child: FocusScope(
          autofocus: true,
          // Below the shortcuts, so arrow keys pass here before they move
          // focus; the event itself is never consumed.
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent) _keyboardUsed.value = true;
              return KeyEventResult.ignored;
            },
            child: Listener(
              onPointerDown: (_) => _keyboardUsed.value = false,
              child: _KeyboardUse(
                notifier: _keyboardUsed,
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  minHeight: 0,
                  maxHeight:
                      kTrayPanelMaxCardHeight + 2 * kTrayPanelShadowInset,
                  child: Padding(
                    padding: const EdgeInsets.all(kTrayPanelShadowInset),
                    child: SizedBox(
                      key: _cardKey,
                      width: kTrayPanelCardWidth,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: WpRadius.borderLg,
                          boxShadow: WpShadows.elevated,
                        ),
                        child: ClipRRect(
                          borderRadius: WpRadius.borderLg,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: WpColors.floatingSurface,
                              border: Border.all(color: WpColors.borderDefault),
                              borderRadius: WpRadius.borderLg,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(WpSpacing.sm),
                              child: KeyedSubtree(
                                key: ValueKey(switch (view) {
                                  _PickerView(:final switchId) =>
                                    'picker-$switchId',
                                  _OverflowView() => 'overflow',
                                  _MainView() => 'main',
                                }),
                                child: page,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Whether the user has pressed a key in this showing of the panel; the
/// panel's controls show their focus ring only then.
class _KeyboardUse extends InheritedNotifier<ValueNotifier<bool>> {
  const _KeyboardUse({required super.notifier, required super.child});

  /// True outside a panel body, so a lone control keeps the plain ring rule.
  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_KeyboardUse>()
          ?.notifier
          ?.value ??
      true;
}

// ── Pages ────────────────────────────────────────────────────────────────────

class _MainPage extends StatelessWidget {
  const _MainPage({
    required this.content,
    required this.onAction,
    required this.onOpenPicker,
    required this.onOpenOverflow,
  });

  final TrayPanelContent content;
  final ValueChanged<String> onAction;
  final ValueChanged<String> onOpenPicker;
  final VoidCallback onOpenOverflow;

  @override
  Widget build(BuildContext context) {
    final recording = content.phase == TrayPanelPhase.recording;
    final busy = content.phase == TrayPanelPhase.transcribing;
    final banner = content.banner;
    final unlock = content.recentUnlock;
    final all = content.recentAll;
    final hasRecent = content.recent.isNotEmpty || unlock != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (banner != null) ...[
          _BannerRow(entry: banner, onPressed: () => onAction(banner.id)),
          const SizedBox(height: WpSpacing.sm),
        ],
        _StateRow(
          label: content.statusLabel,
          color: recording
              ? WpColors.recordingAccent
              : busy
              ? WpColors.warning
              : WpColors.success,
        ),
        const SizedBox(height: WpSpacing.sm),
        _PrimaryButton(
          label: content.primaryLabel,
          shortcut: content.shortcut,
          recording: recording,
          enabled: !busy,
          onPressed: () => onAction(TrayPanelAction.primary),
        ),
        if (content.switches.isNotEmpty) ...[
          const SizedBox(height: WpSpacing.xs),
          for (final s in content.switches)
            _PanelRow(
              testId: 'tray-panel-switch-${s.id}',
              icon: _switchIcon(s.id),
              label: s.label,
              value: s.value,
              enabled: s.enabled,
              drillIn: true,
              onPressed: () => onOpenPicker(s.id),
            ),
        ],
        if (hasRecent) ...[
          const _Divider(),
          _SectionLabel(content.recentLabel),
          Semantics(
            identifier: 'tray-panel-recent-list',
            container: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final r in content.recent)
                  _PanelRow(
                    testId: 'tray-panel-recent-${r.id}',
                    icon: LucideIcons.copy,
                    label: r.label,
                    muted: true,
                    onPressed: () => onAction(r.id),
                  ),
                if (all != null)
                  _PanelRow(
                    testId: 'tray-panel-recent-all',
                    icon: LucideIcons.history,
                    label: all.label,
                    drillIn: true,
                    onPressed: () => onAction(all.id),
                  ),
                if (unlock != null)
                  _PanelRow(
                    testId: 'tray-panel-recent-unlock',
                    icon: LucideIcons.lockKeyhole,
                    label: unlock.label,
                    onPressed: () => onAction(unlock.id),
                  ),
              ],
            ),
          ),
        ],
        const _Divider(),
        Row(
          children: [
            Expanded(
              child: _PanelRow(
                testId: 'tray-panel-open-app',
                icon: LucideIcons.appWindow,
                label: content.openApp.label,
                onPressed: () => onAction(content.openApp.id),
              ),
            ),
            _IconButton(
              testId: 'tray-panel-settings',
              icon: LucideIcons.settings,
              label: content.settings.label,
              onPressed: () => onAction(content.settings.id),
            ),
            if (content.overflow.isNotEmpty)
              _IconButton(
                testId: 'tray-panel-overflow',
                icon: LucideIcons.ellipsis,
                label: content.overflowLabel,
                onPressed: onOpenOverflow,
              ),
          ],
        ),
      ],
    );
  }
}

IconData _switchIcon(String id) => switch (id) {
  TrayPanelSwitchIds.microphone => LucideIcons.mic,
  TrayPanelSwitchIds.language => LucideIcons.languages,
  TrayPanelSwitchIds.profile => LucideIcons.userRound,
  _ => LucideIcons.sparkles,
};

IconData _overflowIcon(String id) => switch (id) {
  'transcribe_file' => LucideIcons.fileAudio,
  'side_panel' => LucideIcons.panelRight,
  'feedback' => LucideIcons.messageSquare,
  'quit' => LucideIcons.power,
  _ => LucideIcons.chevronRight,
};

class _PickerPage extends StatelessWidget {
  const _PickerPage({
    required this.sw,
    required this.backLabel,
    required this.onBack,
    required this.onChoose,
  });

  final TrayPanelSwitch sw;
  final String backLabel;
  final VoidCallback onBack;
  final ValueChanged<String> onChoose;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BackRow(title: sw.label, backLabel: backLabel, onPressed: onBack),
        const _Divider(),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            children: [
              for (final o in sw.options)
                _PanelRow(
                  testId: 'tray-panel-picker-option-${o.id}',
                  label: o.label,
                  checked: o.checked,
                  onPressed: () => onChoose(o.id),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OverflowPage extends StatelessWidget {
  const _OverflowPage({
    required this.content,
    required this.backLabel,
    required this.onBack,
    required this.onChoose,
  });

  final TrayPanelContent content;
  final String backLabel;
  final VoidCallback onBack;
  final ValueChanged<String> onChoose;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BackRow(
          title: content.overflowLabel,
          backLabel: backLabel,
          onPressed: onBack,
        ),
        const _Divider(),
        for (final o in content.overflow)
          _PanelRow(
            testId: 'tray-panel-overflow-${o.id}',
            icon: _overflowIcon(o.id),
            label: o.label,
            onPressed: () => onChoose(o.id),
          ),
      ],
    );
  }
}

// ── Building blocks ──────────────────────────────────────────────────────────

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: WpSpacing.xs),
    child: WpRowDivider(),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      WpSpacing.xs,
      WpSpacing.xxs,
      WpSpacing.xs,
      WpSpacing.xxs,
    ),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: TextStyle(
          color: WpColors.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

class _StateRow extends StatelessWidget {
  const _StateRow({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: 'tray-panel-state',
      liveRegion: true,
      label: label,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: WpSpacing.xxs),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: WpSpacing.xs),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: WpColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Focusable, pressable surface with the app's keyboard focus ring. Enter and
/// Space activate it through the [InkWell].
class _Pressable extends StatefulWidget {
  const _Pressable({
    required this.testId,
    required this.semanticsLabel,
    required this.onPressed,
    required this.child,
    this.enabled = true,
    this.autofocus = false,
    this.checked,
    this.color,
    this.radius,
  });

  final String testId;
  final String semanticsLabel;
  final VoidCallback onPressed;
  final Widget child;
  final bool enabled;
  final bool autofocus;
  final bool? checked;
  final Color? color;
  final BorderRadius? radius;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.radius ?? WpRadius.borderSm;
    return Semantics(
      identifier: widget.testId,
      // A row with a checked state is an option of a picker: a radio button,
      // because the desktop embedders let a button role drop the state.
      button: widget.checked == null,
      inMutuallyExclusiveGroup: widget.checked != null ? true : null,
      enabled: widget.enabled,
      checked: widget.checked,
      label: widget.semanticsLabel,
      excludeSemantics: true,
      child: WpFocusRing(
        focusNode: _focus,
        radius: radius.topLeft.x,
        visible: _KeyboardUse.of(context),
        child: Material(
          color: widget.color ?? Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            focusNode: _focus,
            autofocus: widget.autofocus,
            canRequestFocus: widget.enabled,
            borderRadius: radius,
            hoverColor: WpColors.hover,
            focusColor: Colors.transparent,
            onTap: widget.enabled ? widget.onPressed : null,
            child: Opacity(
              opacity: widget.enabled ? 1 : 0.5,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelRow extends StatelessWidget {
  const _PanelRow({
    required this.testId,
    required this.label,
    required this.onPressed,
    this.icon,
    this.value,
    this.enabled = true,
    this.drillIn = false,
    this.muted = false,
    this.checked,
  });

  final String testId;
  final IconData? icon;
  final String label;
  final String? value;
  final bool enabled;
  final bool drillIn;
  final bool muted;

  /// Radio state of a picker option; null for a plain entry.
  final bool? checked;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final icon = this.icon;
    final value = this.value;
    return _Pressable(
      testId: testId,
      semanticsLabel: value == null ? label : '$label: $value',
      enabled: enabled,
      checked: checked,
      onPressed: onPressed,
      child: SizedBox(
        height: 36,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: WpSpacing.xs),
          child: Row(
            children: [
              if (checked != null) ...[
                SizedBox(
                  width: 16,
                  child: checked!
                      ? Icon(
                          LucideIcons.check,
                          size: WpIconSize.sm,
                          color: WpColors.accent,
                        )
                      : null,
                ),
                const SizedBox(width: WpSpacing.xs),
              ],
              if (icon != null) ...[
                Icon(icon, size: WpIconSize.sm, color: WpColors.textSecondary),
                const SizedBox(width: WpSpacing.xs),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: muted
                        ? WpColors.textSecondary
                        : WpColors.textPrimary,
                    fontSize: 14,
                  ),
                ),
              ),
              if (value != null) ...[
                const SizedBox(width: WpSpacing.xs),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: WpColors.textMuted, fontSize: 13),
                  ),
                ),
              ],
              if (drillIn) ...[
                const SizedBox(width: WpSpacing.xxs),
                Icon(
                  rtl ? LucideIcons.chevronLeft : LucideIcons.chevronRight,
                  size: WpIconSize.xs,
                  color: WpColors.textMuted,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BackRow extends StatelessWidget {
  const _BackRow({
    required this.title,
    required this.backLabel,
    required this.onPressed,
  });

  final String title;
  final String backLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return _Pressable(
      testId: 'tray-panel-picker-back',
      semanticsLabel: '$backLabel, $title',
      autofocus: true,
      onPressed: onPressed,
      child: SizedBox(
        height: 36,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: WpSpacing.xs),
          child: Row(
            children: [
              Icon(
                rtl ? LucideIcons.chevronRight : LucideIcons.chevronLeft,
                size: WpIconSize.sm,
                color: WpColors.textSecondary,
              ),
              const SizedBox(width: WpSpacing.xs),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: WpColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.testId,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final String testId;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: _Pressable(
        testId: testId,
        semanticsLabel: label,
        onPressed: onPressed,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: WpIconSize.sm, color: WpColors.textSecondary),
        ),
      ),
    );
  }
}

class _BannerRow extends StatelessWidget {
  const _BannerRow({required this.entry, required this.onPressed});

  final TrayPanelEntry entry;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      testId: 'tray-panel-banner',
      semanticsLabel: entry.label,
      color: WpColors.warningActiveFill,
      radius: WpRadius.borderMd,
      onPressed: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.sm,
          vertical: WpSpacing.xs,
        ),
        child: Row(
          children: [
            Icon(
              LucideIcons.triangleAlert,
              size: WpIconSize.sm,
              color: WpColors.warning,
            ),
            const SizedBox(width: WpSpacing.xs),
            Expanded(
              child: Text(
                entry.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: WpColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.shortcut,
    required this.recording,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final String shortcut;
  final bool recording;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final fill = recording ? WpColors.primaryRecordFill : WpColors.ctaFill;
    final ink = recording ? WpColors.onPrimaryRecord : WpColors.onCta;
    return _Pressable(
      testId: 'tray-panel-primary',
      semanticsLabel: label,
      enabled: enabled,
      autofocus: true,
      color: fill,
      radius: WpRadius.borderMd,
      onPressed: onPressed,
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: WpSpacing.md),
          child: Row(
            children: [
              Icon(
                recording ? LucideIcons.square : LucideIcons.mic,
                size: WpIconSize.md,
                color: ink,
              ),
              const SizedBox(width: WpSpacing.xs),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (shortcut.isNotEmpty && !recording)
                WpKeycap.onFilled(label: shortcut, ink: ink),
            ],
          ),
        ),
      ),
    );
  }
}
