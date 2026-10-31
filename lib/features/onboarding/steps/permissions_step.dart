// Onboarding v6 screen 3 "Freigaben": the microphone and the text insertion
// permission on the split page: purpose first titles in one quiet list (the
// accordion with a button inside read badly), a granted row shows a
// checkmark. Continue is always enabled (2a) but asks once when a permission
// is missing: without the microphone the mic test asks again, without
// insertion the text is copied.
//
// macOS: microphone, then Accessibility (button + System Settings deep link,
// the drag helper docks below System Settings). Windows: only the microphone,
// insertion is on by default (1a). Linux: the insertion setup of
// AutoPasteStep (portal, pkexec, copied command) inside the card.
//
// The panel paints a light trail on the glacier: a waveform on the cyan band
// leads into text lines in the gate, each lights up with its permission; no
// tiles, mock switches or fields that look clickable (maintainer, 2026-10-30).
import 'dart:math' as math;

import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_labels.dart' show pasteShortcutLabel;
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/paste/paste_capability_notifier.dart';
import '../../../services/paste/paster.dart';
import '../../../services/permission_helper_service.dart';
import '../../../services/permissions/tcc_entry_reset_confirm.dart';
import '../../../services/permissions/mic_permission_notifier.dart';
import '../../../services/permissions/settings_window_placement.dart';
import '../../../widgets/dialog.dart' show showWpConfirmDialog;
import '../../../widgets/wp_button.dart';
import '../../../widgets/wp_hero_button.dart';
import '../onboarding_scene.dart';
import '../onboarding_split_page.dart';
import 'auto_paste_step.dart';
import 'onboarding_headings.dart' show onboardingCompactText;

/// Screen 3. The shell owns the navigation; [onNext] and [onBack] are called
/// from the page's own actions.
class PermissionsStep extends ConsumerStatefulWidget {
  const PermissionsStep({
    super.key,
    required this.onNext,
    this.onBack,
    this.primaryKey,
  });

  final VoidCallback onNext;
  final VoidCallback? onBack;
  final Key? primaryKey;

  @override
  ConsumerState<PermissionsStep> createState() => _PermissionsStepState();
}

class _PermissionsStepState extends ConsumerState<PermissionsStep> {
  Timer? _liveTimer;
  PasteCapabilityNotifier? _pasteNotifier;
  PermissionHelperService? _helper;
  StreamSubscription<PermissionHelperEvent>? _helperEvents;
  bool _helperShown = false;
  bool _grantInFlight = false;

