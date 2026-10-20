// Guard: every interactive Wp* control must accept pointers across a 48 x 48 px
// square. Measured by hit-testing points just inside the 48 px edge around the
// control's centre. The check reads where the render tree accepts a pointer,
// so it does not tap and does not trigger any callback.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/core/theme/tokens.dart';
import 'package:whispaste/widgets/wp_button.dart';
import 'package:whispaste/widgets/wp_discoverability_hint.dart';
import 'package:whispaste/widgets/wp_dropdown.dart';
import 'package:whispaste/widgets/wp_favourite_star.dart';
import 'package:whispaste/widgets/wp_filter_chip.dart';
import 'package:whispaste/widgets/wp_hero_button.dart';
import 'package:whispaste/widgets/wp_icon_button.dart';
import 'package:whispaste/widgets/wp_row_action.dart';
import 'package:whispaste/widgets/wp_row_checkbox.dart';
import 'package:whispaste/widgets/wp_search_field.dart';
import 'package:whispaste/widgets/wp_segmented_selector.dart';
import 'package:whispaste/widgets/wp_tabs.dart';
import 'package:whispaste/widgets/wp_text_link.dart';
import 'package:whispaste/widgets/wp_touch_target.dart';
import 'package:whispaste/widgets/wp_voice_input_button.dart';

import '../fixtures/test_helpers.dart';

/// Extent every interactive `Wp*` control must reach, unless it is a
/// documented exception below.
const double _requiredExtent = WpLayout.minTouchTarget;

/// Half of the required square, minus a sliver so the probe lies inside it.
const double _probe = _requiredExtent / 2 - 0.05;

/// Offsets from the centre that must be accepted for a control whose tap area
/// is [extent] square: just inside the edge, in eight directions.
List<Offset> _probesFor(double extent) {
  final p = extent / 2 - 0.05;
  return [
    Offset(p, 0),
    Offset(-p, 0),
    Offset(0, p),
    Offset(0, -p),
    Offset(p, p),
    Offset(-p, p),
    Offset(p, -p),
    Offset(-p, -p),
  ];
}

/// The documented shortfalls of the 48 px rule (DESIGN.md, "The Confirmed
/// Dense-Row Exception", decision E6 = (a)). Each is a `dense` variant whose
/// tap area is deliberately its visual box, so the guard checks that exact
/// size and also that it does not grow. Any other entry here is a regression.
const Map<String, double> _denseExceptions = {
  // 16 px glyph + 6 px padding per side. Dense row actions in the history
  // list, card and compact views, and in notes.
  'WpRowAction, dense': 28,
  // 32 px control, hit target equals its visual box. Trailing slot of a dense
  // settings row, toast actions, footer resets, hint "fix this" links.
  'WpButton secondary, dense': 32,
};

/// Whether the pointer at [position] is accepted by a render object that
/// belongs to the subtree of [root].
bool _acceptsWithin(RenderObject root, Offset position) {
  final result = HitTestResult();
  RendererBinding.instance.renderViews.first.hitTest(
    result,
    position: position,
  );
  for (final entry in result.path) {
    final target = entry.target;
    if (target is! RenderObject) continue;
    RenderObject? node = target;
    while (node != null) {
      if (identical(node, root)) return true;
      node = node.parent;
    }
  }
  return false;
}

class _Case {
  const _Case(this.name, this.build, {this.anchor, this.setUp});

  final String name;
  final Widget Function() build;

  /// The control whose centre the probes surround, when it is not the root
  /// of [build] (e.g. the dismiss button inside a hint).
  final Finder Function(Finder root)? anchor;

  final Future<void> Function()? setUp;
}

void _noopString(String? _) {}

final _cases = <_Case>[
  _Case(
    'WpButton primary, standard',
    () => WpButton(
      label: 'Speichern',
      variant: WpButtonVariant.primary,
      onPressed: () {},
    ),
  ),
  _Case(
    'WpButton secondary, dense',
    () => WpButton(
      label: 'Abbrechen',
      variant: WpButtonVariant.secondary,
      size: WpButtonSize.dense,
      onPressed: () {},
    ),
  ),
  _Case('WpHeroButton', () => WpHeroButton(label: 'Weiter', onPressed: () {})),
  _Case(
    'WpDropdown',
    () => const WpDropdown<String>(
      value: 'a',
      items: [
        WpDropdownItem(value: 'a', label: 'Alpha'),
        WpDropdownItem(value: 'b', label: 'Beta'),
      ],
      onChanged: _noopString,
    ),
  ),
  _Case(
    'WpFilterChip, short label',
    () => WpFilterChip(label: 'A', isActive: false, onTap: () {}),
  ),
  _Case(
    'WpFavouriteStar',
    () => WpFavouriteStar(
      isFavourite: false,
      semanticsLabel: 'Favorit',
      onToggle: () {},
    ),
  ),
  _Case(
    'WpIconButton',
    () => WpIconButton(
      icon: LucideIcons.x,
      tooltip: 'Schließen',
      onPressed: () {},
    ),
  ),
  _Case(
    'WpRowAction, standard',
    () =>
        WpRowAction(icon: LucideIcons.trash2, tooltip: 'Löschen', onTap: () {}),
  ),
  _Case(
    'WpRowAction, dense',
    () => WpRowAction(
      icon: LucideIcons.trash2,
      tooltip: 'Löschen',
      onTap: () {},
      dense: true,
    ),
  ),
  _Case('WpRowCheckbox', () => WpRowCheckbox(value: false, onChanged: () {})),
  _Case(
    'WpSearchField',
    () => WpSearchField(
      controller: TextEditingController(),
      hintText: 'Suchen',
      variant: WpSearchFieldVariant.outlined,
    ),
  ),
  _Case(
    'WpSegmentedSelector',
    () => WpSegmentedSelector(
      items: [
        WpSegmentItem(label: 'Eins', isActive: true, onTap: () {}),
        WpSegmentItem(label: 'Zwei', isActive: false, onTap: () {}),
      ],
      borderColor: Colors.grey,
      surfaceColor: Colors.white,
      textSecondary: Colors.grey,
    ),
  ),
  _Case(
    'WpTabs',
    () => WpTabs(
      labels: const ['Eins', 'Zwei'],
      selectedIndex: 0,
      onSelected: (_) {},
    ),
  ),
  _Case(
    'WpTextLink',
    () => WpTextLink(label: 'Mehr erfahren', onPressed: () {}),
  ),
  _Case(
    'WpVoiceInputButton',
    () => WpVoiceInputButton(onTranscript: (_) {}),
    anchor: (root) => find.descendant(of: root, matching: find.byType(InkWell)),
  ),
  _Case(
    'WpDiscoverabilityHint, dismiss control',
    () => const WpDiscoverabilityHint(hintId: 'wp58', text: 'Tipp'),
    anchor: (root) => find.descendant(of: root, matching: find.byType(InkWell)),
    setUp: () async => SharedPreferences.setMockInitialValues({}),
  ),
];

