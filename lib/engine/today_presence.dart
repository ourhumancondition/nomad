import '../data/countries.dart';
import 'day_engine.dart';
import 'local_date.dart';
import 'models.dart';

/// How today's country was reached.
enum TodayStatus {
  /// A counting stay covers today.
  confirmed,

  /// A qualifying flight bracket covers today's wake-up.
  fromFlights,

  /// The wake time is spent in the air, or a stay records it in transit.
  inTransit,

  /// Two wake-up countries overlap today.
  conflict,

  /// Nothing counts today.
  unknown,
}

/// What the Today banner shows. Read-only: building one writes nothing.
class TodayPresence {
  const TodayPresence({
    required this.date,
    required this.status,
    required this.sourceLabel,
    this.countryCode,
    this.dayCountThisYear = 0,
    this.sinceDate,
    this.conflictCountries = const [],
    this.conflictingStays = const [],
    this.likelyCountry,
  });

  /// The traveler's local calendar date.
  final LocalDate date;
  final TodayStatus status;

  /// ISO alpha-2 code, or null when today has no single wake-up country.
  final String? countryCode;

  /// Counted wake-up days in [countryCode] from 1 January through today.
  final int dayCountThisYear;

  /// First day of the unbroken run in [countryCode] that reaches today.
  final LocalDate? sinceDate;

  /// A short human reason, e.g. "Confirmed stay".
  final String sourceLabel;

  /// Countries that overlap today when [status] is [TodayStatus.conflict].
  final List<String> conflictCountries;

  /// Stored stays behind a conflict, so the banner can point at them.
  final List<Stay> conflictingStays;

  /// A suggestion for an unknown day. Never counted, never saved on its own.
  final String? likelyCountry;

  String? get countryName =>
      countryCode == null ? null : countryNames[countryCode] ?? countryCode;

  /// The country "Yes, I'm here" would confirm, if the banner should offer it.
  String? get confirmCandidate => switch (status) {
    TodayStatus.fromFlights => countryCode,
    TodayStatus.unknown => likelyCountry,
    _ => null,
  };
}

/// Resolves today from the device clock.
///
/// [now] is read in the device's time zone. A UTC instant is converted to
/// local time first, so late evening never slides into tomorrow's date.
TodayPresence resolveToday(
  DateTime now, {
  required List<Stay> stays,
  required List<FlightRecord> flights,
  required CountingRules rules,
  required List<EvidenceStatusDef> statuses,
}) {
  return resolveTodayOn(
    LocalDate.fromDateTime(now.isUtc ? now.toLocal() : now),
    stays: stays,
    flights: flights,
    rules: rules,
    statuses: statuses,
  );
}

/// Resolves [today] with the same engine the year totals use.
///
/// This does not count anything itself. It reads today's entry from
/// [DayEngine.tally], so the banner and the totals cannot disagree.
TodayPresence resolveTodayOn(
  LocalDate today, {
  required List<Stay> stays,
  required List<FlightRecord> flights,
  required CountingRules rules,
  required List<EvidenceStatusDef> statuses,
}) {
  YearTally tallyFor(int year) => DayEngine.tally(
    stays: stays,
    flights: flights,
    year: year,
    today: today,
    rules: rules,
    statuses: statuses,
  );

  final tally = tallyFor(today.year);
  final day = tally.days.firstWhere((item) => item.date == today);

  switch (day.kind) {
    case DayKind.primaryCountry:
      final code = day.primaryCountry!;
      return TodayPresence(
        date: today,
        status: day.fromFlights
            ? TodayStatus.fromFlights
            : TodayStatus.confirmed,
        countryCode: code,
        dayCountThisYear: tally.primaryDays[code] ?? 0,
        sinceDate: _runStart(today, code, tally, tallyFor),
        sourceLabel: day.fromFlights
            ? _flightSource(today, code, tally)
            : _staySource(today, code, stays, rules, statuses),
      );
    case DayKind.inTransit:
      return TodayPresence(
        date: today,
        status: TodayStatus.inTransit,
        sourceLabel: day.fromFlights
            ? 'From flights: airborne at ${rules.wakeLabel}'
            : 'Recorded in transit at wake-up',
      );
    case DayKind.overlap:
      final countries = day.overlapCountries;
      return TodayPresence(
        date: today,
        status: TodayStatus.conflict,
        conflictCountries: countries,
        conflictingStays: [
          for (final stay in stays)
            if (stay.covers(today) &&
                stay.phase == TripPhase.actual &&
                stay.role == PresenceRole.primary &&
                countries.contains(stay.countryCode))
              stay,
        ],
        sourceLabel: day.fromFlights
            ? 'Flights put you in ${_names(countries)}'
            : 'Stays in ${_names(countries)} both cover today',
      );
    case DayKind.gap:
    case DayKind.future:
      return TodayPresence(
        date: today,
        status: TodayStatus.unknown,
        likelyCountry: _likelyCountry(today, stays, flights, tally),
        sourceLabel: 'No record for today',
      );
  }
}

