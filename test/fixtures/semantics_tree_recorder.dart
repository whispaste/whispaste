import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test binding that mirrors every semantics update into a [SemanticsTreeRecorder]
/// and validates it the way the desktop engines' `AccessibilityBridge` does.
///
/// Background (issue #153, flutter/flutter#190357, #175041): the framework can
/// serialize a node that no parent claims as a child. The engine's `AXTree`
/// rejects such an update ("N will not be in the tree and is not the new
/// root") and, on Windows release builds, a later update dereferences that
/// node's null parent in `CreateRemoveReparentedNodesUpdate` and crashes the
/// app. The engine only receives semantics while an accessibility client is
/// listening, which is why the crash is machine-dependent; this binding makes
/// the defect visible in a plain `flutter test`.
///
/// test/flutter_test_config.dart creates it as the binding of every test file
/// ([install]), because the binding must exist before the tests register (it
/// carries their time limit) and only one binding can exist. Recording stays
/// off until a test file calls [ensureInitialized] at the top of `main()`;
/// until then it behaves like [AutomatedTestWidgetsFlutterBinding].
class SemanticsRecordingBinding extends AutomatedTestWidgetsFlutterBinding {
  SemanticsRecordingBinding._();

  /// Creates the binding without recording; returns the existing one.
  static SemanticsRecordingBinding install() {
    if (_instance == null) SemanticsRecordingBinding._();
    return _instance!;
  }

  /// Turns recording on for this test file (each file runs in its own
  /// isolate, so other files are not affected).
  static SemanticsRecordingBinding ensureInitialized() =>
      install().._recording = true;

  static SemanticsRecordingBinding? _instance;

  bool _recording = false;

  /// Tests stay silent (#1491): the binding puts this into [debugPrint] at
  /// start and before every test, and checks after every test that it is
  /// still there. Replacing [debugPrint] from outside the binding instead
  /// failed the first test of each file ("The value of a foundation debug
  /// variable was changed by the test") and made the rest loud again.
  @override
  DebugPrintCallback get debugPrintOverride => silentDebugPrint;

  @override
  void initInstances() {
    super.initInstances();
    _instance = this;
  }

  final SemanticsTreeRecorder recorder = SemanticsTreeRecorder();

  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() => _recording
      ? _RecordingUpdateBuilder(super.createSemanticsUpdateBuilder(), recorder)
      : super.createSemanticsUpdateBuilder();
}

/// Accumulates incremental semantics updates into a parent → children map,
/// exactly like the engine-side tree, and records every update that would be
/// rejected by `ui::AXTree::Unserialize`.
class SemanticsTreeRecorder {
  final Map<int, List<int>> _children = {};
  final Map<int, String> _describe = {};

  /// Human-readable descriptions of rejected updates, one per orphan node.
  final List<String> violations = [];

  /// Forgets all state, e.g. between tests that enable semantics afresh.
  void reset() {
    _children.clear();
    _describe.clear();
    violations.clear();
  }

  void _apply(Map<int, List<int>> update) {
    _children.addAll(update);
    // Prune everything the root can no longer reach, as AXTree does.
    final reachable = <int>{};
    final stack = <int>[0];
    while (stack.isNotEmpty) {
      final id = stack.removeLast();
      if (!_children.containsKey(id) || !reachable.add(id)) continue;
      stack.addAll(_children[id]!);
    }
    for (final id in update.keys) {
      if (!reachable.contains(id)) {
        violations.add(
          'node $id (${_describe[id]}) will not be in the tree and is not '
          'the root',
        );
      }
    }
    _children.removeWhere((id, _) => !reachable.contains(id));
  }
}

/// Forwards every call to the real builder and captures node topology.
///
/// Implemented via [noSuchMethod] + [Function.apply] so the wrapper does not
/// have to restate `updateNode`'s ~40 named parameters, which change between
/// Flutter releases.
class _RecordingUpdateBuilder implements ui.SemanticsUpdateBuilder {
  _RecordingUpdateBuilder(this._inner, this._recorder);

  final ui.SemanticsUpdateBuilder _inner;
  final SemanticsTreeRecorder _recorder;
  final Map<int, List<int>> _pending = {};

  @override
  ui.SemanticsUpdate build() {
    _recorder._apply(_pending);
    return _inner.build();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final args = invocation.namedArguments;
    switch (invocation.memberName) {
      case #updateNode:
        final children = args[#childrenInTraversalOrder] as Int32List;
        final id = args[#id] as int;
        _pending[id] = List<int>.of(children);
        _recorder._describe[id] =
            'label="${args[#label]}" flags=${args[#flags]} '
            'rect=${args[#rect]}';
        return Function.apply(_inner.updateNode, const [], args);
      case #updateCustomAction:
        return Function.apply(_inner.updateCustomAction, const [], args);
    }
    return super.noSuchMethod(invocation);
  }
}

/// The [debugPrint] of every test (#1491): drops the line. Tests that assert
/// on debug output install their own hook and restore this one.
void silentDebugPrint(String? message, {int? wrapWidth}) {}
