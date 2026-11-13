import 'flight_brackets.dart';
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
    this.fromFlights = false,
    this.flightLabel,
  });

  final LocalDate date;
  final DayKind kind;
  final String? primaryCountry;
  final List<String> overlapCountries;
  final List<String> layoverCountries;
  final bool overnight;
  final List<String> plannedCountries;
  final List<String> futureActualCountries;

  /// True when this morning was assigned from a qualifying flight rather
  /// than from a stored stay.
  final bool fromFlights;

  /// Flight numbers that produced [fromFlights], when there are any.
  final String? flightLabel;
}

class ExcludedCoverage {
  const ExcludedCoverage({
    required this.stay,
    required this.reason,
    required this.daysInWindow,
    this.morningsAlreadyCounted = 0,
  });

  final Stay stay;
  final String reason;
  final int daysInWindow;

  /// In-window mornings of this stay that the wake-up total already includes.
  final int morningsAlreadyCounted;
}

class OverlapSpan {
  const OverlapSpan({required this.range, required this.countries});

  final DateRange range;
  final List<String> countries;
}

/// Wake-ups a flight bracket contributed inside the year window.
class AppliedFlightBracket {
  const AppliedFlightBracket({
    required this.countryCode,
    required this.start,
    required this.end,
    required this.days,
    required this.arrivalNumber,
    required this.departureNumber,
    this.leftFrom,
    this.landedOn,
    this.leftOn,
  });

  final String countryCode;
  final LocalDate start;
  final LocalDate end;
  final int days;
  final String arrivalNumber;
  final String departureNumber;

  /// Country the closing flight left, when that is not [countryCode].
  final String? leftFrom;

  /// Civil arrival date of the opening flight, when this came from flights.
  final LocalDate? landedOn;

  /// Civil departure date of the closing flight, when this came from flights.
  final LocalDate? leftOn;
}

/// Dates a flight bracket would have given to [flightCountry] that a stored
/// stay in [stayCountry] kept.
class BracketConflict {
  const BracketConflict({
    required this.flightCountry,
    required this.stayCountry,
    required this.range,
  });

  final String flightCountry;
  final String stayCountry;
  final DateRange range;
}

/// A recorded in-transit wake-up that ends a flight bracket early.
class TransitInterruption {
  const TransitInterruption({
    required this.countryCode,
    required this.date,
    required this.arrivalNumber,
    required this.departureNumber,
  });

  final String countryCode;
  final LocalDate date;
  final String arrivalNumber;
  final String departureNumber;
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
    required this.stayPrimaryDays,
    required this.flightBracketDays,
    required this.appliedBrackets,
    required this.flightGaps,
    required this.bracketConflicts,
    required this.transitInterruptions,
    required this.inferredKeptOutDays,
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

  /// Wake-up days that came from a stored stay. Part of [primaryDays].
  final Map<String, int> stayPrimaryDays;

  /// Wake-up days counted from a qualifying flight bracket. Part of [primaryDays].
  final Map<String, int> flightBracketDays;

  final List<AppliedFlightBracket> appliedBrackets;
  final List<FlightGap> flightGaps;
  final List<BracketConflict> bracketConflicts;
  final List<TransitInterruption> transitInterruptions;

  /// Inferred primary mornings in this window that are not in the wake-up total.
  final int inferredKeptOutDays;

  int get windowLength => windowStart == null || windowEnd == null
      ? 0
      : windowEnd!.differenceInDays(windowStart!) + 1;

  int get flightBracketDayCount =>
      flightBracketDays.values.fold<int>(0, (sum, value) => sum + value);

  int get stayPrimaryDayCount =>
      stayPrimaryDays.values.fold<int>(0, (sum, value) => sum + value);

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