String _names(List<String> codes) =>
    codes.map((code) => countryNames[code] ?? code).join(' and ');

/// Walks back through counted days, crossing into earlier years if needed.
LocalDate _runStart(
  LocalDate today,
  String code,
  YearTally tally,
  YearTally Function(int year) tallyFor,
) {
  var current = tally;
  var start = today;
  // A run longer than a few years is not plausible; stop at five.
  for (var guard = 0; guard < 5; guard++) {
    final byDate = {for (final day in current.days) day.date: day};
    var date = start.addDays(-1);
    while (date.year == current.year) {
      final day = byDate[date];
      if (day == null ||
          day.kind != DayKind.primaryCountry ||
          day.primaryCountry != code) {
        return start;
      }
      start = date;
      date = date.addDays(-1);
    }
    if (date.year < 1) return start;
    current = tallyFor(date.year);
  }
  return start;
}

String _staySource(
  LocalDate today,
  String code,
  List<Stay> stays,
  CountingRules rules,
  List<EvidenceStatusDef> statuses,
) {
  for (final stay in stays) {
    if (!stay.covers(today)) continue;
    if (stay.role != PresenceRole.primary || stay.countryCode != code) continue;
    if (!DayEngine.countsAsActual(stay, rules, statuses)) continue;
    final status = DayEngine.statusFor(stay.evidenceStatus, statuses);
    return '${status?.label ?? 'Counted'} stay';
  }
  return 'Counted stay';
}

String _flightSource(LocalDate today, String code, YearTally tally) {
  for (final bracket in tally.appliedBrackets) {
    if (bracket.countryCode != code) continue;
    if (today < bracket.start || today > bracket.end) continue;
    final landed = bracket.landedOn;
    final base = landed == null
        ? 'From flights: ${bracket.arrivalNumber}'
        : 'From flights: landed ${bracket.arrivalNumber} on ${_monthDay(landed)}';
    final leftFrom = bracket.leftFrom;
    return leftFrom == null ? base : '$base (left from $leftFrom)';
  }
  return 'From flights';
}

/// A country to offer on an unknown day. It is only a suggestion.
///
/// Prefers a stay that covers today but does not count (for example a
/// booking), then the arrival of the latest flight that landed on or before
/// today, then yesterday's counted country.
String? _likelyCountry(
  LocalDate today,
  List<Stay> stays,
  List<FlightRecord> flights,
  YearTally tally,
) {
  for (final stay in stays) {
    if (stay.phase != TripPhase.actual) continue;
    if (stay.role != PresenceRole.primary) continue;
    if (stay.countryCode.isEmpty || !stay.covers(today)) continue;
    return stay.countryCode;
  }
  FlightRecord? latest;
  for (final flight in flights) {
    if (flight.reviewState == FlightReviewState.rejected) continue;
    if (flight.arrive.date > today) continue;
    if (latest == null || compareFlights(flight, latest) > 0) latest = flight;
  }
  if (latest != null) return latest.toCountry;
  final yesterday = today.addDays(-1);
  for (final day in tally.days) {
    if (day.date == yesterday && day.kind == DayKind.primaryCountry) {
      return day.primaryCountry;
    }
  }
  return null;
}

const _shortMonths = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _monthDay(LocalDate date) =>
    '${_shortMonths[date.month - 1]} ${date.day}';

/// "Nov 9" style date for the banner, matching the issue's wording.
String todayMonthDay(LocalDate date) => _monthDay(date);
