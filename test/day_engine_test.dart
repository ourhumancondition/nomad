import 'package:flutter_test/flutter_test.dart';
import 'package:nomadic_residence/demo/example_dataset.dart';
import 'package:nomadic_residence/engine/day_engine.dart';
import 'package:nomadic_residence/engine/local_date.dart';
import 'package:nomadic_residence/engine/models.dart';

void main() {
  const rules = CountingRules.standard;
  final statuses = defaultEvidenceStatuses;
  final today = LocalDate(2026, 11, 8);

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
      id: '$country-$start',
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

  YearTally count(
    List<Stay> stays, {
    int year = 2026,
    LocalDate? asOf,
    CountingRules? counting,
    List<EvidenceStatusDef>? statusList,
  }) {
    return DayEngine.tally(
      stays: stays,
      year: year,
      today: asOf ?? today,
      rules: counting ?? rules,
      statuses: statusList ?? statuses,
    );
  }

  test('the example dataset matches the hand-checked 2026 window', () {
    final dataset = buildExampleDataset();
    final tally = count(dataset.stays);
    expect(tally.windowLength, 312);
    expect(tally.daysInYear, 365);
    expect(tally.primaryDays['PT'], 90);
    expect(tally.primaryDays['JP'], 6);
    expect(tally.primaryDays['SG'], 71);
    expect(tally.primaryDays['GR'], 4);
    expect(tally.primaryDays['IT'], 2);
    expect(tally.primaryDays['MX'], 39);
    expect(tally.primaryDays.containsKey('FR'), isFalse);
    expect(tally.primaryDays.containsKey('NZ'), isFalse);
    expect(tally.primaryDays.containsKey('CL'), isFalse);
    expect(tally.primaryCountryDays, 212);
    expect(tally.overlapDays, 6);
    expect(tally.transitWakeDays, 1);
    expect(tally.gapDays, 93);
    expect(tally.layoverDays['QA'], 1);
    expect(tally.overnightNights, 1);
    expect(tally.identityHolds, isTrue);
    expect(
      tally.primaryCountryDays +
          tally.layoverDays.values.fold<int>(0, (a, b) => a + b),
      isNot(tally.windowLength),
    );
  });

  test('2024 keeps the leap day inside Iceland', () {
    final dataset = buildExampleDataset();
    final tally = count(dataset.stays, year: 2024, asOf: today);
    expect(tally.daysInYear, 366);
    expect(tally.windowLength, 366);
    expect(tally.primaryDays['IS'], 4);
    final leap = tally.days.singleWhere(
      (day) => day.date == LocalDate(2024, 2, 29),
    );
    expect(leap.kind, DayKind.primaryCountry);
    expect(leap.primaryCountry, 'IS');
    expect(tally.identityHolds, isTrue);
  });

  test('a year boundary splits one stay without moving the dates', () {
    final rows = [stay(country: 'PT', start: '2025-12-30', end: '2026-01-02')];
    final previous = count(rows, year: 2025, asOf: today);
    final current = count(rows, year: 2026, asOf: today);
    expect(previous.primaryDays['PT'], 2);
    expect(current.primaryDays['PT'], 2);
    expect(previous.identityHolds, isTrue);
    expect(current.identityHolds, isTrue);
  });

  test('two wake-up countries on one date stay unresolved', () {
    final tally = count([
      stay(country: 'GR', start: '2026-07-01', end: '2026-07-03'),
      stay(country: 'IT', start: '2026-07-02', end: '2026-07-04'),
    ]);
    expect(tally.primaryDays['GR'], 1);
    expect(tally.primaryDays['IT'], 1);
    expect(tally.overlapDays, 2);
    expect(tally.overlapSpans.single.countries, ['GR', 'IT']);
    expect(tally.identityHolds, isTrue);
  });

  test(
    'a layover is recorded separately and does not take the wake-up day',
    () {
      final tally = count([
        stay(country: 'SG', start: '2026-05-02', end: '2026-05-02'),
        stay(
          country: 'QA',
          start: '2026-05-02',
          end: '2026-05-02',
          role: PresenceRole.layover,
        ),
      ]);
      expect(tally.primaryDays['SG'], 1);
      expect(tally.primaryDays.containsKey('QA'), isFalse);
      expect(tally.layoverDays['QA'], 1);
      final day = tally.days.singleWhere(
        (item) => item.date == LocalDate(2026, 5, 2),
      );
      expect(day.kind, DayKind.primaryCountry);
      expect(day.layoverCountries, ['QA']);
    },
  );

  test(
    'overnight nights do not consume the wake-up day, airborne wake-ups do',
    () {
      final tally = count([
        stay(country: 'JP', start: '2026-04-20', end: '2026-04-20'),
        stay(
          country: '',
          start: '2026-04-20',
          end: '2026-04-20',
          role: PresenceRole.transitNight,
        ),
        stay(
          country: '',
          start: '2026-04-21',
          end: '2026-04-21',
          role: PresenceRole.transitWake,
        ),
      ]);
      expect(tally.primaryDays['JP'], 1);
      expect(tally.overnightNights, 1);
      expect(tally.transitWakeDays, 1);
      expect(tally.identityHolds, isTrue);
    },
  );

  test('booking-only, inference, planned, and future dates stay out', () {
    final tally = count([
      stay(
        country: 'FR',
        start: '2026-08-01',
        end: '2026-08-02',
        evidence: 'booking_only',
      ),
      stay(
        country: 'FR',
        start: '2026-08-03',
        end: '2026-08-03',
        inference: InferenceKind.inferredItinerary,
      ),
      stay(
        country: 'NZ',
        start: '2026-12-20',
        end: '2026-12-22',
        phase: TripPhase.planned,
      ),
      stay(country: 'CL', start: '2026-12-01', end: '2026-12-02'),
    ]);
    expect(tally.primaryCountryDays, 0);
    expect(tally.excluded, hasLength(2));
    expect(tally.planned, hasLength(1));
    expect(tally.futureActual, hasLength(1));
    expect(tally.gapDays, tally.windowLength);
  });

  test('an unknown status fails closed and a traveler status can count', () {
    final unknown = count([
      stay(
        country: 'PT',
        start: '2026-01-01',
        end: '2026-01-01',
        evidence: 'passport_stamp',
      ),
    ]);
    expect(unknown.primaryCountryDays, 0);
    final custom = defaultEvidenceStatuses.followedBy([
      const EvidenceStatusDef(
        id: 'passport_stamp',
        label: 'Passport stamp',
        countsAsActual: true,
      ),
    ]).toList();
    final counted = count([
      stay(
        country: 'PT',
        start: '2026-01-01',
        end: '2026-01-01',
        evidence: 'passport_stamp',
      ),
    ], statusList: custom);
    expect(counted.primaryDays['PT'], 1);
  });

  test('opting in to inferences counts them and still skips booking only', () {
    final rows = [
      stay(
        country: 'FR',
        start: '2026-08-21',
        end: '2026-08-21',
        inference: InferenceKind.inferredItinerary,
      ),
      stay(
        country: 'FR',
        start: '2026-08-22',
        end: '2026-08-22',
        evidence: 'booking_only',
      ),
    ];
    final included = count(
      rows,
      counting: const CountingRules(includeInferred: true),
    );
    expect(included.primaryDays['FR'], 1);
    expect(included.excluded.single.stay.evidenceStatus, 'booking_only');
  });

  test('today counts and tomorrow does not', () {
    final tally = count([
      stay(country: 'MX', start: '2026-11-08', end: '2026-11-09'),
    ]);
    expect(tally.primaryDays['MX'], 1);
    final tomorrow = tally.days.singleWhere(
      (day) => day.date == LocalDate(2026, 11, 9),
    );
    expect(tomorrow.kind, DayKind.future);
  });

  test('a gap between two stays is left empty', () {
    final tally = count([
      stay(country: 'PT', start: '2026-01-01', end: '2026-01-02'),
      stay(country: 'PT', start: '2026-01-05', end: '2026-01-05'),
    ]);
    final gap = tally.days.singleWhere(
      (day) => day.date == LocalDate(2026, 1, 3),
    );
    expect(gap.kind, DayKind.gap);
    expect(
      tally.gapRanges.any((range) => range.contains(LocalDate(2026, 1, 4))),
      isTrue,
    );
  });

  test('personal marker is unset by default', () {
    expect(CountingRules.standard.personalDayMarker, isNull);
    expect(CountingRules.standard.includeInferred, isFalse);
  });
}
