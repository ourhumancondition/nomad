import 'flight_proposals.dart';
import 'local_date.dart';
import 'models.dart';

/// Why a pair of flights did not become wake-up days.
enum FlightGapKind { mismatch, unqualified, noWake }

/// A same-country arrival and the next departure from that country.
///
/// [start] and [end] are inclusive civil wake-up dates from
/// [firstWakeInDestination] and [lastWakeBeforeDeparture]. They are not
/// stored stays.
class FlightBracket {
  const FlightBracket({
    required this.countryCode,
    required this.start,
    required this.end,
    required this.inbound,
    required this.outbound,
    this.leftFrom,
  });

  final String countryCode;
  final LocalDate start;
  final LocalDate end;
  final FlightRecord inbound;
  final FlightRecord outbound;

  /// Set when [outbound] leaves a country other than [countryCode].
  /// The mornings are still counted as [countryCode].
  final String? leftFrom;

  bool covers(LocalDate date) => date >= start && date <= end;
}

/// A gap the summary leaves unknown, or a same-day pair with no wake-up.
class FlightGap {
  const FlightGap({
    required this.kind,
    required this.arrivalCountry,
    required this.otherCountry,
    required this.arrivalNumber,
    required this.otherNumber,
    required this.fromDate,
    required this.toDate,
    required this.reason,
  });

  final FlightGapKind kind;
  final String arrivalCountry;
  final String otherCountry;
  final String arrivalNumber;
  final String otherNumber;
  final LocalDate fromDate;
  final LocalDate toDate;

  /// `mismatch`, `needs_manual`, `not_evidence`, or `no_wake`.
  final String reason;

  bool overlaps(LocalDate start, LocalDate end) {
    final from = fromDate <= toDate ? fromDate : toDate;
    final to = fromDate <= toDate ? toDate : fromDate;
    return from <= end && to >= start;
  }
}

class FlightBracketPlan {
  const FlightBracketPlan({
    required this.brackets,
    required this.gaps,
    required this.qualifying,
    required this.rules,
  });

  final List<FlightBracket> brackets;
  final List<FlightGap> gaps;
  final List<FlightRecord> qualifying;
  final CountingRules rules;

  bool airborneAt(LocalDate date) {
    for (final flight in qualifying) {
      if (airborneAtWake(flight, date, rules)) return true;
    }
    return false;
  }
}

/// A flight may open or close a counted bracket when Alex accepted it, or
/// when its evidence status counts, and it is not rejected or marked as
/// needing a manual stay.
///
/// Acceptance qualifies a booking-only flight: he recorded that he flew.
/// A pending booking-only flight does not. `needs_manual` does not, even
/// when the evidence status would otherwise count, because that review
/// state asks for a stay he enters himself. Rejected flights do not.
bool flightQualifiesForBracket(
  FlightRecord flight,
  List<EvidenceStatusDef> statuses,
) {
  if (flight.reviewState == FlightReviewState.rejected) return false;
  if (flight.reviewState == FlightReviewState.needsManual) return false;
  if (flight.arrive.date < flight.depart.date) return false;
  if (flight.reviewState == FlightReviewState.accepted) return true;
  return _evidenceCounts(flight.evidenceStatus, statuses);
}

