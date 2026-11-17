import 'package:flutter_test/flutter_test.dart';
import 'package:nomadic_residence/engine/day_engine.dart';
import 'package:nomadic_residence/engine/local_date.dart';
import 'package:nomadic_residence/engine/models.dart';
import 'package:nomadic_residence/engine/today_presence.dart';

/// Fictional records used only by these tests. Not a real trip.
Stay stay(
  String id,
  String country,
  String start,
  String end, {
  String evidence = 'confirmed',
  PresenceRole role = PresenceRole.primary,
  InferenceKind inference = InferenceKind.none,
  TripPhase phase = TripPhase.actual,
}) => Stay(
  id: id,
  countryCode: country,
  start: LocalDate.parse(start),
  end: LocalDate.parse(end),
  role: role,
  evidenceStatus: evidence,
  inference: inference,
  phase: phase,
  timezone: 'Etc/UTC',
  externalId: id,
);

FlightRecord flight(
  String id,
  String number,
  String from,
  String to,
  String depart,
  String arrive, {
  String evidence = 'confirmed',
  FlightReviewState review = FlightReviewState.accepted,
}) => FlightRecord(
  id: id,
  flightNumber: number,
  fromIata: 'AAA',
  toIata: 'BBB',
  fromCountry: from,
  toCountry: to,
  depart: WallTime.parse(depart),
  arrive: WallTime.parse(arrive),
  departTimezone: 'Etc/UTC',
  arriveTimezone: 'Etc/UTC',
  evidenceStatus: evidence,
  inference: InferenceKind.none,
  reviewState: review,
  externalId: id,
);

TodayPresence on(
  String date, {
  List<Stay> stays = const [],
  List<FlightRecord> flights = const [],
  CountingRules rules = CountingRules.standard,
}) => resolveTodayOn(
  LocalDate.parse(date),
  stays: stays,
  flights: flights,
  rules: rules,
  statuses: defaultEvidenceStatuses,
);

