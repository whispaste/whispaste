import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/shared_render_engine_helpers.dart';

class _FakeRenderChannel implements RenderChannel {
  bool readyCalled = false;
  bool disposeCalled = false;
  final List<String> reportedErrors = [];

  @override
  void notifyReady() => readyCalled = true;

  @override
  void reportError(String message) => reportedErrors.add(message);

  @override
  void dispose() => disposeCalled = true;
}

class _TestRenderWidget extends StatefulWidget {
  const _TestRenderWidget({required this.channel});
  final _FakeRenderChannel channel;

  @override
  State<_TestRenderWidget> createState() => _TestRenderWidgetState();
}

class _TestRenderWidgetState
    extends RenderEngineState<_TestRenderWidget, _FakeRenderChannel> {
  _TestRenderWidgetState() : super('default label');

  @override
  _FakeRenderChannel createChannel() => widget.channel;

  @override
  String labelOf(L10n l10n) => 'resolved label';

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  // `RenderEngineState.initState` installs `FlutterError.onError` — save and
  // restore it around every test so a leaked handler never affects other
  // tests (including the framework's own error-catching for this test file).
  late FlutterExceptionHandler? savedOnError;

  setUp(() {
    savedOnError = FlutterError.onError;
  });

  tearDown(() {
    FlutterError.onError = savedOnError;
  });

  testWidgets('initState notifies ready and installs error reporting', (
    tester,
  ) async {
    final channel = _FakeRenderChannel();
    await tester.pumpWidget(_TestRenderWidget(channel: channel));

    expect(channel.readyCalled, isTrue);
    expect(FlutterError.onError, isNotNull);
  });

  testWidgets('an uncaught FlutterError is reported through the channel — '
      'this is the diagnostic gap fix for the floating-overlay-render-gap '
      'investigation (a render-engine-side exception was previously invisible '
      'anywhere but raw stdout)', (tester) async {
    final channel = _FakeRenderChannel();
    await tester.pumpWidget(_TestRenderWidget(channel: channel));

    final handler = FlutterError.onError;
    expect(handler, isNotNull);
    handler!(FlutterErrorDetails(exception: StateError('render engine boom')));

    expect(channel.reportedErrors, hasLength(1));
    expect(channel.reportedErrors.single, contains('render engine boom'));
  });

  testWidgets('dispose tears down the channel', (tester) async {
    final channel = _FakeRenderChannel();
    await tester.pumpWidget(_TestRenderWidget(channel: channel));
    await tester.pumpWidget(const SizedBox.shrink());

    expect(channel.disposeCalled, isTrue);
  });
}
