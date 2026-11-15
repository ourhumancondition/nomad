import 'dart:convert';

import '../data/countries.dart';
import '../engine/flight_brackets.dart';
import '../engine/local_date.dart';
import '../engine/models.dart';
import 'format.dart';

/// Facts already saved around one stretch of unknown days.
///
/// This only reads stays and flights. It does not decide what counts.
class UnknownTile {
  const UnknownTile({
    required this.range,
    this.facts = const [],
    this.hint,
    this.suggestions = const [],
  });

  final DateRange range;
  final List<GapFact> facts;
  final String? hint;
  final List<GapSuggestion> suggestions;
}

class GapSuggestion {
  const GapSuggestion({required this.countryCode, required this.label});

  final String countryCode;
  final String label;
}

enum GapFactKind { landing, departure, stay }

class GapFact {
  const GapFact({
    required this.heading,
    required this.kind,
    required this.countryCode,
    required this.detail,
    this.when,
    this.note,
    this.moreDetails = const [],
    this.unconfirmed = false,
    this.flight,
  });

  final String heading;
  final GapFactKind kind;
  final String countryCode;
  final String detail;
  final LocalDate? when;
  final String? note;

  /// Readable extra fields. Never raw JSON or a web address.
  final List<String> moreDetails;

  /// True when the flight is not counted yet.
  final bool unconfirmed;
  final FlightRecord? flight;

  bool get canConfirm =>
      flight != null && flight!.reviewState == FlightReviewState.pending;
}

List<UnknownTile> describeUnknownTiles({
  required List<DateRange> ranges,
  required List<Stay> stays,
  required List<FlightRecord> flights,
  required List<EvidenceStatusDef> statuses,
}) {
  final usableStays = stays.where(_isPlaceStay).toList();
  final usableFlights = flights.where(_isListedFlight).toList();
  return [
    for (final range in ranges)
      _describe(range, usableStays, usableFlights, statuses),
  ];
}

UnknownTile _describe(
  DateRange range,
  List<Stay> stays,
  List<FlightRecord> flights,
  List<EvidenceStatusDef> statuses,
) {
  final before = _before(range, stays, flights, statuses);
  final after = _after(range, stays, flights, statuses);
  final inside = _inside(range, flights, statuses);
  final facts = <GapFact>[];
  void add(GapFact? fact) {
    if (fact == null) return;
    final duplicate = facts.any(
      (item) =>
          item.kind == fact.kind &&
          item.flight != null &&
          item.flight == fact.flight,
    );
    if (duplicate) return;
    facts.add(fact);
  }

  add(before);
  add(inside.landing);
  add(inside.leaving);
  add(after);
  facts.removeWhere(
    (fact) =>
        fact.kind == GapFactKind.landing &&
        facts.any(
          (other) =>
              other.kind == GapFactKind.departure &&
              other.flight == fact.flight,
        ),
  );
  GapFact? landing;
  GapFact? leaving;
  for (final fact in facts) {
    if (landing == null && fact.kind == GapFactKind.landing) landing = fact;
    if (fact.kind == GapFactKind.departure) leaving = fact;
  }
  return UnknownTile(
    range: range,
    facts: facts,
    hint: _hint(landing, leaving) ?? _stayHint(before, after),
    suggestions: _suggestions(landing, leaving, before, after),
  );
}

class _Inside {
  const _Inside({this.landing, this.leaving});

  final GapFact? landing;
  final GapFact? leaving;
}

bool _isPlaceStay(Stay stay) =>
    stay.phase == TripPhase.actual &&
    stay.role == PresenceRole.primary &&
    RegExp(r'^[A-Z]{2}$').hasMatch(stay.countryCode);

bool _isListedFlight(FlightRecord flight) {
  if (flight.reviewState == FlightReviewState.rejected) return false;
  if (flight.arrive.date < flight.depart.date) return false;
  if (!RegExp(r'^[A-Z]{2}$').hasMatch(flight.fromCountry)) return false;
  if (!RegExp(r'^[A-Z]{2}$').hasMatch(flight.toCountry)) return false;
  return true;
}

