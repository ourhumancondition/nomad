import 'day_engine.dart';
import 'local_date.dart';
import 'models.dart';

/// A flight or stay that still needs a decision.
///
/// Accepted flights stay in the archive. A stay is here when its evidence
/// is `inferred`, including a planned stay. Building this list does not
/// write anything.
class ReviewEntry {
  const ReviewEntry.flight(this.flight) : stay = null;

  const ReviewEntry.stay(this.stay) : flight = null;

  final FlightRecord? flight;
  final Stay? stay;

  bool get isFlight => flight != null;

  String get id => flight?.id ?? stay!.id;

  LocalDate get date => flight?.depart.date ?? stay!.start;

  int get year => date.year;
}

/// Inferred stays are the ones waiting on a yes or a no.
///
/// Confirmed, corroborated, booking-only, and unknown stays stay off this
/// list. A planned stay is included when its evidence is still inferred.
bool stayNeedsCheck(Stay stay) => stay.evidenceStatus == 'inferred';

/// Pending, rejected, and needs-manual flights stay on the list.
/// Accepted flights are archived elsewhere.
bool flightNeedsCheck(FlightRecord flight) =>
    flight.reviewState != FlightReviewState.accepted;

/// Oldest first. A flight and a stay on the same day keep the flight first.
List<ReviewEntry> reviewQueue({
  required Iterable<FlightRecord> flights,
  required Iterable<Stay> stays,
}) {
  final items = <ReviewEntry>[
    for (final flight in flights)
      if (flightNeedsCheck(flight)) ReviewEntry.flight(flight),
    for (final stay in stays)
      if (stayNeedsCheck(stay)) ReviewEntry.stay(stay),
  ];
  items.sort((a, b) {
    final byDate = a.date.compareTo(b.date);
    if (byDate != 0) return byDate;
    if (a.flight != null && b.flight != null) {
      return compareFlights(a.flight!, b.flight!);
    }
    if (a.flight != null) return -1;
    if (b.flight != null) return 1;
    return a.stay!.id.compareTo(b.stay!.id);
  });
  return items;
}

int reviewQueueCount({
  required Iterable<FlightRecord> flights,
  required Iterable<Stay> stays,
}) => reviewQueue(flights: flights, stays: stays).length;

List<int> reviewYears(Iterable<ReviewEntry> entries) {
  final years = entries.map((entry) => entry.year).toSet().toList()..sort();
  return years;
}

/// Countries already in the wake-up total on each date in the range.
///
/// An empty list means that morning is not a country day. Dates after
/// [today] are omitted. Overlap mornings list every country on that date.
Map<LocalDate, List<String>> countedCountries({
  required List<Stay> stays,
  required List<FlightRecord> flights,
  required CountingRules rules,
  required List<EvidenceStatusDef> statuses,
  required LocalDate today,
  required LocalDate start,
  required LocalDate end,
}) {
  final result = <LocalDate, List<String>>{};
  if (end < start) return result;
  for (var year = start.year; year <= end.year; year++) {
    final tally = DayEngine.tally(
      stays: stays,
      flights: flights,
      year: year,
      today: today,
      rules: rules,
      statuses: statuses,
    );
    for (final day in tally.days) {
      if (day.date < start || day.date > end || day.date > today) continue;
      if (day.kind == DayKind.primaryCountry && day.primaryCountry != null) {
        result[day.date] = [day.primaryCountry!];
      } else if (day.kind == DayKind.overlap &&
          day.overlapCountries.isNotEmpty) {
        result[day.date] = List<String>.from(day.overlapCountries);
      } else {
        result[day.date] = const [];
      }
    }
  }
  return result;
}

/// How confirming [incoming] should trim other counting stays.
///
/// A different country that already counts on those dates is shortened,
/// split, or removed, so the morning does not become two countries.
/// Stays that do not count are left alone. Nothing is written here.
class StayCarve {
  const StayCarve({required this.save, required this.deleteIds});

  final List<Stay> save;
  final List<String> deleteIds;
}

