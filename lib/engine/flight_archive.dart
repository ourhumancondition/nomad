import '../data/countries.dart';
import 'models.dart';

/// How the flights page groups records.
///
/// Accepted flights are archived. [broughtBack] holds accepted flights the
/// traveler chose to show beside the review list for this session. Neither
/// group is stored, and the flight records themselves are not modified.
class FlightArchiveSplit {
  const FlightArchiveSplit({
    required this.needsReview,
    required this.broughtBack,
    required this.archived,
  });

  final List<FlightRecord> needsReview;
  final List<FlightRecord> broughtBack;
  final List<FlightRecord> archived;
}

/// Accepted means archived, unless [unarchivedIds] pulls that flight back
/// onto the review list. Pending, rejected, and needs-manual flights stay
/// in [FlightArchiveSplit.needsReview].
bool flightIsArchived(
  FlightRecord flight, {
  Set<String> unarchivedIds = const {},
}) {
  return flight.reviewState == FlightReviewState.accepted &&
      !unarchivedIds.contains(flight.id);
}

FlightArchiveSplit splitFlights(
  Iterable<FlightRecord> flights, {
  Set<String> unarchivedIds = const {},
}) {
  final sorted = [...flights]..sort(compareFlights);
  final needsReview = <FlightRecord>[];
  final broughtBack = <FlightRecord>[];
  final archived = <FlightRecord>[];
  for (final flight in sorted) {
    if (flight.reviewState != FlightReviewState.accepted) {
      needsReview.add(flight);
    } else if (unarchivedIds.contains(flight.id)) {
      broughtBack.add(flight);
    } else {
      archived.add(flight);
    }
  }
  return FlightArchiveSplit(
    needsReview: needsReview,
    broughtBack: broughtBack,
    archived: archived,
  );
}

/// Case-insensitive search over the flight's own fields and country names.
/// Every whitespace-separated word must match. An empty query matches all.
bool flightMatchesQuery(FlightRecord flight, String query) {
  final tokens = query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty);
  if (tokens.isEmpty) return true;
  final haystack = [
    flight.flightNumber,
    flight.fromIata,
    flight.toIata,
    flight.fromCountry,
    flight.toCountry,
    countryLabel(flight.fromCountry),
    countryLabel(flight.toCountry),
    flight.notes,
    flight.depart.iso,
    flight.arrive.iso,
    flight.evidenceStatus,
    flight.reviewState.wire,
    flight.reviewState.label,
    flight.externalId,
  ].join('\n').toLowerCase();
  for (final token in tokens) {
    if (!haystack.contains(token)) return false;
  }
  return true;
}
