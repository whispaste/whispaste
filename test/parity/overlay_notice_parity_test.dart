// Overlay notice card parity guard (overlay F2).
//
// The notice card is drawn by the shared Dart view, but two things live in
// each native shell: the window size of the size class `notice`, and the
// relay of a card button (`noticeAction` from the render engine to
// `onNoticeAction` on the main engine, with the {id} map unchanged). If one
// shell misses either, the card is clipped or its buttons do nothing on that
// platform only.
//
// The card grows with its content (#1845): every shell starts from the
// smallest card (346 × 164) and takes the height from the snapshot's
// `noticeHeight`.
//
// Static check: it proves the size literal, the height key and the relay
// exist per platform, not that the card renders.
import 'dart:io';

import 'package:flutter/painting.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';

/// Per shell: file, width and smallest-height patterns, the `noticeHeight`
/// read, and the button relay.
const _shells =
    <
      String,
      (String file, String width, String minHeight, String reads, String relay)
    >{
      'macos': (
        'macos/Runner/FloatingOverlayHost.swift',
        r'case "notice":[^\n]*\n(?:\s*//[^\n]*\n)*\s*return NSSize\(width: (\d+), height: noticeHeight\)',
        r'private var noticeHeight: CGFloat = (\d+)',
        r'args\["noticeHeight"\]',
        // Within the case body: the next `case "` ends it (#2165 put the
        // edit-focus branch before the relay).
        r'case "noticeAction":(?:(?!case ")[\s\S])*?invokeMethod\("onNoticeAction", arguments: call\.arguments\)',
      ),
      'windows': (
        'windows/runner/floating_overlay_host.cpp',
        r'kNoticeW = (\d+);',
        r'kNoticeMinH = (\d+);',
        r'GetDouble\(\*map, "noticeHeight"',
        r'method == "noticeAction"[\s\S]{0,200}?SendEvent\("onNoticeAction", args \? \*args',
      ),
      'linux': (
        'linux/runner/floating_overlay_window.h',
        r'kOverlayNoticeW = (\d+);',
        r'kOverlayNoticeMinH = (\d+);',
        '',
        '',
      ),
    };

void main() {
  final spec = OverlayDesignSpec.noticeWindowSize;

  for (final entry in _shells.entries) {
    final (file, widthPattern, minHeightPattern, readsPattern, relayPattern) =
        entry.value;

    test('${entry.key} starts the notice window at the smallest card', () {
      final source = File(file).readAsStringSync();
      final w = RegExp(widthPattern).firstMatch(source);
      final h = RegExp(minHeightPattern).firstMatch(source);
      expect(w, isNotNull, reason: 'notice width not found in $file');
      expect(h, isNotNull, reason: 'notice min height not found in $file');
      expect(
        Size(double.parse(w!.group(1)!), double.parse(h!.group(1)!)),
        spec,
      );
    });

    if (readsPattern.isNotEmpty) {
      test('${entry.key} takes the card height from the snapshot', () {
        expect(
          RegExp(readsPattern).hasMatch(File(file).readAsStringSync()),
          isTrue,
        );
      });
    }

    if (relayPattern.isNotEmpty) {
      test('${entry.key} relays noticeAction with its arguments', () {
        expect(
          RegExp(relayPattern).hasMatch(File(file).readAsStringSync()),
          isTrue,
        );
      });
    }
  }

  test('linux takes the card height from the snapshot', () {
    expect(
      File('linux/runner/floating_overlay_host.cc').readAsStringSync().contains(
        'fl_value_lookup_string(args, "noticeHeight")',
      ),
      isTrue,
    );
  });

  test('linux relays noticeAction with its arguments', () {
    expect(
      RegExp(
        r'strcmp\(method, "noticeAction"\)[\s\S]{0,200}?InvokeMainChannel\("onNoticeAction", args\)',
      ).hasMatch(
        File('linux/runner/floating_overlay_host.cc').readAsStringSync(),
      ),
      isTrue,
    );
  });

  test('every shell resolves the size class "notice"', () {
    for (final (file, height) in [
      ('windows/runner/floating_overlay_host.cpp', 'g_notice_h'),
      ('linux/runner/floating_overlay_window.h', r'OverlayNoticeH\(\)'),
    ]) {
      final source = File(file).readAsStringSync();
      expect(
        RegExp(r'size_class == "notice"\) return k\w*NoticeW').hasMatch(source),
        isTrue,
        reason: file,
      );
      expect(
        RegExp('size_class == "notice"\\) return $height').hasMatch(source),
        isTrue,
        reason: file,
      );
    }
  });
}
