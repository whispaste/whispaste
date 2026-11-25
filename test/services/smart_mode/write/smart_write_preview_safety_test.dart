import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/smart_mode/write/smart_write_notice.dart';
import 'package:whispaste/services/floating_overlay/dictation_notice.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/services/paste/paster.dart';
import 'package:whispaste/services/smart_mode/write/smart_write_environment.dart';
import 'package:whispaste/services/smart_mode/write/smart_write_preview.dart';

class FakeWritePaster implements Paster {
  String target = 'editor';
  ForegroundWindow? front = const ForegroundWindow(id: 'editor');
  final pasted = <String>[];
  final copied = <String>[];
  PasteOutcome outcome = PasteOutcome.success;
  bool grabs = true;
  bool copyFails = false;
  Completer<bool>? pendingGrab;
  final grabStarted = Completer<void>();
  int releases = 0;
  bool throws = false;
  Completer<ForegroundWindow?>? pendingFront;
  void Function()? enter;

  SmartWriteEnvironment environment({bool wayland = false}) =>
      SmartWriteEnvironment(
        wayland: wayland,
        target: getTargetBundleId,
        foreground: () async => pendingFront?.future ?? front,
        copy: (text) async {
          if (copyFails) return false;
          copied.add(text);
          return true;
        },
        grab: (insert, discard) async {
          enter = insert;
          if (!grabStarted.isCompleted) grabStarted.complete();
          return pendingGrab?.future ?? grabs;
        },
        release: () async {
          releases++;
        },
      );

  @override
  Future<PasteOutcome> paste(String text, PasteOptions options) async {
    if (throws) throw StateError('native failed');
    pasted.add(text);
    return outcome;
  }

  @override
  Future<void> prime() async {
    target = front!.id;
  }

  @override
  Future<String?> getTargetBundleId() async => target;
  @override
  Future<PasteOutcome> typeText(String text, PasteOptions options) async =>
      outcome;
  @override
  Future<PasteCapability> checkCapability({
    bool promptIfMissing = false,
  }) async => const PasteCapability(status: PasteCapabilityStatus.ready);
}

class FakeWriteSettings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;
}

