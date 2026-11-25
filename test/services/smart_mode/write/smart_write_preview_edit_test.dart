/// The editable write preview (#254, ADR 0015 D13/D21): the field takes the
/// Enter/Esc grabs and gives them back with a fresh key epoch, Enter in the
/// field inserts the edited text only after the focus went back to the
/// target app, a refinement works on the edited text, and with the platform
/// flag off the card is as before.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/floating_overlay/dictation_notice.dart';
import 'package:whispaste/services/floating_overlay/macos_floating_overlay_controller.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_events.dart';
import 'package:whispaste/services/floating_overlay/overlay_notice.dart';
import 'package:whispaste/services/floating_overlay/overlay_render_channel.dart';
import 'package:whispaste/services/paste/paster.dart';
import 'package:whispaste/services/smart_mode/write/smart_write_environment.dart';
import 'package:whispaste/services/smart_mode/write/smart_write_notice.dart';
import 'package:whispaste/services/smart_mode/write/smart_write_preview.dart';
import 'package:whispaste/widgets/floating_overlay/overlay_notice_card.dart';

/// One registration of Enter (insert) and Esc (discard).
typedef _Grab = ({void Function() enter, void Function() escape});

class _EditPaster implements Paster {
  String target = 'editor';
  ForegroundWindow? front = const ForegroundWindow(id: 'editor');
  final pasted = <String>[];
  final copied = <String>[];
  final grabs = <_Grab>[];
  final focusReturns = <String?>[];

  /// The order of the native steps, to show the focus goes back first.
  final steps = <String>[];
  bool focusReturned = true;
  int releases = 0;

  SmartWriteEnvironment environment({
    bool wayland = false,
    bool canEdit = true,
  }) => SmartWriteEnvironment(
    wayland: wayland,
    canEditPreview: canEdit,
    target: getTargetBundleId,
    foreground: () async => front,
    copy: (text) async {
      copied.add(text);
      return true;
    },
    grab: (insert, discard) async {
      grabs.add((enter: insert, escape: discard));
      return true;
    },
    release: () async {
      releases++;
    },
    returnFocus: (target) async {
      focusReturns.add(target);
      steps.add('focus');
      return focusReturned;
    },
  );

  @override
  Future<PasteOutcome> paste(String text, PasteOptions options) async {
    steps.add('paste');
    pasted.add(text);
    return PasteOutcome.success;
  }

  @override
  Future<void> prime() async {
    target = front!.id;
  }

  @override
  Future<String?> getTargetBundleId() async => target;
  @override
  Future<PasteOutcome> typeText(String text, PasteOptions options) async =>
      PasteOutcome.success;
  @override
  Future<PasteCapability> checkCapability({
    bool promptIfMissing = false,
  }) async => const PasteCapability(status: PasteCapabilityStatus.ready);
}

class _Settings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;
}

