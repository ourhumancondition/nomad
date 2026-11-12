import 'package:flutter_test/flutter_test.dart';
import 'package:nomadic_residence/engine/csv_codec.dart';
import 'package:nomadic_residence/engine/flight_archive.dart';
import 'package:nomadic_residence/engine/local_date.dart';
import 'package:nomadic_residence/engine/models.dart';
import 'package:nomadic_residence/state/app_controller.dart';

import 'fixtures/archive_flights.dart';

void main() {
  List<FlightRecord> flights() => archiveFixtureFlights();

  test('accepted flights are archived and other review states stay open', () {
    final split = splitFlights(flights());

    expect(split.archived.map((flight) => flight.flightNumber), [
      'NA501',
      'NA201',
      'NA202',
      'NA502',
      'NA503',
      'NA500',
      'NA504',
      'NA505',
    ]);
    expect(split.needsReview.map((flight) => flight.flightNumber), [
      'NA310',
      'NA311',
      'NA404',
      'NA312',
      'NA313',
    ]);
    expect(split.broughtBack, isEmpty);
    expect(split.needsReview.map((flight) => flight.reviewState).toSet(), {
      FlightReviewState.needsManual,
      FlightReviewState.pending,
      FlightReviewState.rejected,
    });
    expect(
      split.archived.every(
        (flight) => flight.reviewState == FlightReviewState.accepted,
      ),
      isTrue,
    );
    expect(
      split.archived.map((flight) => flight.evidenceStatus),
      containsAll(['confirmed', 'booking_only', 'corroborated']),
    );
  });

  test('a query filters archived flights and leaves the review list whole', () {
    final split = splitFlights(flights());
    final japan = split.archived
        .where((flight) => flightMatchesQuery(flight, 'Japan'))
        .toList();
    final booking = split.archived
        .where((flight) => flightMatchesQuery(flight, 'booking'))
        .toList();
    final dated = split.archived
        .where((flight) => flightMatchesQuery(flight, 'nrt 2025-04'))
        .toList();

    expect(japan.map((flight) => flight.flightNumber), ['NA201', 'NA202']);
    expect(booking.map((flight) => flight.flightNumber), ['NA500']);
    expect(dated.map((flight) => flight.flightNumber), ['NA201', 'NA202']);
    expect(flightMatchesQuery(split.needsReview.first, ''), isTrue);
    expect(
      split.needsReview.where((flight) => flight.flightNumber == 'NA311'),
      isNotEmpty,
    );
  });

  test('un-archive is display only and the sheet has no archive column', () {
    final controller = AppController(clock: () => LocalDate(2026, 11, 8));
    controller.openExample();
    controller.flights = flights();
    controller.stays = [
      Stay(
        id: 'fixture-stay-pt',
        countryCode: 'PT',
        start: LocalDate(2026, 1, 1),
        end: LocalDate(2026, 1, 10),
        role: PresenceRole.primary,
        evidenceStatus: 'confirmed',
        inference: InferenceKind.none,
        phase: TripPhase.actual,
        timezone: 'Europe/Lisbon',
        notes:
            'Fictional stay used to check that archive does not change totals.',
      ),
    ];

    final originalFlights = controller.flights;
    final originalStay = controller.stays.single;
    final csv = controller.exportCsv();
    final plan = controller
        .betweenFlightPlan()
        .rows
        .map((row) => row.summary)
        .join('\n');
    final tally = Map<String, int>.of(controller.tally.primaryDays);
    final states = [
      for (final flight in controller.flights)
        (
          flight.id,
          flight.reviewState,
          flight.evidenceStatus,
          flight.depart.iso,
          flight.notes,
        ),
    ];

    expect(csv.split('\n').first, csvColumns.join(','));
    expect(csv.contains('archived'), isFalse);
    expect(plan, contains('NA201'));
    expect(plan, contains('NA202'));
    expect(controller.betweenFlightPlan().savable, isNotEmpty);

    var notifications = 0;
    controller.addListener(() => notifications += 1);
    controller.unarchiveFlight('fixture-na201');
    controller.unarchiveFlight('fixture-na201');
    controller.unarchiveFlight('');

    final split = splitFlights(
      controller.flights,
      unarchivedIds: controller.unarchivedFlightIds,
    );
    expect(notifications, 1);
    expect(identical(controller.flights, originalFlights), isTrue);
    expect(identical(controller.stays.single, originalStay), isTrue);
    expect(split.broughtBack.map((flight) => flight.flightNumber), ['NA201']);
    expect(
      split.archived.map((flight) => flight.flightNumber),
      isNot(contains('NA201')),
    );
    expect(
      flightIsArchived(
        controller.flights.firstWhere((flight) => flight.id == 'fixture-na201'),
        unarchivedIds: controller.unarchivedFlightIds,
      ),
      isFalse,
    );
    expect(controller.exportCsv(), csv);
    expect(
      controller.betweenFlightPlan().rows.map((row) => row.summary).join('\n'),
      plan,
    );
    expect(controller.tally.primaryDays, tally);
    expect([
      for (final flight in controller.flights)
        (
          flight.id,
          flight.reviewState,
          flight.evidenceStatus,
          flight.depart.iso,
          flight.notes,
        ),
    ], states);
    expect(
      controller.flights
          .firstWhere((flight) => flight.id == 'fixture-na201')
          .reviewState,
      FlightReviewState.accepted,
    );

    controller.rearchiveFlight('fixture-na201');
    expect(controller.unarchivedFlightIds, isEmpty);
    expect(
      splitFlights(
        controller.flights,
        unarchivedIds: controller.unarchivedFlightIds,
      ).archived.map((flight) => flight.flightNumber),
      contains('NA201'),
    );
    expect(controller.exportCsv(), csv);
    expect(controller.tally.primaryDays, tally);
    expect(notifications, 2);

    final roundTrip = CsvCodec.parse(csv);
    expect(roundTrip.errors, isEmpty);
    expect(roundTrip.flights, hasLength(flights().length));
    expect(
      roundTrip.flights.map((flight) => flight.reviewState.wire).toList(),
      flights().map((flight) => flight.reviewState.wire).toList(),
    );
  });

  test('saving a non-accepted review drops the display override', () async {
    final controller = AppController(clock: () => LocalDate(2026, 11, 8));
    controller.openExample();
    controller.flights = flights();
    controller.unarchiveFlight('fixture-na201');
    final flight = controller.flights.firstWhere(
      (item) => item.id == 'fixture-na201',
    );

    await controller.saveFlight(flight.copyWith(notes: 'Fictional note edit.'));
    expect(controller.unarchivedFlightIds, contains('fixture-na201'));
    expect(
      controller.flights
          .firstWhere((item) => item.id == 'fixture-na201')
          .reviewState,
      FlightReviewState.accepted,
    );
    expect(
      controller.flights
          .firstWhere((item) => item.id == 'fixture-na201')
          .evidenceStatus,
      'confirmed',
    );

    await controller.saveFlight(
      flight.copyWith(reviewState: FlightReviewState.pending),
    );
    expect(controller.unarchivedFlightIds, isEmpty);
    final pending = controller.flights.firstWhere(
      (item) => item.id == 'fixture-na201',
    );
    expect(pending.reviewState, FlightReviewState.pending);
    expect(pending.evidenceStatus, 'confirmed');
    expect(
      splitFlights(controller.flights).needsReview
          .map((item) => item.flightNumber),
      contains('NA201'),
    );

    await controller.saveFlight(
      pending.copyWith(reviewState: FlightReviewState.accepted),
    );
    expect(
      splitFlights(controller.flights).archived
          .map((item) => item.flightNumber),
      contains('NA201'),
    );
    expect(controller.unarchivedFlightIds, isEmpty);

    controller.unarchiveFlight('fixture-na500');
    await controller.deleteFlight('fixture-na500');
    expect(controller.unarchivedFlightIds, isEmpty);
    expect(
      controller.flights.map((item) => item.id),
      isNot(contains('fixture-na500')),
    );
  });
}
