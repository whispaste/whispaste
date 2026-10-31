import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/wp_error_notice.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );

  testWidgets('shows cause and next step', (tester) async {
    await tester.pumpWidget(
      host(
        const WpErrorNotice(
          cause: 'Microphone not found.',
          nextStep: 'Connect a microphone and try again.',
        ),
      ),
    );
    expect(find.byKey(const Key('error-notice-cause')), findsOneWidget);
    expect(find.text('Microphone not found.'), findsOneWidget);
    expect(find.byKey(const Key('error-notice-next-step')), findsOneWidget);
  });

  testWidgets('omits next step line when none is given', (tester) async {
    await tester.pumpWidget(
      host(const WpErrorNotice(cause: 'Recording failed.')),
    );
    expect(find.byKey(const Key('error-notice-cause')), findsOneWidget);
    expect(find.byKey(const Key('error-notice-next-step')), findsNothing);
  });

  testWidgets('renders the optional action', (tester) async {
    await tester.pumpWidget(
      host(
        WpErrorNotice(
          cause: 'Permission denied.',
          action: TextButton(
            key: const Key('error-notice-action'),
            onPressed: () {},
            child: const Text('Open'),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('error-notice-action')), findsOneWidget);
  });
}
