/// Lab-only: makes the stable semantics identifiers visible to AT-SPI and
/// Windows UI Automation (#973, #1314).
///
/// Flutter's Linux and Windows engines (3.47.x) drop `Semantics.identifier`: the ATK node
/// only receives the label (`fl_view_accessible.cc`), so every AT-SPI client
/// sees an empty id. With `WHISPASTE_A11Y_IDS=1` on Linux, this binding mixin
/// appends ` [id=<identifier>]` to the label of every node that has an
/// identifier, in one place (the semantics update builder), so a lab driver
/// can find controls by ID.
///
/// Without the variable nothing changes: the stock builder is returned and
/// labels are byte-identical (test/core/accessibility/atspi_ids_test.dart).
/// Do not set the variable for real users; it would be read out by screen
/// readers.
library;

import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';

/// Environment variable that enables the identifier suffix (Linux, Windows).
const String atspiIdsEnvVar = 'WHISPASTE_A11Y_IDS';

/// Whether the suffix is active for this process.
bool atspiIdsEnabled() {
  if (kIsWeb || !(Platform.isLinux || Platform.isWindows)) return false;
  return Platform.environment[atspiIdsEnvVar] == '1';
}

/// [label] with the identifier suffix; [label] itself when [identifier] is
/// empty.
String labelWithAtspiId(String label, String identifier) {
  if (identifier.isEmpty) return label;
  final suffix = '[id=$identifier]';
  return label.isEmpty ? suffix : '$label $suffix';
}

/// Wraps [inner] and rewrites the label of nodes that carry an identifier.
class AtspiIdSemanticsUpdateBuilder implements ui.SemanticsUpdateBuilder {
  /// Creates a wrapper around [inner].
  AtspiIdSemanticsUpdateBuilder(this.inner);

  /// The builder that receives the rewritten nodes.
  final ui.SemanticsUpdateBuilder inner;

  @override
  void updateNode({
    required int id,
    required ui.SemanticsFlags flags,
    required int actions,
    required int maxValueLength,
    required int currentValueLength,
    required int textSelectionBase,
    required int textSelectionExtent,
    required int platformViewId,
    required int scrollChildren,
    required int scrollIndex,
    required int traversalParent,
    required double scrollPosition,
    required double scrollExtentMax,
    required double scrollExtentMin,
    required ui.Rect rect,
    required String identifier,
    required String label,
    required List<ui.StringAttribute> labelAttributes,
    required String value,
    required List<ui.StringAttribute> valueAttributes,
    required String increasedValue,
    required List<ui.StringAttribute> increasedValueAttributes,
    required String decreasedValue,
    required List<ui.StringAttribute> decreasedValueAttributes,
    required String hint,
    required List<ui.StringAttribute> hintAttributes,
    required String tooltip,
    required ui.TextDirection? textDirection,
    required Float64List transform,
    required Float64List hitTestTransform,
    required Int32List childrenInTraversalOrder,
    required Int32List childrenInHitTestOrder,
    required Int32List additionalActions,
    int headingLevel = 0,
    String linkUrl = '',
    ui.SemanticsRole role = ui.SemanticsRole.none,
    required List<String>? controlsNodes,
    ui.SemanticsValidationResult validationResult =
        ui.SemanticsValidationResult.none,
    ui.SemanticsHitTestBehavior hitTestBehavior =
        ui.SemanticsHitTestBehavior.defer,
    required ui.SemanticsInputType inputType,
    required ui.Locale? locale,
    required String minValue,
    required String maxValue,
  }) {
    inner.updateNode(
      id: id,
      flags: flags,
      actions: actions,
      maxValueLength: maxValueLength,
      currentValueLength: currentValueLength,
      textSelectionBase: textSelectionBase,
      textSelectionExtent: textSelectionExtent,
      platformViewId: platformViewId,
      scrollChildren: scrollChildren,
      scrollIndex: scrollIndex,
      traversalParent: traversalParent,
      scrollPosition: scrollPosition,
      scrollExtentMax: scrollExtentMax,
      scrollExtentMin: scrollExtentMin,
      rect: rect,
      identifier: identifier,
      label: labelWithAtspiId(label, identifier),
      labelAttributes: labelAttributes,
      value: value,
      valueAttributes: valueAttributes,
      increasedValue: increasedValue,
      increasedValueAttributes: increasedValueAttributes,
      decreasedValue: decreasedValue,
      decreasedValueAttributes: decreasedValueAttributes,
      hint: hint,
      hintAttributes: hintAttributes,
      tooltip: tooltip,
      textDirection: textDirection,
      transform: transform,
      hitTestTransform: hitTestTransform,
      childrenInTraversalOrder: childrenInTraversalOrder,
      childrenInHitTestOrder: childrenInHitTestOrder,
      additionalActions: additionalActions,
      headingLevel: headingLevel,
      linkUrl: linkUrl,
      role: role,
      controlsNodes: controlsNodes,
      validationResult: validationResult,
      hitTestBehavior: hitTestBehavior,
      inputType: inputType,
      locale: locale,
      minValue: minValue,
      maxValue: maxValue,
    );
  }

  @override
  void updateCustomAction({
    required int id,
    String? label,
    String? hint,
    int overrideId = -1,
  }) => inner.updateCustomAction(
    id: id,
    label: label,
    hint: hint,
    overrideId: overrideId,
  );

  @override
  ui.SemanticsUpdate build() => inner.build();
}

/// Binding mixin: the single place that installs the lab-only wrapper.
mixin AtspiIdsBinding on SemanticsBinding {
  /// Whether the wrapper is installed; overridable for tests.
  @visibleForTesting
  bool get atspiIdsActive => atspiIdsEnabled();

  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() {
    final builder = super.createSemanticsUpdateBuilder();
    return atspiIdsActive ? AtspiIdSemanticsUpdateBuilder(builder) : builder;
  }
}