  TargetPlatform get _platform => defaultTargetPlatform;
  bool get _hasMicCard => _platform != TargetPlatform.linux;
  bool get _hasPasteCard => _platform != TargetPlatform.windows;
  bool get _isMac => _platform == TargetPlatform.macOS;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pasteNotifier = ref.read(pasteCapabilityNotifierProvider.notifier);
      _helper = ref.read(permissionHelperProvider);
      _helperEvents = _helper!.events.listen((_) => _helperShown = false);
      _tick();
      _liveTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    });
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _pasteNotifier?.stopPolling();
    unawaited(_helperEvents?.cancel());
    if (_helperShown) unawaited(_helper?.hide());
    super.dispose();
  }

  /// Re-reads both permissions every second, so a switch flipped in System
  /// Settings shows its checkmark without a click.
  void _tick() {
    if (!mounted) return;
    if (_hasMicCard) {
      unawaited(
        ref
            .read(micPermissionNotifierProvider.notifier)
            .check()
            .catchError((Object _) => false),
      );
    }
    final pasteReady =
        ref.read(pasteCapabilityNotifierProvider).capability?.status ==
        PasteCapabilityStatus.ready;
    if (!pasteReady) {
      unawaited(_pasteNotifier?.check().catchError((Object _) {}));
    } else if (_helperShown) {
      _helperShown = false;
      unawaited(_helper?.hide());
    }
  }

  void _requestMic() {
    unawaited(ref.read(micPermissionNotifierProvider.notifier).request());
  }

  Future<void> _requestPaste(L10n l10n) async {
    if (_grantInFlight) return;
    setState(() => _grantInFlight = true);
    try {
      final paste = ref.read(pasteCapabilityNotifierProvider.notifier);
      // An entry left by an older build of the app stays switched on in
      // System Settings but no longer counts, and dragging the app in again
      // does nothing (maintainer report, 2026-10-30). Clear it first, after
      // the usual confirmation; without evidence of a stale entry this is a
      // no-op.
      await paste.resetStaleEntry(
        confirmReset: () => confirmTccEntryReset(l10n: l10n),
      );
      unawaited(paste.requestGrant());
      if (!_isMac || !mounted) return;
      // The drag helper docks below System Settings; where it cannot (Mac
      // App Store build, older macOS), the window moves beside the pane.
      final shown = await _helper?.show(
        PermissionHelperKind.accessibility,
        text: l10n.onboardingAccessibilityDragHint('WhisPaste'),
        closeLabel: l10n.actionClose,
      );
      if (shown == PermissionHelperShowResult.shown) {
        _helperShown = true;
      } else {
        unawaited(placeBesideSystemSettings());
      }
    } finally {
      if (mounted) setState(() => _grantInFlight = false);
    }
  }

  /// Continue stays enabled (2a), but with a permission still missing it asks
  /// once more and names what will not work (maintainer, 2026-10-30).
  Future<void> _continue(L10n l10n) async {
    final micMissing =
        _hasMicCard &&
        ref.read(micPermissionNotifierProvider).status !=
            MicPermissionStatus.granted;
    final pasteMissing =
        _isMac &&
        ref.read(pasteCapabilityNotifierProvider).capability?.status !=
            PasteCapabilityStatus.ready;
    if (!micMissing && !pasteMissing) {
      widget.onNext();
      return;
    }
    final message = [
      if (micMissing) l10n.onboardingPermSkipMic,
      if (pasteMissing)
        l10n.onboardingPermSkipPaste(pasteShortcutLabel(l10n: l10n)),
      l10n.onboardingPermSkipLater,
    ].join(' ');
    final skip = await showWpConfirmDialog(
      context: context,
      title: l10n.onboardingPermSkipTitle,
      message: message,
      confirmLabel: l10n.onboardingPermSkipConfirm,
      cancelLabel: l10n.onboardingPermSkipCancel,
    );
    if (skip && mounted) widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final compact = onboardingCompactText(context);
    final gap = compact ? WpSpacing.lg : WpSpacing.xl;

    final mic = ref.watch(micPermissionNotifierProvider).status;
    final paste = ref.watch(pasteCapabilityNotifierProvider);
    final micDone = mic == MicPermissionStatus.granted;
    final pasteDone = paste.capability?.status == PasteCapabilityStatus.ready;
    final allDone = (!_hasMicCard || micDone) && (!_hasPasteCard || pasteDone);

    final rows = <Widget>[
      if (_hasMicCard)
        _PermissionRow(
          testId: 'onboarding-permissions-mic',
          icon: LucideIcons.mic,
          title: l10n.onboardingPermMicTitle,
          body: mic == MicPermissionStatus.denied
              ? l10n.onboardingPermMicDenied
              : l10n.onboardingPermMicBody,
          done: micDone,
          busy: mic == MicPermissionStatus.requesting,
          // Once denied, macOS shows no second prompt: open the pane.
          onAllow: mic == MicPermissionStatus.denied
              ? () => unawaited(
                  ref
                      .read(micPermissionNotifierProvider.notifier)
                      .openSystemSettings(),
                )
              : _requestMic,
        ),
      if (_isMac)
        _PermissionRow(
          testId: 'onboarding-permissions-paste',
          icon: LucideIcons.textCursorInput,
          title: l10n.onboardingPermPasteTitle,
          body: paste.sentToOsGrantFlow && !pasteDone
              ? l10n.onboardingPasteWaitingForGrantHint
              : '${l10n.onboardingPermPasteBody} '
                    '${l10n.onboardingPermPasteMacNote}',
          done: pasteDone,
          busy: _grantInFlight,
          onAllow: () => unawaited(_requestPaste(l10n)),
        ),
    ];

    return OnboardingSplitPage(
      panelAsset: 'assets/onboarding/permissions-glacier.webp',
      panel: _PermissionsScene(
        showMic: _hasMicCard,
        showPaste: _hasPasteCard,
        micDone: micDone,
        pasteDone: pasteDone,
      ),
      copy: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.onBack != null)
            OnboardingBackLink(
              testId: 'onboarding-permissions-back',
              label: l10n.onboardingBack,
              onPressed: widget.onBack!,
            ),
          OnboardingSplitHeading(
            allDone
                ? l10n.onboardingPermissionsTitleDone
                : l10n.onboardingPermissionsTitle,
            testId: 'onboarding-permissions-heading',
          ),
          const SizedBox(height: WpSpacing.sm),
          _BodyText(l10n.onboardingPermissionsSubtitle),
          SizedBox(height: gap),
          if (rows.isNotEmpty)
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: WpColors.cardFill,
                borderRadius: WpRadius.borderLg,
                border: Border.all(color: WpColors.cardEdgeHighlight),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0)
                      Divider(height: 1, color: WpColors.cardEdgeHighlight),
                    rows[i],
                  ],
                ],
              ),
            ),
          // Linux keeps the full insertion setup (portal, pkexec, command).
          if (_platform == TargetPlatform.linux) const AutoPasteStep(),
          if (_isMac && !pasteDone) ...[
            const SizedBox(height: WpSpacing.md),
            Text(
              l10n.onboardingPermPasteWithout(pasteShortcutLabel(l10n: l10n)),
              style: TextStyle(
                fontSize: WpTypography.small,
                height: 1.4,
                color: WpColors.textMuted,
              ),
            ),
          ],
          SizedBox(height: gap),
          SizedBox(
            width: kOnboardingCopyWidth,
            child: WpHeroButton(
              testId: 'onboarding-permissions-next',
              key: widget.primaryKey,
              label: l10n.onboardingNext,
              onPressed: () => unawaited(_continue(l10n)),
            ),
          ),
        ],
      ),
    );
  }
}