  /// Counts the year window.
  ///
  /// Stored stays are applied first. Qualifying flight brackets then fill
  /// mornings that are still empty, using the wake time and the civil dates
  /// on the tickets. A stored stay of a different country is left in place.
  /// [flights] defaults to empty, which keeps a stay-only tally unchanged.
  static YearTally tally({
    required List<Stay> stays,
    List<FlightRecord> flights = const [],
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

    bool inWindow(LocalDate date) =>
        windowStart != null &&
        windowEnd != null &&
        date >= windowStart &&
        date <= windowEnd;

    final plan = planFlightBrackets(
      flights: flights,
      rules: rules,
      statuses: statuses,
    );
    final clips = <_FlightClip>[];
    final interruptions = <TransitInterruption>[];
    for (final bracket in plan.brackets) {
      var end = bracket.end;
      final leftFrom = bracket.leftFrom;
      if (leftFrom != null) {
        final stayed = _earliestPrimaryStay(
          stays,
          leftFrom,
          bracket.start,
          bracket.end,
        );
        if (stayed != null) {
          final clipped = stayed.addDays(-1);
          if (clipped < end) end = clipped;
        }
      }
      LocalDate? transitOn;
      for (final stay in stays) {
        if (stay.phase != TripPhase.actual) continue;
        if (stay.role != PresenceRole.transitWake) continue;
        if (stay.end < bracket.start || stay.start > bracket.end) continue;
        final overlapStart = stay.start > bracket.start
            ? stay.start
            : bracket.start;
        if (transitOn == null || overlapStart < transitOn) {
          transitOn = overlapStart;
          final transitEnd = overlapStart.addDays(-1);
          if (transitEnd < end) end = transitEnd;
        }
      }
      clips.add(_FlightClip(bracket, end));
      if (transitOn != null && inWindow(transitOn)) {
        interruptions.add(
          TransitInterruption(
            countryCode: bracket.countryCode,
            date: transitOn,
            arrivalNumber: bracket.inbound.flightNumber,
            departureNumber: bracket.outbound.flightNumber,
          ),
        );
      }
    }

    final primaryDays = <String, int>{};
    final stayPrimaryDays = <String, int>{};
    final flightBracketDays = <String, int>{};
    final layoverDays = <String, int>{};
    final assignments = <DayAssignment>[];
    final gapDates = <LocalDate>[];
    final overlapGroups = <OverlapSpan>[];
    final conflictBuckets = <String, List<LocalDate>>{};
    var transitWakeDays = 0;
    var gapCount = 0;
    var overlapCount = 0;
    var overnightNights = 0;

    void noteConflict(
      String flightCountry,
      String stayCountry,
      LocalDate date,
    ) {
      if (stayCountry.isEmpty || stayCountry == flightCountry) return;
      final bucket = conflictBuckets['$flightCountry|$stayCountry'] ??=
          <LocalDate>[];
      if (bucket.isNotEmpty && bucket.last == date) return;
      bucket.add(date);
    }

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
      final hits = <_FlightClip>[
        for (final clip in clips)
          if (clip.covers(date)) clip,
      ];

      var kind = DayKind.gap;
      String? primary;
      var fromFlights = false;
      String? flightLabel;
      var overlapCountries = primaries.length > 1
          ? List<String>.unmodifiable(primaries)
          : const <String>[];

      if (primaries.length > 1) {
        kind = DayKind.overlap;
      } else if (primaries.length == 1) {
        kind = DayKind.primaryCountry;
        primary = primaries.single;
      } else if (transitWake) {
        kind = DayKind.inTransit;
      } else {
        final open = <_FlightClip>[
          for (final clip in hits)
            if (!_otherCountryStay(covering, clip.bracket.countryCode)) clip,
        ];
        final blocked = hits.isNotEmpty && open.isEmpty;
        if (!blocked && plan.airborneAt(date)) {
          kind = DayKind.inTransit;
          fromFlights = true;
          flightLabel = 'Airborne at the wake time';
        } else if (!blocked && open.isNotEmpty) {
          final countries =
              open.map((clip) => clip.bracket.countryCode).toSet().toList()
                ..sort();
          if (countries.length == 1) {
            kind = DayKind.primaryCountry;
            primary = countries.single;
            fromFlights = true;
            final clip = open.firstWhere(
              (item) => item.bracket.countryCode == primary,
            );
            flightLabel =
                '${clip.bracket.inbound.flightNumber} to ${clip.bracket.outbound.flightNumber}';
            final leftFrom = clip.bracket.leftFrom;
            if (leftFrom != null) {
              flightLabel = '$flightLabel (left from $leftFrom)';
            }
            clip.counted.add(date);
          } else {
            kind = DayKind.overlap;
            overlapCountries = List<String>.unmodifiable(countries);
            fromFlights = true;
          }
        }
      }

      if (kind == DayKind.overlap) {
        overlapCount += 1;
        if (overlapGroups.isNotEmpty &&
            overlapGroups.last.range.end.addDays(1) == date &&
            _sameCodes(overlapGroups.last.countries, overlapCountries)) {
          final last = overlapGroups.removeLast();
          overlapGroups.add(
            OverlapSpan(
              range: DateRange(last.range.start, date),
              countries: overlapCountries,
            ),
          );
        } else {
          overlapGroups.add(
            OverlapSpan(
              range: DateRange(date, date),
              countries: overlapCountries,
            ),
          );
        }
      } else if (kind == DayKind.primaryCountry) {
        final code = primary!;
        primaryDays[code] = (primaryDays[code] ?? 0) + 1;
        final source = fromFlights ? flightBracketDays : stayPrimaryDays;
        source[code] = (source[code] ?? 0) + 1;
      } else if (kind == DayKind.inTransit) {
        transitWakeDays += 1;
      } else {
        gapCount += 1;
        gapDates.add(date);
      }

      if (overnight) overnightNights += 1;
      for (final code in layovers) {
        if (primary != null && code == primary) continue;
        layoverDays[code] = (layoverDays[code] ?? 0) + 1;
      }

      for (final clip in hits) {
        final flightCountry = clip.bracket.countryCode;
        if (kind == DayKind.primaryCountry && primary == flightCountry) {
          continue;
        }
        if (kind == DayKind.inTransit && fromFlights) continue;
        if (kind == DayKind.primaryCountry &&
            primary != null &&
            primary != flightCountry) {
          noteConflict(flightCountry, primary, date);
          continue;
        }
        if (kind == DayKind.overlap && !fromFlights) {
          for (final code in overlapCountries) {
            if (code != flightCountry) noteConflict(flightCountry, code, date);
          }
          continue;
        }
        if (kind == DayKind.overlap) continue;
        for (final stay in covering) {
          if (stay.phase != TripPhase.actual) continue;
          if (stay.role != PresenceRole.primary) continue;
          if (stay.countryCode.isEmpty || stay.countryCode == flightCountry) {
            continue;
          }
          noteConflict(flightCountry, stay.countryCode, date);
        }
      }

      assignments.add(
        DayAssignment(
          date: date,
          kind: kind,
          primaryCountry: primary,
          overlapCountries: overlapCountries,
          layoverCountries: layovers
              .where((code) => code != primary)
              .toList(growable: false),
          overnight: overnight,
          fromFlights: fromFlights,
          flightLabel: flightLabel,
        ),
      );
    }

    final byDate = {for (final day in assignments) day.date: day};
    final excluded = <ExcludedCoverage>[];
    for (final stay in stays) {
      if (stay.phase != TripPhase.actual) continue;
      if (countsAsActual(stay, rules, statuses)) continue;
      final days = _daysInside(stay, windowStart, windowEnd);
      if (days == 0) continue;
      final already = _morningsAlreadyCounted(
        stay,
        byDate,
        windowStart,
        windowEnd,
      );
      var reason = exclusionReason(stay, rules, statuses);
      if (already > 0 && already == days) {
        reason = 'These mornings are already in the wake-up total, so this stored record is not added again.';
      } else if (already > 0) {
        reason =
            '$reason $already of these mornings are already in the wake-up total.';
      }
      excluded.add(
        ExcludedCoverage(
          stay: stay,
          reason: reason,
          daysInWindow: days,
          morningsAlreadyCounted: already,
        ),
      );
    }

    final inferredKeptOut = _inferredKeptOut(
      stays: stays,
      byDate: byDate,
      windowStart: windowStart,
      windowEnd: windowEnd,
      rules: rules,
      statuses: statuses,
    );

    final planned =
        stays.where((stay) => stay.phase == TripPhase.planned).toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    final futureActual = stays.where((stay) {
      if (stay.phase != TripPhase.actual) return false;
      return stay.end > today &&
          stay.start.year <= year &&
          stay.end.year >= year;
    }).toList()..sort((a, b) => a.start.compareTo(b.start));

    final applied = <AppliedFlightBracket>[];
    for (final clip in clips) {
      for (final range in _consecutive(clip.counted)) {
        applied.add(
          AppliedFlightBracket(
            countryCode: clip.bracket.countryCode,
            start: range.start,
            end: range.end,
            days: range.length,
            arrivalNumber: clip.bracket.inbound.flightNumber,
            departureNumber: clip.bracket.outbound.flightNumber,
            leftFrom: clip.bracket.leftFrom,
            landedOn: clip.bracket.inbound.arrive.date,
            leftOn: clip.bracket.outbound.depart.date,
          ),
        );
      }
    }

    final conflicts = <BracketConflict>[];
    for (final entry in conflictBuckets.entries) {
      final parts = entry.key.split('|');
      for (final range in _consecutive(entry.value)) {
        conflicts.add(
          BracketConflict(
            flightCountry: parts[0],
            stayCountry: parts[1],
            range: range,
          ),
        );
      }
    }

    final gaps = windowStart == null || windowEnd == null
        ? const <FlightGap>[]
        : plan.gaps
              .where((gap) => gap.overlaps(windowStart!, windowEnd!))
              .toList(growable: false);

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
      stayPrimaryDays: stayPrimaryDays,
      flightBracketDays: flightBracketDays,
      appliedBrackets: applied,
      flightGaps: gaps,
      bracketConflicts: conflicts,
      transitInterruptions: interruptions,
      inferredKeptOutDays: inferredKeptOut,
    );
  }

  static int _morningsAlreadyCounted(
    Stay stay,
    Map<LocalDate, DayAssignment> byDate,
    LocalDate? windowStart,
    LocalDate? windowEnd,
  ) {
    if (windowStart == null || windowEnd == null) return 0;
    if (stay.role != PresenceRole.primary || stay.countryCode.isEmpty) {
      return 0;
    }
    final start = stay.start > windowStart ? stay.start : windowStart;
    final end = stay.end < windowEnd ? stay.end : windowEnd;
    if (end < start) return 0;
    var counted = 0;
    for (var date = start; date <= end; date = date.addDays(1)) {
      final day = byDate[date];
      if (day != null &&
          day.kind == DayKind.primaryCountry &&
          day.primaryCountry == stay.countryCode) {
        counted += 1;
      }
    }
    return counted;
  }

  static int _inferredKeptOut({
    required List<Stay> stays,
    required Map<LocalDate, DayAssignment> byDate,
    required LocalDate? windowStart,
    required LocalDate? windowEnd,
    required CountingRules rules,
    required List<EvidenceStatusDef> statuses,
  }) {
    if (windowStart == null || windowEnd == null) return 0;
    final dates = <LocalDate>{};
    for (final stay in stays) {
      if (stay.role != PresenceRole.primary) continue;
      if (stay.phase != TripPhase.actual) continue;
      if (!stay.inference.isInference) continue;
      if (countsAsActual(stay, rules, statuses)) continue;
      final start = stay.start > windowStart ? stay.start : windowStart;
      final end = stay.end < windowEnd ? stay.end : windowEnd;
      if (end < start) continue;
      for (var date = start; date <= end; date = date.addDays(1)) {
        final day = byDate[date];
        if (day != null && day.kind == DayKind.primaryCountry) continue;
        dates.add(date);
      }
    }
    return dates.length;
  }

  static LocalDate? _earliestPrimaryStay(
    List<Stay> stays,
    String country,
    LocalDate start,
    LocalDate end,
  ) {
    LocalDate? earliest;
    for (final stay in stays) {
      if (stay.phase != TripPhase.actual) continue;
      if (stay.role != PresenceRole.primary) continue;
      if (stay.countryCode != country) continue;
      if (stay.end < start || stay.start > end) continue;
      if (earliest == null || stay.start < earliest) earliest = stay.start;
    }
    return earliest;
  }

  static bool _otherCountryStay(List<Stay> covering, String country) {
    for (final stay in covering) {
      if (stay.phase != TripPhase.actual) continue;
      if (stay.role != PresenceRole.primary) continue;
      if (stay.countryCode.isEmpty || stay.countryCode == country) continue;
      return true;
    }
    return false;
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

  /// Primary days marked as inference that the actual total does not include.
  static int inferredPrimaryDays({
    required List<Stay> stays,
    required LocalDate? windowStart,
    required LocalDate? windowEnd,
    required CountingRules rules,
    required List<EvidenceStatusDef> statuses,
  }) {
    if (windowStart == null || windowEnd == null) return 0;
    final dates = <LocalDate>{};
    for (final stay in stays) {
      if (stay.role != PresenceRole.primary) continue;
      if (stay.phase != TripPhase.actual) continue;
      if (!stay.inference.isInference) continue;
      if (countsAsActual(stay, rules, statuses)) continue;
      final start = stay.start > windowStart ? stay.start : windowStart;
      final end = stay.end < windowEnd ? stay.end : windowEnd;
      if (end < start) continue;
      for (var date = start; date <= end; date = date.addDays(1)) {
        dates.add(date);
      }
    }
    return dates.length;
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

class _FlightClip {
  _FlightClip(this.bracket, this.end);

  final FlightBracket bracket;
  final LocalDate end;
  final List<LocalDate> counted = [];

  bool covers(LocalDate date) =>
      end >= bracket.start && date >= bracket.start && date <= end;
}
