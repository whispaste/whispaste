/// UX probe: the flat snippet picker panel (WP-75 flat pass, no glass) on a
/// neutral desktop ground, in the dark and navy themes, with a long German
/// title to check truncation. Writes one PNG per variant into UX_SCREENS_DIR.
///
/// Tagged `ux-screens` (not part of the normal suite). Run on the Mac:
///
///   UX_SCREENS_DIR=OUT_DIR flutter test --tags=ux-screens test/ux_audit/ux_snippet_picker_test.dart
@Tags(<String>['ux-screens'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart' show loadAppFonts;
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/services/snippet_picker/snippet_picker_render_channel.dart';
import 'package:whispaste/snippet_picker_render_entrypoint.dart';

import '../features/settings/widgets/settings_golden_board.dart';

const _items = [
  SnippetPickerRenderItem(
    id: '1',
    title: 'Begrüßung für Kundenanfragen mit Terminvorschlag',
    body: 'Guten Tag, vielen Dank für Ihre Nachricht.',
  ),
  SnippetPickerRenderItem(
    id: '2',
    title: 'Grußformel',
    body: 'Mit freundlichen Grüßen',
  ),
  SnippetPickerRenderItem(
    id: '3',
    title: 'E-Mail-Signatur',
    body: 'Silvio Lindstedt',
  ),
];

const _panel = Size(460, 340);
const _canvas = Size(560, 420);

void main() {
  setUpAll(() async => loadAppFonts());

  final outDir =
      Platform.environment['UX_SCREENS_DIR'] ?? '.scratch/ux-review/screens';

  for (final theme in const ['dark', 'navy']) {
    for (final desktop in const [Color(0xFF3B4150), Color(0xFFDDE3EC)]) {
      final tone = desktop.computeLuminance() > 0.5 ? 'hell' : 'dunkel';
      final name = 'snippet-picker_${theme}_desktop-$tone';
      testWidgets('ux-snippet-picker $name', (tester) async {
        tester.view.physicalSize = _canvas;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        WpColors.activate(kSettingsGoldenSets[theme]!);
        addTearDown(() => WpColors.activate(kSettingsGoldenSets['dark']!));

        final controller = TextEditingController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: wpDarkTheme(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            locale: const Locale('de'),
            home: Scaffold(
              backgroundColor: desktop,
              body: Center(
                child: SizedBox(
                  width: _panel.width,
                  height: _panel.height,
                  child: SnippetPickerBody(
                    items: _items,
                    showGeneration: 0,
                    visible: true,
                    searchController: controller,
                    l10n: lookupL10n(const Locale('de')),
                    onSelect: (_) {},
                    onCancel: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 600));

        await tester.runAsync(() async {
          final layer =
              tester.binding.renderViews.first.debugLayer! as OffsetLayer;
          final image = await layer.toImage(Offset.zero & _canvas);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          Directory(outDir).createSync(recursive: true);
          File(
            '$outDir/$name.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
        });

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  }
}
