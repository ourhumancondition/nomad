import 'package:flutter_test/flutter_test.dart';
import 'package:nomadic_residence/engine/between_flights.dart';
import 'package:nomadic_residence/engine/day_engine.dart';
import 'package:nomadic_residence/engine/flight_proposals.dart';
import 'package:nomadic_residence/engine/local_date.dart';
import 'package:nomadic_residence/engine/models.dart';
import 'package:nomadic_residence/state/app_controller.dart';

void main() {
  const rules = CountingRules.standard;

  FlightRecord flight({
    required String id,
    required String from,
    required String to,
    required String depart,
    required String arrive,
    String evidence = 'confirmed',
    FlightReviewState review = FlightReviewState.needsManual,
    String departZone = 'Etc/UTC',
    String arriveZone = 'Etc/UTC',
    String number = 'EX100',
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

  Stay? saved(BetweenFlightPlan plan) {
    final stays = plan.savable;
    return stays.isEmpty ? null : stays.single;
  }

  test('same-country arrival and a later departure fill the inclusive interior', () {
    final plan = planContinuousCountry(
      flights: [
        flight(
          id: 'in',
          from: 'PT',
          to: 'JP',
          depart: '2025-04-01T09:00',
          arrive: '2025-04-01T18:00',
          arriveZone: 'Asia/Tokyo',
        ),
        flight(
          id: 'out',
          from: 'JP',
          to: 'SG',
          depart: '2025-04-20T09:00',
          arrive: '2025-04-20T15:00',
          departZone: 'Asia/Tokyo',
        ),
      ],
      existing: const [],
      rules: rules,
    );
    final stay = saved(plan)!;
    expect(stay.countryCode, 'JP');
    expect(stay.role, PresenceRole.primary);
    expect(stay.start, LocalDate(2025, 4, 2));
    expect(stay.end, LocalDate(2025, 4, 20));
    expect(stay.evidenceStatus, 'inferred');
    expect(stay.inference, InferenceKind.inferredItinerary);
    expect(stay.timezone, 'Asia/Tokyo');
    expect(stay.externalId, 'btw-in-out');
    expect(stay.notes, contains('in'));
    expect(stay.notes, contains('out'));
    expect(stay.end.differenceInDays(stay.start) + 1, 19);
    expect(
      proposeItinerary([
        flight(
          id: 'in',
          from: 'PT',
          to: 'JP',
          depart: '2025-04-01T09:00',
          arrive: '2025-04-01T18:00',
        ),
        flight(
          id: 'out',
          from: 'JP',
          to: 'SG',
          depart: '2025-04-20T09:00',
          arrive: '2025-04-20T15:00',
        ),
      ], rules).any((proposal) => proposal.reason.contains('stay unknown')),
      isTrue,
    );
  });

  test('a different next country, a rejected flight, and a duplicate are not bridged', () {
    final missing = planContinuousCountry(
      flights: [
        flight(
          id: 'a',
          from: 'PT',
          to: 'JP',
          depart: '2025-04-01T09:00',
          arrive: '2025-04-01T18:00',
        ),
        flight(
          id: 'b',
          from: 'SG',
          to: 'FR',
          depart: '2025-04-20T09:00',
          arrive: '2025-04-20T15:00',
        ),
      ],
      existing: const [],
      rules: rules,
    );
    expect(missing.savable, isEmpty);
    expect(missing.rows.any((row) => row.summary.contains('not filled')), isTrue);

    final rejected = planContinuousCountry(
      flights: [
        flight(
          id: 'a',
          from: 'PT',
          to: 'JP',
          depart: '2025-04-01T09:00',
          arrive: '2025-04-01T18:00',
          review: FlightReviewState.rejected,
        ),
        flight(
          id: 'b',
          from: 'JP',
          to: 'SG',
          depart: '2025-04-20T09:00',
          arrive: '2025-04-20T15:00',
        ),
      ],
      existing: const [],
      rules: rules,
    );
    expect(rejected.savable, isEmpty);

    final duplicate = planContinuousCountry(
      flights: [
        flight(
          id: 'a',
          from: 'PT',
          to: 'JP',
          depart: '2025-04-01T09:00',
          arrive: '2025-04-01T18:00',
          number: 'EX1',
        ),
        flight(
          id: 'a2',
          from: 'PT',
          to: 'JP',
          depart: '2025-04-01T09:00',
          arrive: '2025-04-01T18:00',
          number: 'EX1',
        ),
        flight(
          id: 'b',
          from: 'JP',
          to: 'SG',
          depart: '2025-04-20T09:00',
          arrive: '2025-04-20T15:00',
        ),
      ],
      existing: const [],
      rules: rules,
    );
    expect(duplicate.savable, isEmpty);
    expect(duplicate.rows.any((row) => row.summary.contains('duplicated')), isTrue);
  });

  test('a conflicting earlier departure and a manual stay are left alone', () {
    final conflict = planContinuousCountry(
      flights: [
        flight(
          id: 'long',
          from: 'PT',
          to: 'JP',
          depart: '2025-04-01T09:00',
          arrive: '2025-04-10T18:00',
        ),
        flight(
          id: 'early',
          from: 'JP',
          to: 'SG',
          depart: '2025-04-02T09:00',
          arrive: '2025-04-02T15:00',
        ),
      ],
      existing: const [],
      rules: rules,
    );
    expect(conflict.savable, isEmpty);
    expect(conflict.rows.any((row) => row.summary.contains('conflict')), isTrue);

    final manual = Stay(
      id: 'mine',
      countryCode: 'JP',
      start: LocalDate(2025, 4, 5),
      end: LocalDate(2025, 4, 8),
      role: PresenceRole.primary,
      evidenceStatus: 'confirmed',
      inference: InferenceKind.none,
      phase: TripPhase.actual,
      timezone: 'Asia/Tokyo',
      source: RecordSource.manual,
    );
    final blocked = planContinuousCountry(
      flights: [
        flight(
          id: 'in',
          from: 'PT',
          to: 'JP',
          depart: '2025-04-01T09:00',
          arrive: '2025-04-01T18:00',
        ),
        flight(
          id: 'out',
          from: 'JP',
          to: 'SG',
          depart: '2025-04-20T09:00',
          arrive: '2025-04-20T15:00',
        ),
      ],
      existing: [manual],
      rules: rules,
    );
    expect(blocked.savable, isEmpty);
    expect(blocked.rows.any((row) => row.summary.contains('not replaced')), isTrue);
  });

  test('a year boundary and a leap day stay inside the civil dates', () {
    final year = planContinuousCountry(
      flights: [
        flight(
          id: 'in',
          from: 'PT',
          to: 'JP',
          depart: '2025-12-28T10:00',
          arrive: '2025-12-28T18:00',
        ),
        flight(
          id: 'out',
          from: 'JP',
          to: 'PT',
          depart: '2026-01-03T10:00',
          arrive: '2026-01-03T18:00',
        ),
      ],
      existing: const [],
      rules: rules,
    );
    final stay = saved(year)!;
    expect(stay.start, LocalDate(2025, 12, 29));
    expect(stay.end, LocalDate(2026, 1, 3));
    final tally2025 = DayEngine.tally(
      stays: [stay],
      year: 2025,
      today: LocalDate(2026, 11, 8),
      rules: rules,
      statuses: defaultEvidenceStatuses,
    );
    expect(tally2025.primaryCountryDays, 0);
    expect(
      DayEngine.inferredPrimaryDays(
        stays: [stay],
        windowStart: tally2025.windowStart,
        windowEnd: tally2025.windowEnd,
        rules: rules,
        statuses: defaultEvidenceStatuses,
      ),
      3,
    );

    final leap = saved(
      planContinuousCountry(
        flights: [
          flight(
            id: 'in',
            from: 'PT',
            to: 'IS',
            depart: '2024-02-27T10:00',
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
        existing: const [],
        rules: rules,
      ),
    )!;
    expect(leap.start <= LocalDate(2024, 2, 29), isTrue);
    expect(leap.end >= LocalDate(2024, 2, 29), isTrue);
    expect(leap.covers(LocalDate(2024, 2, 29)), isTrue);
    expect(leap.covers(LocalDate(2024, 3, 10)), isFalse);
  });

  test('DST does not drop a civil date, and booking-only is not confirmed', () {
    final stay = saved(
      planContinuousCountry(
        flights: [
          flight(
            id: 'in',
            from: 'GB',
            to: 'US',
            depart: '2025-03-08T09:00',
            arrive: '2025-03-08T18:00',
            arriveZone: 'America/New_York',
            evidence: 'booking_only',
          ),
          flight(
            id: 'out',
            from: 'US',
            to: 'GB',
            depart: '2025-03-12T10:00',
            arrive: '2025-03-12T22:00',
            departZone: 'America/New_York',
          ),
        ],
        existing: const [],
        rules: rules,
      ),
    )!;
    expect(stay.covers(LocalDate(2025, 3, 9)), isTrue);
    expect(stay.covers(LocalDate(2025, 3, 10)), isTrue);
    expect(stay.timezone, 'America/New_York');
    expect(stay.evidenceStatus, 'inferred');
    expect(stay.notes, contains('booking-only'));
    expect(DayEngine.countsAsActual(stay, rules, defaultEvidenceStatuses), isFalse);
  });

  test('saving twice updates the same inferred stay', () async {
    final controller = AppController(clock: () => LocalDate(2026, 11, 8));
    controller.openExample();
    controller.flights = [
      flight(
        id: 'in',
        from: 'PT',
        to: 'JP',
        depart: '2025-04-01T09:00',
        arrive: '2025-04-01T18:00',
      ),
      flight(
        id: 'out',
        from: 'JP',
        to: 'SG',
        depart: '2025-04-20T09:00',
        arrive: '2025-04-20T15:00',
      ),
    ];
    controller.stays = [];
    controller.year = 2025;
    expect(await controller.saveBetweenFlightPlan(), isNull);
    expect(await controller.saveBetweenFlightPlan(), isNull);
    final inferred = controller.stays.where(
      (stay) => stay.externalId == 'btw-in-out',
    );
    expect(inferred, hasLength(1));
    expect(controller.rules.includeInferred, isFalse);
    expect(controller.tally.primaryCountryDays, 0);
    expect(controller.inferredCountryDays, greaterThan(0));
  });
}
