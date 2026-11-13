import '../data/countries.dart';
import '../engine/day_engine.dart';
import '../engine/flight_brackets.dart';
import '../engine/local_date.dart';
import '../engine/models.dart';
import 'format.dart';

/// Plain totals for the home screen.
///
/// A country's days are the engine's wake-up total for that country: stored
/// stays and qualifying flight brackets already added together. Nothing here
/// applies a second counting rule.
class CountryPresence {
  const CountryPresence({
    required this.countries,
    required this.knownDays,
    required this.unknownDays,
    required this.daysInAir,
    required this.unclearDays,
    required this.stopovers,
    required this.nightsOnPlanes,
    required this.guessedDays,
    required this.unconfirmedBookingDays,
    required this.unknownRanges,
    required this.flightAssumptions,
    required this.start,
    required this.end,
    required this.rolling,
    required this.year,
  });

  final List<CountryDays> countries;
  final int knownDays;
  final int unknownDays;
  final int daysInAir;
  final int unclearDays;
  final int stopovers;
  final int nightsOnPlanes;
  final int guessedDays;
  final int unconfirmedBookingDays;
  final List<DateRange> unknownRanges;
  final List<FlightAssumption> flightAssumptions;
  final LocalDate? start;
  final LocalDate? end;
  final bool rolling;
  final int year;

  bool get hasWindow => start != null && end != null;
}

/// A counted stretch whose closing flight left a different country.
class FlightAssumption {
  const FlightAssumption({
    required this.id,
    required this.sentence,
    required this.leftName,
    required this.start,
    required this.end,
  });

  final String id;
  final String sentence;
  final String leftName;
  final LocalDate start;
  final LocalDate end;
}

class CountryDays {
  const CountryDays({
    required this.code,
    required this.name,
    required this.flag,
    required this.days,
  });

  final String code;
  final String name;
  final String flag;
  final int days;
}

/// First civil date of a last-12-months window that ends on [today].
///
/// The window is the day after the same calendar date one year earlier,
/// through [today]. 29 February uses the last real day of February when
/// the previous year has no leap day.
LocalDate rollingStart(LocalDate today) {
  final year = today.year - 1;
  final day = today.day.clamp(1, LocalDate.daysInMonth(year, today.month));
  return LocalDate(year, today.month, day).addDays(1);
}

CountryPresence summarizePresence({
  required List<Stay> stays,
  required List<FlightRecord> flights,
  required CountingRules rules,
  required List<EvidenceStatusDef> statuses,
  required LocalDate today,
  required int year,
  required bool rolling,
}) {
  final tallies = _tallies(
    stays: stays,
    flights: flights,
    rules: rules,
    statuses: statuses,
    today: today,
    year: year,
    rolling: rolling,
  );
  final start = rolling ? rollingStart(today) : _single(tallies)?.windowStart;
  final end = rolling ? today : _single(tallies)?.windowEnd;
  return _summarize(
    tallies: tallies,
    stays: stays,
    rules: rules,
    statuses: statuses,
    start: start,
    end: end,
    rolling: rolling,
    year: year,
  );
}

