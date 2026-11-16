/// A notice that lives on a page instead of in a toast.
///
/// It stays until it is closed or replaced, also while no slot of the page is
/// on screen, so an error or an import result cannot pass unread. Each
/// page names its own notice by an id; the slot sits below the page head. A
/// notice with an [WpPageNotice.area] shows only in the slot of that area (an
/// entry's detail, a settings section); a confirmation with
/// [WpPageNotice.autoDismiss] closes itself, an error never does.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/accessibility/announce.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/tokens.dart';
import 'onboarding_hold.dart';
import 'wp_banner.dart';
import 'wp_button.dart';
import 'wp_icon_button.dart';

@immutable
class WpPageNotice {
  const WpPageNotice({
    required this.id,
    required this.message,
    this.nextStep,
    this.tone = WpBannerTone.error,
    this.area,
    this.action,
    this.autoDismiss,
  });

  /// Stable name of the situation; `page-notice-<id>` is its testID.
  final String id;

  /// What happened, in one sentence.
  final String message;

  /// What the user can do now; omitted when the message says it already.
  final String? nextStep;
  final WpBannerTone tone;

  /// Where on the page it shows (an entry id, a section name); null means
  /// below the page head.
  final String? area;

  /// Optional control next to the close button.
  final WidgetBuilder? action;

  /// When set, the notice closes itself after this time. Only for a
  /// confirmation; an error must stay until it is closed.
  final Duration? autoDismiss;

  /// Text read out and shown: cause, then next step.
  String get spoken => nextStep == null ? message : '$message $nextStep';
}

class WpPageNoticeNotifier extends Notifier<WpPageNotice?> {
  WpPageNoticeNotifier(this._page);

  final String _page;
  Timer? _timer;

  @override
  WpPageNotice? build() {
    assert(_page.isNotEmpty, 'a page notice needs a page id');
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  void show(WpPageNotice notice) {
    // A confirmation or a hint never pushes out an error that is still open;
    // the caller announces it, and the error stays until it is closed.
    final open = state;
    if (open != null &&
        open.tone == WpBannerTone.error &&
        notice.tone != WpBannerTone.error) {
      return;
    }
    _timer?.cancel();
    state = notice;
    final after = notice.autoDismiss;
    if (after != null) {
      _timer = Timer(after, () {
        if (state == notice) state = null;
      });
    }
  }

  void dismiss() {
    _timer?.cancel();
    state = null;
  }
}

/// The current notice of the page named [page] (for example `dictionary`).
/// It outlives its slot, so a notice raised while the page is not on screen
/// (a service, a dialog on top) is still there when the slot is built.
final wpPageNoticeProvider =
    NotifierProvider.family<WpPageNoticeNotifier, WpPageNotice?, String>(
      WpPageNoticeNotifier.new,
    );

/// Shows [notice] on [page] and reads it out, replacing any earlier one.
void showWpPageNotice(
  BuildContext context, {
  required String page,
  required WpPageNotice notice,
}) {
  ProviderScope.containerOf(
    context,
    listen: false,
  ).read(wpPageNoticeProvider(page).notifier).show(notice);
  announce(View.of(context), notice.spoken, Directionality.of(context));
}

/// The page ids of the notice slots, in one place (a literal at each call
/// site would let a typo open a notice nobody shows).
abstract final class WpNoticePage {
  static const app = 'app';
  static const analytics = 'analytics';
  static const dictionary = 'dictionary';
  static const history = 'history';
  static const notes = 'notes';
  static const settings = 'settings';
  static const snippets = 'snippets';
}

/// Page id of the dictation message banner of the main window (see
/// `kAppNoticePage`); app errors have their own list ([wpAppErrorsProvider]).
const kWpAppNoticePage = WpNoticePage.app;

/// An error that has no page of its own (a setting that could not be stored,
/// a link that did not open): it stands below the page head of whichever
/// page is open, with an optional [actionLabel] button, until it is closed.
/// While onboarding covers that slot the onboarding hold takes it.
void showWpAppError(
  BuildContext context, {
  required String id,
  required String message,
  String? actionLabel,
  String? actionTestId,
  VoidCallback? onAction,
}) {
  if (WpOnboardingHold.holding) {
    WpOnboardingHold.add(
      context,
      message: message,
      type: WpMessageType.error,
      actionLabel: actionLabel,
      onAction: onAction,
      actionTestId: actionTestId,
    );
    return;
  }
  final notice = WpPageNotice(
    id: id,
    message: message,
    action: actionLabel == null || onAction == null
        ? null
        : (context) => WpButton(
            testId: actionTestId ?? 'page-notice-action-$id',
            label: actionLabel,
            variant: WpButtonVariant.ghost,
            onPressed: onAction,
          ),
  );
  ProviderScope.containerOf(
    context,
    listen: false,
  ).read(wpAppErrorsProvider.notifier).add(notice);
  announce(View.of(context), notice.spoken, Directionality.of(context));
}

/// The open app errors, oldest first, at most [kWpAppErrorLimit]. An error
/// with an id that is already open replaces only that one; a new one never
/// pushes out another (the oldest goes only when the limit is exceeded).
class WpAppErrorsNotifier extends Notifier<List<WpPageNotice>> {
  @override
  List<WpPageNotice> build() => const [];

