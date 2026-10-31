import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/wp_keycap.dart';

import '../fixtures/test_helpers.dart';

void main() {
  testWidgets('renders the key label', (tester) async {
    await tester.pumpWidget(makeTestable(const WpKeycap(label: 'Ctrl')));

    expect(find.text('Ctrl'), findsOneWidget);
  });
}