GapFact? _before(
  DateRange range,
  List<Stay> stays,
  List<FlightRecord> flights,
  List<EvidenceStatusDef> statuses,
) {
  Stay? stay;
  for (final item in stays) {
    if (item.end >= range.start) continue;
    if (stay == null || item.end > stay.end) stay = item;
  }
  FlightRecord? flight;
  for (final item in flights) {
    if (item.arrive.date > range.start) continue;
    if (flight == null || _arrivedLater(item, flight)) flight = item;
  }
  if (stay == null && flight == null) return null;
  if (flight == null) return _stayFact('Before', stay!, ended: true);
  if (stay == null) return _landingFact('Before', flight, statuses);
  final stayDistance = range.start.differenceInDays(stay.end);
  final flightDistance = range.start.differenceInDays(flight.arrive.date);
  if (flightDistance < stayDistance) {
    return _landingFact('Before', flight, statuses);
  }
  if (stayDistance < flightDistance) {
    return _stayFact('Before', stay, ended: true);
  }
  return _arrivedLaterThanStay(flight, stay)
      ? _landingFact('Before', flight, statuses)
      : _stayFact('Before', stay, ended: true);
}

GapFact? _after(
  DateRange range,
  List<Stay> stays,
  List<FlightRecord> flights,
  List<EvidenceStatusDef> statuses,
) {
  Stay? stay;
  for (final item in stays) {
    if (item.start <= range.end) continue;
    if (stay == null || item.start < stay.start) stay = item;
  }
  FlightRecord? flight;
  for (final item in flights) {
    if (item.depart.date < range.end) continue;
    if (flight == null || _departedEarlier(item, flight)) flight = item;
  }
  if (stay == null && flight == null) return null;
  if (flight == null) return _stayFact('After', stay!, ended: false);
  if (stay == null) return _departureFact('After', flight, statuses);
  final stayDistance = stay.start.differenceInDays(range.end);
  final flightDistance = flight.depart.date.differenceInDays(range.end);
  if (flightDistance < stayDistance) {
    return _departureFact('After', flight, statuses);
  }
  if (stayDistance < flightDistance) {
    return _stayFact('After', stay, ended: false);
  }
  return flight.depart.minutes <= 12 * 60
      ? _departureFact('After', flight, statuses)
      : _stayFact('After', stay, ended: false);
}

_Inside _inside(
  DateRange range,
  List<FlightRecord> flights,
  List<EvidenceStatusDef> statuses,
) {
  FlightRecord? landing;
  FlightRecord? leaving;
  for (final flight in flights) {
    final landedInside =
        flight.arrive.date >= range.start && flight.arrive.date <= range.end;
    final leftInside =
        flight.depart.date >= range.start && flight.depart.date <= range.end;
    if (landedInside && (landing == null || _arrivedEarlier(flight, landing))) {
      landing = flight;
    }
    if (leftInside && (leaving == null || _departedLater(flight, leaving))) {
      leaving = flight;
    }
  }
  return _Inside(
    landing: landing == null ? null : _landingFact('During', landing, statuses),
    leaving: leaving == null || leaving == landing
        ? null
        : _departureFact('During', leaving, statuses),
  );
}

bool _arrivedLater(FlightRecord candidate, FlightRecord current) {
  final byDate = candidate.arrive.date.compareTo(current.arrive.date);
  if (byDate != 0) return byDate > 0;
  return candidate.arrive.minutes > current.arrive.minutes;
}

bool _arrivedEarlier(FlightRecord candidate, FlightRecord current) =>
    !_arrivedLater(candidate, current) && candidate != current;

bool _departedEarlier(FlightRecord candidate, FlightRecord current) {
  final byDate = candidate.depart.date.compareTo(current.depart.date);
  if (byDate != 0) return byDate < 0;
  return candidate.depart.minutes < current.depart.minutes;
}

