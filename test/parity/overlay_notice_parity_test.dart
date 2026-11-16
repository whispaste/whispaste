// Overlay notice card parity guard (overlay F2).
//
// The notice card is drawn by the shared Dart view, but two things live in
// each native shell: the window size of the size class `notice`, and the
// relay of a card button (`noticeAction` from the render engine to
// `onNoticeAction` on the main engine, with the {id} map unchanged). If one
// shell misses either, the card is clipped or its buttons do nothing on that
// platform only.
//
// Static check: it proves the size literal and the relay exist per platform,
// not that the card renders.
import 'dart:io';

import 'package:flutter/painting.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';

const _shells = <String, (String file, String size, String relay)>{
  'macos': (
    'macos/Runner/FloatingOverlayHost.swift',
    r'case "notice":[^\n]*\n(?:\s*//[^\n]*\n)*\s*return NSSize\(width: (\d+), height: (\d+)\)',
    r'case "noticeAction":[\s\S]{0,200}?invokeMethod\("onNoticeAction", arguments: call\.arguments\)',
  ),
  'windows': (
    'windows/runner/floating_overlay_host.cpp',
    r'kNoticeW = (\d+);\s*constexpr int kNoticeH = (\d+);',
    r'method == "noticeAction"[\s\S]{0,200}?SendEvent\("onNoticeAction", args \? \*args',
  ),
  'linux': (
    'linux/runner/floating_overlay_window.h',
    r'kOverlayNoticeW = (\d+);\s*constexpr int kOverlayNoticeH = (\d+);',
    '',
  ),
};

void main() {
  final spec = OverlayDesignSpec.noticeWindowSize;

  for (final entry in _shells.entries) {
    final (file, sizePattern, relayPattern) = entry.value;

    test('${entry.key} sizes the notice window like the Dart spec', () {
      final m = RegExp(sizePattern).firstMatch(File(file).readAsStringSync());
      expect(m, isNotNull, reason: 'notice size not found in $file');
      expect(Size(double.parse(m!.group(1)!), double.parse(m.group(2)!)), spec);
    });

    if (relayPattern.isNotEmpty) {
      test('${entry.key} relays noticeAction with its arguments', () {
        expect(
          RegExp(relayPattern).hasMatch(File(file).readAsStringSync()),
          isTrue,
        );
      });
    }
  }

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
    for (final file in [
      'windows/runner/floating_overlay_host.cpp',
      'linux/runner/floating_overlay_window.h',
    ]) {
      final source = File(file).readAsStringSync();
      expect(
        RegExp(r'size_class == "notice"\) return k\w*NoticeW').hasMatch(source),
        isTrue,
        reason: file,
      );
      expect(
        RegExp(r'size_class == "notice"\) return k\w*NoticeH').hasMatch(source),
        isTrue,
        reason: file,
      );
    }
  });
}
