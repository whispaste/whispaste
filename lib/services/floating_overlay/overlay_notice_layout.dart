/// The size of the overlay's notice card, measured once for both engines:
/// the main engine sends the window height to the native shells with the
/// snapshot, the overlay engine lays the card out at the same height (#1845).
///
/// A card that holds more than the smallest card's content grows taller
/// instead of shrinking or cutting its text: the footer keeps the small type
/// step and wraps, and buttons that do not fit side by side stack.
library;

import 'dart:math' as math;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/painting.dart';

import '../../core/theme/overlay_design_spec.dart';
import '../../core/theme/theme.dart' show kWpFontFallback;
import 'overlay_notice.dart';

/// Lines the card's headline may take. Without a body the title carries the
/// whole message: the Esc hint of the discard ask needs the second line, a
/// message card may take three (#453).
int overlayNoticeTitleMaxLines(OverlayNotice notice) {
  if (notice.body.isNotEmpty) return 1;
  return notice.kind == OverlayNoticeKind.message ? 3 : 2;
}

/// Lines the card's body may take before it is cut. A message card gets a
/// third line when the key footer or the button row leaves room for it: with
/// both a third line would not fit the card (#781). A message card without
/// buttons (a skipped paste, #1617) keeps the third line at the largest text
/// scale too.
int overlayNoticeBodyMaxLines(OverlayNotice notice) {
  final hasButtons = notice.actions.any((a) => !a.action.isClose);
  final roomy = notice.footer.isEmpty || !hasButtons;
  return notice.kind == OverlayNoticeKind.message && roomy ? 3 : 2;
}

/// Text style of the card at [size] and [weight] (ink set by the caller).
TextStyle overlayNoticeTextStyle(double size, FontWeight weight) => TextStyle(
  fontFamily: OverlayDesignSpec.fontFamily,
  fontFamilyFallback: kWpFontFallback,
  fontSize: size,
  fontWeight: weight,
  height: 1.3,
);

/// Width of the card's content column.
double get overlayNoticeContentWidth =>
    OverlayDesignSpec.noticeCardSize.width -
    2 * OverlayDesignSpec.noticeCardPadding;

/// Horizontal padding inside a notice button.
const double overlayNoticeButtonPadH = 10;

/// Width a button needs to show its whole label and key.
double overlayNoticeButtonWidth(OverlayNoticeAction action, TextScaler scaler) {
  final painter = TextPainter(
    text: TextSpan(
      text: action.fullLabel,
      style: overlayNoticeTextStyle(
        OverlayDesignSpec.noticeBodyFontSize,
        OverlayDesignSpec.primaryFontWeight,
      ),
    ),
    maxLines: 1,
    textScaler: scaler,
    textDirection: TextDirection.ltr,
  )..layout();
  final width = painter.width.ceilToDouble() + 1 + 2 * overlayNoticeButtonPadH;
  painter.dispose();
  return width;
}

/// Whether the card's buttons stand on top of each other: they do when their
/// whole labels do not fit side by side.
bool overlayNoticeStacksButtons(OverlayNotice notice, TextScaler scaler) {
  final buttons = notice.actions.where((a) => !a.action.isClose).toList();
  if (buttons.length < 2) return false;
  final row =
      buttons.fold<double>(
        0,
        (sum, b) => sum + overlayNoticeButtonWidth(b, scaler),
      ) +
      OverlayDesignSpec.noticeStackGap * (buttons.length - 1);
  return row > overlayNoticeContentWidth;
}

double _textHeight(
  String text,
  TextStyle style,
  double width,
  TextScaler scaler, {
  int? maxLines,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: maxLines,
    ellipsis: maxLines == null ? null : '…',
    textScaler: scaler,
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: width);
  final height = painter.height;
  painter.dispose();
  return height;
}

/// Inner padding of the edit field (#254).
const double overlayNoticeEditPadding = 6;

