import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomadic_residence/engine/local_date.dart';
import 'package:nomadic_residence/state/app_controller.dart';
import 'package:nomadic_residence/ui/nomadic_app.dart';

void main() {
  testWidgets('the gate shows no travel rows until the example is chosen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = AppController(clock: () => LocalDate(2026, 11, 8));
    await tester.pumpWidget(NomadicApp(controller: controller));
    expect(find.byKey(const Key('gate-title')), findsOneWidget);
    expect(find.textContaining('Portugal'), findsNothing);
    expect(controller.isConnected, isFalse);

    await tester.tap(find.byKey(const Key('open-example')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('example-banner')), findsOneWidget);
    expect(find.textContaining('Not connected to PocketBase'), findsOneWidget);
    expect(find.textContaining('Portugal'), findsWidgets);
    expect(controller.isExample, isTrue);
    expect(controller.isConnected, isFalse);
    expect(controller.tally.identityHolds, isTrue);
    expect(controller.tally.primaryDays['PT'], 90);
    expect(find.textContaining('183'), findsNothing);
    expect(find.textContaining('not a tax'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.rule));
    await tester.pumpAndSettle();
    expect(find.textContaining('Unknown'), findsWidgets);
    expect(find.textContaining('1 Apr 2026'), findsWidgets);

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    expect(find.textContaining('not a legal test'), findsOneWidget);
    expect(find.textContaining('183'), findsNothing);

    await tester.tap(find.text('Leave example'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gate-title')), findsOneWidget);
    expect(find.textContaining('Portugal'), findsNothing);
  });
}
