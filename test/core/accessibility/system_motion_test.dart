// Handover native channel → MediaQuery for "Reduce motion" (#1756): the
// value the shell reports at boot and every runtime change must land in
// MediaQuery.disableAnimations, and the embedder's own flag is never undone.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/accessibility/system_motion.dart';

const _channel = MethodChannel(kSystemMotionChannelName);

/// Records what the scope's subtree sees.
class _Probe extends StatelessWidget {
  const _Probe(this.seen);

  final List<bool> seen;

  @override
  Widget build(BuildContext context) {
    seen.add(MediaQuery.disableAnimationsOf(context));
    return const SizedBox.shrink();
  }
}

/// Answers the initial `reduceMotion` read with [initial].
void _shellReports(WidgetTester tester, bool? initial) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (
    call,
  ) async {
    if (call.method == 'reduceMotion') return initial;
    return null;
  });
}

/// Simulates the native shell pushing a runtime change.
Future<void> _shellPushes(WidgetTester tester, bool value) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    kSystemMotionChannelName,
    _channel.codec.encodeMethodCall(MethodCall('reduceMotionChanged', value)),
    (_) {},
  );
  await tester.pump();
}

void main() {
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  testWidgets('system switch on at boot → disableAnimations true', (
    tester,
  ) async {
    _shellReports(tester, true);
    final seen = <bool>[];
    await tester.pumpWidget(SystemMotionScope(child: _Probe(seen)));
    await tester.pump();
    expect(seen.last, isTrue);
  });

  testWidgets('system switch off → disableAnimations false', (tester) async {
    _shellReports(tester, false);
    final seen = <bool>[];
    await tester.pumpWidget(SystemMotionScope(child: _Probe(seen)));
    await tester.pump();
    expect(seen.last, isFalse);
  });

  testWidgets('runtime change is taken over in both directions', (
    tester,
  ) async {
    _shellReports(tester, false);
    final seen = <bool>[];
    await tester.pumpWidget(SystemMotionScope(child: _Probe(seen)));
    await tester.pump();
    expect(seen.last, isFalse);

    await _shellPushes(tester, true);
    expect(seen.last, isTrue);

    await _shellPushes(tester, false);
    expect(seen.last, isFalse);
  });

  testWidgets('a switch keeps the subtree mounted (state survives)', (
    tester,
  ) async {
    _shellReports(tester, false);
    final key = GlobalKey();
    await tester.pumpWidget(SystemMotionScope(child: SizedBox(key: key)));
    await tester.pump();
    final before = key.currentContext;

    await _shellPushes(tester, true);
    expect(key.currentContext, same(before));
  });

  testWidgets('MaterialApp routes inherit boot and runtime motion settings', (
    tester,
  ) async {
    _shellReports(tester, true);
    final seen = <bool>[];
    await tester.pumpWidget(
      SystemMotionScope(child: MaterialApp(home: _Probe(seen))),
    );
    await tester.pump();
    expect(seen.last, isTrue);

    await _shellPushes(tester, false);
    expect(seen.last, isFalse);
    await _shellPushes(tester, true);
    expect(seen.last, isTrue);
  });

  testWidgets('failed initial read still accepts runtime changes', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _channel,
      (call) async => throw PlatformException(code: 'unavailable'),
    );
    final seen = <bool>[];
    await tester.pumpWidget(SystemMotionScope(child: _Probe(seen)));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(seen.last, isFalse);

    await _shellPushes(tester, true);
    expect(seen.last, isTrue);
  });

  testWidgets('embedder flag stays on when the system value is off', (
    tester,
  ) async {
    _shellReports(tester, false);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final seen = <bool>[];
    await tester.pumpWidget(SystemMotionScope(child: _Probe(seen)));
    await tester.pump();
    expect(seen.last, isTrue);
  });

  testWidgets('shell without the channel keeps the default', (tester) async {
    final seen = <bool>[];
    await tester.pumpWidget(SystemMotionScope(child: _Probe(seen)));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(seen.last, isFalse);
  });

  testWidgets('a late boot answer never overwrites a newer push', (
    tester,
  ) async {
    final answer = <bool>[];
    final release = Completer<void>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (
      call,
    ) async {
      // Answer only after the push below has arrived.
      await release.future;
      answer.add(false);
      return false;
    });
    final seen = <bool>[];
    await tester.pumpWidget(SystemMotionScope(child: _Probe(seen)));
    await _shellPushes(tester, true);
    release.complete();
    await tester.pump();
    expect(answer, [false]);
    expect(seen.last, isTrue);
  });
}