bool _departedLater(FlightRecord candidate, FlightRecord current) =>
    !_departedEarlier(candidate, current) && candidate != current;

bool _arrivedLaterThanStay(FlightRecord flight, Stay stay) {
  if (flight.arrive.date != stay.end) return flight.arrive.date > stay.end;
  return true;
}

GapFact _landingFact(
  String heading,
  FlightRecord flight,
  List<EvidenceStatusDef> statuses,
) {
  final place = countryName(flight.toCountry);
  final unconfirmed = !_counts(flight, statuses);
  final readable = _readableNotes(flight.notes);
  return GapFact(
    heading: heading,
    kind: GapFactKind.landing,
    countryCode: flight.toCountry,
    detail:
        'Landed in $place · ${flight.flightNumber} · ${flight.fromIata} to ${flight.toIata} · ${shortDate(flight.arrive.date)} at ${shortClock(flight.arrive)}',
    when: flight.arrive.date,
    note: _visibleNote(readable.plain, unconfirmed),
    moreDetails: readable.details,
    unconfirmed: unconfirmed,
    flight: flight,
  );
}

GapFact _departureFact(
  String heading,
  FlightRecord flight,
  List<EvidenceStatusDef> statuses,
) {
  final place = countryName(flight.fromCountry);
  final unconfirmed = !_counts(flight, statuses);
  final readable = _readableNotes(flight.notes);
  return GapFact(
    heading: heading,
    kind: GapFactKind.departure,
    countryCode: flight.fromCountry,
    detail:
        'Flew out of $place · ${flight.flightNumber} · ${flight.fromIata} to ${flight.toIata} · ${shortDate(flight.depart.date)} at ${shortClock(flight.depart)}',
    when: flight.depart.date,
    note: _visibleNote(readable.plain, unconfirmed),
    moreDetails: readable.details,
    unconfirmed: unconfirmed,
    flight: flight,
  );
}

GapFact _stayFact(String heading, Stay stay, {required bool ended}) {
  final place = countryName(stay.countryCode);
  final when = ended
      ? 'until ${shortDate(stay.end)}'
      : 'from ${shortDate(stay.start)}';
  final readable = _readableNotes(stay.notes);
  final bits = <String>[
    ?readable.plain,
    if (stay.source == RecordSource.csv) 'From a spreadsheet',
  ];
  return GapFact(
    heading: heading,
    kind: GapFactKind.stay,
    countryCode: stay.countryCode,
    detail: 'You were in $place $when',
    when: ended ? stay.end : stay.start,
    note: bits.isEmpty ? null : bits.join(' · '),
    moreDetails: readable.details,
  );
}

String? _visibleNote(String? plain, bool unconfirmed) {
  final parts = <String>[
    if (unconfirmed) 'Not confirmed yet',
    ?plain,
  ];
  if (parts.isEmpty) return null;
  return parts.join(' · ');
}

class _ReadableNotes {
  const _ReadableNotes({this.plain, this.details = const []});

  final String? plain;
  final List<String> details;
}

const _noteLabels = <String, String>{
  'raw_evidence_class': 'How it was recorded',
  'raw_class': 'How it was recorded',
  'allocation': 'Time used',
  'timezone_basis': 'Time zone',
  'count_qualified': 'Counts toward the total',
  'inclusive_end': 'Includes the last day',
  'notes': 'Note',
  'source': 'Where it came from',
};

final _jsonObject = RegExp(r'\{(?:[^{}]|\{[^{}]*\})*\}');

