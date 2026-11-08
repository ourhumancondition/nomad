import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomadic_residence/data/instance_endpoint.dart';
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

  testWidgets('a connected database shows one account action at a time', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = AppController(clock: () => LocalDate(2026, 11, 8));
    controller.pendingEndpoint = InstanceEndpoint.parse(
      'nomad.pockethost.io',
      allowLocal: false,
    );
    await tester.pumpWidget(NomadicApp(controller: controller));

    expect(find.byKey(const Key('connected-host')), findsOneWidget);
    expect(find.text('nomad.pockethost.io'), findsWidgets);
    expect(find.byKey(const Key('account-create-mode')), findsOneWidget);
    expect(find.byKey(const Key('auth-confirm')), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('Sign in'), findsNothing);
    expect(find.textContaining('administrator'), findsNothing);
    expect(find.textContaining('superuser'), findsNothing);

    await tester.tap(find.text('I have an account'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('account-signin-mode')), findsOneWidget);
    expect(find.byKey(const Key('auth-confirm')), findsNothing);
    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Create account'), findsNothing);

    await tester.tap(find.text('I am new'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('auth-email')), 'not-an-email');
    await tester.enterText(find.byKey(const Key('auth-password')), 'short');
    await tester.enterText(find.byKey(const Key('auth-confirm')), 'other');
    await tester.ensureVisible(find.byKey(const Key('auth-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('auth-submit')));
    await tester.pump();

    expect(find.byKey(const Key('auth-error')), findsOneWidget);
    expect(find.text('Those passwords do not match.'), findsOneWidget);
    expect(find.textContaining('Failed to create record'), findsNothing);
    expect(controller.isConnected, isFalse);
  });
}