void main() {
  test('a confirmed stay', () {
    final today = on(
      '2026-11-17',
      stays: [stay('ca', 'CA', '2026-11-09', '2026-11-30')],
    );
    expect(today.status, TodayStatus.confirmed);
    expect(today.countryCode, 'CA');
    expect(today.countryName, 'Canada');
    expect(today.dayCountThisYear, 9);
    expect(today.sinceDate, LocalDate(2026, 11, 9));
    expect(today.sourceLabel, 'Confirmed stay');
    expect(today.confirmCandidate, isNull);
  });

  test('a corroborated stay names its own status', () {
    final today = on(
      '2026-11-17',
      stays: [
        stay('ca', 'CA', '2026-11-17', '2026-11-17', evidence: 'corroborated'),
      ],
    );
    expect(today.status, TodayStatus.confirmed);
    expect(today.sourceLabel, 'Corroborated stay');
  });

  group('between flights', () {
    test('counts the arrival country and names the landing', () {
      final today = on(
        '2026-11-17',
        flights: [
          flight(
            'in',
            'AC5',
            'PT',
            'CA',
            '2026-11-09T10:00',
            '2026-11-09T14:00',
          ),
          flight(
            'out',
            'AC9',
            'CA',
            'MX',
            '2026-11-25T10:00',
            '2026-11-25T16:00',
          ),
        ],
      );
      expect(today.status, TodayStatus.fromFlights);
      expect(today.countryCode, 'CA');
      // The 08:00 wake-up on 9 Nov was still in Portugal.
      expect(today.sinceDate, LocalDate(2026, 11, 10));
      expect(today.dayCountThisYear, 8);
      expect(today.sourceLabel, 'From flights: landed AC5 on Nov 9');
      expect(today.confirmCandidate, 'CA');
    });

    test('landing in one country and leaving from another', () {
      final today = on(
        '2026-11-17',
        flights: [
          flight(
            'in',
            'AC5',
            'PT',
            'CA',
            '2026-11-09T10:00',
            '2026-11-09T14:00',
          ),
          flight(
            'out',
            'AA1',
            'US',
            'MX',
            '2026-11-25T10:00',
            '2026-11-25T16:00',
          ),
        ],
      );
      expect(today.status, TodayStatus.fromFlights);
      expect(today.countryCode, 'CA');
      expect(
        today.sourceLabel,
        'From flights: landed AC5 on Nov 9 (left from US)',
      );
    });
  });

  test('an overnight flight over the wake time is in transit', () {
    final today = on(
      '2026-11-17',
      stays: [stay('ca', 'CA', '2026-11-01', '2026-11-16')],
      flights: [
        flight('ov', 'MS1', 'CA', 'EG', '2026-11-16T22:00', '2026-11-17T15:00'),
        flight(
          'next',
          'MS2',
          'EG',
          'PT',
          '2026-11-28T10:00',
          '2026-11-28T14:00',
        ),
      ],
    );
    expect(today.status, TodayStatus.inTransit);
    expect(today.countryCode, isNull);
    expect(today.sourceLabel, 'From flights: airborne at 08:00');
    expect(today.confirmCandidate, isNull);
  });

  test('a recorded in-transit wake-up is in transit', () {
    final today = on(
      '2026-11-17',
      stays: [
        stay(
          't',
          '',
          '2026-11-17',
          '2026-11-17',
          role: PresenceRole.transitWake,
        ),
      ],
    );
    expect(today.status, TodayStatus.inTransit);
    expect(today.sourceLabel, 'Recorded in transit at wake-up');
  });

  test('a booking-only trip is ignored', () {
    final today = on(
      '2026-11-17',
      stays: [
        stay('fr', 'FR', '2026-11-10', '2026-11-20', evidence: 'booking_only'),
      ],
      flights: [
        flight(
          'b1',
          'AF1',
          'PT',
          'FR',
          '2026-11-10T09:00',
          '2026-11-10T12:00',
          evidence: 'booking_only',
          review: FlightReviewState.pending,
        ),
        flight(
          'b2',
          'AF2',
          'FR',
          'PT',
          '2026-11-20T09:00',
          '2026-11-20T12:00',
          evidence: 'booking_only',
          review: FlightReviewState.pending,
        ),
      ],
    );
    expect(today.status, TodayStatus.unknown);
    expect(today.countryCode, isNull);
    expect(today.dayCountThisYear, 0);
    expect(today.sourceLabel, 'No record for today');
    // It can be suggested, but only a tap would save it.
    expect(today.likelyCountry, 'FR');
  });

  test('an overlapping CA/EG conflict stays unresolved', () {
    final ca = stay('ca', 'CA', '2026-11-01', '2026-11-17');
    final eg = stay('eg', 'EG', '2026-11-17', '2026-11-25');
    final today = on('2026-11-17', stays: [ca, eg]);
    expect(today.status, TodayStatus.conflict);
    expect(today.countryCode, isNull);
    expect(today.conflictCountries, ['CA', 'EG']);
    expect(today.conflictingStays.map((s) => s.id), ['ca', 'eg']);
    expect(today.confirmCandidate, isNull);
  });

  test('an unknown day', () {
    final today = on('2026-11-17');
    expect(today.status, TodayStatus.unknown);
    expect(today.likelyCountry, isNull);
    expect(today.sourceLabel, 'No record for today');
    expect(today.confirmCandidate, isNull);
  });

  test('an unknown day suggests yesterday\'s country', () {
    final today = on(
      '2026-11-17',
      stays: [stay('ca', 'CA', '2026-11-01', '2026-11-16')],
    );
    expect(today.status, TodayStatus.unknown);
    expect(today.likelyCountry, 'CA');
    expect(today.confirmCandidate, 'CA');
  });

  group('wake-time boundary', () {
    final flights = [
      flight('in', 'TP7', 'PT', 'CA', '2026-11-16T23:00', '2026-11-17T02:00'),
      flight('out', 'AC9', 'CA', 'MX', '2026-11-30T10:00', '2026-11-30T16:00'),
    ];

    test('a 02:00 landing with an 08:00 wake time counts the arrival', () {
      final today = on('2026-11-17', flights: flights);
      expect(today.status, TodayStatus.fromFlights);
      expect(today.countryCode, 'CA');
      expect(today.dayCountThisYear, 1);
      expect(today.sinceDate, LocalDate(2026, 11, 17));
    });

    test('the same flight with a 01:00 wake time is in transit', () {
      final today = on(
        '2026-11-17',
        flights: flights,
        rules: const CountingRules(wakeHour: 1),
      );
      expect(today.status, TodayStatus.inTransit);
    });
  });

  group('time zone near midnight', () {
    final stays = [stay('ca', 'CA', '2026-11-01', '2026-11-17')];

    TodayPresence at(DateTime now) => resolveToday(
      now,
      stays: stays,
      flights: const [],
      rules: CountingRules.standard,
      statuses: defaultEvidenceStatuses,
    );

    test('one second before local midnight is still today', () {
      final today = at(DateTime(2026, 11, 17, 23, 59, 59));
      expect(today.date, LocalDate(2026, 11, 17));
      expect(today.status, TodayStatus.confirmed);
    });

    test('one second after local midnight is the next day', () {
      final today = at(DateTime(2026, 11, 18, 0, 0, 1));
      expect(today.date, LocalDate(2026, 11, 18));
      expect(today.status, TodayStatus.unknown);
    });

    test('a UTC instant is read in the device time zone', () {
      final instant = DateTime.utc(2026, 11, 17, 23, 30);
      final today = at(instant);
      expect(today.date, LocalDate.fromDateTime(instant.toLocal()));
    });
  });

  group('year edges', () {
    test('the first day of the year carries a run from last year', () {
      final today = on(
        '2026-01-01',
        stays: [stay('pt', 'PT', '2025-12-20', '2026-01-05')],
      );
      expect(today.status, TodayStatus.confirmed);
      expect(today.dayCountThisYear, 1);
      expect(today.sinceDate, LocalDate(2025, 12, 20));
    });

    test('the last day of a leap year counts 366', () {
      final today = on(
        '2024-12-31',
        stays: [stay('pt', 'PT', '2024-01-01', '2024-12-31')],
      );
      expect(today.dayCountThisYear, 366);
      expect(today.sinceDate, LocalDate(2024, 1, 1));
    });

    test('the last day of a common year counts 365', () {
      final today = on(
        '2026-12-31',
        stays: [stay('pt', 'PT', '2026-01-01', '2026-12-31')],
      );
      expect(today.dayCountThisYear, 365);
    });
  });

  test('matches the totals engine for every day of a mixed month', () {
    final stays = [
      stay('pt', 'PT', '2026-11-01', '2026-11-05'),
      stay('ca', 'CA', '2026-11-14', '2026-11-15'),
      stay('eg', 'EG', '2026-11-15', '2026-11-16'),
      stay('fr', 'FR', '2026-11-20', '2026-11-22', evidence: 'booking_only'),
      stay(
        'inf',
        'MX',
        '2026-11-25',
        '2026-11-26',
        evidence: 'inferred',
        inference: InferenceKind.inferredGap,
      ),
    ];
    final flights = [
      flight('a', 'TP1', 'PT', 'CA', '2026-11-06T10:00', '2026-11-06T15:00'),
      flight('b', 'AC2', 'CA', 'EG', '2026-11-12T22:00', '2026-11-13T14:00'),
      flight('c', 'MS3', 'EG', 'PT', '2026-11-18T09:00', '2026-11-18T13:00'),
    ];
    for (
      var date = LocalDate(2026, 11, 1);
      date <= LocalDate(2026, 11, 30);
      date = date.addDays(1)
    ) {
      final tally = DayEngine.tally(
        stays: stays,
        flights: flights,
        year: date.year,
        today: date,
        rules: CountingRules.standard,
        statuses: defaultEvidenceStatuses,
      );
      final day = tally.days.firstWhere((item) => item.date == date);
      final today = resolveTodayOn(
        date,
        stays: stays,
        flights: flights,
        rules: CountingRules.standard,
        statuses: defaultEvidenceStatuses,
      );
      final expected = switch (day.kind) {
        DayKind.primaryCountry =>
          day.fromFlights ? TodayStatus.fromFlights : TodayStatus.confirmed,
        DayKind.inTransit => TodayStatus.inTransit,
        DayKind.overlap => TodayStatus.conflict,
        _ => TodayStatus.unknown,
      };
      expect(today.status, expected, reason: date.iso);
      expect(today.countryCode, day.primaryCountry, reason: date.iso);
      if (day.primaryCountry != null) {
        expect(
          today.dayCountThisYear,
          tally.primaryDays[day.primaryCountry],
          reason: date.iso,
        );
      }
    }
  });

  test('resolving writes nothing', () {
    final stays = [stay('ca', 'CA', '2026-11-09', '2026-11-30')];
    final copy = List<Stay>.unmodifiable(stays);
    final flights = List<FlightRecord>.unmodifiable([
      flight('in', 'AC5', 'PT', 'CA', '2026-11-09T10:00', '2026-11-09T14:00'),
    ]);
    // Unmodifiable inputs throw on any write.
    expect(
      () => on('2026-11-17', stays: copy, flights: flights),
      returnsNormally,
    );
  });
}