/// One permission as a list row: glyph, purpose title,
/// one line of why, and a small Allow button at the end that turns into a
/// quiet "Allowed" checkmark. All rows stay visible; nothing expands.
class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.testId,
    required this.icon,
    required this.title,
    required this.body,
    required this.done,
    required this.busy,
    required this.onAllow,
  });

  final String testId;
  final IconData icon;
  final String title;
  final String body;
  final bool done;
  final bool busy;
  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Semantics(
      identifier: testId,
      container: true,
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.all(WpSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: WpSpacing.xxs),
              child: Icon(
                icon,
                size: WpIconSize.md,
                color: done ? WpColors.accent : WpColors.textSecondary,
              ),
            ),
            const SizedBox(width: WpSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: WpTypography.rowTitle,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                      color: WpColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: WpSpacing.xxs),
                  Text(
                    body,
                    style: TextStyle(
                      fontSize: WpTypography.small,
                      height: 1.4,
                      color: WpColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: WpSpacing.md),
            done
                ? Padding(
                    padding: const EdgeInsets.only(top: WpSpacing.xxs),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.check,
                          size: WpIconSize.sm,
                          color: WpColors.accent,
                        ),
                        const SizedBox(width: WpSpacing.xxs),
                        Text(
                          l10n.permissionRowGranted,
                          style: TextStyle(
                            fontSize: WpTypography.small,
                            fontWeight: FontWeight.w600,
                            color: WpColors.accent,
                          ),
                        ),
                      ],
                    ),
                  )
                : WpButton(
                    testId: '$testId-allow',
                    label: l10n.permissionRowAllow,
                    semanticsLabel: '${l10n.permissionRowAllow}: $title',
                    variant: WpButtonVariant.secondary,
                    size: WpButtonSize.dense,
                    isLoading: busy,
                    onPressed: onAllow,
                  ),
          ],
        ),
      ),
    );
  }
}

class _BodyText extends StatelessWidget {
  const _BodyText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: WpTypography.body,
      height: 1.45,
      color: WpColors.textSecondary,
    ),
  );
}

/// The panel: a message in some app, the place where you write. The
/// dictated sentence lands in it under the amber marker, and a hand-drawn
/// marker arrow leads up to it from the recording pill below: what the two
/// permissions are for, hearing and inserting where you type. A light sheet
/// instead of the navy card of screen 2, so the pages do not repeat
/// (maintainer, 2026-10-30). The pill turns amber once the microphone is
/// granted, the sentence appears once insertion is; each changes once and
/// then rests, reduced motion swaps it at once. The open-source sticker sits
/// on the sheet's corner. Decorative for assistive technology; the rows
/// carry the state.
class _PermissionsScene extends StatelessWidget {
  const _PermissionsScene({
    required this.showMic,
    required this.showPaste,
    required this.micDone,
    required this.pasteDone,
  });