StayCarve carveConflictingStays({
  required Stay incoming,
  required List<Stay> stays,
  required CountingRules rules,
  required List<EvidenceStatusDef> statuses,
}) {
  if (incoming.role != PresenceRole.primary || incoming.countryCode.isEmpty) {
    return const StayCarve(save: [], deleteIds: []);
  }
  final save = <Stay>[];
  final deleteIds = <String>[];
  for (final other in stays) {
    if (other.id == incoming.id) continue;
    if (other.role != PresenceRole.primary) continue;
    if (other.countryCode.isEmpty ||
        other.countryCode == incoming.countryCode) {
      continue;
    }
    if (!DayEngine.countsAsActual(other, rules, statuses)) continue;
    if (other.end < incoming.start || other.start > incoming.end) continue;

    final startsBefore = other.start < incoming.start;
    final endsAfter = other.end > incoming.end;
    if (!startsBefore && !endsAfter) {
      deleteIds.add(other.id);
      continue;
    }
    if (startsBefore && endsAfter) {
      save.add(other.copyWith(end: incoming.start.addDays(-1)));
      save.add(
        other.copyWith(id: '', start: incoming.end.addDays(1), externalId: ''),
      );
      continue;
    }
    if (startsBefore) {
      save.add(other.copyWith(end: incoming.start.addDays(-1)));
      continue;
    }
    save.add(other.copyWith(start: incoming.end.addDays(1)));
  }
  return StayCarve(save: save, deleteIds: deleteIds);
}

/// Short words for a note, plus one web address when the note has one.
class EvidenceBrief {
  const EvidenceBrief({this.text = '', this.sourceUrl});

  final String text;
  final String? sourceUrl;
}

final _urlPattern = RegExp(r'https?://[^\s<>\]\)"\x27]+');

const _droppedSentences = <String>[
  'all clocks are scheduled',
  'not verified actual',
  'named airports',
  'no stays generated',
  'needs manual review',
  'needs a manual stay',
];

EvidenceBrief evidenceBrief(String notes) {
  final raw = notes.trim();
  if (raw.isEmpty) return const EvidenceBrief();
  final source = _firstUrl(raw);
  final lower = raw.toLowerCase();
  final calendar = lower.contains('calendar');
  final hours = RegExp(r'hours?\s+log').hasMatch(lower);
  final email =
      lower.contains('gmail') ||
      lower.contains('verified from booking') ||
      lower.contains('email booking') ||
      lower.contains('mail.google.com');
  final kinds = <String>[
    if (calendar) 'a calendar event',
    if (hours) 'an hours log',
    if (email) 'an email booking',
  ];
  final bits = <String>[];
  if (kinds.isNotEmpty) bits.add('From ${_and(kinds)}.');
  final strength = RegExp(
    r'strength\s*[:=]\s*(strong|medium|weak)',
    caseSensitive: false,
  ).firstMatch(raw);
  if (strength != null) {
    final word = strength.group(1)!.toLowerCase();
    bits.add('${word[0].toUpperCase()}${word.substring(1)} match.');
  }
  final conflict = RegExp(
    r'conflicts?\s+with\s+([^.\n]{1,80})',
    caseSensitive: false,
  ).firstMatch(raw);
  if (conflict != null) {
    final what = conflict
        .group(1)!
        .replaceAll(_urlPattern, '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (what.isNotEmpty) bits.add('Conflicts with $what.');
  }
  if (email) {
    final passenger = RegExp(r'Passenger ([A-Z][A-Za-z]+(?: [A-Z][A-Za-z]+)?)')
        .firstMatch(raw);
    if (passenger != null) bits.add('Passenger ${passenger.group(1)}.');
  }
  if (bits.isNotEmpty) {
    return EvidenceBrief(text: bits.join(' '), sourceUrl: source);
  }
  return EvidenceBrief(text: _plainProse(raw), sourceUrl: source);
}

String? _firstUrl(String raw) {
  for (final match in _urlPattern.allMatches(raw)) {
    final url = match.group(0)!.replaceAll(RegExp(r'[.,;:]+$'), '');
    final uri = Uri.tryParse(url);
    if (uri == null) continue;
    if (uri.scheme != 'http' && uri.scheme != 'https') continue;
    if (uri.host.isEmpty) continue;
    return uri.toString();
  }
  return null;
}

String _plainProse(String raw) {
  var prose = raw.replaceAll(_urlPattern, ' ');
  prose = prose.replaceAll(RegExp(r'\b[A-Za-z]+(?:/[A-Za-z0-9._+-]+)+\b'), ' ');
  final kept = <String>[];
  for (final sentence in prose.split(RegExp(r'(?<=[.!?])\s+'))) {
    final text = sentence.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) continue;
    final lower = text.toLowerCase();
    if (_droppedSentences.any(lower.contains)) continue;
    kept.add(text);
  }
  final summary = kept.join(' ');
  if (summary.length <= 180) return summary;
  return '${summary.substring(0, 177).trim()}…';
}

String _and(List<String> parts) {
  if (parts.length == 1) return parts.single;
  if (parts.length == 2) return '${parts[0]} and ${parts[1]}';
  return '${parts.sublist(0, parts.length - 1).join(', ')}, and ${parts.last}';
}
