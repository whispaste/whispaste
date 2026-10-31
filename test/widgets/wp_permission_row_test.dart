import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart' show loadAppFonts;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/services/permissions/permissions_overview_provider.dart';
import 'package:whispaste/widgets/wp_permission_row.dart';

import '../fixtures/test_helpers.dart';

const _micPurpose = 'Records your voice. Without it nothing can be recorded.';
const _pastePurpose =
    'Places the text at the cursor. Without it, the text lands on the clipboard.';

Future<void> _pumpRows(
  WidgetTester tester, {
  required List<WpPermissionRow> rows,
  double width = 460,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    makeTestable(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final row in rows) ...[row, const SizedBox(height: 8)],
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

WpPermissionRow _micRow({
  PermissionOverviewStatus status = PermissionOverviewStatus.granted,
  bool optional = false,
  String? actionLabel,
  VoidCallback? onAction,
}) => WpPermissionRow(
  id: 'microphone',
  icon: LucideIcons.mic,
  title: 'Microphone',
  purpose: _micPurpose,
  status: status,
  optional: optional,
  actionLabel: actionLabel,
  onAction: onAction,
);

Finder _actionButton(String id) =>
    find.byKey(ValueKey('permissions-row-$id-action'));

void main() {
  // Real metrics: the default test font is Ahem, whose glyphs are full-em
  // squares, so text (and the overflow check) would be meaningless without it.
  setUpAll(() => loadAppFonts());
  setUp(() => WpColors.activate(wpLightColors));
  tearDown(() => WpColors.activate(wpLightColors));

  testWidgets('granted row shows a check, no purpose and no action button', (
    tester,
  ) async {
    await _pumpRows(tester, rows: [_micRow()]);

    expect(find.byKey(const ValueKey('permissions-row-microphone')), findsOne);
    expect(find.byIcon(LucideIcons.check), findsOneWidget);
    expect(find.text(_micPurpose), findsNothing);
    expect(_actionButton('microphone'), findsNothing);
  });

  testWidgets('missing row shows its purpose and an action that fires once', (
    tester,
  ) async {
    var fired = 0;
    await _pumpRows(
      tester,
      rows: [
        _micRow(
          status: PermissionOverviewStatus.missing,
          actionLabel: 'Open Settings',
          onAction: () => fired++,
        ),
      ],
    );

    expect(find.text(_micPurpose), findsOneWidget);
    expect(find.byIcon(LucideIcons.check), findsNothing);
    expect(find.text('Open Settings'), findsOneWidget);

    await tester.tap(_actionButton('microphone'));
    await tester.pumpAndSettle();
    expect(fired, 1);
  });

  testWidgets('pending row keeps its purpose and action button', (
    tester,
  ) async {
    await _pumpRows(
      tester,
      rows: [
        _micRow(
          status: PermissionOverviewStatus.pending,
          actionLabel: 'Allow',
          onAction: () {},
        ),
      ],
    );

    expect(find.text(_micPurpose), findsOneWidget);
    expect(find.byIcon(LucideIcons.check), findsNothing);
    expect(_actionButton('microphone'), findsOneWidget);
  });

  testWidgets('the optional tag shows only on optional rows', (tester) async {
    await _pumpRows(
      tester,
      rows: [
        _micRow(status: PermissionOverviewStatus.missing, optional: true),
        const WpPermissionRow(
          id: 'auto-paste',
          icon: LucideIcons.clipboardPaste,
          title: 'Auto-paste',
          purpose: _pastePurpose,
          status: PermissionOverviewStatus.missing,
          optional: false,
        ),
      ],
    );

    final l10n = L10n.of(tester.element(find.byType(WpPermissionRow).first));
    final optionalTag = l10n.permissionRowOptional;
    expect(find.text(optionalTag), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('permissions-row-microphone')),
        matching: find.text(optionalTag),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('permissions-row-auto-paste')),
        matching: find.text(optionalTag),
      ),
      findsNothing,
    );
  });
}
