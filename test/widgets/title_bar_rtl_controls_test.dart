@TestOn('linux || windows')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/widgets/title_bar.dart';

/// UIA-VIS-03: on Windows and Linux the window controls follow the text
/// direction, so a Hebrew window carries them on the left, as the platforms
/// mirror caption buttons for RTL apps. macOS keeps its LTR row for the
/// traffic lights (see title_bar_macos_rtl_golden_test.dart).
Future<void> _pumpTitleBar(WidgetTester tester, Locale locale) {
  return tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: const Scaffold(body: WpTitleBar()),
    ),
  );
}

void main() {
  for (final (locale, closeOnRight) in [
    (const Locale('en'), true),
    (const Locale('he'), false),
  ]) {
    testWidgets(
      'the close button sits ${closeOnRight ? 'right' : 'left'} of the '
      'title in ${locale.languageCode}',
      (tester) async {
        await _pumpTitleBar(tester, locale);

        final title = tester.getCenter(find.text('WhisPaste')).dx;
        final close = tester.getCenter(find.byIcon(LucideIcons.x)).dx;
        final minimize = tester.getCenter(find.byIcon(LucideIcons.minus)).dx;
        expect(close > title, closeOnRight);
        // Close stays the outermost control in both directions.
        expect(close > minimize, closeOnRight);
      },
    );
  }
}
