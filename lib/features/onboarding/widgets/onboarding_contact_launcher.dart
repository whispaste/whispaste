/// The round contact button at the bottom right of every onboarding screen
/// and the panel it opens, modelled on the website contact widget
/// (`website/src/components/ContactWidget.astro`, `.cw-launcher`).
///
/// The overlay places the launcher; the panel opens above and to the left of
/// it, anchored to the corner. Esc closes the panel, Tab stays inside it, and
/// focus goes back to the launcher on close.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_info.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/floating_surface.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/external_link.dart';
import '../../../widgets/wp_button.dart';
import '../../../widgets/wp_consent_checkbox.dart';
import '../../../widgets/wp_filter_chip.dart';
import '../../../widgets/wp_focus_ring.dart';
import '../../../widgets/wp_icon_button.dart';
import '../../../widgets/wp_text_field.dart';
import 'onboarding_contact.dart';

const double _launcherSize = 56;
const double _panelMaxWidth = 384;
const double _panelGap = 12;

// Room kept free above the panel for the onboarding's phase bar.
const double _panelTopClearance = 64;

// Chat bubbles take at most this share of the panel width.
const double _bubbleMaxFraction = 0.92;

// The idle float: a slow, small bob and breath in size so the launcher reads
// as alive without pulling the eye from the screen's own content.
const Duration _floatPeriod = Duration(milliseconds: 3200);

// Half cycles of the float before it rests: three breaths after the launcher
// appears, then it stays still. A motion that runs for as long as the page is
// open costs frames and keeps drawing the eye away from the task.
const int _floatHalfCycles = 6;
const double _floatLift = 3;
const double _floatGrow = 0.045;

/// Contact launcher for the onboarding. [stepId] names the screen it sits on
/// and goes with a message only when the user opts in to technical details.
/// When [visible] switches from false to true the button fades in with a
/// slight rise (instant under "reduce motion"); while hidden it takes no
/// input and closes an open panel.
// loam-ignore: unused-public-exports – placed by the onboarding overlay (feat/onboarding-v6, whispaste-7f)
class OnboardingContactLauncher extends StatefulWidget {
  const OnboardingContactLauncher({
    super.key,
    required this.stepId,
    this.visible = true,
    this.onOpened,
  });

  final String stepId;
  final bool visible;

  /// Called each time the panel opens (the `contact_opened` event).
  final VoidCallback? onOpened;

  @override
  State<OnboardingContactLauncher> createState() =>
      _OnboardingContactLauncherState();
}