/// Height of the edit block of [edit] at [scaler]: the toggle line while
/// closed; the field with [kNoticeEditFieldLines] lines and the insert hint
/// line under it while open. Includes the gap above it.
double overlayNoticeEditHeight(OverlayNoticeEdit edit, TextScaler scaler) {
  final width = overlayNoticeContentWidth;
  final small = overlayNoticeTextStyle(
    OverlayDesignSpec.noticeFooterFontSize,
    FontWeight.w400,
  );
  if (!edit.open) {
    return 4 + _textHeight(edit.toggleLabel, small, width, scaler, maxLines: 1);
  }
  final line = _textHeight(
    'X',
    overlayNoticeTextStyle(
      OverlayDesignSpec.noticeBodyFontSize,
      FontWeight.w400,
    ),
    width,
    scaler,
  );
  return 4 +
      kNoticeEditFieldLines * line +
      2 * overlayNoticeEditPadding +
      2 +
      4 +
      _textHeight(edit.insertHint, small, width, scaler, maxLines: 1);
}

/// Height of the card for [notice] at [scaler]: at least the smallest card,
/// more when its title, body, footer and buttons need it.
double overlayNoticeCardHeight(OverlayNotice notice, TextScaler scaler) {
  final width = overlayNoticeContentWidth;
  final hasClose = notice.actions.any((a) => a.action.isClose);
  final buttons = notice.actions.where((a) => !a.action.isClose).length;
  final titleWidth =
      width - 16 - (hasClose ? OverlayDesignSpec.noticeButtonHeight : 0);
  var h = math.max(
    _textHeight(
      notice.title,
      overlayNoticeTextStyle(
        OverlayDesignSpec.noticeTitleFontSize,
        OverlayDesignSpec.primaryFontWeight,
      ),
      titleWidth,
      scaler,
      maxLines: overlayNoticeTitleMaxLines(notice),
    ),
    hasClose ? OverlayDesignSpec.noticeCloseHeight : 0,
  );
  if (notice.body.isNotEmpty) {
    h +=
        4 +
        _textHeight(
          notice.body,
          overlayNoticeTextStyle(
            OverlayDesignSpec.noticeBodyFontSize,
            FontWeight.w400,
          ),
          width,
          scaler,
          maxLines: overlayNoticeBodyMaxLines(notice),
        );
  }
  if (notice.edit case final edit?) h += overlayNoticeEditHeight(edit, scaler);
  for (final note in notice.notes) {
    h +=
        4 +
        _textHeight(
          note.text,
          overlayNoticeTextStyle(
            OverlayDesignSpec.noticeFooterFontSize,
            FontWeight.w400,
          ),
          width,
          scaler,
        );
  }
  h += OverlayDesignSpec.noticeStackGap;
  if (notice.footer.isNotEmpty) {
    h +=
        _textHeight(
          notice.footer,
          overlayNoticeTextStyle(
            OverlayDesignSpec.noticeFooterFontSize,
            FontWeight.w400,
          ),
          width,
          scaler,
        ) +
        OverlayDesignSpec.noticeFooterGap;
  }
  if (buttons > 0) {
    final rows = overlayNoticeStacksButtons(notice, scaler) ? buttons : 1;
    h +=
        rows * OverlayDesignSpec.noticeButtonHeight +
        (rows - 1) * OverlayDesignSpec.noticeStackGap;
  }
  h += 2 * OverlayDesignSpec.noticeCardPadding;
  return math.max(OverlayDesignSpec.noticeCardSize.height, h.ceilToDouble());
}

/// The text scale the card follows: the system font size up to
/// [OverlayDesignSpec.noticeMaxTextScale] (#728).
TextScaler overlayNoticeScaler(TextScaler system) =>
    system.clamp(maxScaleFactor: OverlayDesignSpec.noticeMaxTextScale);

/// The system text scale as the main engine sees it, for the snapshot.
TextScaler get overlayNoticeSystemScaler => overlayNoticeScaler(
  TextScaler.linear(PlatformDispatcher.instance.textScaleFactor),
);
