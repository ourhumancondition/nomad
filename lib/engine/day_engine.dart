import 'local_date.dart';
import 'models.dart';

enum DayKind { primaryCountry, inTransit, gap, overlap, future }

class DayAssignment {
  const DayAssignment({
    required this.date,
    required this.kind,
    this.primaryCountry,
    this.overlapCountries = const [],
    this.layoverCountries = const [],
    this.overnight = false,
    this.plannedCountries = const [],
    this.futureActualCountries = const [],
  });

  final LocalDate date;
  final DayKind kind;
  final String? primaryCountry;
  final List<String> overlapCountries;
  final List<String> layoverCountries;
  final bool overnight;
  final List<String> plannedCountries;
  final List<String> futureActualCountries;
}

class ExcludedCoverage {
  const ExcludedCoverage({
    required this.stay,
    required this.reason,
    required this.daysInWindow,
  });

  final Stay stay;
  final String reason;
  final int daysInWindow;
}

class OverlapSpan {
  const OverlapSpan({required this.range, required this.countries});

  final DateRange range;
  final List<String> countries;
}

class YearTally {
  const YearTally({
    required this.year,
    required this.daysInYear,
    required this.windowStart,
    required this.windowEnd,
    required this.days,
    required this.primaryDays,
    required this.transitWakeDays,
    required this.gapDays,
    required this.overlapDays,
    required this.layoverDays,
    required this.overnightNights,
    required this.gapRanges,
    required this.overlapSpans,
    required this.excluded,
    required this.planned,
    required this.futureActual,
  });

  final int year;
  final int daysInYear;
  final LocalDate? windowStart;
  final LocalDate? windowEnd;
  final List<DayAssignment> days;
  final Map<String, int> primaryDays;
  final int transitWakeDays;
  final int gapDays;
  final int overlapDays;
  final Map<String, int> layoverDays;
  final int overnightNights;
  final List<DateRange> gapRanges;
  final List<OverlapSpan> overlapSpans;
  final List<ExcludedCoverage> excluded;
  final List<Stay> planned;
  final List<Stay> futureActual;

  int get windowLength => windowStart == null || windowEnd == null
      ? 0
      : windowEnd!.differenceInDays(windowStart!) + 1;

  int get primaryCountryDays =>
      primaryDays.values.fold<int>(0, (sum, value) => sum + value);

  int get assignedIdentity =>
      primaryCountryDays + transitWakeDays + gapDays + overlapDays;

  bool get identityHolds => assignedIdentity == windowLength;
}

class DayEngine {
  const DayEngine();

  static EvidenceStatusDef? statusFor(
    String id,
    List<EvidenceStatusDef> statuses,
  ) {
    for (final status in statuses) {
      if (status.id == id) return status;
    }
    return null;
  }

  /// Actual-phase records count only when the status is allowed to count
  /// and, for an inference, when the traveler has opted in.
  static bool countsAsActual(
    Stay stay,
    CountingRules rules,
    List<EvidenceStatusDef> statuses,
  ) {
    if (stay.phase != TripPhase.actual) return false;
    final status = statusFor(stay.evidenceStatus, statuses);
    if (status == null || !status.countsAsActual) return false;
    if (stay.inference.isInference && !rules.includeInferred) return false;
    return true;
  }

  static String exclusionReason(
    Stay stay,
    CountingRules rules,
    List<EvidenceStatusDef> statuses,
  ) {
    if (stay.phase == TripPhase.planned) {
      return 'Planned trips stay off the actual total.';
    }
    final status = statusFor(stay.evidenceStatus, statuses);
    if (status == null) {
      return 'Evidence status "${stay.evidenceStatus}" is not in your list, so these days stay uncounted.';
    }
    if (!status.countsAsActual) {
      if (status.id == 'booking_only') {
        return 'Booking-only records stay out of actual totals until you mark them confirmed or corroborated.';
      }
      return '${status.label} is set to stay out of actual totals.';
    }
    if (stay.inference.isInference && !rules.includeInferred) {
      return '${stay.inference.label} stays out of actual totals until you clear the inference mark or count inferences.';
    }
    return 'This record counts toward actual presence.';
  }

