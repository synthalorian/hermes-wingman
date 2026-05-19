import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_wingman/main.dart';

void main() {
  testWidgets('Hermes Wingman app loads', (WidgetTester tester) async {
    // Basic smoke test — just verify the app tree builds
    // Note: full rendering requires backend + services
    await tester.pumpWidget(const HermesWingmanApp());
    await tester.pump();

    // App shell exists with sidebar
    expect(find.byType(HermesWingmanApp), findsOneWidget);
  });
}
