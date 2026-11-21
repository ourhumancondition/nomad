import '../data/airport_cities.dart';
import '../data/countries.dart';
import '../engine/flight_proposals.dart';
import '../engine/local_date.dart';
import '../engine/models.dart';
import '../engine/review_queue.dart';
import 'format.dart';

String reviewQueueSentence(int count) {
  if (count == 1) return '1 flight or stay needs a check';
  return '$count flights and stays need a check';
}

String stayHeadline(Stay stay) {
  final place = stay.countryCode.isEmpty
      ? 'In transit'
      : countryName(stay.countryCode);
  final days = stay.end.differenceInDays(stay.start) + 1;
  final noun = days == 1 ? 'day' : 'days';
  return 'Stay: $place, ${shortRange(stay.start, stay.end)} ($days $noun)';
}

String flightHeadline(FlightRecord flight) {
  final from = flightPlace(flight.fromIata, flight.fromCountry);
  final to = flightPlace(flight.toIata, flight.toCountry);
  final depart =
      '${shortDate(flight.depart.date)}, ${spokenClock(flight.depart)}';
  final arrive = flight.arrive.date == flight.depart.date
      ? spokenClock(flight.arrive)
      : '${shortDate(flight.arrive.date)}, ${spokenClock(flight.arrive)}';
  return 'Flight $from → $to, $depart → $arrive';
}

String flightPlace(String iata, String countryCode) {
  final country = countryName(countryCode);
  final city = airportCity(iata);
  if (city == null || city.toLowerCase() == country.toLowerCase()) {
    return country;
  }
  return '$city, $country';
}

/// What pressing Confirm does to the day total. It does not write.
String stayConfirmSentence({
  required Stay stay,
  required List<Stay> stays,
  required List<FlightRecord> flights,
  required CountingRules rules,
  required List<EvidenceStatusDef> statuses,
  required LocalDate today,
}) {
  if (stay.role == PresenceRole.layover) {
    final place = countryName(stay.countryCode);
    return 'Records a layover in $place, ${shortRange(stay.start, stay.end)}. That does not add a day in a country.';
  }
  if (stay.role == PresenceRole.transitWake ||
      stay.role == PresenceRole.transitNight ||
      stay.countryCode.isEmpty) {
    return 'Marks ${shortRange(stay.start, stay.end)} as time in transit. That does not add a day in a country.';
  }
  if (stay.inference.isInference && !rules.includeInferred) {
    return 'Records ${shortRange(stay.start, stay.end)} as ${countryName(stay.countryCode)}, and leaves those days out of the total while they are still marked as a guess.';
  }
  return _primarySentence(
    stay: stay,
    stays: stays,
    flights: flights,
    rules: rules,
    statuses: statuses,
    today: today,
    replace: true,
  );
}

/// What pressing Confirm does for one flight. It does not write.
///
/// [keepOut] is the "leave these days out of the total" option.
String flightConfirmSentence({
  required FlightRecord flight,
  required List<Stay> stays,
  required List<FlightRecord> flights,
  required CountingRules rules,
  required List<EvidenceStatusDef> statuses,
  required LocalDate today,
  bool keepOut = false,
}) {
  final proposals = proposeItinerary([
    flight,
  ], rules).where((proposal) => proposal.flightId == flight.id);
  final concrete = proposals
      .map((proposal) => proposal.stay)
      .whereType<Stay>()
      .toList();
  if (concrete.isEmpty) {
    return 'Confirming does not add a country day. You would still enter where you woke up.';
  }
  final parts = <String>[];
  for (final stay in concrete) {
    if (stay.role == PresenceRole.layover) {
      parts.add(
        'Records a layover in ${countryName(stay.countryCode)}, ${shortRange(stay.start, stay.end)}. That does not add a day in a country.',
      );
      continue;
    }
    if (stay.role != PresenceRole.primary || stay.countryCode.isEmpty) {
      parts.add(
        'Marks ${shortRange(stay.start, stay.end)} as time in transit. That does not add a day in a country.',
      );
      continue;
    }
    if (keepOut && !rules.includeInferred) {
      parts.add(
        'Suggests ${shortRange(stay.start, stay.end)} as ${countryName(stay.countryCode)}, and leaves those days out of the total.',
      );
      continue;
    }
    parts.add(
      _primarySentence(
        stay: stay,
        stays: stays,
        flights: flights,
        rules: rules,
        statuses: statuses,
        today: today,
        replace: false,
      ),
    );
  }
  return parts.join(' ');
}

String _primarySentence({
  required Stay stay,
  required List<Stay> stays,
  required List<FlightRecord> flights,
  required CountingRules rules,
  required List<EvidenceStatusDef> statuses,
  required LocalDate today,
  required bool replace,
}) {
  final place = countryName(stay.countryCode);
  final current = countedCountries(
    stays: stays,
    flights: flights,
    rules: rules,
    statuses: statuses,
    today: today,
    start: stay.start,
    end: stay.end,
  );
  final slices = <_Slice>[];
  _Slice? open;
  var anyFuture = false;
  var anyAlready = false;

  void close() {
    if (open != null) slices.add(open!);
    open = null;
  }

  for (var date = stay.start; date <= stay.end; date = date.addDays(1)) {
    if (date > today) {
      anyFuture = true;
      close();
      continue;
    }
    final countries = current[date] ?? const <String>[];
    final others = countries.where((code) => code != stay.countryCode).toList()
      ..sort();
    final ours = countries.contains(stay.countryCode);
    if (others.isEmpty && ours) {
      anyAlready = true;
      close();
      continue;
    }
    final kind = others.isEmpty
        ? 'count'
        : replace
        ? 'change'
        : 'unresolved';
    final key = others.join('|');
    if (open != null &&
        open!.kind == kind &&
        open!.fromKey == key &&
        open!.end.addDays(1) == date) {
      open!.end = date;
    } else {
      close();
      open = _Slice(kind, date, others);
    }
  }
  close();

  final parts = <String>[
    for (final slice in slices)
      switch (slice.kind) {
        'change' =>
          'Changes ${shortRange(slice.start, slice.end)} from ${_names(slice.from)} to $place.',
        'unresolved' => _unresolved(slice, place),
        _ => 'Counts ${shortRange(slice.start, slice.end)} as $place.',
      },
  ];
  if (parts.isEmpty && anyAlready) {
    parts.add('These days already count as $place.');
  }
  if (parts.isEmpty && anyFuture) {
    parts.add('Records ${shortRange(stay.start, stay.end)} as $place.');
  }
  if (anyFuture) {
    parts.add('Days after today stay out of the total.');
  }
  if (parts.isEmpty) return 'Confirming records this stay.';
  return parts.join(' ');
}

String _unresolved(_Slice slice, String place) {
  final when = shortRange(slice.start, slice.end);
  final one = slice.start == slice.end;
  final days = one ? 'that day' : 'those days';
  return '$when already counts as ${_names(slice.from)}. Confirming also records $place, so $days ${one ? 'is' : 'are'} left unresolved and ${one ? 'drops' : 'drop'} out of the total until you edit one stay.';
}

String _names(List<String> codes) {
  final names = codes.map(countryName).toList()..sort();
  return _and(names);
}

String _and(List<String> parts) {
  if (parts.length == 1) return parts.single;
  if (parts.length == 2) return '${parts[0]} and ${parts[1]}';
  return '${parts.sublist(0, parts.length - 1).join(', ')}, and ${parts.last}';
}

class _Slice {
  _Slice(this.kind, this.start, this.from) : end = start;

  final String kind;
  final LocalDate start;
  LocalDate end;
  final List<String> from;

  String get fromKey => from.join('|');
}
