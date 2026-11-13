import 'flight_proposals.dart';
import 'models.dart';

class BetweenFlightRow {
  const BetweenFlightRow({
    required this.summary,
    this.stay,
    this.blocked = false,
  });

  final String summary;
  final Stay? stay;
  final bool blocked;

  bool get canSave => stay != null && !blocked;
}

class BetweenFlightPlan {
  const BetweenFlightPlan({required this.rows});

  final List<BetweenFlightRow> rows;

  List<Stay> get savable =>
      rows.where((row) => row.canSave).map((row) => row.stay!).toList();
}

/// Proposes a continuous country between an arrival and a later departure
/// from that same country. The saved stay is inferred and does not count
/// by itself. The year summary may still count the same mornings when the
/// flights qualify as a bracket.
///
/// Civil dates are used as written. No zone is invented. A rejected flight,
/// a duplicate ticket, a different-country next departure, or an overlap
/// with a stay the traveler already wrote is not bridged.
BetweenFlightPlan planContinuousCountry({
  required List<FlightRecord> flights,
  required List<Stay> existing,
  required CountingRules rules,
}) {
  final rows = <BetweenFlightRow>[
    const BetweenFlightRow(
      summary: 'This preview does not check passenger names. Remove a flight that is not this traveler before saving.',
    ),
  ];
  final duplicates = _duplicateKeys(flights);
  final usable = <FlightRecord>[];
  for (final flight in flights) {
    if (flight.reviewState == FlightReviewState.rejected) {
      rows.add(
        BetweenFlightRow(
          summary:
              '${flight.flightNumber} is rejected, so it is not used to infer days.',
        ),
      );
      continue;
    }
    if (duplicates.contains(_flightKey(flight))) {
      rows.add(
        BetweenFlightRow(
          summary:
              '${flight.flightNumber} on ${flight.depart.date.iso} is duplicated. Neither copy is used.',
        ),
      );
      continue;
    }
    if (flight.arrive.date < flight.depart.date) {
      rows.add(
        BetweenFlightRow(
          summary:
              '${flight.flightNumber} arrives on an earlier civil date than it departs. Those dates are not converted across time zones, and no days are inferred from it.',
        ),
      );
      continue;
    }
    usable.add(flight);
  }
  usable.sort(compareFlights);

  for (var i = 0; i < usable.length - 1; i++) {
    final inbound = usable[i];
    final outbound = usable[i + 1];
    rows.add(
      _pair(
        inbound: inbound,
        outbound: outbound,
        existing: existing,
        rules: rules,
      ),
    );
  }
  if (usable.length < 2) {
    rows.add(
      const BetweenFlightRow(
        summary: 'At least two usable flights are needed before days between them can be proposed.',
      ),
    );
  }
  return BetweenFlightPlan(rows: rows);
}

String betweenFlightExternalId(FlightRecord inbound, FlightRecord outbound) {
  final raw = 'btw-${inbound.id}-${outbound.id}';
  return raw.length <= 80 ? raw : raw.substring(0, 80);
}

BetweenFlightRow _pair({
  required FlightRecord inbound,
  required FlightRecord outbound,
  required List<Stay> existing,
  required CountingRules rules,
}) {
  final from = inbound.flightNumber;
  final to = outbound.flightNumber;
  if (inbound.toCountry != outbound.fromCountry) {
    return BetweenFlightRow(
      summary:
          '$from arrives in ${inbound.toCountry} and $to leaves ${outbound.fromCountry}. The days between them are not filled.',
    );
  }
  if (outbound.depart.date < inbound.arrive.date) {
    return BetweenFlightRow(
      summary:
          '$to departs before $from arrives. Those flights conflict, so no days are inferred.',
    );
  }
  final start = firstWakeInDestination(inbound, rules);
  final end = lastWakeBeforeDeparture(outbound, rules);
  if (start == null || end == null || start > end) {
    return BetweenFlightRow(
      summary:
          'The wake time does not fall in ${inbound.toCountry} between $from and $to. No country day is inferred.',
    );
  }
  final sameDay = inbound.arrive.date == outbound.depart.date;
  final wokeThere =
      inbound.arrive.minutes <= rules.wakeMinutes &&
      outbound.depart.minutes > rules.wakeMinutes;
  final role = sameDay && !wokeThere
      ? PresenceRole.layover
      : PresenceRole.primary;
  final externalId = betweenFlightExternalId(inbound, outbound);
  final booking =
      inbound.evidenceStatus == 'booking_only' ||
      outbound.evidenceStatus == 'booking_only';
  final stay = Stay(
    id: 'between-$externalId',
    countryCode: inbound.toCountry,
    start: start,
    end: end,
    role: role,
    evidenceStatus: 'inferred',
    inference: InferenceKind.inferredItinerary,
    phase: TripPhase.actual,
    timezone: inbound.arriveTimezone,
    notes:
        'Inferred between $from (${inbound.id}) and $to (${outbound.id}). '
        '${booking ? 'A source flight is booking-only. This stay does not confirm that booking. ' : ''}'
        'Not counted until you change the evidence.',
    externalId: externalId,
    source: RecordSource.flightReview,
  );
  final blocked = _blockedByOwner(stay, existing);
  return BetweenFlightRow(
    summary: blocked
        ? '${stay.countryCode} ${start.iso} through ${end.iso} overlaps a stay you already entered. It was not replaced.'
        : 'Inferred ${role.label.toLowerCase()} in ${stay.countryCode}, ${start.iso} through ${end.iso}, from $from and $to. Evidence stays inferred.',
    stay: blocked ? null : stay,
    blocked: blocked,
  );
}

bool _blockedByOwner(Stay proposed, List<Stay> existing) {
  for (final stay in existing) {
    if (stay.externalId == proposed.externalId &&
        stay.source == RecordSource.flightReview) {
      continue;
    }
    final overlaps = stay.start <= proposed.end && proposed.start <= stay.end;
    if (!overlaps) continue;
    if (stay.role == PresenceRole.primary ||
        stay.role == PresenceRole.layover) {
      return true;
    }
  }
  return false;
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
