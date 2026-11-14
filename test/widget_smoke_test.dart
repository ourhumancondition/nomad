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
    expect(find.byKey(const Key('days-title')), findsOneWidget);
    expect(find.textContaining('Practice data'), findsOneWidget);
    expect(find.textContaining('PocketBase'), findsNothing);
    expect(find.textContaining('Portugal'), findsWidgets);
    expect(controller.isExample, isTrue);
    expect(controller.isConnected, isFalse);
    expect(controller.tally.identityHolds, isTrue);
    expect(controller.tally.primaryDays['PT'], 90);
    expect(find.textContaining('183'), findsNothing);
    expect(find.textContaining('not a tax'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.folder_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-review')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Unknown'), findsWidgets);
    expect(find.textContaining('1 Apr 2026'), findsWidgets);

    await tester.tap(find.byKey(const Key('back-to-list')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-rules')));
    await tester.pumpAndSettle();
    expect(find.textContaining('not a legal test'), findsOneWidget);
    expect(find.textContaining('183'), findsNothing);

    await tester.tap(find.text('Leave practice data'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gate-title')), findsOneWidget);
    expect(find.textContaining('Portugal'), findsNothing);
  });

  testWidgets('sign-up is a separate page and the server stays hidden', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = AppController(clock: () => LocalDate(2026, 11, 8));
    await tester.pumpWidget(NomadicApp(controller: controller));

    expect(find.byKey(const Key('gate-title')), findsOneWidget);
    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('I am new'), findsNothing);
    expect(find.text('I have an account'), findsNothing);
    expect(find.byKey(const Key('instance-url')), findsNothing);
    expect(find.textContaining('administrator'), findsNothing);
    expect(find.textContaining('superuser'), findsNothing);

    await tester.tap(find.byKey(const Key('change-server')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('instance-url')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('instance-url')))
          .controller
          ?.text,
      defaultInstanceUrl,
    );

    await tester.tap(find.byKey(const Key('go-to-signup')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('signup-title')), findsOneWidget);
    expect(find.byKey(const Key('auth-confirm')), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('I am new'), findsNothing);

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

    await tester.tap(find.byKey(const Key('go-to-login')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gate-title')), findsOneWidget);
    expect(find.byKey(const Key('auth-confirm')), findsNothing);
  });
}