class _OnboardingContactLauncherState extends State<OnboardingContactLauncher>
    with TickerProviderStateMixin {
  final _portal = OverlayPortalController();
  final _launcherFocus = FocusNode(debugLabel: 'onboarding-contact-launcher');
  final _tapGroup = Object();

  late final AnimationController _appear = AnimationController(
    vsync: this,
    duration: WpMotion.smooth,
    value: widget.visible ? 1 : 0,
  );
  late final AnimationController _panel = AnimationController(
    vsync: this,
    duration: WpMotion.normal,
  );
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: _floatPeriod,
  );

  bool _hover = false;
  bool _pressed = false;

  // Set once the float has started; it runs its breaths once per launcher.
  bool _floated = false;

  bool get _open => _portal.isShowing;

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncFloat();
  }

  // Floats only while it is shown, idle and motion is allowed: hover, press
  // and an open panel hold it still so it never moves under the pointer.
  void _syncFloat() {
    final idle = widget.visible && !_hover && !_pressed && !_open;
    if (idle && !_reduceMotion) {
      if (!_float.isAnimating && !_floated) {
        _floated = true;
        _float.repeat(reverse: true, count: _floatHalfCycles);
      }
    } else if (_float.isAnimating || _float.value != 0) {
      _float.stop();
      _reduceMotion ? _float.value = 0 : _float.animateTo(0);
    }
  }

  @override
  void didUpdateWidget(OnboardingContactLauncher old) {
    super.didUpdateWidget(old);
    if (widget.visible == old.visible) return;
    if (widget.visible) {
      _reduceMotion ? _appear.value = 1 : _appear.forward(from: 0);
    } else {
      _appear.value = 0;
      _close(restoreFocus: false);
    }
    _syncFloat();
  }

  @override
  void dispose() {
    _appear.dispose();
    _panel.dispose();
    _float.dispose();
    _launcherFocus.dispose();
    super.dispose();
  }

  void _toggle() => _open ? _close() : _show();

  void _show() {
    widget.onOpened?.call();
    setState(_portal.show);
    _syncFloat();
    _reduceMotion ? _panel.value = 1 : _panel.forward(from: 0);
  }

  Future<void> _close({bool restoreFocus = true}) async {
    if (!_open) return;
    if (!_reduceMotion && mounted) await _panel.reverse();
    if (!mounted) return;
    setState(_portal.hide);
    _syncFloat();
    if (restoreFocus) _launcherFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final rise = Tween(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _appear, curve: WpMotion.defaultCurve));

    return AnimatedBuilder(
      animation: _appear,
      builder: (context, child) => IgnorePointer(
        ignoring: !widget.visible,
        child: ExcludeSemantics(
          excluding: !widget.visible,
          child: FadeTransition(
            opacity: _appear,
            child: SlideTransition(position: rise, child: child),
          ),
        ),
      ),
      child: OverlayPortal.overlayChildLayoutBuilder(
        controller: _portal,
        overlayChildBuilder: _buildPanel,
        child: TapRegion(groupId: _tapGroup, child: _buildLauncher(l10n)),
      ),
    );
  }

  Widget _buildLauncher(L10n l10n) {
    final borderColor = _hover || _launcherFocus.hasFocus
        ? WpColors.accent
        : WpColors.accent.withValues(alpha: 0.35);
    // The child's semantics are excluded, so the node carries its own
    // identifier and tap action; otherwise screen readers could not open it.
    return Semantics(
      identifier: 'onboarding-contact-launcher',
      button: true,
      expanded: _open,
      label: l10n.onboardingContactOpen,
      onTap: _toggle,
      excludeSemantics: true,
      child: Tooltip(
        message: l10n.onboardingContactOpen,
        waitDuration: WpMotion.tooltipWait,
        child: FocusableActionDetector(
          focusNode: _launcherFocus,
          mouseCursor: SystemMouseCursors.click,
          onShowHoverHighlight: (v) {
            setState(() => _hover = v);
            _syncFloat();
          },
          onFocusChange: (_) => setState(() {}),
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) => _toggle(),
            ),
          },
          child: GestureDetector(
            key: const ValueKey('onboarding-contact-launcher'),
            onTapDown: (_) => setState(() => _pressed = true),
            onTapCancel: () => setState(() => _pressed = false),
            onTap: () {
              setState(() => _pressed = false);
              _toggle();
            },
            child: AnimatedBuilder(
              animation: _float,
              builder: (context, child) {
                final t = Curves.easeInOut.transform(_float.value);
                return Transform.translate(
                  offset: Offset(0, -_floatLift * t),
                  child: Transform.scale(
                    scale: 1 + _floatGrow * t,
                    child: child,
                  ),
                );
              },
              child: WpFocusRing(
                focusNode: _launcherFocus,
                radius: _launcherSize / 2,
                child: RepaintBoundary(child: _buildLauncherFace(borderColor)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLauncherFace(Color borderColor) => AnimatedContainer(
    duration: _reduceMotion ? Duration.zero : WpMotion.fast,
    curve: WpMotion.defaultCurve,
    width: _launcherSize,
    height: _launcherSize,
    transformAlignment: Alignment.center,
    transform: Matrix4.identity()
      ..translateByDouble(0, _hover ? -2 : 0, 0, 1)
      ..scaleByDouble(_pressed ? 0.97 : 1, _pressed ? 0.97 : 1, 1, 1),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: WpColors.floatingSurface,
      border: Border.all(color: borderColor),
      boxShadow: WpShadows.overlay,
    ),
    child: Center(
      child: CustomPaint(
        size: const Size.square(24),
        painter: _SpeechBubblePainter(WpColors.accent),
      ),
    ),
  );

  Widget _buildPanel(BuildContext context, OverlayChildLayoutInfo info) {
    // The launcher's rect in overlay coordinates. The panel sits above it and
    // is right-aligned to it; the overlay places it, so no follower is needed.
    final screen = info.overlaySize;
    final origin = info.childPaintTransform.getTranslation();
    final launcherRight = origin.x + info.childSize.width;
    final launcherTop = origin.y;
    final width = (screen.width - 2 * WpSpacing.md).clamp(0.0, _panelMaxWidth);
    final maxHeight = (launcherTop - _panelGap - _panelTopClearance).clamp(
      0.0,
      double.infinity,
    );
    final curve = CurvedAnimation(parent: _panel, curve: WpMotion.defaultCurve);
    return Positioned(
      right: screen.width - launcherRight,
      bottom: screen.height - launcherTop + _panelGap,
      child: TapRegion(
        groupId: _tapGroup,
        onTapOutside: (_) => _close(restoreFocus: false),
        child: FadeTransition(
          opacity: curve,
          child: AnimatedBuilder(
            animation: curve,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, 8 * (1 - curve.value)),
              child: Transform.scale(
                scale: 0.98 + 0.02 * curve.value,
                alignment: Alignment.bottomRight,
                child: child,
              ),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: width,
                minWidth: width,
                maxHeight: maxHeight,
              ),
              child: _OnboardingContactPanel(
                stepId: widget.stepId,
                onClose: _close,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The panel: a chat thread. The greeting and the chosen topic come first,
/// then the idea board link or the message form, or the thank-you after a send.
class _OnboardingContactPanel extends ConsumerStatefulWidget {
  const _OnboardingContactPanel({required this.stepId, required this.onClose});

  final String stepId;
  final Future<void> Function({bool restoreFocus}) onClose;

  @override
  ConsumerState<_OnboardingContactPanel> createState() =>
      _OnboardingContactPanelState();
}

class _OnboardingContactPanelState
    extends ConsumerState<_OnboardingContactPanel> {
  final _message = TextEditingController();
  final _email = TextEditingController();
  // Started when the panel opens; the sender gets the elapsed time with the message.
  final _opened = Stopwatch()..start();
  OnboardingContactKind? _kind;
  bool _includeDiagnostics = false;
  bool _sending = false;
  bool _triedSend = false;
  OnboardingContactOutcome? _outcome;

  @override
  void dispose() {
    _opened.stop();
    _message.dispose();
    _email.dispose();
    super.dispose();
  }

  String _kindLabel(L10n l10n, OnboardingContactKind kind) => switch (kind) {
    OnboardingContactKind.idea => l10n.onboardingContactKindIdea,
    OnboardingContactKind.problem => l10n.onboardingContactKindProblem,
    OnboardingContactKind.question => l10n.onboardingContactKindQuestion,
    OnboardingContactKind.other => l10n.onboardingContactKindOther,
  };

  bool get _messageOk => isSendableContactMessage(_message.text);
  bool get _emailOk => isAcceptableContactEmail(_email.text);

  Future<void> _send() async {
    final kind = _kind;
    if (kind == null || _sending) return;
    setState(() => _triedSend = true);
    if (!_messageOk || !_emailOk) return;
    setState(() {
      _sending = true;
      _outcome = null;
    });
    final outcome = await _submit(kind);
    if (!mounted) return;
    setState(() {
      _sending = false;
      _outcome = outcome;
    });
  }

  /// The one place the panel hands a message over. The transport lives behind
  /// [onboardingContactSenderProvider]; the panel only reads the outcome.
  Future<OnboardingContactOutcome> _submit(OnboardingContactKind kind) {
    // Off until the server accepts the message without a rating: nothing is
    // sent, the panel shows the mail address instead (see _buildKindThread).
    if (!ref.read(onboardingContactSendEnabledProvider)) {
      return Future.value(OnboardingContactOutcome.unavailable);
    }
    final sender = ref.read(onboardingContactSenderProvider);
    return sender(
      OnboardingContactMessage(
        kind: kind,
        message: _message.text,
        email: _email.text.trim(),
        includeDiagnostics: _includeDiagnostics,
        stepId: widget.stepId,
        elapsed: _opened.elapsed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
      },
      child: FocusScope(
        autofocus: true,
        child: Semantics(
          scopesRoute: true,
          namesRoute: true,
          explicitChildNodes: true,
          label: l10n.onboardingContactTitle,
          child: Material(
            key: const ValueKey('onboarding-contact-panel'),
            type: MaterialType.transparency,
            child: Container(
              padding: const EdgeInsets.all(WpSpacing.lg),
              decoration: WpFloatingSurface.decoration,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(l10n, theme),
                    const SizedBox(height: WpSpacing.sm),
                    _buildThread(l10n, theme),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(L10n l10n, ThemeData theme) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.onboardingContactTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: WpColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: WpSpacing.xxs),
            Text(
              l10n.onboardingContactNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: WpColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
      WpIconButton(
        icon: Icons.close_rounded,
        tooltip: l10n.onboardingContactClose,
        testId: 'onboarding-contact-close',
        onPressed: widget.onClose,
      ),
    ],
  );

  Widget _buildThread(L10n l10n, ThemeData theme) {
    final kind = _kind;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Once a topic is picked the greeting gives way to it, so the composer
        // fits the window without scrolling.
        if (kind == null) ...[
          _ChatBubble(speaker: appName, text: l10n.onboardingContactGreeting),
          _threadGap,
          _buildChips(l10n),
        ] else ...[
          _ChatBubble(
            fromUser: true,
            speaker: l10n.onboardingContactSpeakerYou,
            text: _kindLabel(l10n, kind),
          ),
          _threadGap,
          if (kind == OnboardingContactKind.idea)
            _buildIdea(l10n)
          else
            _buildKindThread(l10n, theme, kind),
        ],
      ],
    );
  }

  Widget _buildChips(L10n l10n) => Wrap(
    spacing: WpSpacing.xs,
    runSpacing: WpSpacing.xs,
    children: [
      for (final kind in OnboardingContactKind.values)
        KeyedSubtree(
          key: ValueKey('onboarding-contact-chip-${kind.name}'),
          child: WpFilterChip(
            label: _kindLabel(l10n, kind),
            isActive: false,
            onTap: () => setState(() => _kind = kind),
          ),
        ),
    ],
  );

  Widget _buildIdea(L10n l10n) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      _ChatBubble(speaker: appName, text: l10n.onboardingContactIdeaText),
      _threadGap,
      WpButton(
        testId: 'onboarding-contact-idea-open',
        label: l10n.onboardingContactIdeaOpen,
        icon: Icons.open_in_new_rounded,
        variant: WpButtonVariant.primary,
        autofocus: true,
        onPressed: () => openExternalUrl(context, kOnboardingIdeaBoardUrl),
      ),
      const SizedBox(height: WpSpacing.xs),
      _backButton(l10n),
    ],
  );

  String _formIntro(L10n l10n, OnboardingContactKind kind) => switch (kind) {
    OnboardingContactKind.problem => l10n.onboardingContactProblemText,
    OnboardingContactKind.question => l10n.onboardingContactQuestionText,
    _ => l10n.onboardingContactOtherText,
  };

  Widget _backButton(L10n l10n) => WpButton(
    testId: 'onboarding-contact-back',
    label: l10n.onboardingContactBack,
    variant: WpButtonVariant.ghost,
    onPressed: _sending
        ? null
        : () => setState(() {
            _kind = null;
            _outcome = null;
            _triedSend = false;
          }),
  );

  /// Problem, question or other: the intro bubble, then either the composer
  /// or, after a send, the message and the thank-you.
  Widget _buildKindThread(
    L10n l10n,
    ThemeData theme,
    OnboardingContactKind kind,
  ) {
    final outcome = _outcome;
    final sent = outcome == OnboardingContactOutcome.sent;
    final email = _email.text.trim();
    if (!ref.read(onboardingContactSendEnabledProvider)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _ChatBubble(speaker: appName, text: _formIntro(l10n, kind)),
          _threadGap,
          _ChatBubble(
            speaker: appName,
            text: l10n.onboardingContactSendSoon(
              l10n.onboardingContactMailAddress,
            ),
          ),
          _threadGap,
          WpButton(
            testId: 'onboarding-contact-write-mail',
            label: l10n.onboardingContactWriteMail,
            icon: Icons.mail_outline_rounded,
            variant: WpButtonVariant.primary,
            autofocus: true,
            onPressed: () => openExternalUrl(
              context,
              'mailto:${l10n.onboardingContactMailAddress}',
            ),
          ),
          const SizedBox(height: WpSpacing.xs),
          _backButton(l10n),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _ChatBubble(speaker: appName, text: _formIntro(l10n, kind)),
        _threadGap,
        if (sent) ...[
          _ChatBubble(
            fromUser: true,
            speaker: l10n.onboardingContactSpeakerYou,
            text: _message.text.trim(),
          ),
          _threadGap,
          _ChatBubble(
            key: const ValueKey('onboarding-contact-sent'),
            speaker: appName,
            liveRegion: true,
            text: email.isEmpty
                ? l10n.onboardingContactSent
                : l10n.onboardingContactSentReply(email),
          ),
          const SizedBox(height: WpSpacing.md),
          WpButton(
            testId: 'onboarding-contact-done',
            label: l10n.onboardingContactDone,
            variant: WpButtonVariant.primary,
            autofocus: true,
            onPressed: widget.onClose,
          ),
        ] else
          _buildComposer(l10n, theme, kind),
      ],
    );
  }

  Widget _buildComposer(
    L10n l10n,
    ThemeData theme,
    OnboardingContactKind kind,
  ) {
    final secondary = theme.textTheme.bodyMedium?.copyWith(
      color: WpColors.textSecondary,
    );
    final errorStyle = theme.textTheme.bodySmall?.copyWith(
      color: WpColors.error,
    );
    final outcome = _outcome;
    final outcomeText = switch (outcome) {
      OnboardingContactOutcome.retry => l10n.onboardingContactErrorOffline,
      OnboardingContactOutcome.rateLimited =>
        l10n.onboardingContactErrorRateLimited,
      OnboardingContactOutcome.unavailable =>
        l10n.onboardingContactErrorUnavailable,
      _ => null,
    };
    // Cmd or Ctrl with Enter sends; a plain Enter inserts a line break.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _send,
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _send,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.onboardingContactMessageLabel, style: secondary),
          const SizedBox(height: WpSpacing.xxs),
          KeyedSubtree(
            key: const ValueKey('onboarding-contact-message'),
            child: WpTextField(
              controller: _message,
              variant: WpTextFieldVariant.form,
              semanticsLabel: l10n.onboardingContactMessageLabel,
              autofocus: true,
              // Two lines at rest so the whole form fits the window; the
              // field grows with the text.
              minLines: 2,
              maxLines: 6,
              maxLength: kOnboardingContactMaxMessageLength,
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (_triedSend && !_messageOk) ...[
            const SizedBox(height: WpSpacing.xxs),
            Text(
              l10n.onboardingContactMessageTooShort(
                kOnboardingContactMinLength,
              ),
              style: errorStyle,
            ),
          ],
          const SizedBox(height: WpSpacing.sm),
          Text(l10n.onboardingContactEmailLabel, style: secondary),
          const SizedBox(height: WpSpacing.xxs),
          KeyedSubtree(
            key: const ValueKey('onboarding-contact-email'),
            child: WpTextField(
              controller: _email,
              variant: WpTextFieldVariant.form,
              semanticsLabel: l10n.onboardingContactEmailLabel,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              hintText: l10n.onboardingContactEmailHint,
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (_triedSend && !_emailOk) ...[
            const SizedBox(height: WpSpacing.xxs),
            Text(l10n.onboardingContactEmailInvalid, style: errorStyle),
          ],
          const SizedBox(height: WpSpacing.sm),
          KeyedSubtree(
            key: const ValueKey('onboarding-contact-diagnostics'),
            child: WpConsentCheckbox(
              value: _includeDiagnostics,
              onChanged: (v) => setState(() => _includeDiagnostics = v),
              label: l10n.onboardingContactDiagnosticsLabel,
              explanation: l10n.onboardingContactDiagnosticsExplanation,
            ),
          ),
          if (outcomeText != null) ...[
            const SizedBox(height: WpSpacing.sm),
            Semantics(
              liveRegion: true,
              child: Text(
                outcomeText,
                key: const ValueKey('onboarding-contact-error'),
                style: errorStyle,
              ),
            ),
          ],
          const SizedBox(height: WpSpacing.md),
          // Back left, Send right; when both do not fit the panel width
          // (long translations, larger text) Send drops below instead of
          // overflowing.
          OverflowBar(
            alignment: MainAxisAlignment.spaceBetween,
            overflowAlignment: OverflowBarAlignment.end,
            overflowSpacing: WpSpacing.xs,
            children: [
              _backButton(l10n),
              WpButton(
                testId: 'onboarding-contact-send',
                label: outcome == OnboardingContactOutcome.retry
                    ? l10n.onboardingContactRetry
                    : l10n.onboardingContactSend,
                variant: WpButtonVariant.primary,
                isLoading: _sending,
                onPressed: _sending ? null : _send,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

const _threadGap = SizedBox(height: WpSpacing.sm);

/// One message in the contact thread. Ours sits on the left with a small
/// corner at the bottom left, the user's choice on the right with the small
/// corner at the bottom right. New bubbles fade and rise in; under reduced
/// motion they appear at once.
class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    super.key,
    required this.speaker,
    required this.text,
    this.fromUser = false,
    this.liveRegion = false,
  });

  final String speaker;
  final String text;
  final bool fromUser;
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const round = Radius.circular(WpRadius.lg);
    const tail = Radius.circular(WpRadius.sm);
    final bubble = Semantics(
      container: true,
      label: speaker,
      liveRegion: liveRegion,
      child: LayoutBuilder(
        builder: (context, constraints) => Align(
          alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: constraints.maxWidth * _bubbleMaxFraction,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: fromUser
                    ? WpColors.accentSubtle
                    : WpColors.surfaceMutedFill,
                borderRadius: BorderRadius.only(
                  topLeft: round,
                  topRight: round,
                  bottomLeft: fromUser ? round : tail,
                  bottomRight: fromUser ? tail : round,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: WpSpacing.md,
                  vertical: WpSpacing.sm,
                ),
                child: Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: WpColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final duration = WpMotion.durationFor(context, WpMotion.normal);
    if (duration == Duration.zero) return bubble;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: WpMotion.defaultCurve,
      child: bubble,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, WpSpacing.xs * (1 - t)),
          child: child,
        ),
      ),
    );
  }
}

/// The website launcher's speech bubble (24×24 view box, stroke 1.8).
class _SpeechBubblePainter extends CustomPainter {
  const _SpeechBubblePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    const r = Radius.circular(2.5);
    final bubble = Path()
      ..moveTo(4, 5.5)
      ..arcToPoint(const Offset(6.5, 3), radius: r)
      ..lineTo(17.5, 3)
      ..arcToPoint(const Offset(20, 5.5), radius: r)
      ..lineTo(20, 13.5)
      ..arcToPoint(const Offset(17.5, 16), radius: r)
      ..lineTo(10, 16)
      ..lineTo(5.8, 19.6)
      ..cubicTo(5.3, 20, 4.5, 19.7, 4.5, 19)
      ..lineTo(4.5, 16)
      ..arcToPoint(const Offset(4, 13.5), radius: r)
      ..close()
      ..moveTo(8.5, 8.5)
      ..lineTo(15.5, 8.5)
      ..moveTo(8.5, 11.5)
      ..lineTo(13, 11.5);
    canvas.drawPath(
      bubble,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SpeechBubblePainter old) => old.color != color;
}