void main() {
  final l10n = lookupL10n(const Locale('de'));

  group('SmartWritePreviewNotifier editing', () {
    late _EditPaster paster;
    late ProviderContainer container;
    late SmartWritePreviewNotifier preview;

    void setup({bool wayland = false}) {
      paster = _EditPaster();
      container = ProviderContainer(
        overrides: [
          pasterProvider.overrideWithValue(paster),
          settingsProvider.overrideWith(_Settings.new),
          smartWriteEnvironmentProvider.overrideWithValue(
            paster.environment(wayland: wayland),
          ),
        ],
      );
      preview = container.read(smartWritePreviewProvider.notifier);
      addTearDown(container.dispose);
    }

    SmartWriteDraft? draft() => container.read(smartWritePreviewProvider);

    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await Future<void>.value();
      }
    }

    test('focus in the field drops the grabs; leaving sets new ones and an '
        'old callback does nothing (epoch)', () async {
      setup();
      await preview.offer('draft');
      expect(paster.grabs, hasLength(1));
      final first = paster.grabs.single;

      preview.setEditingFocus(true);
      await settle();
      expect(paster.releases, greaterThan(0));
      first.enter();
      first.escape();
      await settle();
      expect(paster.pasted, isEmpty, reason: 'Enter belongs to the field');
      expect(draft(), isNotNull, reason: 'Esc belongs to the field');

      preview.setEditingFocus(false);
      await settle();
      expect(paster.grabs, hasLength(2), reason: 'grabs set again');
      first.enter();
      first.escape();
      await settle();
      expect(paster.pasted, isEmpty);
      expect(draft(), isNotNull, reason: 'the old grab is dead');

      paster.grabs.last.enter();
      await settle();
      expect(paster.pasted, ['draft']);
    });

    test('a quick focus back into the field leaves no live grab', () async {
      setup();
      await preview.offer('draft');
      preview
        ..setEditingFocus(true)
        ..setEditingFocus(false)
        ..setEditingFocus(true);
      await settle();
      for (final grab in paster.grabs) {
        grab.enter();
        grab.escape();
      }
      await settle();
      expect(paster.pasted, isEmpty);
      expect(draft(), isNotNull);
    });

    test('Enter in the field inserts the edited text once the focus is '
        'back', () async {
      setup();
      await preview.offer('draft');
      preview
        ..openEditor()
        ..setEditingFocus(true)
        ..updateText('draft, edited');
      expect(draft()!.text, 'draft, edited');
      expect(draft()!.edited, isTrue);
      final outcome = await preview.submitEdited('draft, edited\nby hand');
      expect(outcome, PasteOutcome.success);
      expect(paster.focusReturns, ['editor']);
      expect(paster.steps, ['focus', 'paste'], reason: 'focus first');
      expect(paster.pasted, ['draft, edited\nby hand']);
      expect(draft(), isNull);
    });

    test('an unconfirmed focus return inserts nothing, copies nothing and '
        'keeps the draft with a hint', () async {
      setup();
      paster.focusReturned = false;
      await preview.offer('draft');
      preview
        ..openEditor()
        ..setEditingFocus(true);
      final serial = draft()!.serial;
      final outcome = await preview.submitEdited('edited');
      expect(outcome, isNull);
      expect(paster.pasted, isEmpty);
      expect(paster.copied, isEmpty);
      final kept = draft()!;
      expect(kept.text, 'edited');
      expect(kept.focusNotReturned, isTrue);
      expect(kept.serial, greaterThan(serial), reason: 'the card is redrawn');
      final notice = smartWriteDraftNotice(
        l10n,
        kept,
        onInsert: () {},
        onDiscard: () {},
        editor: preview,
      );
      expect(notice.nextStep, startsWith(l10n.smartWriteFocusNotReturned));
      expect(notice.edit?.text, 'edited');

      // The next Enter tries again.
      paster.focusReturned = true;
      await preview.submitEdited('edited');
      expect(paster.pasted, ['edited']);
    });

    test('Wayland pastes with its hint although the return is unconfirmed '
        '(D18)', () async {
      setup(wayland: true);
      paster.focusReturned = false;
      await preview.offer('draft');
      preview.setEditingFocus(true);
      await preview.submitEdited('edited');
      expect(paster.pasted, ['edited']);
      expect(paster.copied, isEmpty);
    });

    test('without focus in the field Enter and Esc work as before', () async {
      setup();
      await preview.offer('draft');
      paster.grabs.single.enter();
      await settle();
      expect(paster.pasted, ['draft']);
      expect(paster.focusReturns, isEmpty, reason: 'nothing to hand back');

      await preview.offer('second');
      paster.grabs.last.escape();
      expect(draft(), isNull);
      expect(paster.pasted, ['draft']);
    });

    test('a refinement replaces the edited text and editing goes on', () async {
      setup();
      await preview.offer('draft');
      preview
        ..openEditor()
        ..updateText('edited by hand');
      final previous = draft()!;
      expect(previous.text, 'edited by hand', reason: 'the <draft> input');
      await preview.offer('refined', previous: previous, rounds: 1);
      final refined = draft()!;
      expect(refined.text, 'refined');
      expect(refined.edited, isFalse);
      expect(refined.editorOpen, isTrue);
      preview.updateText('refined, edited');
      expect(draft()!.text, 'refined, edited');
      final notice = smartWriteDraftNotice(
        l10n,
        draft()!,
        onInsert: () {},
        onDiscard: () {},
        editor: preview,
      );
      expect(notice.edit!.key, refined.serial, reason: 'new text, new key');
    });

    test('typing keeps the serial, so the card is not drawn anew', () async {
      setup();
      await preview.offer('draft');
      final serial = draft()!.serial;
      preview.updateText('a');
      preview.updateText('ab');
      expect(draft()!.serial, serial);
    });
  });

  group('flag off', () {
    test('the card carries no field and its wire form is unchanged', () {
      const draft = SmartWriteDraft(text: 'Hello', serial: 3);
      final before = smartWriteDraftNotice(
        l10n,
        draft,
        onInsert: () {},
        onDiscard: () {},
      );
      expect(before.edit, isNull);
      final wire = overlayNoticeFor(before, l10n, actionKey: 'Enter');
      expect(wire.edit, isNull);
      expect(wire.toMap().containsKey('edit'), isFalse);
      expect(wire.body, contains('Hello'));
    });

    test('editing is on only where the focus return landed', () {
      expect(smartWriteCanEditPreview('macos'), isTrue);
      expect(smartWriteCanEditPreview('windows'), isTrue);
      for (final os in ['linux', 'fuchsia']) {
        expect(smartWriteCanEditPreview(os), isFalse, reason: os);
      }
    });

    test('Linux edits only where the overlay host confirmed the focus', () {
      // X11 with a managing WM answers true; Wayland and tiling WMs false.
      expect(
        smartWriteCanEditPreview('linux', linuxOverlayFocus: true),
        isTrue,
      );
      expect(smartWriteCanEditPreview('linux'), isFalse);
      // The Linux answer never switches another platform on.
      expect(
        smartWriteCanEditPreview('fuchsia', linuxOverlayFocus: true),
        isFalse,
      );
    });
  });

  group('macOS focus return', () {
    test('confirms only when the target itself is in front again', () async {
      final sender = _FocusSender();
      expect(await returnFocusThrough(sender, 'editor'), isTrue);
      expect(sender.activated, ['editor']);
    });

    test('an activation the host declined is unconfirmed', () async {
      final sender = _FocusSender()..activates = false;
      expect(await returnFocusThrough(sender, 'editor'), isFalse);
    });

    test('WhisPaste or another app in front is unconfirmed', () async {
      final own = _FocusSender()
        ..front = const ForegroundWindow(id: 'editor', isOwn: true);
      expect(await returnFocusThrough(own, 'editor'), isFalse);
      final other = _FocusSender()
        ..front = const ForegroundWindow(id: 'browser');
      expect(await returnFocusThrough(other, 'editor'), isFalse);
      final unknown = _FocusSender()..front = null;
      expect(await returnFocusThrough(unknown, 'editor'), isFalse);
    });

    test('without a target or a host nothing is activated', () async {
      final sender = _FocusSender();
      expect(await returnFocusThrough(sender, null), isFalse);
      expect(await returnFocusThrough(sender, ''), isFalse);
      expect(await returnFocusThrough(null, 'editor'), isFalse);
      expect(sender.activated, isEmpty);
    });

    test('a failing host call is unconfirmed, not thrown', () async {
      final sender = _FocusSender()..throws = true;
      expect(await returnFocusThrough(sender, 'editor'), isFalse);
    });
  });

  group('native edit keys', () {
    test('editKey on the render channel reaches the field handler', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final keys = <OverlayNoticeEditKey>[];
      const name = 'test.overlay_render_edit_keys';
      OverlayRenderChannel(
        name: name,
        onSnapshot: (_) {},
        onWaveformBars: (_) {},
        onEditKey: keys.add,
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      Future<void> send(Object? args) async {
        await messenger.handlePlatformMessage(
          name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('editKey', args),
          ),
          (_) {},
        );
      }

      await send({'key': 'enter'});
      await send({'key': 'newline'});
      await send({'key': 'escape'});
      await send({'key': 'tab'});
      await send(null);
      expect(keys, [
        OverlayNoticeEditKey.enter,
        OverlayNoticeEditKey.newline,
        OverlayNoticeEditKey.escape,
      ]);
    });
  });

  group('wire', () {
    test('the edit payload survives toMap/fromMap', () {
      const notice = OverlayNotice(
        kind: OverlayNoticeKind.message,
        tone: OverlayNoticeTone.hint,
        title: 'T',
        body: 'B',
        actions: [],
        edit: OverlayNoticeEdit(
          key: 7,
          text: 'line 1\nline 2',
          open: true,
          toggleLabel: 'Edit',
          fieldLabel: 'Edit draft',
          insertHint: 'Enter: insert',
        ),
      );
      final back = OverlayNotice.fromMap(notice.toMap())!;
      expect(back.edit, notice.edit);
    });

    test('an open field holds the draft, so the body leaves it out', () {
      final notice = smartWriteDraftNotice(
        l10n,
        const SmartWriteDraft(text: 'Hello', serial: 1, editorOpen: true),
        onInsert: () {},
        onDiscard: () {},
        editor: _NoopEditor(),
      );
      final wire = overlayNoticeFor(notice, l10n);
      expect(wire.edit!.open, isTrue);
      expect(wire.body, isNot(contains('Hello')));
      expect(wire.edit!.insertHint, 'Enter: einfügen · Shift+Enter: Zeile');
    });

    test('the field reports arrive with their arguments', () {
      final controller = MacOSFloatingOverlayController();
      final event = controller.parseNativeEvent(
        const MethodCall('onNoticeAction', {
          'id': 'edit_submit',
          'text': 'edited',
        }),
      );
      expect(event, isA<OverlayNoticeActionClicked>());
      final clicked = event! as OverlayNoticeActionClicked;
      final edit = OverlayNoticeEditEvent.fromWire(clicked.id, clicked.args)!;
      expect(edit.kind, OverlayNoticeEditKind.submit);
      expect(edit.text, 'edited');
      expect(OverlayNoticeEditEvent.fromWire('notice_1', const {}), isNull);
    });
  });

  group('overlay field', () {
    Future<List<OverlayNoticeEditEvent>> pumpCard(
      WidgetTester tester, {
      bool open = true,
    }) async {
      final events = <OverlayNoticeEditEvent>[];
      final notice = OverlayNotice(
        kind: OverlayNoticeKind.message,
        tone: OverlayNoticeTone.hint,
        title: 'Entwurf',
        body: 'Enter fügt den Text ein',
        actions: const [],
        edit: OverlayNoticeEdit(
          key: 1,
          text: 'ab',
          open: open,
          toggleLabel: l10n.smartWriteEditToggle,
          fieldLabel: l10n.smartWriteEditFieldLabel,
          insertHint: l10n.smartWriteEditInsertHint,
        ),
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(),
            child: Center(
              child: WpOverlayNoticeCard(
                notice: notice,
                colors: OverlayDesignSpec.colorsFor(),
                onEdit: events.add,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return events;
    }

    testWidgets('the hint line stands in the field; Shift+Enter breaks the '
        'line, Enter submits, Esc cancels', (tester) async {
      final events = await pumpCard(tester);
      final box = find.byKey(const ValueKey(kNoticeEditFieldId));
      final hint = find.byKey(const ValueKey(kNoticeEditInsertHintId));
      expect(
        find.descendant(of: box, matching: hint),
        findsOneWidget,
        reason: 'R25: the hint sits inside the field',
      );
      expect(tester.widget<Text>(hint).data, l10n.smartWriteEditInsertHint);
      final boxRect = tester.getRect(box);
      expect(boxRect.contains(tester.getRect(hint).center), isTrue);

      // The field takes the focus by itself.
      expect(
        events.any(
          (e) => e.kind == OverlayNoticeEditKind.focus && e.focused == true,
        ),
        isTrue,
      );
      final field = tester.widget<EditableText>(find.byType(EditableText));
      field.controller.selection = const TextSelection.collapsed(offset: 2);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(field.controller.text, 'ab\n');
      expect(events.last.kind, OverlayNoticeEditKind.text);
      expect(events.last.text, 'ab\n');
      expect(
        events.where((e) => e.kind == OverlayNoticeEditKind.submit),
        isEmpty,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(events.last.kind, OverlayNoticeEditKind.submit);
      expect(events.last.text, 'ab\n');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(events.last.kind, OverlayNoticeEditKind.cancel);
    });

    testWidgets('Return, Shift+Return and Escape from the macOS shell act '
        'like the keys in the field, with its text', (tester) async {
      final events = await pumpCard(tester);
      final field = tester.widget<EditableText>(find.byType(EditableText));
      field.controller.value = const TextEditingValue(
        text: 'abc',
        selection: TextSelection.collapsed(offset: 3),
      );
      OverlayNoticeEditKeys.dispatch(OverlayNoticeEditKey.newline);
      expect(field.controller.text, 'abc\n');
      expect(events.last.kind, OverlayNoticeEditKind.text);
      expect(
        events.where((e) => e.kind == OverlayNoticeEditKind.submit),
        isEmpty,
      );
      OverlayNoticeEditKeys.dispatch(OverlayNoticeEditKey.enter);
      expect(events.last.kind, OverlayNoticeEditKind.submit);
      expect(events.last.text, 'abc\n');
      OverlayNoticeEditKeys.dispatch(OverlayNoticeEditKey.escape);
      expect(events.last.kind, OverlayNoticeEditKind.cancel);
      // A closed card has no listener left.
      await tester.pumpWidget(const SizedBox());
      final count = events.length;
      OverlayNoticeEditKeys.dispatch(OverlayNoticeEditKey.enter);
      expect(events.length, count);
    });

    testWidgets('the toggle opens the field', (tester) async {
      final events = await pumpCard(tester, open: false);
      expect(find.byType(EditableText), findsNothing);
      await tester.tap(find.byKey(const ValueKey(kNoticeEditToggleId)));
      expect(events.single.kind, OverlayNoticeEditKind.open);
    });

    testWidgets('the main window field keeps the same keys', (tester) async {
      final submitted = <String>[];
      final changed = <String>[];
      var cancelled = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DictationNoticeEditField(
              edit: DictationNoticeEdit(
                key: 1,
                text: 'ab',
                open: true,
                toggleLabel: 'Edit',
                fieldLabel: 'Edit draft',
                insertHint: l10n.smartWriteEditInsertHint,
                onOpen: () {},
                onChanged: changed.add,
                onFocus: (_) {},
                onSubmit: submitted.add,
                onCancel: () => cancelled++,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.text(l10n.smartWriteEditInsertHint),
        findsOneWidget,
        reason: 'R25',
      );
      final field = tester.widget<EditableText>(find.byType(EditableText));
      field.controller.selection = const TextSelection.collapsed(offset: 2);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(changed.last, 'ab\n');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(submitted, ['ab\n']);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(cancelled, 1);
    });
  });
}

/// An editor for the notice builder alone; nothing is called on it.
class _NoopEditor extends SmartWritePreviewNotifier {}

/// The host side of the macOS focus return: `activateTarget` and
/// `foregroundWindow`, nothing else is used.
class _FocusSender implements UndoKeystrokeSender {
  bool activates = true;
  bool throws = false;
  ForegroundWindow? front = const ForegroundWindow(id: 'editor');
  final activated = <String>[];

  @override
  Future<bool> activateTarget(String id) async {
    if (throws) throw PlatformException(code: 'gone');
    activated.add(id);
    return activates;
  }

  @override
  Future<ForegroundWindow?> foregroundWindow() async => front;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