/// Pending trips that are not counted yet, and that would add country days
/// in this period if they were confirmed.
///
/// Confirmation here means the same acceptance the year total already uses.
/// The check runs that total twice and keeps the trips that explain the
/// new days. It does not invent a count.
List<FlightRecord> tripsToConfirm({
  required List<Stay> stays,
  required List<FlightRecord> flights,
  required CountingRules rules,
  required List<EvidenceStatusDef> statuses,
  required LocalDate today,
  required int year,
  required bool rolling,
}) {
  final presence = summarizePresence(
    stays: stays,
    flights: flights,
    rules: rules,
    statuses: statuses,
    today: today,
    year: year,
    rolling: rolling,
  );
  if (presence.start == null || presence.end == null) return const [];

  final candidates = <String, FlightRecord>{};
  for (final flight in flights) {
    if (flight.reviewState != FlightReviewState.pending) continue;
    if (flightQualifiesForBracket(flight, statuses)) continue;
    if (flight.arrive.date < flight.depart.date) continue;
    candidates[flight.id] = flight;
  }
  if (candidates.isEmpty) return const [];

  final before = _primaryDates(
    stays: stays,
    flights: flights,
    rules: rules,
    statuses: statuses,
    today: today,
    year: year,
    rolling: rolling,
  );
  final imagined = [
    for (final flight in flights)
      candidates.containsKey(flight.id)
          ? flight.copyWith(reviewState: FlightReviewState.accepted)
          : flight,
  ];
  final after = _primaryDaysInWindow(
    stays: stays,
    flights: imagined,
    rules: rules,
    statuses: statuses,
    today: today,
    year: year,
    rolling: rolling,
  );
  final fresh = after
      .where((day) => !before.contains(day.date))
      .toList(growable: false);
  if (fresh.isEmpty) return const [];

  final plan = planFlightBrackets(
    flights: imagined,
    rules: rules,
    statuses: statuses,
  );
  final chosen = <String, FlightRecord>{};
  for (final bracket in plan.brackets) {
    final adds = fresh.any(
      (day) =>
          day.primaryCountry == bracket.countryCode && bracket.covers(day.date),
    );
    if (!adds) continue;
    for (final end in [bracket.inbound, bracket.outbound]) {
      final pending = candidates[end.id];
      if (pending != null) chosen[end.id] = pending;
    }
  }
  final list = chosen.values.toList()..sort(compareFlights);
  return list;
}

String unknownSentence(int days) {
  if (days == 1) return "We don't know where you were on 1 day";
  return "We don't know where you were on $days days";
}

String confirmTripsSentence(int trips) {
  final noun = trips == 1 ? 'trip' : 'trips';
  return 'Confirm $trips $noun to count more days';
}

String daysPhrase(int count) {
  final noun = count == 1 ? 'day' : 'days';
  return '$count $noun';
}

List<String> countingNotes(CountryPresence presence) {
  final notes = <String>[
    'The number by each country is every day we can place you there. Days you saved and days from trips you already confirmed are added together.',
  ];
  if (presence.guessedDays > 0) {
    notes.add(
      '${daysPhrase(presence.guessedDays)} ${presence.guessedDays == 1 ? 'is' : 'are'} only a guess, so ${presence.guessedDays == 1 ? 'it is' : 'they are'} left out.',
    );
  }
  if (presence.unconfirmedBookingDays > 0) {
    notes.add(
      '${daysPhrase(presence.unconfirmedBookingDays)} ${presence.unconfirmedBookingDays == 1 ? 'is a booking' : 'are bookings'} you have not confirmed, so ${presence.unconfirmedBookingDays == 1 ? 'it is' : 'they are'} left out.',
    );
  }
  if (presence.daysInAir > 0) {
    notes.add(
      '${daysPhrase(presence.daysInAir)} you were in the air when the day started. ${presence.daysInAir == 1 ? 'That day is' : 'Those days are'} not added to a country.',
    );
  }
  if (presence.stopovers > 0) {
    notes.add(
      '${presence.stopovers == 1 ? '1 stopover is' : '${presence.stopovers} stopovers are'} listed and ${presence.stopovers == 1 ? 'is' : 'are'} not an extra day.',
    );
  }
  if (presence.nightsOnPlanes > 0) {
    notes.add(
      '${presence.nightsOnPlanes == 1 ? '1 night' : '${presence.nightsOnPlanes} nights'} on a plane ${presence.nightsOnPlanes == 1 ? 'is' : 'are'} not added.',
    );
  }
  if (presence.unclearDays > 0) {
    notes.add(
      '${daysPhrase(presence.unclearDays)} had two countries, so neither was chosen.',
    );
  }
  notes.add('None of those extras are included in the country numbers above.');
  return notes;
}

