/// The output selector shows its value once. With the overline visible
/// ("NACH DER TRANSKRIPTION") the value is the short action alone; only where
/// the overline is left out (the compact stage) does the value carry the
/// "Danach:" prefix. The tooltip and semantics always read overline + short
/// value, so the prefix never doubles.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_labels.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/microphone_selection_service.dart'
    show micDefaultLabel;
import 'package:whispaste/widgets/recording_dock.dart';
import 'package:whispaste/widgets/recording_dock_controls.dart';
import 'package:whispaste/widgets/recording_dock_layout.dart';

import '../fixtures/dock_choice_fixtures.dart';
import '../fixtures/test_helpers.dart';

const _overline = 'Nach der Transkription';
const _short = 'Kopieren & Einfügen';
const _compact = 'Danach: Kopieren & Einfügen';

Widget _selector(WpDockSelectorForm form) => Center(
  child: SizedBox(
    width: 320,
    child: WpDockSelector(
      id: 'output-action',
      form: form,
      icon: LucideIcons.copy,
      overline: _overline,
      value: _short,
      compactValue: _compact,
      onTap: () {},
    ),
  ),
);

void main() {
  testWidgets('labelled stage shows the overline and the short value only', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(
        _selector(WpDockSelectorForm.labelled),
        locale: const Locale('de'),
      ),
    );
    await tester.pump();

    expect(find.text(_short), findsOneWidget);
    expect(find.text(_compact), findsNothing);
    expect(find.text(_overline.toUpperCase()), findsOneWidget);
  });

  testWidgets('compact stage shows the prefixed value and no overline', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(
        _selector(WpDockSelectorForm.compact),
        locale: const Locale('de'),
      ),
    );
    await tester.pump();

    expect(find.text(_compact), findsOneWidget);
    expect(find.text(_overline.toUpperCase()), findsNothing);
  });

  testWidgets('icon-only stage shows no text; tooltip has no doubled prefix', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(
        _selector(WpDockSelectorForm.iconOnly),
        locale: const Locale('de'),
      ),
    );
    await tester.pump();

    expect(find.text(_short), findsNothing);
    expect(find.text(_compact), findsNothing);
    expect(find.byTooltip('$_overline: $_short'), findsOneWidget);
  });

  testWidgets('compact stage tooltip reads overline + short value', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(
        _selector(WpDockSelectorForm.compact),
        locale: const Locale('de'),
      ),
    );
    await tester.pump();

    expect(find.byTooltip('$_overline: $_short'), findsOneWidget);
    expect(find.byTooltip('$_overline: $_compact'), findsNothing);
  });

  test('dock label of each action carries no "Danach:" prefix', () async {
    final l10n = lookupL10n(const Locale('de'));
    for (final action in AfterTranscriptionAction.values) {
      expect(
        afterTranscriptionDockLabel(action, l10n),
        isNot(startsWith('Danach')),
        reason: action.name,
      );
    }
  });

  testWidgets('dock popup lists the actions without the prefix', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(
        Align(
          alignment: Alignment.bottomCenter,
          child: WpRecordingDock(
            sttModeLabel: 'Whisper · small',
            sttState: SttServerState.ready,
            smartMode: dockTestSmartMode(label: 'Smart Mode · Aus'),
            hotkeyLabel: 'Strg+Umschalt+D',
            microphoneLabel: micDefaultLabel,
            microphoneOptions: const [micDefaultLabel],
            onMicrophoneChanged: (_) {},
            afterActionLabel: _short,
            afterAction: AfterTranscriptionAction.clipboardAndPaste,
            onAfterActionChanged: (_) {},
            language: dockTestLanguage(label: 'DE'),
          ),
        ),
        size: const Size(1280, 800),
        locale: const Locale('de'),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('dock-output-action')));
    await tester.pumpAndSettle();

    expect(find.text('Kopieren'), findsWidgets);
    expect(find.text('Einfügen'), findsWidgets);
    expect(find.textContaining('Danach:'), findsNothing);
  });
}