void main() {
  late FakeWritePaster paster;
  late ProviderContainer container;
  late SmartWritePreviewNotifier preview;
  void setup({bool wayland = false}) {
    paster = FakeWritePaster();
    container = ProviderContainer(
      overrides: [
        pasterProvider.overrideWithValue(paster),
        settingsProvider.overrideWith(FakeWriteSettings.new),
        smartWriteEnvironmentProvider.overrideWithValue(
          paster.environment(wayland: wayland),
        ),
      ],
    );
    preview = container.read(smartWritePreviewProvider.notifier);
    addTearDown(container.dispose);
  }

  SmartWriteHint? hint() => container.read(smartWriteNoticeProvider)?.hint;

  test(
    'target switch needs a second Enter and captures the new target',
    () async {
      setup();
      await preview.offer('draft');
      paster.front = const ForegroundWindow(id: 'chat');
      await preview.insert();
      expect(paster.pasted, isEmpty);
      expect(container.read(smartWritePreviewProvider)?.targetChanged, isTrue);
      await preview.insert();
      expect(paster.target, 'chat');
      expect(paster.pasted, ['draft']);
      await preview.insert();
      expect(paster.pasted, hasLength(1));
    },
  );

  test('another switch asks again; Esc never inserts', () async {
    setup();
    await preview.offer('draft');
    paster.front = const ForegroundWindow(id: 'chat');
    await preview.insert();
    paster.front = const ForegroundWindow(id: 'mail');
    await preview.insert();
    expect(paster.pasted, isEmpty);
    preview.discard();
    await preview.insert();
    expect(paster.pasted, isEmpty);
  });

  test(
    'Wayland warns in the draft before permitting insertion (D18)',
    () async {
      setup(wayland: true);
      paster.front = null;
      await preview.offer('draft');
      final draft = container.read(smartWritePreviewProvider)!;
      final notice = smartWriteDraftNotice(
        lookupL10n(const Locale('de')),
        draft,
        onInsert: () {},
        onDiscard: () {},
      );
      expect(notice.id, 'smart-write-target-unverifiable-hint');
      expect(
        notice.nextStep,
        startsWith('Auf Wayland kann die Ziel-App nicht geprüft werden'),
      );
      expect(notice.nextStep, contains('Enter'));
      expect(notice.managesOwnKeys, isTrue);
      final overlay = overlayNoticeFor(
        notice,
        lookupL10n(const Locale('de')),
        actionKey: 'Enter',
      );
      expect(overlay.actions[1].keyHint, 'Esc');
      expect(paster.pasted, isEmpty);
      await preview.insert();
      expect(paster.pasted, ['draft']);
    },
  );

  test('unknown foreground outside Wayland copies without pasting', () async {
    setup();
    paster.front = null;
    await preview.offer('draft');
    await preview.insert();
    expect(paster.pasted, isEmpty);
    expect(paster.copied, ['draft']);
    expect(hint(), SmartWriteHint.targetUnknown);
  });

  for (final outcome in PasteOutcome.values.where(
    (o) => o != PasteOutcome.success,
  )) {
    test('paste $outcome retains draft on clipboard', () async {
      setup();
      paster.outcome = outcome;
      await preview.offer('draft');
      await preview.insert();
      expect(paster.copied, ['draft']);
      expect(hint(), SmartWriteHint.pasteFailed);
    });
  }

  test('native exception retains draft on clipboard', () async {
    setup();
    paster.throws = true;
    await preview.offer('draft');
    await preview.insert();
    expect(paster.copied, ['draft']);
    expect(hint(), SmartWriteHint.pasteFailed);
  });

  test('failed grab never opens a preview', () async {
    setup();
    paster.grabs = false;
    final drafts = <SmartWriteDraft?>[];
    container.listen(smartWritePreviewProvider, (_, next) => drafts.add(next));
    await preview.offer('draft');
    expect(drafts.whereType<SmartWriteDraft>(), isEmpty);
    expect(paster.copied, ['draft']);
    expect(hint(), SmartWriteHint.keysFailed);
    expect(paster.releases, greaterThan(0));
  });

  test(
    'clipboard failure keeps the draft in the visible recovery notice',
    () async {
      setup();
      paster.copyFails = true;
      paster.outcome = PasteOutcome.failed;
      await preview.offer('recover me');
      await preview.insert();
      expect(hint(), SmartWriteHint.clipboardFailed);
      expect(
        container.read(smartWriteNoticeProvider)?.retainedText,
        'recover me',
      );
    },
  );

  test('cancel during key registration never opens a late preview', () async {
    setup();
    paster.pendingGrab = Completer<bool>();
    final offering = preview.offer('draft');
    // Wait for the registration boundary, without a real-time delay.
    await paster.grabStarted.future;
    preview.discard();
    paster.pendingGrab!.complete(true);
    await offering;
    expect(container.read(smartWritePreviewProvider), isNull);
    expect(paster.copied, isEmpty);
    expect(paster.releases, greaterThan(0));
  });

  test('timeout releases keys and late Enter does nothing', () {
    fakeAsync((time) {
      setup();
      unawaited(preview.offer('draft'));
      time.flushMicrotasks();
      final lateEnter = paster.enter!;
      time.elapse(const Duration(seconds: 90));
      expect(container.read(smartWritePreviewProvider), isNull);
      expect(hint(), SmartWriteHint.expired);
      lateEnter();
      time.flushMicrotasks();
      expect(paster.pasted, isEmpty);
      expect(paster.releases, greaterThan(0));
    });
  });

  test('unconfirmed target change expires to clipboard', () {
    fakeAsync((time) {
      setup();
      unawaited(preview.offer('draft'));
      time.flushMicrotasks();
      paster.front = const ForegroundWindow(id: 'chat');
      unawaited(preview.insert());
      time.flushMicrotasks();
      time.elapse(const Duration(seconds: 90));
      time.flushMicrotasks();
      expect(paster.copied, ['draft']);
      expect(paster.pasted, isEmpty);
      expect(hint(), SmartWriteHint.targetChanged);
    });
  });

  test('editing suspends timeout; blur restarts inactivity budget', () {
    fakeAsync((time) {
      setup();
      unawaited(preview.offer('draft'));
      time.flushMicrotasks();
      preview.setEditingFocus(true);
      time.elapse(const Duration(minutes: 10));
      expect(container.read(smartWritePreviewProvider), isNotNull);
      preview.setEditingFocus(false);
      time.elapse(const Duration(seconds: 89));
      preview.noteActivity();
      time.elapse(const Duration(seconds: 89));
      expect(container.read(smartWritePreviewProvider), isNotNull);
      time.elapse(const Duration(seconds: 1));
      expect(container.read(smartWritePreviewProvider), isNull);
    });
  });

  test(
    'refinement cannot redirect a checked draft to another native target',
    () async {
      setup();
      await preview.offer('draft');
      paster.target = 'other-app';
      await preview.insert();
      expect(paster.target, 'editor');
      expect(paster.pasted, ['draft']);
    },
  );

  test('old key callback cannot confirm a newer draft', () async {
    setup();
    await preview.offer('old');
    final stale = paster.enter!;
    await preview.offer('new');
    stale();
    await Future<void>.value();
    expect(paster.pasted, isEmpty);
    expect(container.read(smartWritePreviewProvider)?.text, 'new');
  });

  test('refinement preserves an unknown original target', () async {
    setup();
    await preview.offer(
      'refined draft',
      previous: const SmartWriteDraft(text: 'original', serial: 1),
    );
    await preview.insert();
    expect(paster.pasted, isEmpty);
    expect(paster.copied, ['refined draft']);
    expect(hint(), SmartWriteHint.targetUnknown);
  });

  test(
    'discard during a failed foreground read does not revive the draft',
    () async {
      setup();
      await preview.offer('draft');
      paster.pendingFront = Completer<ForegroundWindow?>();
      final inserting = preview.insert();
      preview.discard();
      paster.pendingFront!.completeError(StateError('native stopped'));
      await inserting;
      expect(paster.copied, isEmpty);
      expect(hint(), isNull);
    },
  );

  test('Esc invalidates an outstanding foreground read', () async {
    setup();
    await preview.offer('draft');
    paster.pendingFront = Completer<ForegroundWindow?>();
    final inserting = preview.insert();
    preview.discard();
    paster.pendingFront!.complete(const ForegroundWindow(id: 'editor'));
    await inserting;
    expect(paster.pasted, isEmpty);
  });
}
