import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/snippet_picker/snippet_picker_render_channel.dart';

void main() {
  group('SnippetPickerRenderChannel — incoming native calls', () {
    /// Simulates the native shell invoking [method] on the render channel.
    Future<void> receiveNativeCall(
      String channelName,
      String method, [
      Object? arguments,
    ]) async {
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channelName,
            const StandardMethodCodec().encodeMethodCall(
              MethodCall(method, arguments),
            ),
            (_) {},
          );
    }

    test('panelHidden invokes onPanelHidden', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      var hidden = false;
      final channel = SnippetPickerRenderChannel(
        name: 'test.snippet_picker_render',
        onItems: (_) => fail('setItems must not fire'),
        onSubmit: () => fail('submitHighlighted must not fire'),
        onPanelHidden: () => hidden = true,
        onMoveHighlight: (_) => fail('moveHighlight must not fire'),
      );
      addTearDown(channel.dispose);

      await receiveNativeCall('test.snippet_picker_render', 'panelHidden');

      expect(hidden, isTrue);
    });

    test(
      'moveHighlight invokes onMoveHighlight with the given delta',
      () async {
        TestWidgetsFlutterBinding.ensureInitialized();
        final deltas = <int>[];
        final channel = SnippetPickerRenderChannel(
          name: 'test.snippet_picker_render_move',
          onItems: (_) => fail('setItems must not fire'),
          onSubmit: () => fail('submitHighlighted must not fire'),
          onPanelHidden: () => fail('panelHidden must not fire'),
          onMoveHighlight: deltas.add,
        );
        addTearDown(channel.dispose);

        await receiveNativeCall(
          'test.snippet_picker_render_move',
          'moveHighlight',
          {'delta': 1},
        );
        await receiveNativeCall(
          'test.snippet_picker_render_move',
          'moveHighlight',
          {'delta': -1},
        );

        expect(deltas, [1, -1]);
      },
    );
  });

  group('SnippetPickerRenderItem.tryParse', () {
    test('parses a well-formed map', () {
      final item = SnippetPickerRenderItem.tryParse({
        'id': 's1',
        'title': 'Greeting',
        'body': 'Hello there!',
      });
      expect(item?.id, 's1');
      expect(item?.title, 'Greeting');
      expect(item?.body, 'Hello there!');
    });

    test('returns null for a non-Map value', () {
      expect(SnippetPickerRenderItem.tryParse('not a map'), isNull);
      expect(SnippetPickerRenderItem.tryParse(null), isNull);
      expect(SnippetPickerRenderItem.tryParse(42), isNull);
    });

    test('returns null when a required field is missing', () {
      expect(
        SnippetPickerRenderItem.tryParse({'title': 'x', 'body': 'y'}),
        isNull,
      );
      expect(
        SnippetPickerRenderItem.tryParse({'id': 'x', 'body': 'y'}),
        isNull,
      );
      expect(
        SnippetPickerRenderItem.tryParse({'id': 'x', 'title': 'y'}),
        isNull,
      );
    });

    test('returns null when a field has the wrong type', () {
      expect(
        SnippetPickerRenderItem.tryParse({'id': 1, 'title': 'x', 'body': 'y'}),
        isNull,
      );
    });
  });
}