CountryPresence _summarize({
  required List<YearTally> tallies,
  required List<Stay> stays,
  required CountingRules rules,
  required List<EvidenceStatusDef> statuses,
  required LocalDate? start,
  required LocalDate? end,
  required bool rolling,
  required int year,
}) {
  final byCountry = <String, int>{};
  final gapDates = <LocalDate>[];
  final byDate = <LocalDate, DayAssignment>{};
  var inAir = 0;
  var unclear = 0;
  var stopovers = 0;
  var nights = 0;

  for (final tally in tallies) {
    for (final day in tally.days) {
      if (start == null || end == null) continue;
      if (day.date < start || day.date > end) continue;
      if (day.kind == DayKind.future) continue;
      byDate[day.date] = day;
      switch (day.kind) {
        case DayKind.primaryCountry:
          final code = day.primaryCountry;
          if (code != null && code.isNotEmpty) {
            byCountry[code] = (byCountry[code] ?? 0) + 1;
          }
        case DayKind.inTransit:
          inAir += 1;
        case DayKind.gap:
          gapDates.add(day.date);
        case DayKind.overlap:
          unclear += 1;
        case DayKind.future:
          break;
      }
      stopovers += day.layoverCountries.length;
      if (day.overnight) nights += 1;
    }
  }
  gapDates.sort();

  final countries =
      [
        for (final entry in byCountry.entries)
          if (entry.value > 0)
            CountryDays(
              code: entry.key,
              name: countryName(entry.key),
              flag: countryFlag(entry.key),
              days: entry.value,
            ),
      ]..sort((a, b) {
        final byDays = b.days.compareTo(a.days);
        if (byDays != 0) return byDays;
        final byName = a.name.compareTo(b.name);
        if (byName != 0) return byName;
        return a.code.compareTo(b.code);
      });

  final known = countries.fold<int>(0, (sum, country) => sum + country.days);
  return CountryPresence(
    countries: countries,
    knownDays: known,
    unknownDays: gapDates.length,
    daysInAir: inAir,
    unclearDays: unclear,
    stopovers: stopovers,
    nightsOnPlanes: nights,
    guessedDays: _guessedDays(
      stays: stays,
      byDate: byDate,
      start: start,
      end: end,
      rules: rules,
      statuses: statuses,
    ),
    unconfirmedBookingDays: _unconfirmedBookingDays(
      stays: stays,
      byDate: byDate,
      start: start,
      end: end,
      rules: rules,
      statuses: statuses,
    ),
    unknownRanges: _ranges(gapDates),
    flightAssumptions: _assumptions(tallies, start, end),
    start: start,
    end: end,
    rolling: rolling,
    year: year,
  );
}

List<YearTally> _tallies({
  required List<Stay> stays,
  required List<FlightRecord> flights,
  required CountingRules rules,
  required List<EvidenceStatusDef> statuses,
  required LocalDate today,
  required int year,
  required bool rolling,
}) {
  final years = rolling
      ? [for (var y = rollingStart(today).year; y <= today.year; y++) y]
      : [year];
  return [
    for (final item in years)
      DayEngine.tally(
        stays: stays,
        flights: flights,
        year: item,
        today: today,
        rules: rules,
        statuses: statuses,
      ),
  ];
}

YearTally? _single(List<YearTally> tallies) =>
    tallies.length == 1 ? tallies.single : null;

Set<LocalDate> _primaryDates({
  required List<Stay> stays,
  required List<FlightRecord> flights,
  required CountingRules rules,
  required List<EvidenceStatusDef> statuses,
  required LocalDate today,
  required int year,
  required bool rolling,
}) {
  return {
    for (final day in _primaryDaysInWindow(
      stays: stays,
      flights: flights,
      rules: rules,
      statuses: statuses,
      today: today,
      year: year,
      rolling: rolling,
    ))
      day.date,
  };
}

