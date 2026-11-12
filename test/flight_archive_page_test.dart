import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomadic_residence/demo/example_dataset.dart';
import 'package:nomadic_residence/engine/local_date.dart';
import 'package:nomadic_residence/engine/models.dart';
import 'package:nomadic_residence/state/app_controller.dart';
import 'package:nomadic_residence/ui/nomadic_app.dart';

import 'fixtures/archive_flights.dart';

void main() {
  Future<AppController> pumpFlights(
    WidgetTester tester, {
    bool fixture = true,
  }) async {
    tester.view.physicalSize = const Size(1280, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = AppController(clock: () => LocalDate(2026, 11, 8));
    controller.openExample();
    if (fixture) controller.flights = archiveFixtureFlights();
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('shot-root'),
        child: NomadicApp(
          controller: controller,
          initialSection: Section.flights,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(finder);
  }

  testWidgets('the review list hides accepted flights until un-archive', (
    tester,
  ) async {
    final controller = await pumpFlights(tester);
    final beforeCsv = controller.exportCsv();
    final beforePlan = controller
        .betweenFlightPlan()
        .rows
        .map((row) => row.summary)
        .join('\n');
    final beforeTally = Map<String, int>.of(controller.tally.primaryDays);
    final beforeStays = controller.stays.length;

    expect(find.text('Still to review (5)'), findsOneWidget);
    await reveal(tester, find.text('Archived (8)'));
    expect(find.text('Archived (8)'), findsOneWidget);
    expect(find.textContaining('NA311'), findsWidgets);
    expect(find.textContaining('NA310'), findsWidgets);
    expect(find.textContaining('NA313'), findsWidgets);
    expect(find.textContaining('NA312'), findsWidgets);
    expect(find.textContaining('NA404'), findsWidgets);
    expect(find.byKey(const Key('flight-card-fixture-na201')), findsNothing);
    expect(find.byKey(const Key('flight-card-fixture-na500')), findsNothing);

    await reveal(tester, find.byKey(const Key('archive-toggle')));
    await tester.tap(find.byKey(const Key('archive-toggle')));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const Key('flight-card-fixture-na201')));
    expect(find.byKey(const Key('flight-card-fixture-na201')), findsOneWidget);
    await reveal(tester, find.byKey(const Key('flight-card-fixture-na500')));
    expect(find.byKey(const Key('flight-card-fixture-na500')), findsOneWidget);
    expect(find.textContaining('· Accepted'), findsWidgets);

    await reveal(tester, find.byKey(const Key('unarchive-fixture-na201')));
    await tester.tap(find.byKey(const Key('unarchive-fixture-na201')));
    await tester.pumpAndSettle();

    expect(find.text('Archived (7)'), findsOneWidget);
    expect(find.text('Back on this list (1)'), findsOneWidget);
    expect(find.byKey(const Key('flight-card-fixture-na201')), findsOneWidget);
    expect(
      controller.flights
          .firstWhere((flight) => flight.id == 'fixture-na201')
          .reviewState,
      FlightReviewState.accepted,
    );
    expect(controller.exportCsv(), beforeCsv);
    expect(
      controller.betweenFlightPlan().rows.map((row) => row.summary).join('\n'),
      beforePlan,
    );
    expect(controller.tally.primaryDays, beforeTally);
    expect(controller.stays, hasLength(beforeStays));

    await reveal(tester, find.byKey(const Key('archive-toggle')));
    await tester.tap(find.byKey(const Key('archive-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('flight-card-fixture-na201')), findsOneWidget);
    expect(find.byKey(const Key('archive-fixture-na201')), findsOneWidget);

    await reveal(tester, find.byKey(const Key('archive-fixture-na201')));
    await tester.tap(find.byKey(const Key('archive-fixture-na201')));
    await tester.pumpAndSettle();
    expect(find.text('Archived (8)'), findsOneWidget);
    expect(find.text('Back on this list (1)'), findsNothing);
    expect(find.byKey(const Key('flight-card-fixture-na201')), findsNothing);
    expect(
      controller.flights
          .firstWhere((flight) => flight.id == 'fixture-na201')
          .reviewState,
      FlightReviewState.accepted,
    );
    expect(controller.exportCsv(), beforeCsv);
    expect(controller.tally.primaryDays, beforeTally);
  });

  testWidgets('archive search does not hide flights still to review', (
    tester,
  ) async {
    await pumpFlights(tester);
    await reveal(tester, find.byKey(const Key('archive-toggle')));
    await tester.tap(find.byKey(const Key('archive-toggle')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('archive-search')), 'Japan');
    await tester.pumpAndSettle();

    expect(find.text('Showing 2 of 8.'), findsOneWidget);
    await reveal(tester, find.byKey(const Key('flight-card-fixture-na201')));
    expect(find.byKey(const Key('flight-card-fixture-na201')), findsOneWidget);
    await reveal(tester, find.byKey(const Key('flight-card-fixture-na202')));
    expect(find.byKey(const Key('flight-card-fixture-na202')), findsOneWidget);
    expect(find.byKey(const Key('flight-card-fixture-na501')), findsNothing);
    expect(find.textContaining('NA311'), findsWidgets);
    expect(find.textContaining('NA310'), findsWidgets);

    await tester.enterText(
      find.byKey(const Key('archive-search')),
      'no-such-flight',
    );
    await tester.pumpAndSettle();
    expect(find.text('Showing 0 of 8.'), findsOneWidget);
    expect(find.text('No archived flights match that search.'), findsOneWidget);
    expect(find.textContaining('NA404'), findsWidgets);
  });

  testWidgets('the between-flights preview still reads archived flights', (
    tester,
  ) async {
    final controller = await pumpFlights(tester);
    final plan = controller.betweenFlightPlan();
    final summaries = plan.rows.map((row) => row.summary).join('\n');
    expect(summaries, contains('NA201'));
    expect(summaries, contains('NA202'));
    expect(plan.savable, isNotEmpty);
    expect(find.byKey(const Key('flight-card-fixture-na201')), findsNothing);

    final stays = controller.stays.length;
    await tester.tap(find.byKey(const Key('preview-between-flights')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('between-flights-dialog')), findsOneWidget);
    final saved = plan.savable.length;
    expect(
      find.text('$saved stay${saved == 1 ? '' : 's'} can be saved.'),
      findsOneWidget,
    );
    expect(find.textContaining('NA201'), findsWidgets);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(controller.stays, hasLength(stays));
    expect(
      controller.flights
          .firstWhere((flight) => flight.id == 'fixture-na201')
          .reviewState,
      FlightReviewState.accepted,
    );
    expect(find.byKey(const Key('flight-card-fixture-na201')), findsNothing);
  });

  testWidgets('edit is offered and un-archive does not open the editor', (
    tester,
  ) async {
    final controller = await pumpFlights(tester);
    expect(find.byKey(const Key('edit-fixture-na311')), findsOneWidget);

    await reveal(tester, find.byKey(const Key('archive-toggle')));
    await tester.tap(find.byKey(const Key('archive-toggle')));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const Key('edit-fixture-na201')));
    expect(find.byKey(const Key('edit-fixture-na201')), findsOneWidget);
    expect(find.text('Edit flight'), findsNothing);
    expect(controller.unarchivedFlightIds, isEmpty);
    expect(
      controller.flights
          .firstWhere((flight) => flight.id == 'fixture-na201')
          .reviewState,
      FlightReviewState.accepted,
    );
  });

  testWidgets('the example dataset archives its accepted flight', (
    tester,
  ) async {
    final controller = await pumpFlights(tester, fixture: false);
    expect(find.textContaining('EX512'), findsWidgets);
    expect(find.textContaining('EX440'), findsWidgets);
    expect(find.text('Archived (1)'), findsOneWidget);
    expect(find.byKey(const Key('flight-card-example-ex201')), findsNothing);

    await reveal(tester, find.byKey(const Key('archive-toggle')));
    await tester.tap(find.byKey(const Key('archive-toggle')));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const Key('unarchive-example-ex201')));
    await tester.tap(find.byKey(const Key('unarchive-example-ex201')));
    await tester.pumpAndSettle();
    expect(find.text('Back on this list (1)'), findsOneWidget);
    expect(find.byKey(const Key('archive-toggle')), findsNothing);
    expect(find.textContaining('EX201'), findsWidgets);
    expect(
      controller.flights
          .firstWhere((flight) => flight.id == 'example-ex201')
          .reviewState,
      FlightReviewState.accepted,
    );
    final original = buildExampleDataset().flights;
    expect(
      controller.flights.map((flight) => flight.id).toList(),
      original.map((flight) => flight.id).toList(),
    );
    expect(
      controller.flights.map((flight) => flight.reviewState).toList(),
      original.map((flight) => flight.reviewState).toList(),
    );
  });
}