_ReadableNotes _readableNotes(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return const _ReadableNotes();
  final details = <String>[];
  final seen = <String>{};
  void addLine(String line) {
    if (seen.add(line)) details.add(line);
  }

  void takeMap(Map<dynamic, dynamic> map) {
    for (final entry in map.entries) {
      final label = _noteLabels[entry.key.toString()];
      if (label == null) continue;
      final value = _plainValue(entry.key.toString(), entry.value);
      if (value == null) continue;
      addLine('$label: $value');
    }
  }

  for (final match in _jsonObject.allMatches(text)) {
    try {
      final decoded = jsonDecode(match.group(0)!);
      if (decoded is Map) takeMap(decoded);
    } on FormatException {
      continue;
    }
  }
  final loose = RegExp(
    r'''([A-Za-z][A-Za-z0-9_]*)\s*[:=]\s*("[^"]*"|[^,{}\n]+)''',
  );
  for (final match in loose.allMatches(text)) {
    final key = match.group(1)!;
    if (!_noteLabels.containsKey(key)) continue;
    var value = match.group(2)!.trim();
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      value = value.substring(1, value.length - 1);
    }
    final plain = _plainValue(key, value);
    if (plain == null) continue;
    addLine('${_noteLabels[key]}: $plain');
  }

  final structured =
      text.contains('{') ||
      text.contains('}') ||
      text.contains('http://') ||
      text.contains('https://') ||
      text.contains('docs.google.com');
  if (structured) {
    return _ReadableNotes(details: details);
  }
  if (text.length > 120) {
    return _ReadableNotes(details: [text.substring(0, 117)]);
  }
  return _ReadableNotes(plain: text, details: details);
}

String? _plainValue(String key, Object? value) {
  if (value == null) return null;
  if (value is bool) return value ? 'Yes' : 'No';
  final text = value.toString().trim();
  if (text.isEmpty || text == 'null') return null;
  final lower = text.toLowerCase();
  if (lower == 'true' || lower == 'false') {
    return lower == 'true' ? 'Yes' : 'No';
  }
  if (text.contains('{') || text.contains('}')) return null;
  if (text.contains('http://') ||
      text.contains('https://') ||
      text.contains('docs.google.com')) {
    if (key == 'source') return 'A spreadsheet';
    return null;
  }
  if (text.length > 180) return '${text.substring(0, 177)}…';
  return text;
}

bool _counts(FlightRecord flight, List<EvidenceStatusDef> statuses) =>
    flightQualifiesForBracket(flight, statuses);

String? _hint(GapFact? before, GapFact? after) {
  if (before != null &&
      after != null &&
      before.kind == GapFactKind.landing &&
      after.kind == GapFactKind.departure) {
    final landed = countryName(before.countryCode);
    final left = countryName(after.countryCode);
    if (before.countryCode == after.countryCode) {
      return 'You landed in $landed on ${shortDate(before.when!)} and next flew out of $left on ${shortDate(after.when!)}.';
    }
    return 'You landed in $landed, and the next flight leaves from $left, so a trip between them is missing.';
  }
  if (before != null && before.kind == GapFactKind.landing) {
    return 'You landed in ${countryName(before.countryCode)} on ${shortDate(before.when!)}.';
  }
  if (after != null && after.kind == GapFactKind.departure) {
    return 'The next flight leaves from ${countryName(after.countryCode)} on ${shortDate(after.when!)}.';
  }
  return null;
}

String? _stayHint(GapFact? before, GapFact? after) {
  if (before != null && before.kind == GapFactKind.stay) {
    return 'You were in ${countryName(before.countryCode)} just before these days.';
  }
  if (after != null && after.kind == GapFactKind.stay) {
    return 'The next saved stay is ${countryName(after.countryCode)}.';
  }
  return null;
}

List<GapSuggestion> _suggestions(
  GapFact? landing,
  GapFact? leaving,
  GapFact? before,
  GapFact? after,
) {
  final chosen = landing != null || leaving != null
      ? [landing, leaving]
      : [before, after];
  final codes = <String>[];
  for (final fact in chosen) {
    final code = fact?.countryCode;
    if (code == null || code.isEmpty || codes.contains(code)) continue;
    codes.add(code);
  }
  return [
    for (final code in codes.take(2))
      GapSuggestion(countryCode: code, label: 'I was in ${countryName(code)}'),
  ];
}
