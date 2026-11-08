import 'package:flutter_test/flutter_test.dart';

import 'package:shot_keeper/main.dart';

void main() {
  testWidgets('Home screen smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ShotKeeperApp());
    await tester.pump();

    expect(find.text('ShotKeeper'), findsOneWidget);
    expect(find.text('Auto-detect screenshots'), findsOneWidget);
    expect(find.text('Search screenshots by name...'), findsOneWidget);
  });
}