  final bool showMic;
  final bool showPaste;
  final bool micDone;
  final bool pasteDone;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final duration = WpMotion.durationFor(context, WpMotion.dramatic);
    Widget lit(bool done, Widget Function(double) builder) =>
        TweenAnimationBuilder<double>(
          tween: Tween(end: done ? 1 : 0),
          duration: duration,
          curve: WpMotion.defaultCurve,
          builder: (context, value, _) => builder(value),
        );
    final ink = WpColors.onAction;
    final body = TextStyle(
      fontSize: WpTypography.rowTitle,
      height: 1.5,
      color: ink.withValues(alpha: 0.88),
    );
    Widget sheet(double paste) => Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
        WpSpacing.lg,
        WpSpacing.lg,
        WpSpacing.lg,
        WpSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: WpColors.textPrimary.withValues(alpha: 0.94),
        borderRadius: WpRadius.borderLg,
        boxShadow: WpShadows.overlay,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.onboardingPermissionsSceneGreeting, style: body),
          const SizedBox(height: WpSpacing.xs),
          // The sentence keeps its room while waiting, so nothing jumps
          // when it lands; until then a caret marks where it will go.
          Stack(
            children: [
              PositionedDirectional(
                start: 2,
                top: 4,
                child: Container(
                  width: 2,
                  height: 20,
                  color: WpColors.accent.withValues(alpha: 1 - paste),
                ),
              ),
              Opacity(
                opacity: paste,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: WpColors.highlight.withValues(alpha: 0.55 * paste),
                    borderRadius: WpRadius.borderSm,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text(
                      l10n.onboardingPermissionsSceneSentence,
                      style: body,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: WpSpacing.xl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kOnboardingSceneWidth),
          child: lit(
            // Without a mic row (Linux) the pill simply rests lit.
            micDone || !showMic,
            (mic) => lit(
              // Windows inserts by default (1a): the sentence rests there.
              pasteDone || !showPaste,
              (paste) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      sheet(paste),
                      PositionedDirectional(
                        top: -WpSpacing.md,
                        end: -WpSpacing.md,
                        child: OnboardingSticker(
                          icon: LucideIcons.codeXml,
                          text: l10n.onboardingStickerOpenSource,
                        ),
                      ),
                    ],
                  ),
                  // Below the sheet and off to its side: the pill, and a
                  // marker arrow from it up into the sheet, from voice to
                  // text.
                  SizedBox(
                    height: _kArrowZoneHeight,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: 1),
                            duration: WpMotion.durationFor(
                              context,
                              WpMotion.dramatic,
                            ),
                            curve: WpMotion.defaultCurve,
                            builder: (context, draw, _) => CustomPaint(
                              painter: _MarkerArrowPainter(
                                progress: draw,
                                color: WpColors.highlight,
                                rtl:
                                    Directionality.of(context) ==
                                    TextDirection.rtl,
                              ),
                            ),
                          ),
                        ),
                        PositionedDirectional(
                          start: -WpSpacing.xl,
                          bottom: 0,
                          child: OnboardingWavePill(lit: mic),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Height of the zone below the sheet that holds the pill and the arrow.
const double _kArrowZoneHeight = 150;

/// A curved arrow as if drawn with a felt marker: from beside the pill
/// (bottom start) up to the sheet's lower edge, a little wobbly, with an
/// open two-stroke head. [progress] draws it in once along its length; the
/// head follows at the end. Coordinates are fractions of a 360 x 150 zone
/// and mirror for right-to-left.
class _MarkerArrowPainter extends CustomPainter {
  const _MarkerArrowPainter({
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
    if (rtl) {
      canvas
        ..translate(size.width, 0)
        ..scale(-1, 1);
    }
    Offset at(double x, double y) =>
        Offset(x / 360 * size.width, y / 150 * size.height);
    final path = Path()
      ..moveTo(at(78, 128).dx, at(78, 128).dy)
      ..cubicTo(
        at(136, 124).dx,
        at(136, 124).dy,
        at(190, 84).dx,
        at(190, 84).dy,
        at(196, 14).dx,
        at(196, 14).dy,
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final metric = path.computeMetrics().first;
    final drawn = metric.length * progress;
    canvas.drawPath(metric.extractPath(0, drawn), paint);
    if (progress < 0.9) return;
    // The head: two short strokes back from the tip, slightly unequal like a
    // hand-drawn one, fading in over the last tenth.
    final tip = metric.getTangentForOffset(metric.length)!;
    final back = -tip.vector.direction;
    final head = paint..color = color.withValues(alpha: (progress - 0.9) / 0.1);
    // Each stroke bows a little, as a marker pulled back from the tip does.
    for (final (turn, length, bow) in [
      (0.62, 26.0, 0.12),
      (-0.44, 22.0, -0.1),
    ]) {
      final a = back + turn;
      final end = tip.position + Offset(math.cos(a), math.sin(a)) * length;
      final mid = Offset.lerp(tip.position, end, 0.5)!;
      final normal = Offset(-math.sin(a), math.cos(a)) * (length * bow);
      canvas.drawPath(
        Path()
          ..moveTo(tip.position.dx, tip.position.dy)
          ..quadraticBezierTo(
            mid.dx + normal.dx,
            mid.dy + normal.dy,
            end.dx,
            end.dy,
          ),
        head,
      );
    }
  }

  @override
  bool shouldRepaint(_MarkerArrowPainter old) =>
      old.progress != progress || old.color != color || old.rtl != rtl;
}