void main() {
  behaviourTests();
  for (final c in _cases) {
    final extent = _denseExceptions[c.name] ?? _requiredExtent;
    testWidgets(
      '${c.name}: tap surface is ${extent.toInt()} x ${extent.toInt()} or more',
      (tester) async {
        await c.setUp?.call();
        const key = ValueKey('wp58-target');
        await tester.pumpWidget(
          makeTestable(
            Center(
              child: ProviderScope(
                child: KeyedSubtree(key: key, child: c.build()),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final root = find.byKey(key);
        final rootRender = tester.renderObject(root);
        final anchor = c.anchor?.call(root) ?? root;
        final centre = tester.getCenter(anchor);

        final misses = <Offset>[
          for (final p in _probesFor(extent))
            if (!_acceptsWithin(rootRender, centre + p)) p,
        ];

        expect(
          misses,
          isEmpty,
          reason:
              '${c.name}: points ${(extent / 2 - 0.05).toStringAsFixed(2)} px '
              'from the centre are not accepted by the control (missing '
              'offsets: $misses)',
        );

        if (_denseExceptions.containsKey(c.name)) {
          // The exception is exact, not a floor: just below the box the
          // control must not accept the pointer, or the exception has quietly
          // grown into a 48 px target without anyone deciding it should.
          expect(
            _acceptsWithin(rootRender, centre + Offset(0, extent / 2 + 2)),
            isFalse,
            reason:
                '${c.name} is a documented dense exception: its tap area is '
                'its ${extent.toInt()} px box and must not grow',
          );
        }
      },
    );
  }
}

/// Taps the point [dy] px below the centre of [finder], inside the 48 px
/// square but outside the visual.
Future<void> _tapRing(WidgetTester tester, Finder finder, double dy) async {
  await tester.tapAt(tester.getCenter(finder).translate(0, dy));
  await tester.pumpAndSettle();
}

void behaviourTests() {
  testWidgets('a loose parent does not stretch the tap area', (tester) async {
    await tester.pumpWidget(
      makeTestable(
        Center(
          child: WpTouchTarget(
            onTap: () {},
            child: const SizedBox(width: 20, height: 20),
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(WpTouchTarget)),
      const Size.square(WpLayout.minTouchTarget),
    );
  });

  testWidgets('a tap on the centre of a glyph child fires onTap', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      makeTestable(
        Center(
          child: WpTouchTarget(
            onTap: () => taps++,
            child: const Icon(LucideIcons.x, size: 14),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(Icon));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('a child with its own tap handler wins over the target', (
    tester,
  ) async {
    var childTaps = 0;
    var targetTaps = 0;
    await tester.pumpWidget(
      makeTestable(
        Center(
          child: WpTouchTarget(
            onTap: () => targetTaps++,
            child: InkWell(
              onTap: () => childTaps++,
              child: const SizedBox.square(dimension: 20),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();
    expect(childTaps, 1);
    expect(targetTaps, 0);
  });

  testWidgets('a tap in the ring below WpIconButton fires onPressed', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      makeTestable(
        Center(
          child: WpIconButton(
            icon: LucideIcons.x,
            tooltip: 'Schließen',
            onPressed: () => presses++,
          ),
        ),
      ),
    );
    await _tapRing(tester, find.byType(WpIconButton), _probe);
    expect(presses, 1);
  });

  testWidgets('a tap in the ring below WpDropdown opens its menu', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(
        const Center(
          child: WpDropdown<String>(
            value: 'a',
            items: [
              WpDropdownItem(value: 'a', label: 'Alpha'),
              WpDropdownItem(value: 'b', label: 'Beta'),
            ],
            onChanged: _noopString,
          ),
        ),
      ),
    );
    expect(find.text('Beta'), findsNothing);
    await _tapRing(tester, find.byType(WpDropdown<String>), _probe);
    expect(find.text('Beta'), findsOneWidget);
  });

  testWidgets('a tap in the ring around WpSearchField focuses the field', (
    tester,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      makeTestable(
        Center(
          child: SizedBox(
            width: 300,
            child: WpSearchField(
              controller: TextEditingController(),
              hintText: 'Suchen',
              variant: WpSearchFieldVariant.outlined,
              focusNode: focusNode,
            ),
          ),
        ),
      ),
    );
    expect(focusNode.hasFocus, isFalse);
    await _tapRing(tester, find.byType(WpSearchField), _probe);
    expect(focusNode.hasFocus, isTrue);
  });
}
