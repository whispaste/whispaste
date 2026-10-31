// A finished quick note is saved in the background by default and offers a
// toast action; the setting "Notizen im Hauptfenster öffnen" opens it at once
// (UIA-SHL-08).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/window_activation.dart';
import 'package:whispaste/widgets/recording_behavior.dart';

import '../fixtures/test_helpers.dart';

class _Settings extends SettingsNotifier {
  _Settings(this._openInMain);
  final bool _openInMain;

  @override
  Future<AppSettings> build() async => AppSettings.defaults.copyWithSections(
    quickNoteHotkey: QuickNoteHotkeySettings(openNoteInMainWindow: _openInMain),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required bool openInMain,
  required List<int> activations,
}) {
  return tester.pumpWidget(
    makeTestable(
      Consumer(
        builder: (context, ref, _) => TextButton(
          key: const Key('react'),
          onPressed: () => reactToQuickNoteAppended(context, ref, 'n1'),
          child: const Text('react'),
        ),
      ),
      locale: const Locale('en'),
      overrides: [
        settingsProvider.overrideWith(() => _Settings(openInMain)),
        windowActivatorProvider.overrideWithValue(() async {
          activations.add(1);
        }),
      ],
    ),
  );
}

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  testWidgets('by default the note is saved in the background: a toast with '
      '"Open note" appears and the window stays where it is (UIA-SHL-08)', (
    tester,
  ) async {
    final activations = <int>[];
    await _pump(tester, openInMain: false, activations: activations);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('react')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.quickNoteToastSaved), findsOneWidget);
    expect(find.text(l10n.quickNoteToastOpenNote), findsOneWidget);
    expect(activations, isEmpty);

    await tester.tap(find.text(l10n.quickNoteToastOpenNote));
    await tester.pumpAndSettle();
    expect(activations, [1]);
  });

  testWidgets('with "Notizen im Hauptfenster öffnen" on, the window comes '
      'forward at once (UIA-SHL-08)', (tester) async {
    final activations = <int>[];
    await _pump(tester, openInMain: true, activations: activations);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('react')));
    await tester.pumpAndSettle();

    expect(activations, [1]);
    expect(find.text(l10n.quickNoteToastSaved), findsNothing);
  });
}