/// Brackets are derived from flights. Nothing here is written.
///
/// Recorded flights are every flight except rejected tickets, duplicate
/// tickets (neither copy is used), and a backward civil date. Ordering is
/// the departure civil clock as written, the same order as the rest of the
/// app. Time zones are not converted.
///
/// A qualifying flight that enters country X is paired with the next
/// recorded flight that is not a domestic hop inside X.
/// - That flight also qualifies: the wake-ups between them count as X,
///   including when the flight leaves a different country. That pair is
///   marked [FlightBracket.leftFrom] and listed as a mismatch.
/// - That flight does not qualify: the days are not counted. A later
///   qualifying flight is not used to skip over it.
/// Domestic flights inside X do not end the stay. A rejected flight is
/// ignored. A flight that is not accepted and whose evidence does not count
/// is ignored too, unless it departs X: that recorded departure blocks the
/// bracket and is not skipped for a later flight. An arrival with no later
/// qualifying departure does not fill the days after it.
FlightBracketPlan planFlightBrackets({
  required List<FlightRecord> flights,
  required CountingRules rules,
  required List<EvidenceStatusDef> statuses,
}) {
  final duplicates = _duplicateKeys(flights);
  final recorded = <FlightRecord>[];
  for (final flight in flights) {
    if (flight.reviewState == FlightReviewState.rejected) continue;
    if (duplicates.contains(_flightKey(flight))) continue;
    if (flight.arrive.date < flight.depart.date) continue;
    if (!_country(flight.fromCountry) || !_country(flight.toCountry)) {
      continue;
    }
    recorded.add(flight);
  }
  recorded.sort(compareFlights);

  final brackets = <FlightBracket>[];
  final gaps = <FlightGap>[];
  final qualifying = <FlightRecord>[];

  for (final flight in recorded) {
    if (flightQualifiesForBracket(flight, statuses)) qualifying.add(flight);
  }

  for (var i = 0; i < recorded.length; i++) {
    final arrival = recorded[i];
    if (!flightQualifiesForBracket(arrival, statuses)) continue;
    if (arrival.fromCountry == arrival.toCountry) continue;

    FlightRecord? next;
    for (var j = i + 1; j < recorded.length; j++) {
      final candidate = recorded[j];
      final inside =
          candidate.fromCountry == arrival.toCountry &&
          candidate.toCountry == arrival.toCountry;
      if (inside) continue;
      final leaves = candidate.fromCountry == arrival.toCountry;
      final qualifies = flightQualifiesForBracket(candidate, statuses);
      // A booking that does not leave X is not evidence of leaving.
      if (!leaves && !qualifies) continue;
      next = candidate;
      break;
    }
    if (next == null) continue;

    final sameCountry = next.fromCountry == arrival.toCountry;
    final nextQualifies = flightQualifiesForBracket(next, statuses);
    if (!sameCountry && nextQualifies) {
      gaps.add(
        FlightGap(
          kind: FlightGapKind.mismatch,
          arrivalCountry: arrival.toCountry,
          otherCountry: next.fromCountry,
          arrivalNumber: arrival.flightNumber,
          otherNumber: next.flightNumber,
          fromDate: arrival.arrive.date,
          toDate: next.depart.date,
          reason: 'mismatch',
        ),
      );
    }
    if (!nextQualifies) {
      gaps.add(
        FlightGap(
          kind: FlightGapKind.unqualified,
          arrivalCountry: arrival.toCountry,
          otherCountry: next.fromCountry,
          arrivalNumber: arrival.flightNumber,
          otherNumber: next.flightNumber,
          fromDate: arrival.arrive.date,
          toDate: next.depart.date,
          reason: _unqualifiedReason(next),
        ),
      );
      continue;
    }

    final start = firstWakeInDestination(arrival, rules);
    final end = lastWakeBeforeDeparture(next, rules);
    if (start == null || end == null || start > end) {
      gaps.add(
        FlightGap(
          kind: FlightGapKind.noWake,
          arrivalCountry: arrival.toCountry,
          otherCountry: next.fromCountry,
          arrivalNumber: arrival.flightNumber,
          otherNumber: next.flightNumber,
          fromDate: arrival.arrive.date,
          toDate: next.depart.date,
          reason: 'no_wake',
        ),
      );
      continue;
    }
    brackets.add(
      FlightBracket(
        countryCode: arrival.toCountry,
        start: start,
        end: end,
        inbound: arrival,
        outbound: next,
        leftFrom: sameCountry ? null : next.fromCountry,
      ),
    );
  }

  return FlightBracketPlan(
    brackets: brackets,
    gaps: gaps,
    qualifying: qualifying,
    rules: rules,
  );
}

bool _country(String code) => RegExp(r'^[A-Z]{2}$').hasMatch(code);

bool _evidenceCounts(String id, List<EvidenceStatusDef> statuses) {
  for (final status in statuses) {
    if (status.id == id) return status.countsAsActual;
  }
  return false;
}

String _unqualifiedReason(FlightRecord flight) {
  if (flight.reviewState == FlightReviewState.needsManual) {
    return 'needs_manual';
  }
  return 'not_evidence';
}

Set<String> _duplicateKeys(List<FlightRecord> flights) {
  final counts = <String, int>{};
  for (final flight in flights) {
    final key = _flightKey(flight);
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return counts.entries
      .where((entry) => entry.value > 1)
      .map((entry) => entry.key)
      .toSet();
}

String _flightKey(FlightRecord flight) =>
    '${flight.flightNumber}|${flight.depart.iso}|${flight.fromIata}|${flight.toIata}|${flight.fromCountry}|${flight.toCountry}';
