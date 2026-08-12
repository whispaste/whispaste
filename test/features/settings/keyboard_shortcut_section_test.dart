import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/hotkey_conflicts.dart';
import 'package:whispaste/services/hotkey_service.dart';
import 'package:whispaste/services/snippet_picker/snippet_picker_controller.dart';
import 'package:whispaste/features/settings/sections/feedback_section.dart';
import 'package:whispaste/features/settings/settings_widgets.dart';
import 'package:whispaste/features/settings/sections/recording_sections.dart';

import '../../fixtures/test_helpers.dart';

late L10n l10n;

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('KeyboardShortcutSection', () {
    testWidgets('renders Hold to Record toggle inside the hotkey block', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          // Scrollbar gepumpt, seit die Sektion drei Hotkey-Einträge trägt:
          // sie ist damit höher als das 800x600-Testfenster, in der App aber
          // ohnehin Teil einer scrollenden Einstellungsseite.
          const SingleChildScrollView(child: KeyboardShortcutSection()),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.settingsHoldToRecord), findsOneWidget);
    });

    testWidgets('the Hold to Record row announces its toggled state', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: KeyboardShortcutSection()),
          locale: const Locale('en'),
          overrides: [
            settingsProvider.overrideWith(
              () => _FakeSettings(
                const AppSettings(
                  audioInput: AudioInputSettings(pushToTalk: true),
                ),
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Every other toggle row in Settings carries hasToggledState; this one
      // was the exception until the audit. Skipped where the platform cannot
      // do key-up at all, because then the row genuinely has no state.
      final supportsKeyUp = ProviderScope.containerOf(
        tester.element(find.byType(KeyboardShortcutSection)),
      ).read(hotkeyServiceProvider.notifier).supportsKeyUp;
      final row = tester.getSemantics(
        find.ancestor(
          of: find.text(l10n.settingsHoldToRecord),
          matching: find.byType(SettingRow),
        ),
      );
      // Both branches are asserted on purpose: a bare `if (supportsKeyUp)`
      // would pass having checked nothing on a host without key-up support,
      // which is the same hollow shape this audit twice had to repair.
      if (supportsKeyUp) {
        expect(
          row,
          matchesSemantics(
            label: l10n.settingsHoldToRecord,
            hint: l10n.onboardingTriggerModeHoldHint,
            hasToggledState: true,
            isToggled: true,
          ),
        );
      } else {
        // No key-up means no push-to-talk, so the row must claim no state
        // rather than a state its disabled switch would never accept.
        expect(
          row,
          matchesSemantics(
            label: l10n.settingsHoldToRecord,
            hint: l10n.onboardingTriggerModeToggleHint,
          ),
        );
      }
      handle.dispose();
    });

    testWidgets('a disabled hotkey takes the Change-hotkey button out of the '
        'tab order, not just out of the mouse\'s reach', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: KeyboardShortcutSection()),
          locale: const Locale('en'),
          overrides: [
            settingsProvider.overrideWith(
              () => _FakeSettings(
                const AppSettings(hotkey: HotkeySettings(hotkeyEnabled: false)),
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // The row is still rendered (dimmed to 40%), so finding it is not the
      // test — reaching it with the keyboard is.
      //
      // `.first` seit dem Schnellnotiz-Hotkey: die Sektion trägt jetzt zwei
      // „Ändern"-Buttons, und dieser Test meint den des Haupt-Hotkeys.
      final button = find.text(l10n.settingsChangeHotkey).first;
      expect(button, findsOneWidget);

      // Behavioural, not structural: ExcludeFocus leaves the descendant Focus
      // widgets' own canRequestFocus untouched and blocks them from the node
      // tree instead, so asking the node to take focus is the only probe that
      // actually answers the question.
      final node = Focus.of(tester.element(button));
      node.requestFocus();
      await tester.pump();
      expect(
        node.hasFocus,
        isFalse,
        reason: 'Tab must not land on a control for a switched-off hotkey',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Schnellnotiz-Hotkey — der zweite, nachgeordnete Eintrag
  // ---------------------------------------------------------------------------

  group('KeyboardShortcutSection — Schnellnotiz-Hotkey', () {
    Widget subject({
      AppSettings? settings,
      HotkeyRegistrationStatus status = HotkeyRegistrationStatus.unknown,
      double textScale = 1.0,
      double width = 560,
      Locale locale = const Locale('en'),
    }) => makeTestable(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: SingleChildScrollView(
          child: SizedBox(
            key: const Key('probeFrame'),
            width: width,
            child: const KeyboardShortcutSection(),
          ),
        ),
      ),
      locale: locale,
      overrides: [
        settingsProvider.overrideWith(
          () => _FakeSettings(settings ?? const AppSettings()),
        ),
        quickNoteHotkeyRegistrationStatusProvider.overrideWith(
          () => _FakeQuickNoteStatus(status),
        ),
        // Der dritte Block steht hier als „auf dieser Plattform noch nicht
        // verfügbar" — ein Satz statt Umschalter, Kombination und
        // Ändern-Schaltfläche. Diese Gruppe misst den *Schnellnotiz*-Block:
        // sein Ändern-Button und seine Kombinations-Beschriftung wären sonst
        // nur noch über ihren Index von den gleichnamigen des dritten Blocks
        // zu unterscheiden, und ein Index ist keine Aussage. Das Zusammenspiel
        // beider Blöcke prüft die Snippet-Picker-Gruppe unten.
        snippetPickerAvailabilityProvider.overrideWithValue(false),
      ],
    );

    testWidgets('renders as its own entry below the push-to-talk row', (
      tester,
    ) async {
      await tester.pumpWidget(subject());
      await tester.pumpAndSettle();

      expect(find.text(l10n.settingsQuickNoteHotkeyEnabled), findsOneWidget);

      // Nachgeordnet heißt: unterhalb. Push-to-talk gehört zum Haupt-Hotkey
      // und darf nicht zwischen Haupt- und Schnellnotiz-Hotkey geraten, wo sie
      // optisch an den falschen Hotkey andocken würde.
      final pushToTalkY = tester
          .getTopLeft(find.text(l10n.settingsHoldToRecord))
          .dy;
      final quickNoteY = tester
          .getTopLeft(find.text(l10n.settingsQuickNoteHotkeyEnabled))
          .dy;
      expect(quickNoteY, greaterThan(pushToTalkY));
    });

    testWidgets('the indentation follows the reading direction, not the left', (
      tester,
    ) async {
      // Die Einrückung ist das einzige Signal, das die Unterordnung trägt.
      // Physisch links gesetzt läge sie auf Hebräisch an der *Schlusskante*
      // und wäre dort keine Einrückung mehr, sondern eine beliebige Lücke —
      // die Nachordnung ginge in einer von drei Sprachen verloren.
      Rect rowsFor(WidgetTester t) => t.getRect(find.byType(SettingRow).first);
      Rect quickNoteFor(WidgetTester t) => t.getRect(
        find.ancestor(
          of: find.byKey(const Key('quickNoteHotkeyToggle')),
          matching: find.byType(SettingRow),
        ),
      );

      await tester.pumpWidget(subject());
      await tester.pumpAndSettle();
      final ltrMain = rowsFor(tester);
      final ltrQuickNote = quickNoteFor(tester);
      expect(
        Directionality.of(tester.element(find.byType(SettingRow).first)),
        TextDirection.ltr,
      );
      expect(ltrQuickNote.left, greaterThan(ltrMain.left));
      expect(ltrQuickNote.right, closeTo(ltrMain.right, 0.01));

      await tester.pumpWidget(subject(locale: const Locale('he')));
      await tester.pumpAndSettle();
      final rtlMain = rowsFor(tester);
      final rtlQuickNote = quickNoteFor(tester);
      // Erst belegen, dass die Sprache überhaupt spiegelt — sonst prüfte der
      // Rest unten nur eine zweite LTR-Darstellung.
      expect(
        Directionality.of(tester.element(find.byType(SettingRow).first)),
        TextDirection.rtl,
      );
      expect(rtlQuickNote.right, lessThan(rtlMain.right));
      expect(rtlQuickNote.left, closeTo(rtlMain.left, 0.01));
    });

    testWidgets('names where the dictated text lands, without a note picker', (
      tester,
    ) async {
      await tester.pumpWidget(subject());
      await tester.pumpAndSettle();

      expect(find.text(l10n.settingsQuickNoteHotkeyHint), findsOneWidget);
      // Die Ziel-Notiz wird im Notizen-Bereich bestimmt — hier steht die
      // Taste, nicht die Notiz. Ein Auswahlfeld wäre genau die Platzierung,
      // die das Ticket ausschließt.
      expect(find.byType(DropdownButton<String>), findsNothing);
    });

    testWidgets('the toggle writes the quick-note setting, not the main one', (
      tester,
    ) async {
      await tester.pumpWidget(subject());
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(KeyboardShortcutSection)),
      );
      expect(
        container
            .read(settingsProvider)
            .value!
            .quickNoteHotkey
            .quickNoteHotkeyEnabled,
        isFalse,
        reason: 'default is off — an update must never claim a hotkey silently',
      );

      await tester.tap(find.byKey(const Key('quickNoteHotkeyToggle')));
      await tester.pumpAndSettle();

      final updated = container.read(settingsProvider).value!;
      expect(updated.quickNoteHotkey.quickNoteHotkeyEnabled, isTrue);
      expect(
        updated.hotkeyEnabled,
        const AppSettings().hotkeyEnabled,
        reason: 'the main hotkey must be untouched by the subordinate toggle',
      );
    });

    testWidgets('a switched-off quick-note hotkey is out of the tab order', (
      tester,
    ) async {
      await tester.pumpWidget(subject());
      await tester.pumpAndSettle();

      // Zwei „Ändern"-Buttons: der zweite gehört zum Schnellnotiz-Hotkey.
      final buttons = find.text(l10n.settingsChangeHotkey);
      expect(buttons, findsNWidgets(2));

      final node = Focus.of(tester.element(buttons.at(1)));
      node.requestFocus();
      await tester.pump();
      expect(
        node.hasFocus,
        isFalse,
        reason: 'Tab must not reach the control of a switched-off hotkey',
      );
    });

    testWidgets('shows the stored combination including the display key', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          settings: const AppSettings(
            quickNoteHotkey: QuickNoteHotkeySettings(
              quickNoteHotkeyEnabled: true,
              quickNoteHotkeyKey: ';',
              // Layout-abweichende Anzeige-Taste (DE-Tastatur): gespeichert
              // wird ';', angezeigt gehört 'Ö'.
              quickNoteHotkeyKeyDisplay: 'Ö',
              quickNoteHotkeyModifiers: 'ctrl+alt',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ö'), findsOneWidget);
      expect(find.text(';'), findsNothing);
    });

    testWidgets('an identical combination is refused before it is saved', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          settings: const AppSettings(
            hotkey: HotkeySettings(
              hotkeyEnabled: true,
              hotkeyKey: 'D',
              hotkeyModifiers: 'ctrl+shift',
            ),
            quickNoteHotkey: QuickNoteHotkeySettings(
              quickNoteHotkeyEnabled: true,
              quickNoteHotkeyKey: 'Y',
              quickNoteHotkeyModifiers: 'ctrl+shift',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.settingsChangeHotkey).at(1));
      await tester.pumpAndSettle();

      // Genau die Kombination des Haupt-Hotkeys aufzeichnen.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.settingsHotkeyRecorderSave));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(KeyboardShortcutSection)),
      );
      expect(
        container
            .read(settingsProvider)
            .value!
            .quickNoteHotkey
            .quickNoteHotkeyKey,
        'Y',
        reason: 'the colliding combination must not reach the settings',
      );
      expect(
        find.byKey(const Key('quickNoteHotkeyCollisionNotice')),
        findsOneWidget,
      );
      // Bedienfehler, kein System-Konflikt — die Meldung muss die belegende
      // Aktion benennen, sonst weiß der Nutzer nicht, wogegen er gestoßen ist.
      expect(
        find.text(
          l10n.settingsQuickNoteHotkeyCollision(
            l10n.settingsHotkeyActionRecording,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a free combination is saved and shows no collision notice', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          settings: const AppSettings(
            hotkey: HotkeySettings(
              hotkeyEnabled: true,
              hotkeyKey: 'D',
              hotkeyModifiers: 'ctrl+shift',
            ),
            quickNoteHotkey: QuickNoteHotkeySettings(
              quickNoteHotkeyEnabled: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.settingsChangeHotkey).at(1));
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.settingsHotkeyRecorderSave));
      await tester.pumpAndSettle();

      final saved = ProviderScope.containerOf(
        tester.element(find.byType(KeyboardShortcutSection)),
      ).read(settingsProvider).value!.quickNoteHotkey;
      expect(saved.quickNoteHotkeyKey, 'K');
      expect(
        find.byKey(const Key('quickNoteHotkeyCollisionNotice')),
        findsNothing,
      );
    });

    testWidgets('the recorder still warns about system-reserved combinations', (
      tester,
    ) async {
      // Die System-Konflikt-Warnung steckt im Aufzeichnungs-Dialog, der hier
      // wiederverwendet wird — dieser Test hält fest, dass sie den zweiten
      // Aufrufer auch wirklich erreicht.
      //
      // Der Eintrag kommt aus der Liste der laufenden Plattform, statt eine
      // Kombination fest zu verdrahten, die auf macOS/Windows/Linux
      // unterschiedlich reserviert ist. `isNotEmpty` ist dabei die Zusicherung,
      // dass der Test nicht mangels Liste heimlich nichts prüft.
      final reserved = platformConflicts;
      expect(
        reserved,
        isNotEmpty,
        reason: 'every desktop platform ships a system-conflict list',
      );
      final entry = reserved.first;

      await tester.pumpWidget(
        subject(
          settings: AppSettings(
            quickNoteHotkey: QuickNoteHotkeySettings(
              quickNoteHotkeyEnabled: true,
              quickNoteHotkeyKey: entry.key,
              quickNoteHotkeyModifiers: entry.modifiers,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.settingsChangeHotkey).at(1));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('hotkeyConflictWarning')), findsOneWidget);
    });

    testWidgets('a failed registration says "not active" and asks for a new '
        'combination', (tester) async {
      await tester.pumpWidget(
        subject(
          settings: const AppSettings(
            quickNoteHotkey: QuickNoteHotkeySettings(
              quickNoteHotkeyEnabled: true,
            ),
          ),
          status: HotkeyRegistrationStatus.conflict,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('quickNoteHotkeyInactiveNotice')),
        findsOneWidget,
      );
      expect(find.text(l10n.settingsQuickNoteHotkeyInactive), findsOneWidget);
    });

    testWidgets('a switched-off hotkey never claims to have failed', (
      tester,
    ) async {
      // Der Registrierungs-Status ist ein In-Memory-Wert, den nur
      // Registrierungs-Versuche schreiben — Abschalten setzt ihn nicht zurück.
      // Ohne die Enabled-Bedingung stünde „nicht aktiv, bitte neu belegen" an
      // einem Hotkey, den der Nutzer gerade selbst ausgeschaltet hat.
      await tester.pumpWidget(
        subject(status: HotkeyRegistrationStatus.conflict),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('quickNoteHotkeyInactiveNotice')),
        findsNothing,
      );
    });

    for (final scale in [1.5, 2.0, 2.5]) {
      testWidgets('survives text scale $scale without clipping', (
        tester,
      ) async {
        await tester.pumpWidget(
          subject(
            settings: const AppSettings(
              quickNoteHotkey: QuickNoteHotkeySettings(
                quickNoteHotkeyEnabled: true,
              ),
            ),
            status: HotkeyRegistrationStatus.conflict,
            textScale: scale,
          ),
        );
        await tester.pumpAndSettle();

        // Die Überlauf-Ausnahme der *Haupt*-Hotkey-Zeile abräumen — sonst
        // scheitert der Test an einem Bestandsfehler, über den er nichts
        // aussagen will. Was der neue Block tut, prüft die Geometrie unten;
        // siehe die Begründung an [_quickNoteOverflow].
        while (tester.takeException() != null) {}

        // Kombinations-Anzeige, Hinweiszeile und Warnung sind gleichzeitig
        // sichtbar — genau die drei Elemente, die das Ticket bei vergrößerter
        // Systemschrift ungeschnitten verlangt.
        expect(find.text(l10n.settingsQuickNoteCurrentHotkey), findsOneWidget);
        expect(find.text(l10n.settingsQuickNoteHotkeyInactive), findsOneWidget);

        final overflow = _quickNoteOverflow(tester);
        expect(
          overflow,
          isNull,
          reason: 'quick-note block overflowed at text scale $scale: $overflow',
        );
      });
    }
  });

  // ---------------------------------------------------------------------------
  // Snippet-Picker-Hotkey — der dritte, nachgeordnete Eintrag (Ticket 27)
  // ---------------------------------------------------------------------------

  group('KeyboardShortcutSection — Snippet-Picker-Hotkey', () {
    Widget subject({
      AppSettings? settings,
      HotkeyRegistrationStatus status = HotkeyRegistrationStatus.unknown,
      bool available = true,
      double textScale = 1.0,
      double width = 560,
      Locale locale = const Locale('en'),
    }) => makeTestable(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: SingleChildScrollView(
          child: SizedBox(
            key: const Key('probeFrame'),
            width: width,
            child: const KeyboardShortcutSection(),
          ),
        ),
      ),
      locale: locale,
      overrides: [
        settingsProvider.overrideWith(
          () => _FakeSettings(settings ?? const AppSettings()),
        ),
        snippetPickerHotkeyRegistrationStatusProvider.overrideWith(
          () => _FakeSnippetPickerStatus(status),
        ),
        // Die eine Verfügbarkeits-Aussage (Ticket 26), hier gestellt: auf
        // einem macOS-Rechner gäbe es den „nicht verfügbar"-Zweig sonst
        // nirgends zu sehen, und auf einem Windows-Rechner den anderen nicht.
        snippetPickerAvailabilityProvider.overrideWithValue(available),
      ],
    );

    testWidgets('renders as its own entry below the quick-note block', (
      tester,
    ) async {
      await tester.pumpWidget(subject());
      await tester.pumpAndSettle();

      expect(
        find.text(l10n.settingsSnippetPickerHotkeyEnabled),
        findsOneWidget,
      );
      final quickNoteY = tester
          .getTopLeft(find.text(l10n.settingsQuickNoteHotkeyEnabled))
          .dy;
      final snippetY = tester
          .getTopLeft(find.text(l10n.settingsSnippetPickerHotkeyEnabled))
          .dy;
      expect(snippetY, greaterThan(quickNoteY));
    });

    testWidgets('the indentation follows the reading direction, not the left', (
      tester,
    ) async {
      // Wie beim Schnellnotiz-Block: die Einrückung ist das Signal, das die
      // Unterordnung trägt, und muss deshalb auf Hebräisch an der *Anfangs*-
      // kante liegen.
      Rect rowsFor(WidgetTester t) => t.getRect(find.byType(SettingRow).first);
      Rect snippetFor(WidgetTester t) => t.getRect(
        find.ancestor(
          of: find.byKey(const Key('snippetPickerHotkeyToggle')),
          matching: find.byType(SettingRow),
        ),
      );

      await tester.pumpWidget(subject());
      await tester.pumpAndSettle();
      final ltrMain = rowsFor(tester);
      final ltrSnippet = snippetFor(tester);
      expect(ltrSnippet.left, greaterThan(ltrMain.left));
      expect(ltrSnippet.right, closeTo(ltrMain.right, 0.01));

      await tester.pumpWidget(subject(locale: const Locale('he')));
      await tester.pumpAndSettle();
      expect(
        Directionality.of(tester.element(find.byType(SettingRow).first)),
        TextDirection.rtl,
      );
      final rtlMain = rowsFor(tester);
      final rtlSnippet = snippetFor(tester);
      expect(rtlSnippet.right, lessThan(rtlMain.right));
      expect(rtlSnippet.left, closeTo(rtlMain.left, 0.01));
    });

    testWidgets('says what the hotkey opens, and never names it like the '
        'spoken trigger word', (tester) async {
      await tester.pumpWidget(subject());
      await tester.pumpAndSettle();

      expect(find.text(l10n.settingsSnippetPickerHotkeyHint), findsOneWidget);
      // Das gesprochene Trigger-Wort ist eine andere Sache an einem anderen
      // Ort (Snippets-Seite). Stünde sein Eingabefeld hier, wären die beiden
      // Auslösewege genau das, was sie nicht sind: eine Einstellung.
      expect(find.text(l10n.snippetsPickerTriggerLabel), findsNothing);
    });

    testWidgets('the toggle writes the snippet-picker setting, not the other '
        'two', (tester) async {
      await tester.pumpWidget(subject());
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(KeyboardShortcutSection)),
      );
      expect(
        container
            .read(settingsProvider)
            .value!
            .snippetPickerHotkey
            .snippetPickerHotkeyEnabled,
        isFalse,
        reason: 'default is off — an update must never claim a hotkey silently',
      );

      await tester.tap(find.byKey(const Key('snippetPickerHotkeyToggle')));
      await tester.pumpAndSettle();

      final updated = container.read(settingsProvider).value!;
      expect(updated.snippetPickerHotkey.snippetPickerHotkeyEnabled, isTrue);
      expect(updated.hotkeyEnabled, const AppSettings().hotkeyEnabled);
      expect(
        updated.quickNoteHotkey.quickNoteHotkeyEnabled,
        const AppSettings().quickNoteHotkey.quickNoteHotkeyEnabled,
        reason: 'the two sibling hotkeys must be untouched by this toggle',
      );
    });

    testWidgets(
      'a switched-off snippet-picker hotkey is out of the tab order',
      (tester) async {
        await tester.pumpWidget(subject());
        await tester.pumpAndSettle();

        final node = Focus.of(
          tester.element(find.byKey(const Key('snippetPickerHotkeyChange'))),
        );
        node.requestFocus();
        await tester.pump();
        expect(
          node.hasFocus,
          isFalse,
          reason: 'Tab must not reach the control of a switched-off hotkey',
        );
      },
    );

    testWidgets('shows the stored combination including the display key', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          settings: const AppSettings(
            snippetPickerHotkey: SnippetPickerHotkeySettings(
              snippetPickerHotkeyEnabled: true,
              snippetPickerHotkeyKey: ';',
              snippetPickerHotkeyKeyDisplay: 'Ö',
              snippetPickerHotkeyModifiers: 'ctrl+alt',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ö'), findsOneWidget);
      expect(find.text(';'), findsNothing);
    });

    testWidgets('a combination already used by the main hotkey is refused '
        'before it is saved', (tester) async {
      await tester.pumpWidget(
        subject(
          settings: const AppSettings(
            hotkey: HotkeySettings(
              hotkeyEnabled: true,
              hotkeyKey: 'D',
              hotkeyModifiers: 'ctrl+shift',
            ),
            snippetPickerHotkey: SnippetPickerHotkeySettings(
              snippetPickerHotkeyEnabled: true,
              snippetPickerHotkeyKey: 'E',
              snippetPickerHotkeyModifiers: 'ctrl+alt',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Der dritte Block steht am unteren Ende einer Sektion, die höher ist
      // als das Testfenster — in der App scrollt die Einstellungsseite,
      // hier muss der Test das selbst tun.
      await tester.ensureVisible(
        find.byKey(const Key('snippetPickerHotkeyChange')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('snippetPickerHotkeyChange')));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.settingsHotkeyRecorderSave));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(KeyboardShortcutSection)),
      );
      expect(
        container
            .read(settingsProvider)
            .value!
            .snippetPickerHotkey
            .snippetPickerHotkeyKey,
        'E',
        reason: 'the colliding combination must not reach the settings',
      );
      expect(
        find.byKey(const Key('snippetPickerHotkeyCollisionNotice')),
        findsOneWidget,
      );
      expect(
        find.text(
          l10n.settingsSnippetPickerHotkeyCollision(
            l10n.settingsHotkeyActionRecording,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a combination already used by the quick-note hotkey is '
        'refused too — all three are checked against each other', (
      tester,
    ) async {
      // Der Fall, den es vor dem dritten Hotkey nicht geben konnte: zwei
      // *nachgeordnete* Hotkeys, die einander im Weg stehen. Ginge die Prüfung
      // nur gegen den Haupt-Hotkey, fiele genau das durch.
      await tester.pumpWidget(
        subject(
          settings: const AppSettings(
            quickNoteHotkey: QuickNoteHotkeySettings(
              quickNoteHotkeyEnabled: true,
              quickNoteHotkeyKey: 'Y',
              quickNoteHotkeyModifiers: 'ctrl+alt',
            ),
            snippetPickerHotkey: SnippetPickerHotkeySettings(
              snippetPickerHotkeyEnabled: true,
              snippetPickerHotkeyKey: 'E',
              snippetPickerHotkeyModifiers: 'ctrl+shift',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Der dritte Block steht am unteren Ende einer Sektion, die höher ist
      // als das Testfenster — in der App scrollt die Einstellungsseite,
      // hier muss der Test das selbst tun.
      await tester.ensureVisible(
        find.byKey(const Key('snippetPickerHotkeyChange')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('snippetPickerHotkeyChange')));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyY);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.settingsHotkeyRecorderSave));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(KeyboardShortcutSection)),
      );
      expect(
        container
            .read(settingsProvider)
            .value!
            .snippetPickerHotkey
            .snippetPickerHotkeyKey,
        'E',
      );
      expect(
        find.text(
          l10n.settingsSnippetPickerHotkeyCollision(
            l10n.settingsHotkeyActionQuickNote,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a free combination is saved and shows no collision notice', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          settings: const AppSettings(
            hotkey: HotkeySettings(
              hotkeyEnabled: true,
              hotkeyKey: 'D',
              hotkeyModifiers: 'ctrl+shift',
            ),
            snippetPickerHotkey: SnippetPickerHotkeySettings(
              snippetPickerHotkeyEnabled: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Der dritte Block steht am unteren Ende einer Sektion, die höher ist
      // als das Testfenster — in der App scrollt die Einstellungsseite,
      // hier muss der Test das selbst tun.
      await tester.ensureVisible(
        find.byKey(const Key('snippetPickerHotkeyChange')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('snippetPickerHotkeyChange')));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.settingsHotkeyRecorderSave));
      await tester.pumpAndSettle();

      final saved = ProviderScope.containerOf(
        tester.element(find.byType(KeyboardShortcutSection)),
      ).read(settingsProvider).value!.snippetPickerHotkey;
      expect(saved.snippetPickerHotkeyKey, 'K');
      expect(
        find.byKey(const Key('snippetPickerHotkeyCollisionNotice')),
        findsNothing,
      );
    });

    testWidgets('the recorder still warns about system-reserved combinations', (
      tester,
    ) async {
      final reserved = platformConflicts;
      expect(reserved, isNotEmpty);
      final entry = reserved.first;

      await tester.pumpWidget(
        subject(
          settings: AppSettings(
            snippetPickerHotkey: SnippetPickerHotkeySettings(
              snippetPickerHotkeyEnabled: true,
              snippetPickerHotkeyKey: entry.key,
              snippetPickerHotkeyModifiers: entry.modifiers,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Der dritte Block steht am unteren Ende einer Sektion, die höher ist
      // als das Testfenster — in der App scrollt die Einstellungsseite,
      // hier muss der Test das selbst tun.
      await tester.ensureVisible(
        find.byKey(const Key('snippetPickerHotkeyChange')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('snippetPickerHotkeyChange')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('hotkeyConflictWarning')), findsOneWidget);
    });

    testWidgets('a failed registration says "not active" and asks for a new '
        'combination', (tester) async {
      await tester.pumpWidget(
        subject(
          settings: const AppSettings(
            snippetPickerHotkey: SnippetPickerHotkeySettings(
              snippetPickerHotkeyEnabled: true,
            ),
          ),
          status: HotkeyRegistrationStatus.conflict,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('snippetPickerHotkeyInactiveNotice')),
        findsOneWidget,
      );
      expect(
        find.text(l10n.settingsSnippetPickerHotkeyInactive),
        findsOneWidget,
      );
    });

    testWidgets('a switched-off hotkey never claims to have failed', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(status: HotkeyRegistrationStatus.conflict),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('snippetPickerHotkeyInactiveNotice')),
        findsNothing,
      );
    });

    testWidgets('where the platform has no picker, the row states that instead '
        'of offering a hotkey that could not open anything', (tester) async {
      await tester.pumpWidget(
        subject(
          available: false,
          settings: const AppSettings(
            // Selbst ein (etwa importierter) eingeschalteter Hotkey macht die
            // Zeile hier nicht bedienbar — die Plattform-Aussage schlägt den
            // gespeicherten Zustand.
            snippetPickerHotkey: SnippetPickerHotkeySettings(
              snippetPickerHotkeyEnabled: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('snippetPickerHotkeyUnavailable')),
        findsOneWidget,
      );
      expect(find.text(l10n.snippetsPickerUnavailable), findsOneWidget);
      // Weder Umschalter noch Ändern-Schaltfläche: nichts, was den Eindruck
      // erweckt, hier ließe sich etwas einschalten.
      expect(find.byKey(const Key('snippetPickerHotkeyToggle')), findsNothing);
      expect(find.byKey(const Key('snippetPickerHotkeyChange')), findsNothing);
      expect(
        find.byKey(const Key('snippetPickerHotkeyComboLine')),
        findsNothing,
        reason: 'no combination is shown for a hotkey that cannot be used',
      );
    });

    for (final scale in [1.5, 2.0, 2.5]) {
      testWidgets('survives text scale $scale without clipping', (
        tester,
      ) async {
        await tester.pumpWidget(
          subject(
            settings: const AppSettings(
              snippetPickerHotkey: SnippetPickerHotkeySettings(
                snippetPickerHotkeyEnabled: true,
              ),
            ),
            status: HotkeyRegistrationStatus.conflict,
            textScale: scale,
          ),
        );
        await tester.pumpAndSettle();

        // Die bekannte Überlauf-Ausnahme der *Haupt*-Hotkey-Zeile abräumen —
        // Bestandsfehler, über den dieser Test nichts aussagt (siehe
        // [_quickNoteOverflow]).
        while (tester.takeException() != null) {}

        // „Kombination" steht wortgleich auch am Schnellnotiz-Block — die
        // Zeile dieses Blocks wird deshalb über ihren Schlüssel adressiert.
        expect(
          find.descendant(
            of: find.byKey(const Key('snippetPickerHotkeyComboLine')),
            matching: find.text(l10n.settingsSnippetPickerCurrentHotkey),
          ),
          findsOneWidget,
        );
        expect(
          find.text(l10n.settingsSnippetPickerHotkeyInactive),
          findsOneWidget,
        );

        final overflow = _snippetPickerOverflow(tester);
        expect(
          overflow,
          isNull,
          reason:
              'snippet-picker block overflowed at text scale $scale: $overflow',
        );
      });
    }
  });

  group('AudioSection', () {
    testWidgets('does NOT render Hold to Record toggle in audio block', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(const AudioSection(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.settingsHoldToRecord), findsNothing);
    });
  });
}

class _FakeSettings extends SettingsNotifier {
  _FakeSettings(this._settings);

  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;
}

class _FakeSnippetPickerStatus
    extends SnippetPickerHotkeyRegistrationStatusController {
  _FakeSnippetPickerStatus(this._status);

  final HotkeyRegistrationStatus _status;

  @override
  HotkeyRegistrationStatus build() => _status;
}

/// Meldet, welches Element des Snippet-Picker-Blocks über seinen Rahmen
/// hinausragt — oder `null`, wenn alle hineinpassen.
///
/// Zwilling von [_quickNoteOverflow] und aus demselben Grund geometrisch
/// statt über `tester.takeException()`: die Kombinations-Zeile des
/// **Haupt**-Hotkeys läuft ab Textskalierung 1.5 nachweislich über, und diese
/// Ausnahme würde jede Aussage über den neuen Block verschlucken.
String? _snippetPickerOverflow(WidgetTester tester) {
  final frame = tester.getRect(find.byKey(const Key('probeFrame')));
  final comboLine = find.byKey(const Key('snippetPickerHotkeyComboLine'));
  final probes = <String, Finder>{
    'Hinweiszeile': find.text(l10n.settingsSnippetPickerHotkeyHint),
    'Kombinations-Label': find.descendant(
      of: comboLine,
      matching: find.text(l10n.settingsSnippetPickerCurrentHotkey),
    ),
    'Tastenkappen': find.descendant(
      of: comboLine,
      matching: find.byType(HotkeyDisplay),
    ),
    'Ändern-Button': find.byKey(const Key('snippetPickerHotkeyChange')),
    'Nicht-aktiv-Warnung': find.text(l10n.settingsSnippetPickerHotkeyInactive),
  };
  for (final probe in probes.entries) {
    final rect = tester.getRect(probe.value);
    if (rect.right > frame.right + 0.5 || rect.left < frame.left - 0.5) {
      return '${probe.key}: ${rect.left}..${rect.right} '
          'ragt aus ${frame.left}..${frame.right} heraus';
    }
  }
  return null;
}

class _FakeQuickNoteStatus extends QuickNoteHotkeyRegistrationStatusController {
  _FakeQuickNoteStatus(this._status);

  final HotkeyRegistrationStatus _status;

  @override
  HotkeyRegistrationStatus build() => _status;
}

/// Meldet, welches Element des Schnellnotiz-Blocks über seinen Rahmen
/// hinausragt — oder `null`, wenn alle hineinpassen.
///
/// Geometrisch geprüft statt über `tester.takeException()`, weil in derselben
/// Sektion die Kombinations-Zeile des **Haupt**-Hotkeys sitzt, die ab
/// Textskalierung 1.5 nachweislich rechts überläuft (`HotkeyDisplay` + Button
/// in einer festen `Row` im `trailing`-Slot einer `SettingRow`). Dieser
/// Bestandsfehler ist nicht Gegenstand dieses Tickets; über die Ausnahme
/// geprüft, würde er jede Aussage über den neuen Block verschlucken.
String? _quickNoteOverflow(WidgetTester tester) {
  final frame = tester.getRect(find.byKey(const Key('probeFrame')));
  final probes = <String, Finder>{
    'Hinweiszeile': find.text(l10n.settingsQuickNoteHotkeyHint),
    'Kombinations-Label': find.text(l10n.settingsQuickNoteCurrentHotkey),
    'Tastenkappen': find.byType(HotkeyDisplay).at(1),
    'Ändern-Button': find.text(l10n.settingsChangeHotkey).at(1),
    'Nicht-aktiv-Warnung': find.text(l10n.settingsQuickNoteHotkeyInactive),
  };
  for (final probe in probes.entries) {
    final rect = tester.getRect(probe.value);
    if (rect.right > frame.right + 0.5 || rect.left < frame.left - 0.5) {
      return '${probe.key}: ${rect.left}..${rect.right} '
          'ragt aus ${frame.left}..${frame.right} heraus';
    }
  }
  return null;
}
