import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/accessibility/atspi_ids.dart';

class _Recorder implements ui.SemanticsUpdateBuilder {
  final labels = <String>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #updateNode) {
      labels.add(invocation.namedArguments[#label]! as String);
    }
    return null;
  }
}

void _node(ui.SemanticsUpdateBuilder b, String identifier, String label) =>
    b.updateNode(
      id: 1,
      flags: ui.SemanticsFlags.none,
      actions: 0,
      maxValueLength: 0,
      currentValueLength: 0,
      textSelectionBase: 0,
      textSelectionExtent: 0,
      platformViewId: 0,
      scrollChildren: 0,
      scrollIndex: 0,
      traversalParent: 0,
      scrollPosition: 0,
      scrollExtentMax: 0,
      scrollExtentMin: 0,
      rect: ui.Rect.zero,
      identifier: identifier,
      label: label,
      labelAttributes: const [],
      value: '',
      valueAttributes: const [],
      increasedValue: '',
      increasedValueAttributes: const [],
      decreasedValue: '',
      decreasedValueAttributes: const [],
      hint: '',
      hintAttributes: const [],
      tooltip: '',
      textDirection: null,
      transform: Float64List(16),
      hitTestTransform: Float64List(16),
      childrenInTraversalOrder: Int32List(0),
      childrenInHitTestOrder: Int32List(0),
      additionalActions: Int32List(0),
      controlsNodes: null,
      inputType: ui.SemanticsInputType.none,
      locale: null,
      minValue: '',
      maxValue: '',
    );

void main() {
  test('label is untouched without an identifier', () {
    expect(labelWithAtspiId('Weiter', ''), 'Weiter');
    expect(labelWithAtspiId('', ''), '');
  });

  test('identifier is appended, also to an empty label', () {
    expect(labelWithAtspiId('Weiter', 'a-b'), 'Weiter [id=a-b]');
    expect(labelWithAtspiId('', 'a-b'), '[id=a-b]');
  });

  test('the lab mode is off unless the variable is set', () {
    expect(atspiIdsEnabled(), isFalse);
  });

  test('wrapper rewrites only nodes with an identifier', () {
    final inner = _Recorder();
    final wrapper = AtspiIdSemanticsUpdateBuilder(inner);
    _node(wrapper, 'x-y', 'Label');
    _node(wrapper, '', 'Plain');
    expect(inner.labels, ['Label [id=x-y]', 'Plain']);
  });
}
