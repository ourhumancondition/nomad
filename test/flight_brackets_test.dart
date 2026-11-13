import 'package:flutter_test/flutter_test.dart';
import 'package:nomadic_residence/demo/example_dataset.dart';
import 'package:nomadic_residence/engine/day_engine.dart';
import 'package:nomadic_residence/engine/flight_brackets.dart';
import 'package:nomadic_residence/engine/local_date.dart';
import 'package:nomadic_residence/engine/models.dart';
import 'package:nomadic_residence/state/app_controller.dart';

void main() {
  const rules = CountingRules.standard;
  final statuses = defaultEvidenceStatuses;
  final today = LocalDate(2026, 11, 13);

  FlightRecord flight({
    required String id,
    required String from,
    required String to,
    required String depart,
    required String arrive,
    String evidence = 'confirmed',
    FlightReviewState review = FlightReviewState.accepted,
    String number = 'EX100',
    String departZone = 'Etc/UTC',
    String arriveZone = 'Etc/UTC',
  }) {
    return FlightRecord(
      id: id,
      flightNumber: number,
      fromIata: 'AAA',
      toIata: 'BBB',
      fromCountry: from,
      toCountry: to,
      depart: WallTime.parse(depart),
      arrive: WallTime.parse(arrive),
      departTimezone: departZone,
      arriveTimezone: arriveZone,
      evidenceStatus: evidence,
      inference: InferenceKind.none,
      reviewState: review,
      externalId: id,
    );
  }

  Stay stay({
    required String country,
    required String start,
    required String end,
    PresenceRole role = PresenceRole.primary,
    String evidence = 'confirmed',
    InferenceKind inference = InferenceKind.none,
    TripPhase phase = TripPhase.actual,
  }) {
    return Stay(
      id: '$country-$start-${role.wire}',
      countryCode: country,
      start: LocalDate.parse(start),
      end: LocalDate.parse(end),
      role: role,
      evidenceStatus: evidence,
      inference: inference,
      phase: phase,
      timezone: 'Etc/UTC',
    );
  }

  YearTally count({
    List<Stay> stays = const [],
    List<FlightRecord> flights = const [],
    int year = 2025,
    LocalDate? asOf,
  }) {
    return DayEngine.tally(
      stays: stays,
      flights: flights,
      year: year,
      today: asOf ?? today,
      rules: rules,
      statuses: statuses,
    );
  }

  test('a same-country bracket counts in the wake-up total', () {
    final inferred = stay(
      country: 'CA',
      start: '2025-08-08',
      end: '2025-09-10',
      evidence: 'inferred',
      inference: InferenceKind.inferredItinerary,
    );
    final imported = stay(
      country: 'FR',
      start: '2025-03-01',
      end: '2025-03-10',
      evidence: 'inferred',
      inference: InferenceKind.inferredItinerary,
    );
    final flights = [
      flight(
        id: 'in',
        from: 'PT',
        to: 'CA',
        depart: '2025-08-07T09:00',
        arrive: '2025-08-07T18:00',
        number: 'NB100',
        arriveZone: 'America/Toronto',
      ),
      flight(
        id: 'out',
        from: 'CA',
        to: 'PT',
        depart: '2025-09-10T11:00',
        arrive: '2025-09-10T22:00',
        number: 'NB200',
        departZone: 'America/Toronto',
      ),
    ];
    final without = count(stays: [inferred, imported]);
    expect(without.primaryDays.containsKey('CA'), isFalse);
    expect(without.inferredKeptOutDays, 34 + 10);

    final tally = count(stays: [inferred, imported], flights: flights);
    expect(tally.primaryDays['CA'], 34);
    expect(tally.flightBracketDays['CA'], 34);
    expect(tally.stayPrimaryDays.containsKey('CA'), isFalse);
    expect(tally.primaryCountryDays, 34);
    expect(tally.flightBracketDayCount, 34);
    expect(inferred.evidenceStatus, 'inferred');
    expect(tally.inferredKeptOutDays, 10);
    expect(tally.appliedBrackets.single.countryCode, 'CA');
    expect(tally.appliedBrackets.single.start, LocalDate(2025, 8, 8));
    expect(tally.appliedBrackets.single.end, LocalDate(2025, 9, 10));
    final morning = tally.days.singleWhere(
      (day) => day.date == LocalDate(2025, 8, 8),
    );
    expect(morning.kind, DayKind.primaryCountry);
    expect(morning.primaryCountry, 'CA');
    expect(morning.fromFlights, isTrue);
    expect(morning.flightLabel, 'NB100 to NB200');
    expect(tally.identityHolds, isTrue);
  });

  test('a mismatched next country stays unknown and is listed', () {
    final tally = count(
      flights: [
        flight(
          id: 'in',
          from: 'MX',
          to: 'JP',
          depart: '2025-05-01T08:00',
          arrive: '2025-05-01T20:00',
          number: 'NB310',
        ),
        flight(
          id: 'out',
          from: 'US',
          to: 'FR',
          depart: '2025-05-20T09:00',
          arrive: '2025-05-20T18:00',
          number: 'NB320',
        ),
      ],
    );
    expect(tally.primaryCountryDays, 0);
    expect(tally.flightBracketDayCount, 0);
    expect(tally.flightGaps.single.kind, FlightGapKind.mismatch);
    expect(tally.flightGaps.single.arrivalCountry, 'JP');
    expect(tally.flightGaps.single.otherCountry, 'US');
    final gap = tally.days.singleWhere(
      (day) => day.date == LocalDate(2025, 5, 2),
    );
    expect(gap.kind, DayKind.gap);
    expect(tally.identityHolds, isTrue);
  });

  test('an existing stay of another country wins and is reported', () {
    final tally = count(
      stays: [stay(country: 'MX', start: '2025-11-02', end: '2025-11-04')],
      flights: [
        flight(
          id: 'in',
          from: 'GB',
          to: 'US',
          depart: '2025-10-31T09:00',
          arrive: '2025-10-31T16:00',
          number: 'NB410',
        ),
        flight(
          id: 'out',
          from: 'US',
          to: 'GB',
          depart: '2025-11-08T18:00',
          arrive: '2025-11-09T06:00',
          number: 'NB420',
        ),
      ],
    );
    expect(tally.primaryDays['US'], 5);
    expect(tally.flightBracketDays['US'], 5);
    expect(tally.primaryDays['MX'], 3);
    expect(tally.stayPrimaryDays['MX'], 3);
    expect(tally.bracketConflicts.single.flightCountry, 'US');
    expect(tally.bracketConflicts.single.stayCountry, 'MX');
    expect(tally.bracketConflicts.single.range.start, LocalDate(2025, 11, 2));
    expect(tally.bracketConflicts.single.range.end, LocalDate(2025, 11, 4));
    final kept = tally.days.singleWhere(
      (day) => day.date == LocalDate(2025, 11, 3),
    );
    expect(kept.primaryCountry, 'MX');
    expect(kept.fromFlights, isFalse);
    final counted = tally.days.singleWhere(
      (day) => day.date == LocalDate(2025, 11, 1),
    );
    expect(counted.primaryCountry, 'US');
    expect(counted.fromFlights, isTrue);
    expect(tally.identityHolds, isTrue);
  });

  test('an inferred stay in another country is kept and not overwritten', () {
    final tally = count(
      stays: [
        stay(
          country: 'US',
          start: '2025-08-10',
          end: '2025-08-12',
          evidence: 'inferred',
          inference: InferenceKind.inferredItinerary,
        ),
      ],
      flights: [
        flight(
          id: 'in',
          from: 'PT',
          to: 'CA',
          depart: '2025-08-07T09:00',
          arrive: '2025-08-07T18:00',
        ),
        flight(
          id: 'out',
          from: 'CA',
          to: 'PT',
          depart: '2025-08-20T11:00',
          arrive: '2025-08-20T18:00',
        ),
      ],
    );
    for (final iso in ['2025-08-10', '2025-08-11', '2025-08-12']) {
      final day = tally.days.singleWhere(
        (item) => item.date == LocalDate.parse(iso),
      );
      expect(day.kind, DayKind.gap, reason: iso);
    }
    expect(tally.bracketConflicts.single.stayCountry, 'US');
    expect(tally.primaryDays['CA'], 10);
    expect(tally.inferredKeptOutDays, 3);
  });

  test('an overnight wake-up stays in transit and is not the destination', () {
    final tally = count(
      flights: [
        flight(
          id: 'over',
          from: 'FR',
          to: 'TH',
          depart: '2025-06-01T22:00',
          arrive: '2025-06-02T10:30',
          number: 'NB510',
        ),
        flight(
          id: 'back',
          from: 'TH',
          to: 'FR',
          depart: '2025-06-06T15:00',
          arrive: '2025-06-06T22:00',
          number: 'NB520',
        ),
      ],
    );
    final airborne = tally.days.singleWhere(
      (day) => day.date == LocalDate(2025, 6, 2),
    );
    expect(airborne.kind, DayKind.inTransit);
    expect(airborne.fromFlights, isTrue);
    expect(airborne.primaryCountry, isNull);
    expect(tally.transitWakeDays, 1);
    expect(tally.primaryDays['TH'], 4);
    expect(tally.flightBracketDays['TH'], 4);
    final first = tally.days.singleWhere(
      (day) => day.date == LocalDate(2025, 6, 3),
    );
    expect(first.primaryCountry, 'TH');
    final departed = tally.days.singleWhere(
      (day) => day.date == LocalDate(2025, 6, 1),
    );
    expect(departed.kind, DayKind.gap);
    expect(tally.overnightNights, 0);
    expect(tally.identityHolds, isTrue);
  });

  test('a recorded in-transit wake-up ends the bracket', () {
    final tally = count(
      stays: [
        stay(
          country: '',
          start: '2025-08-10',
          end: '2025-08-10',
          role: PresenceRole.transitWake,
        ),
      ],
      flights: [
        flight(
          id: 'in',
          from: 'PT',
          to: 'CA',
          depart: '2025-08-07T09:00',
          arrive: '2025-08-07T18:00',
        ),
        flight(
          id: 'out',
          from: 'CA',
          to: 'PT',
          depart: '2025-08-20T11:00',
          arrive: '2025-08-20T18:00',
        ),
      ],
    );
    expect(tally.primaryDays['CA'], 2);
    expect(
      tally.days
          .singleWhere((day) => day.date == LocalDate(2025, 8, 9))
          .primaryCountry,
      'CA',
    );
    final transit = tally.days.singleWhere(
      (day) => day.date == LocalDate(2025, 8, 10),
    );
    expect(transit.kind, DayKind.inTransit);
    expect(transit.fromFlights, isFalse);
    expect(
      tally.days.singleWhere((day) => day.date == LocalDate(2025, 8, 11)).kind,
      DayKind.gap,
    );
    expect(tally.transitInterruptions.single.date, LocalDate(2025, 8, 10));
    expect(tally.identityHolds, isTrue);
  });

  test('a layover on a bracketed morning stays out of the country total', () {
    final tally = count(
      stays: [
        stay(
          country: 'QA',
          start: '2025-08-08',
          end: '2025-08-08',
          role: PresenceRole.layover,
        ),
      ],
      flights: [
        flight(
          id: 'in',
          from: 'PT',
          to: 'CA',
          depart: '2025-08-07T09:00',
          arrive: '2025-08-07T18:00',
        ),
        flight(
          id: 'out',
          from: 'CA',
          to: 'PT',
          depart: '2025-08-10T11:00',
          arrive: '2025-08-10T18:00',
        ),
      ],
    );
    expect(tally.primaryDays['CA'], 3);
    expect(tally.primaryDays.containsKey('QA'), isFalse);
    expect(tally.layoverDays['QA'], 1);
    final day = tally.days.singleWhere(
      (item) => item.date == LocalDate(2025, 8, 8),
    );
    expect(day.primaryCountry, 'CA');
    expect(day.layoverCountries, ['QA']);
  });

  test('booking-only, needs-manual, and rejected flights do not count', () {
    final pendingBooking = count(
      flights: [
        flight(
          id: 'in',
          from: 'DE',
          to: 'IT',
          depart: '2025-04-01T09:00',
          arrive: '2025-04-01T12:00',
          evidence: 'booking_only',
          review: FlightReviewState.pending,
          number: 'NB610',
        ),
        flight(
          id: 'out',
          from: 'IT',
          to: 'DE',
          depart: '2025-04-15T12:00',
          arrive: '2025-04-15T15:00',
          evidence: 'booking_only',
          review: FlightReviewState.pending,
          number: 'NB620',
        ),
      ],
    );
    expect(pendingBooking.primaryCountryDays, 0);
    expect(pendingBooking.flightGaps, isEmpty);

    final acceptedBooking = count(
      flights: [
        flight(
          id: 'in',
          from: 'PT',
          to: 'ES',
          depart: '2025-02-01T09:00',
          arrive: '2025-02-01T18:00',
          evidence: 'booking_only',
          review: FlightReviewState.accepted,
          number: 'NB710',
        ),
        flight(
          id: 'out',
          from: 'ES',
          to: 'PT',
          depart: '2025-02-04T10:00',
          arrive: '2025-02-04T12:00',
          evidence: 'booking_only',
          review: FlightReviewState.accepted,
          number: 'NB720',
        ),
      ],
    );
    expect(acceptedBooking.primaryDays['ES'], 3);
    expect(acceptedBooking.flightBracketDays['ES'], 3);

    final pendingConfirmed = count(
      flights: [
        flight(
          id: 'in',
          from: 'PT',
          to: 'ES',
          depart: '2025-02-01T09:00',
          arrive: '2025-02-01T18:00',
          review: FlightReviewState.pending,
          number: 'NB710',
        ),
        flight(
          id: 'out',
          from: 'ES',
          to: 'PT',
          depart: '2025-02-04T10:00',
          arrive: '2025-02-04T12:00',
          review: FlightReviewState.pending,
          number: 'NB720',
        ),
      ],
    );
    expect(pendingConfirmed.flightBracketDays['ES'], 3);

    final manual = count(
      flights: [
        flight(
          id: 'in',
          from: 'PT',
          to: 'CA',
          depart: '2025-08-07T09:00',
          arrive: '2025-08-07T18:00',
          number: 'NB100',
        ),
        flight(
          id: 'out',
          from: 'CA',
          to: 'PT',
          depart: '2025-09-10T11:00',
          arrive: '2025-09-10T22:00',
          review: FlightReviewState.needsManual,
          number: 'NB200',
        ),
      ],
    );
    expect(manual.primaryCountryDays, 0);
    expect(manual.flightGaps.single.kind, FlightGapKind.unqualified);
    expect(manual.flightGaps.single.reason, 'needs_manual');

    final rejectedBetween = count(
      flights: [
        flight(
          id: 'in',
          from: 'PT',
          to: 'CA',
          depart: '2025-08-07T09:00',
          arrive: '2025-08-07T18:00',
          number: 'NB100',
        ),
        flight(
          id: 'nope',
          from: 'CA',
          to: 'MX',
          depart: '2025-08-20T09:00',
          arrive: '2025-08-20T12:00',
          review: FlightReviewState.rejected,
          number: 'NB150',
        ),
        flight(
          id: 'out',
          from: 'CA',
          to: 'PT',
          depart: '2025-09-10T11:00',
          arrive: '2025-09-10T22:00',
          number: 'NB200',
        ),
      ],
    );
    expect(rejectedBetween.primaryDays['CA'], 34);
    expect(rejectedBetween.flightGaps, isEmpty);
  });

  test('a booking-only departure is not skipped for a later flight', () {
    final tally = count(
      flights: [
        flight(
          id: 'in',
          from: 'PT',
          to: 'CA',
          depart: '2025-08-07T09:00',
          arrive: '2025-08-07T18:00',
          number: 'NB100',
        ),
        flight(
          id: 'booked',
          from: 'CA',
          to: 'MX',
          depart: '2025-08-20T10:00',
          arrive: '2025-08-20T14:00',
          evidence: 'booking_only',
          review: FlightReviewState.pending,
          number: 'NB150',
        ),
        flight(
          id: 'later',
          from: 'CA',
          to: 'PT',
          depart: '2025-09-10T11:00',
          arrive: '2025-09-10T22:00',
          number: 'NB200',
        ),
      ],
    );
    expect(tally.primaryDays.containsKey('CA'), isFalse);
    expect(tally.flightGaps.single.reason, 'not_evidence');
    expect(tally.flightGaps.single.otherNumber, 'NB150');
  });

  test('a qualifying flight from another country is not bridged', () {
    final tally = count(
      flights: [
        flight(
          id: 'in',
          from: 'PT',
          to: 'CA',
          depart: '2025-08-07T09:00',
          arrive: '2025-08-07T18:00',
          number: 'NB100',
        ),
        flight(
          id: 'side',
          from: 'MX',
          to: 'FR',
          depart: '2025-08-20T10:00',
          arrive: '2025-08-20T16:00',
          number: 'NB150',
        ),
        flight(
          id: 'later',
          from: 'CA',
          to: 'PT',
          depart: '2025-09-10T11:00',
          arrive: '2025-09-10T22:00',
          number: 'NB200',
        ),
      ],
    );
    expect(tally.primaryDays.containsKey('CA'), isFalse);
    expect(
      tally.flightGaps.any(
        (gap) =>
            gap.kind == FlightGapKind.mismatch &&
            gap.arrivalCountry == 'CA' &&
            gap.otherCountry == 'MX',
      ),
      isTrue,
    );
  });

  test('an unaccepted booking that does not leave the country is ignored', () {
    final tally = count(
      flights: [
        flight(
          id: 'in',
          from: 'PT',
          to: 'CA',
          depart: '2025-08-07T09:00',
          arrive: '2025-08-07T18:00',
          number: 'NB100',
        ),
        flight(
          id: 'elsewhere',
          from: 'MX',
          to: 'FR',
          depart: '2025-08-20T10:00',
          arrive: '2025-08-20T16:00',
          evidence: 'booking_only',
          review: FlightReviewState.pending,
          number: 'NB150',
        ),
        flight(
          id: 'out',
          from: 'CA',
          to: 'PT',
          depart: '2025-09-10T11:00',
          arrive: '2025-09-10T22:00',
          number: 'NB200',
        ),
      ],
    );
    expect(tally.primaryDays['CA'], 34);
    expect(tally.flightGaps, isEmpty);
  });

  test('a domestic flight inside the country does not split the bracket', () {
    final tally = count(
      flights: [
        flight(
          id: 'in',
          from: 'PT',
          to: 'CA',
          depart: '2025-08-07T09:00',
          arrive: '2025-08-07T18:00',
          number: 'NB100',
        ),
        flight(
          id: 'hop',
          from: 'CA',
          to: 'CA',
          depart: '2025-08-15T09:00',
          arrive: '2025-08-15T12:00',
          number: 'NB150',
        ),
        flight(
          id: 'out',
          from: 'CA',
          to: 'PT',
          depart: '2025-08-20T11:00',
          arrive: '2025-08-20T18:00',
          number: 'NB200',
        ),
      ],
    );
    expect(tally.primaryDays['CA'], 13);
    expect(tally.appliedBrackets, hasLength(1));
    expect(tally.appliedBrackets.single.start, LocalDate(2025, 8, 8));
    expect(tally.appliedBrackets.single.end, LocalDate(2025, 8, 20));
  });

  test('duplicate tickets are not used', () {
    final tally = count(
      flights: [
        flight(
          id: 'in-a',
          from: 'PT',
          to: 'CA',
          depart: '2025-08-07T09:00',
          arrive: '2025-08-07T18:00',
          number: 'NB100',
        ),
        flight(
          id: 'in-b',
          from: 'PT',
          to: 'CA',
          depart: '2025-08-07T09:00',
          arrive: '2025-08-07T18:00',
          number: 'NB100',
        ),
        flight(
          id: 'out',
          from: 'CA',
          to: 'PT',
          depart: '2025-08-20T11:00',
          arrive: '2025-08-20T18:00',
          number: 'NB200',
        ),
      ],
    );
    expect(tally.primaryCountryDays, 0);
    expect(tally.flightGaps, isEmpty);
  });

  test('a same-day connection counts only when the wake falls there', () {
    final woke = count(
      flights: [
        flight(
          id: 'in',
          from: 'PT',
          to: 'QA',
          depart: '2025-05-02T00:30',
          arrive: '2025-05-02T06:00',
        ),
        flight(
          id: 'out',
          from: 'QA',
          to: 'GB',
          depart: '2025-05-02T12:00',
          arrive: '2025-05-02T18:00',
        ),
      ],
    );
    expect(woke.primaryDays['QA'], 1);

    final missed = count(
      flights: [
        flight(
          id: 'in',
          from: 'PT',
          to: 'QA',
          depart: '2025-05-02T09:00',
          arrive: '2025-05-02T11:00',
        ),
        flight(
          id: 'out',
          from: 'QA',
          to: 'GB',
          depart: '2025-05-02T14:00',
          arrive: '2025-05-02T18:00',
        ),
      ],
    );
    expect(missed.primaryCountryDays, 0);
    expect(missed.layoverDays.containsKey('QA'), isFalse);
    expect(missed.flightGaps.single.kind, FlightGapKind.noWake);
  });

  test('a year boundary and a leap day stay on their civil dates', () {
    final crossing = [
      flight(
        id: 'in',
        from: 'PT',
        to: 'JP',
        depart: '2025-12-30T09:00',
        arrive: '2025-12-30T18:00',
      ),
      flight(
        id: 'out',
        from: 'JP',
        to: 'PT',
        depart: '2026-01-03T10:00',
        arrive: '2026-01-03T18:00',
      ),
    ];
    final previous = count(flights: crossing, year: 2025);
    final current = count(flights: crossing, year: 2026);
    expect(previous.primaryDays['JP'], 1);
    expect(current.primaryDays['JP'], 3);
    expect(previous.identityHolds, isTrue);
    expect(current.identityHolds, isTrue);

    final leap = count(
      flights: [
        flight(
          id: 'in',
          from: 'PT',
          to: 'IS',
          depart: '2024-02-27T09:00',
          arrive: '2024-02-27T18:00',
        ),
        flight(
          id: 'out',
          from: 'IS',
          to: 'PT',
          depart: '2024-03-02T10:00',
          arrive: '2024-03-02T16:00',
        ),
      ],
      year: 2024,
    );
    expect(leap.primaryDays['IS'], 4);
    final day = leap.days.singleWhere(
      (item) => item.date == LocalDate(2024, 2, 29),
    );
    expect(day.primaryCountry, 'IS');
    expect(day.fromFlights, isTrue);
  });

  test('a same-country confirmed stay is not counted twice', () {
    final tally = count(
      stays: [stay(country: 'CA', start: '2025-08-08', end: '2025-08-10')],
      flights: [
        flight(
          id: 'in',
          from: 'PT',
          to: 'CA',
          depart: '2025-08-07T09:00',
          arrive: '2025-08-07T18:00',
        ),
        flight(
          id: 'out',
          from: 'CA',
          to: 'PT',
          depart: '2025-08-14T11:00',
          arrive: '2025-08-14T18:00',
        ),
      ],
    );
    expect(tally.primaryDays['CA'], 7);
    expect(tally.stayPrimaryDays['CA'], 3);
    expect(tally.flightBracketDays['CA'], 4);
    expect(tally.bracketConflicts, isEmpty);
  });

  test('the example dataset is unchanged when its flights are included', () {
    final dataset = buildExampleDataset();
    final staysOnly = DayEngine.tally(
      stays: dataset.stays,
      year: 2026,
      today: LocalDate(2026, 11, 8),
      rules: rules,
      statuses: statuses,
    );
    final withFlights = DayEngine.tally(
      stays: dataset.stays,
      flights: dataset.flights,
      year: 2026,
      today: LocalDate(2026, 11, 8),
      rules: rules,
      statuses: statuses,
    );
    expect(withFlights.primaryDays, staysOnly.primaryDays);
    expect(withFlights.transitWakeDays, staysOnly.transitWakeDays);
    expect(withFlights.gapDays, staysOnly.gapDays);
    expect(withFlights.overlapDays, staysOnly.overlapDays);
    expect(withFlights.layoverDays, staysOnly.layoverDays);
    expect(withFlights.overnightNights, staysOnly.overnightNights);
    expect(withFlights.flightBracketDayCount, 0);
    expect(withFlights.flightGaps, isEmpty);
    expect(withFlights.identityHolds, isTrue);
    expect(withFlights.primaryDays['PT'], 90);
  });

  test(
    'the summary counts accepted flights without rewriting the stay',
    () async {
      final controller = AppController(clock: () => today);
      controller.openExample();
      controller.year = 2025;
      controller.stays = [
        stay(
          country: 'CA',
          start: '2025-08-08',
          end: '2025-09-10',
          evidence: 'inferred',
          inference: InferenceKind.inferredItinerary,
        ),
      ];
      controller.flights = [
        flight(
          id: 'in',
          from: 'PT',
          to: 'CA',
          depart: '2025-08-07T09:00',
          arrive: '2025-08-07T18:00',
          number: 'NB100',
        ),
        flight(
          id: 'out',
          from: 'CA',
          to: 'PT',
          depart: '2025-09-10T11:00',
          arrive: '2025-09-10T22:00',
          number: 'NB200',
        ),
      ];
      expect(controller.tally.primaryDays['CA'], 34);
      expect(controller.inferredCountryDays, 0);
      expect(controller.stays.single.evidenceStatus, 'inferred');
      expect(controller.tally.identityHolds, isTrue);
    },
  );
}