  void add(WpPageNotice notice) {
    final index = state.indexWhere((other) => other.id == notice.id);
    if (index >= 0) {
      state = [...state]..[index] = notice;
      return;
    }
    final next = [...state, notice];
    state = next.length > kWpAppErrorLimit
        ? next.sublist(next.length - kWpAppErrorLimit)
        : next;
  }

  /// Closes the error named [id]; the others stay.
  void dismiss(String id) {
    state = [
      for (final other in state)
        if (other.id != id) other,
    ];
  }
}

const kWpAppErrorLimit = 3;

final wpAppErrorsProvider =
    NotifierProvider<WpAppErrorsNotifier, List<WpPageNotice>>(
      WpAppErrorsNotifier.new,
    );

/// The app errors as a plain list below the page head of every page.
class WpAppErrorSlot extends ConsumerWidget {
  const WpAppErrorSlot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final errors = ref.watch(wpAppErrorsProvider);
    if (errors.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final notice in errors)
          _NoticeBanner(
            // Keyed, so a state (and the focus it remembers) stays with its
            // own error when an earlier one is closed.
            key: ValueKey(notice.id),
            notice: notice,
            dismissId: notice.id,
            onDismiss: () =>
                ref.read(wpAppErrorsProvider.notifier).dismiss(notice.id),
          ),
      ],
    );
  }
}

class _NoticeBanner extends StatefulWidget {
  const _NoticeBanner({
    super.key,
    required this.notice,
    required this.dismissId,
    required this.onDismiss,
  });

  final WpPageNotice notice;
  final String dismissId;
  final VoidCallback onDismiss;

  @override
  State<_NoticeBanner> createState() => _NoticeBannerState();
}

class _NoticeBannerState extends State<_NoticeBanner> {
  /// What had the focus when the notice appeared: the place to go back to
  /// when it is closed, so keyboard and screen reader users are not thrown
  /// to the top of the window (#599).
  FocusNode? _before;

  @override
  void initState() {
    super.initState();
    _before = FocusManager.instance.primaryFocus;
  }

  void _dismiss() {
    final before = _before;
    widget.onDismiss();
    // The banner (and the focused close button in it) is gone after this
    // frame; move the focus back to where it was, else on to the next field.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (before != null && before.context != null && before.canRequestFocus) {
        before.requestFocus();
      } else {
        FocusManager.instance.primaryFocus?.nextFocus();
      }
    });
  }

  WpPageNotice get notice => widget.notice;
  String get dismissId => widget.dismissId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WpSpacing.md,
        0,
        WpSpacing.md,
        WpSpacing.sm,
      ),
      child: Semantics(
        identifier: 'page-notice-${notice.id}',
        child: WpBanner(
          key: ValueKey('page-notice-${notice.id}'),
          tone: notice.tone,
          message: notice.spoken,
          // A Wrap: with two actions and the close cross at a large system text
          // size the row breaks onto a second line instead of overflowing.
          action: Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: WpSpacing.xs,
            runSpacing: WpSpacing.xs,
            children: [
              if (notice.action case final action?) action(context),
              WpIconButton(
                key: ValueKey('page-notice-dismiss-$dismissId'),
                icon: LucideIcons.x,
                tooltip: L10n.of(context).actionDismiss,
                testId: 'page-notice-dismiss-$dismissId',
                onPressed: _dismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows the notice of [page] with a close button. Without [area] it takes
/// every notice that has no area, or one whose area is not [openArea] (so a
/// failure stays visible after switching entries); place it once, below the
/// page head. With [area] it shows only the notice of that area.
class WpPageNoticeSlot extends ConsumerWidget {
  const WpPageNoticeSlot({
    super.key,
    required this.page,
    this.area,
    this.openArea,
  });

  final String page;
  final String? area;
  final String? openArea;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = ref.watch(wpPageNoticeProvider(page));
    final mine = area == null
        ? notice?.area == null || notice?.area != openArea
        : notice?.area == area;
    if (notice == null || !mine) return const SizedBox.shrink();
    return _NoticeBanner(
      // A new notice gets a fresh state, so the focus it returns to is the one
      // from when it appeared, not from an earlier notice in this slot.
      key: ValueKey(notice.id),
      notice: notice,
      dismissId: page,
      onDismiss: () => ref.read(wpPageNoticeProvider(page).notifier).dismiss(),
    );
  }
}