List<DayAssignment> _primaryDaysInWindow({
  required List<Stay> stays,
  required List<FlightRecord> flights,
  required CountingRules rules,
  required List<EvidenceStatusDef> statuses,
  required LocalDate today,
  required int year,
  required bool rolling,
}) {
  final tallies = _tallies(
    stays: stays,
    flights: flights,
    rules: rules,
    statuses: statuses,
    today: today,
    year: year,
    rolling: rolling,
  );
  final start = rolling ? rollingStart(today) : tallies.single.windowStart;
  final end = rolling ? today : tallies.single.windowEnd;
  if (start == null || end == null) return const [];
  final days = <DayAssignment>[];
  for (final tally in tallies) {
    for (final day in tally.days) {
      if (day.date < start || day.date > end) continue;
      if (day.kind == DayKind.primaryCountry) days.add(day);
    }
  }
  return days;
}

int _guessedDays({
  required List<Stay> stays,
  required Map<LocalDate, DayAssignment> byDate,
  required LocalDate? start,
  required LocalDate? end,
  required CountingRules rules,
  required List<EvidenceStatusDef> statuses,
}) {
  if (start == null || end == null) return 0;
  final dates = <LocalDate>{};
  for (final stay in stays) {
    if (stay.role != PresenceRole.primary) continue;
    if (stay.phase != TripPhase.actual) continue;
    if (!stay.inference.isInference) continue;
    if (DayEngine.countsAsActual(stay, rules, statuses)) continue;
    final from = stay.start > start ? stay.start : start;
    final to = stay.end < end ? stay.end : end;
    if (to < from) continue;
    for (var date = from; date <= to; date = date.addDays(1)) {
      final day = byDate[date];
      if (day != null && day.kind == DayKind.primaryCountry) continue;
      dates.add(date);
    }
  }
  return dates.length;
}

int _unconfirmedBookingDays({
  required List<Stay> stays,
  required Map<LocalDate, DayAssignment> byDate,
  required LocalDate? start,
  required LocalDate? end,
  required CountingRules rules,
  required List<EvidenceStatusDef> statuses,
}) {
  if (start == null || end == null) return 0;
  final dates = <LocalDate>{};
  for (final stay in stays) {
    if (stay.evidenceStatus != 'booking_only') continue;
    if (stay.role != PresenceRole.primary) continue;
    if (stay.phase != TripPhase.actual) continue;
    if (DayEngine.countsAsActual(stay, rules, statuses)) continue;
    final from = stay.start > start ? stay.start : start;
    final to = stay.end < end ? stay.end : end;
    if (to < from) continue;
    for (var date = from; date <= to; date = date.addDays(1)) {
      final day = byDate[date];
      if (day != null &&
          day.kind == DayKind.primaryCountry &&
          day.primaryCountry == stay.countryCode) {
        continue;
      }
      dates.add(date);
    }
  }
  return dates.length;
}

List<FlightAssumption> _assumptions(
  List<YearTally> tallies,
  LocalDate? start,
  LocalDate? end,
) {
  final notes = <String, FlightAssumption>{};
  for (final tally in tallies) {
    for (final bracket in tally.appliedBrackets) {
      final left = bracket.leftFrom;
      final landedOn = bracket.landedOn;
      final leftOn = bracket.leftOn;
      if (left == null || landedOn == null || leftOn == null) continue;
      if (bracket.days <= 0) continue;
      if (start != null &&
          end != null &&
          (bracket.end < start || bracket.start > end)) {
        continue;
      }
      final id =
          '${bracket.arrivalNumber}-${bracket.departureNumber}-${bracket.countryCode}-$left';
      final landed = countryName(bracket.countryCode);
      final leftName = countryName(left);
      final existing = notes[id];
      final spanStart = existing == null || bracket.start < existing.start
          ? bracket.start
          : existing.start;
      final spanEnd = existing == null || bracket.end > existing.end
          ? bracket.end
          : existing.end;
      notes[id] = FlightAssumption(
        id: id,
        leftName: leftName,
        start: spanStart,
        end: spanEnd,
        sentence:
            'You landed in $landed on ${shortDate(landedOn)} and next flew out of $leftName on ${shortDate(leftOn)}; we counted these days as $landed.',
      );
    }
  }
  final list = notes.values.toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  return list;
}

List<DateRange> _ranges(List<LocalDate> dates) {
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
