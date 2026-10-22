import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/snippets/snippets_page.dart'
    show SnippetItem;
import 'package:whispaste/services/paste/paste_failure_notifier.dart';
import 'package:whispaste/services/paste/paste_result_notice.dart';
import 'package:whispaste/services/paste/paster.dart';
import 'package:whispaste/services/snippet_picker/snippet_picker_controller.dart';
import 'package:whispaste/services/snippet_picker/snippet_picker_events.dart';
import 'package:whispaste/services/snippet_picker/snippet_picker_service.dart';
import 'package:whispaste/services/system_attention_service.dart';
import 'package:whispaste/services/sound_feedback_service.dart';
import 'package:whispaste/services/tray_service.dart';

import '../../test_helpers/paste_notice_fakes.dart';

class _FakeSnippetPickerController implements SnippetPickerController {
  final _events = StreamController<SnippetPickerEvent>.broadcast();

  @override
  Future<void> show({required List<Map<String, String>> items}) async {}

  @override
  Future<void> hide() async {}

  @override
  Stream<SnippetPickerEvent> get events => _events.stream;

  void select(String id) => _events.add(SnippetPickerItemSelected(id));

  @override
  Future<void> dispose() async {
    await _events.close();
  }
}

class _FakePaster implements Paster {
  _FakePaster(this.outcome);

  final PasteOutcome outcome;

  @override
  Future<void> prime() async {}

  @override
  Future<PasteOutcome> paste(String text, PasteOptions options) async =>
      outcome;

  @override
  Future<PasteOutcome> typeText(String text, PasteOptions options) async =>
      outcome;

  @override
  Future<PasteCapability> checkCapability({
    bool promptIfMissing = false,
  }) async => const PasteCapability(status: PasteCapabilityStatus.ready);

  @override
  Future<String?> getTargetBundleId() async => null;
}

void main() {
  late _FakeSnippetPickerController controller;
  late RecordingSystemAttention attention;

  setUp(() {
    controller = _FakeSnippetPickerController();
  });

  tearDown(() async {
    await controller.dispose();
  });

  /// Shows one snippet, selects it and lets the paste finish.
  Future<void> pickSnippet(ProviderContainer container) async {
    final service = container.read(snippetPickerServiceProvider.notifier);
    await service.show(
      items: const [SnippetItem(id: 's1', title: 'Sig', body: 'Best, Me')],
    );
    controller.select('s1');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  ProviderContainer containerWith({
    required PasteOutcome? outcome,
    bool hasPaster = true,
  }) {
    final container = ProviderContainer(
      overrides: [
        snippetPickerControllerProvider.overrideWith((ref) => controller),
        pasterProvider.overrideWith(
          (ref) => hasPaster ? _FakePaster(outcome!) : null,
        ),
        systemAttentionServiceProvider.overrideWith(
          (ref) => attention = RecordingSystemAttention(ref),
        ),
        trayServiceProvider.overrideWith(() => FakeNoticeTray()),
        soundFeedbackProvider.overrideWith(() => FakeNoticeSound()),
      ],
    );
    // Production wires this in the composition root (service_bootstrap.dart).
    container
        .read(snippetPickerServiceProvider.notifier)
        .onPasteResult = (outcome) async {
      await container.read(pasteResultReporterProvider).report(outcome);
    };
    return container;
  }

  group('SnippetPickerService paste feedback', () {
    test('a snippet that fails to paste sends one failure notice', () async {
      final container = containerWith(outcome: PasteOutcome.failed);
      addTearDown(container.dispose);
      container.read(systemAttentionServiceProvider);

      await pickSnippet(container);

      expect(attention.requests, hasLength(1));
      expect(attention.requests.single.kind, AttentionKind.pasteFailedUnknown);
      expect(attention.requests.single.body, isNotEmpty);
      expect(
        container.read(pasteFailureNotifierProvider)?.outcome,
        PasteOutcome.failed,
      );
    });

    test('a snippet pasted into a blocked app stays silent, like the '
        'dictation pipeline', () async {
      final container = containerWith(outcome: PasteOutcome.blocked);
      addTearDown(container.dispose);
      container.read(systemAttentionServiceProvider);

      await pickSnippet(container);

      expect(attention.requests, isEmpty);
    });

    test('a snippet that lands sends no notice', () async {
      final container = containerWith(outcome: PasteOutcome.success);
      addTearDown(container.dispose);
      container.read(systemAttentionServiceProvider);

      await pickSnippet(container);

      expect(attention.requests, isEmpty);
    });

    test('with no paster available the snippet reports the failure', () async {
      final container = containerWith(outcome: null, hasPaster: false);
      addTearDown(container.dispose);
      container.read(systemAttentionServiceProvider);

      await pickSnippet(container);

      expect(attention.requests.single.kind, AttentionKind.pasteFailedUnknown);
    });
  });
}