  static YearTally tally({
    required List<Stay> stays,
    required int year,
    required LocalDate today,
    required CountingRules rules,
    required List<EvidenceStatusDef> statuses,
  }) {
    final yearStart = LocalDate(year, 1, 1);
    final yearEnd = LocalDate(year, 12, LocalDate.daysInMonth(year, 12));
    LocalDate? windowStart;
    LocalDate? windowEnd;
    if (year < today.year) {
      windowStart = yearStart;
      windowEnd = yearEnd;
    } else if (year == today.year && today >= yearStart) {
      windowStart = yearStart;
      windowEnd = today < yearEnd ? today : yearEnd;
    }

    final primaryDays = <String, int>{};
    final layoverDays = <String, int>{};
    final assignments = <DayAssignment>[];
    final gapDates = <LocalDate>[];
    final overlapGroups = <OverlapSpan>[];
    var transitWakeDays = 0;
    var gapCount = 0;
    var overlapCount = 0;
    var overnightNights = 0;

    bool inWindow(LocalDate date) =>
        windowStart != null &&
        windowEnd != null &&
        date >= windowStart &&
        date <= windowEnd;

    for (var date = yearStart; date <= yearEnd; date = date.addDays(1)) {
      final covering = stays.where((stay) => stay.covers(date)).toList();
      if (!inWindow(date)) {
        final plannedCountries = <String>[];
        final futureCountries = <String>[];
        for (final stay in covering) {
          if (stay.role != PresenceRole.primary || stay.countryCode.isEmpty) {
            continue;
          }
          if (stay.phase == TripPhase.planned) {
            _addUnique(plannedCountries, stay.countryCode);
          } else {
            _addUnique(futureCountries, stay.countryCode);
          }
        }
        assignments.add(
          DayAssignment(
            date: date,
            kind: DayKind.future,
            plannedCountries: plannedCountries,
            futureActualCountries: futureCountries,
          ),
        );
        continue;
      }

      final countable = covering
          .where((stay) => countsAsActual(stay, rules, statuses))
          .toList();
      final primaries =
          countable
              .where((stay) => stay.role == PresenceRole.primary)
              .map((stay) => stay.countryCode)
              .where((code) => code.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      final layovers =
          countable
              .where((stay) => stay.role == PresenceRole.layover)
              .map((stay) => stay.countryCode)
              .where((code) => code.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      final overnight = countable.any(
        (stay) => stay.role == PresenceRole.transitNight,
      );
      final transitWake = countable.any(
        (stay) => stay.role == PresenceRole.transitWake,
      );

      late final DayKind kind;
      String? primary;
      if (primaries.length > 1) {
        kind = DayKind.overlap;
        overlapCount += 1;
      } else if (primaries.length == 1) {
        kind = DayKind.primaryCountry;
        primary = primaries.single;
        primaryDays[primary] = (primaryDays[primary] ?? 0) + 1;
      } else if (transitWake) {
        kind = DayKind.inTransit;
        transitWakeDays += 1;
      } else {
        kind = DayKind.gap;
        gapCount += 1;
        gapDates.add(date);
      }

      if (overnight) overnightNights += 1;
      final primaryCode = primary;
      for (final code in layovers) {
        if (primaryCode != null && code == primaryCode) continue;
        layoverDays[code] = (layoverDays[code] ?? 0) + 1;
      }

      if (kind == DayKind.overlap) {
        final countries = List<String>.unmodifiable(primaries);
        if (overlapGroups.isNotEmpty &&
            overlapGroups.last.range.end.addDays(1) == date &&
            _sameCodes(overlapGroups.last.countries, countries)) {
          final last = overlapGroups.removeLast();
          overlapGroups.add(
            OverlapSpan(
              range: DateRange(last.range.start, date),
              countries: countries,
            ),
          );
        } else {
          overlapGroups.add(
            OverlapSpan(range: DateRange(date, date), countries: countries),
          );
        }
      }

      assignments.add(
        DayAssignment(
          date: date,
          kind: kind,
          primaryCountry: primary,
          overlapCountries: primaries.length > 1 ? primaries : const [],
          layoverCountries: layovers
              .where((code) => code != primaryCode)
              .toList(growable: false),
          overnight: overnight,
        ),
      );
    }

    final excluded = <ExcludedCoverage>[];
    for (final stay in stays) {
      if (stay.phase != TripPhase.actual) continue;
      if (countsAsActual(stay, rules, statuses)) continue;
      final days = _daysInside(stay, windowStart, windowEnd);
      if (days == 0) continue;
      excluded.add(
        ExcludedCoverage(
          stay: stay,
          reason: exclusionReason(stay, rules, statuses),
          daysInWindow: days,
        ),
      );
    }

    final planned =
        stays.where((stay) => stay.phase == TripPhase.planned).toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    final futureActual = stays.where((stay) {
      if (stay.phase != TripPhase.actual) return false;
      return stay.end > today &&
          stay.start.year <= year &&
          stay.end.year >= year;
    }).toList()..sort((a, b) => a.start.compareTo(b.start));

    return YearTally(
      year: year,
      daysInYear: LocalDate.lengthOfYear(year),
      windowStart: windowStart,
      windowEnd: windowEnd,
      days: assignments,
      primaryDays: primaryDays,
      transitWakeDays: transitWakeDays,
      gapDays: gapCount,
      overlapDays: overlapCount,
      layoverDays: layoverDays,
      overnightNights: overnightNights,
      gapRanges: _consecutive(gapDates),
      overlapSpans: overlapGroups,
      excluded: excluded,
      planned: planned,
      futureActual: futureActual,
    );
  }

  static int _daysInside(
    Stay stay,
    LocalDate? windowStart,
    LocalDate? windowEnd,
  ) {
    if (windowStart == null || windowEnd == null) return 0;
    final start = stay.start > windowStart ? stay.start : windowStart;
    final end = stay.end < windowEnd ? stay.end : windowEnd;
    if (end < start) return 0;
    return end.differenceInDays(start) + 1;
  }

  static List<DateRange> _consecutive(List<LocalDate> dates) {
    if (dates.isEmpty) return const [];
    final ranges = <DateRange>[];
    var start = dates.first;
    var previous = dates.first;
    for (final date in dates.skip(1)) {
      if (previous.addDays(1) == date) {
        previous = date;
      } else {
        ranges.add(DateRange(start, previous));
        start = date;
        previous = date;
      }
    }
    ranges.add(DateRange(start, previous));
    return ranges;
  }

  static void _addUnique(List<String> values, String code) {
    if (!values.contains(code)) values.add(code);
  }

  static bool _sameCodes(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
