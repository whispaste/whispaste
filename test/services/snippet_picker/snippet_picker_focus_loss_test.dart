/// The picker stays open while the user is still choosing (#1680): a focus
/// change the user did not cause keeps it on screen, a click outside closes
/// it. The native shells only report why focus went; this checks the one
/// decision all three platforms share, at the hand-off from the shell's
/// event to closing the panel.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/snippets/snippets_page.dart'
    show SnippetItem;
import 'package:whispaste/services/method_channel_platform_host.dart';
import 'package:whispaste/services/snippet_picker/snippet_picker_controller.dart';
import 'package:whispaste/services/snippet_picker/snippet_picker_controller_mixin.dart';
import 'package:whispaste/services/snippet_picker/snippet_picker_events.dart';
import 'package:whispaste/services/snippet_picker/snippet_picker_service.dart';

class _FakeController implements SnippetPickerController {
  final _events = StreamController<SnippetPickerEvent>.broadcast();
  final hides = <bool>[];
  int focusCalls = 0;

  @override
  Future<void> show({
    required List<Map<String, String>> items,
    String query = '',
  }) async {}

  @override
  Future<void> hide({bool outsideClick = false}) async =>
      hides.add(outsideClick);

  @override
  Future<void> focus() async => focusCalls++;

  @override
  Stream<SnippetPickerEvent> get events => _events.stream;

  Future<void> lose(SnippetPickerFocusLossCause cause) async {
    _events.add(SnippetPickerFocusLost(cause));
    await Future<void>.delayed(Duration.zero);
  }

  @override
  Future<void> dispose() async => _events.close();
}

/// Only the shared native-event parser, no channel traffic.
class _Parser extends MethodChannelPlatformHost<SnippetPickerEvent>
    with SnippetPickerControllerMixin {
  _Parser() : super('test.snippet_picker_focus_loss');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeController controller;
  late ProviderContainer container;
  late SnippetPickerService service;

  setUp(() async {
    controller = _FakeController();
    container = ProviderContainer(
      overrides: [
        snippetPickerControllerProvider.overrideWith((ref) => controller),
      ],
    );
    service = container.read(snippetPickerServiceProvider.notifier);
    await service.show(
      items: [
        SnippetItem(
          createdAt: DateTime(2026),
          id: 's1',
          title: 'Sig',
          body: 'Best',
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await controller.dispose();
  });

  test('the native cause strings parse, unknown ones close', () {
    SnippetPickerFocusLossCause parse(Object? cause) {
      final event = _Parser().parseNativeEvent(
        MethodCall('onFocusLost', {'cause': cause}),
      );
      return (event! as SnippetPickerFocusLost).cause;
    }

    expect(parse('click'), SnippetPickerFocusLossCause.outsideClick);
    expect(parse('other'), SnippetPickerFocusLossCause.other);
    expect(parse('unknown'), SnippetPickerFocusLossCause.unknown);
    expect(parse(null), SnippetPickerFocusLossCause.unknown);
    expect(
      snippetPickerClosesOnFocusLoss(SnippetPickerFocusLossCause.unknown),
      isTrue,
    );
  });

  test('a focus loss without a click keeps the picker open', () async {
    await controller.lose(SnippetPickerFocusLossCause.other);

    expect(service.isOpen, isTrue);
    expect(controller.hides, isEmpty);

    // The hotkey brings the keyboard back to the open panel.
    await service.focus();
    expect(controller.focusCalls, 1);
  });

  test('a click outside closes it once, without handing focus back', () async {
    await controller.lose(SnippetPickerFocusLossCause.other);
    await controller.lose(SnippetPickerFocusLossCause.outsideClick);
    // The focus loss the click causes arrives after it; nothing more to do.
    await controller.lose(SnippetPickerFocusLossCause.outsideClick);

    expect(service.isOpen, isFalse);
    expect(controller.hides, [true]);
    await service.focus();
    expect(controller.focusCalls, 0);
  });

  test('where clicks cannot be seen, a focus loss closes it', () async {
    await controller.lose(SnippetPickerFocusLossCause.unknown);

    expect(service.isOpen, isFalse);
    expect(controller.hides, [false]);
  });

  test('closing on a click outside ends an open field preview', () async {
    final preview = service.showFieldPreview(
      title: 'Bug',
      template: '{{a}}',
      fieldNames: const ['a'],
      values: const ['x'],
      modelReady: false,
    );
    await Future<void>.delayed(Duration.zero);
    await controller.lose(SnippetPickerFocusLossCause.outsideClick);

    expect(await preview, isNull);
  });
}
