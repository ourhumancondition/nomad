import 'local_date.dart';
import 'models.dart';

class FlightProposal {
  const FlightProposal({
    required this.flightId,
    required this.reason,
    this.stay,
  });

  final String flightId;
  final String reason;
  final Stay? stay;

  bool get needsManualReview => stay == null;
}

/// Turns flight evidence into proposed stays.
///
/// Proposals are inferences. They use the evidence status `inferred`, which
/// does not count, until the traveler accepts them. Civil dates are compared
/// as written on each ticket and are not converted between time zones.
List<FlightProposal> proposeItinerary(
  List<FlightRecord> flights,
  CountingRules rules,
) {
  final sorted = [...flights]..sort(compareFlights);
  final proposals = <FlightProposal>[];
  final consumedDestination = <String>{};
  final seenStays = <String>{};

  void addStay(FlightProposal proposal) {
    final stay = proposal.stay;
    if (stay != null) {
      final key =
          '${stay.role.wire}|${stay.start.iso}|${stay.end.iso}|${stay.countryCode}';
      if (!seenStays.add(key)) return;
    }
    proposals.add(proposal);
  }

  for (final flight in sorted) {
    if (flight.arrive.date < flight.depart.date) {
      proposals.add(
        FlightProposal(
          flightId: flight.id,
          reason:
              'The arrival civil date is before the departure civil date. '
              'Automatic transit is skipped. Enter the wake-up country yourself. '
              'Civil dates are not converted across time zones.',
        ),
      );
      continue;
    }

    final wakeDates = <LocalDate>[];
    for (
      var date = flight.depart.date;
      date <= flight.arrive.date;
      date = date.addDays(1)
    ) {
      if (airborneAtWake(flight, date, rules)) wakeDates.add(date);
    }
    for (final range in _ranges(wakeDates)) {
      addStay(
        FlightProposal(
          flightId: flight.id,
          reason:
              'Airborne at the wake time (${rules.wakeLabel}). '
              'This is an in-transit main day.',
          stay: _proposedStay(
            flight: flight,
            start: range.start,
            end: range.end,
            role: PresenceRole.transitWake,
            country: '',
            inference: InferenceKind.inferredItinerary,
            timezone: flight.arriveTimezone,
            notes: 'Proposed from ${flight.flightNumber}. Airborne at wake-up.',
          ),
        ),
      );
    }

    if (flight.arrive.date > flight.depart.date) {
      addStay(
        FlightProposal(
          flightId: flight.id,
          reason: 'Overnight flight night. Shown separately, and kept out of the wake-up country total.',
          stay: _proposedStay(
            flight: flight,
            start: flight.depart.date,
            end: flight.arrive.date.addDays(-1),
            role: PresenceRole.transitNight,
            country: '',
            inference: InferenceKind.inferredItinerary,
            timezone: flight.departTimezone,
            notes:
                'Proposed from ${flight.flightNumber}. Night in transit, separate from the wake-up day.',
          ),
        ),
      );
    }
  }

  for (var i = 0; i < sorted.length - 1; i++) {
    final inbound = sorted[i];
    final outbound = sorted[i + 1];
    if (inbound.arrive.date < inbound.depart.date) continue;
    if (inbound.toCountry != outbound.fromCountry) continue;
    if (outbound.depart.date < inbound.arrive.date) continue;

    final gapDays = outbound.depart.date.differenceInDays(inbound.arrive.date);
    if (gapDays > 1) {
      proposals.add(
        FlightProposal(
          flightId: inbound.id,
          reason:
              'The next flight from ${inbound.toCountry} is $gapDays days later. '
              'The days between them stay unknown. They are not filled from the booking.',
        ),
      );
      continue;
    }

    if (inbound.arrive.date == outbound.depart.date) {
      final date = inbound.arrive.date;
      final wokeThere =
          inbound.arrive.minutes <= rules.wakeMinutes &&
          outbound.depart.minutes > rules.wakeMinutes;
      if (wokeThere) {
        addStay(
          FlightProposal(
            flightId: inbound.id,
            reason:
                'Wake time falls in ${inbound.toCountry} between these flights, so this is a main day. '
                'Change the role before accepting if you want it recorded only as a layover.',
            stay: _proposedStay(
              flight: inbound,
              start: date,
              end: date,
              role: PresenceRole.primary,
              country: inbound.toCountry,
              inference: InferenceKind.inferredConnection,
              timezone: inbound.arriveTimezone,
              notes:
                  'Proposed from ${inbound.flightNumber}. Wake-up in the connection country.',
            ),
          ),
        );
      } else {
        addStay(
          FlightProposal(
            flightId: inbound.id,
            reason: 'Same-day connection. Counted as layover presence, separate from the wake-up country.',
            stay: _proposedStay(
              flight: inbound,
              start: date,
              end: date,
              role: PresenceRole.layover,
              country: inbound.toCountry,
              inference: InferenceKind.inferredConnection,
              timezone: inbound.arriveTimezone,
              notes: 'Proposed from ${inbound.flightNumber}. Same-day layover.',
            ),
          ),
        );
      }
      consumedDestination.add(inbound.id);
      continue;
    }

    final first = firstWakeInDestination(inbound, rules);
    final last = lastWakeBeforeDeparture(outbound, rules);
    if (first != null && last != null && first <= last) {
      addStay(
        FlightProposal(
          flightId: inbound.id,
          reason: 'Wake-up country between these flights. Limited to mornings the wake time falls there. No extra days are filled.',
          stay: _proposedStay(
            flight: inbound,
            start: first,
            end: last,
            role: PresenceRole.primary,
            country: inbound.toCountry,
            inference: InferenceKind.inferredConnection,
            timezone: inbound.arriveTimezone,
            notes:
                'Proposed from ${inbound.flightNumber}. Short connection with a wake-up in ${inbound.toCountry}.',
          ),
        ),
      );
      consumedDestination.add(inbound.id);
    }
  }

  for (final flight in sorted) {
    if (consumedDestination.contains(flight.id)) continue;
    if (flight.arrive.date < flight.depart.date) continue;
    final first = firstWakeInDestination(flight, rules);
    if (first == null) continue;
    addStay(
      FlightProposal(
        flightId: flight.id,
        reason:
            'Suggested wake-up country on the first morning that is not airborne. '
            'Only this date is proposed. Later days stay unknown until you extend the stay.',
        stay: _proposedStay(
          flight: flight,
          start: first,
          end: first,
          role: PresenceRole.primary,
          country: flight.toCountry,
          inference: InferenceKind.inferredItinerary,
          timezone: flight.arriveTimezone,
          notes:
              'Proposed from ${flight.flightNumber}. First wake-up in ${flight.toCountry}. Extend it if you stayed longer.',
        ),
      ),
    );
  }

  return proposals;
}

bool airborneAtWake(FlightRecord flight, LocalDate date, CountingRules rules) {
  final depart = flight.depart;
  final arrive = flight.arrive;
  if (arrive.date < depart.date) return false;
  if (date < depart.date || date > arrive.date) return false;
  final wake = rules.wakeMinutes;
  if (depart.date == arrive.date) {
    return date == depart.date &&
        depart.minutes <= wake &&
        arrive.minutes > wake;
  }
  if (date == depart.date) return depart.minutes <= wake;
  if (date == arrive.date) return arrive.minutes > wake;
  return true;
}

LocalDate? firstWakeInDestination(FlightRecord flight, CountingRules rules) {
  if (flight.arrive.date < flight.depart.date) return null;
  final arrival = flight.arrive.date;
  final arrivedByWake = flight.arrive.minutes <= rules.wakeMinutes;
  if (!airborneAtWake(flight, arrival, rules) && arrivedByWake) {
    return arrival;
  }
  return arrival.addDays(1);
}

LocalDate? lastWakeBeforeDeparture(FlightRecord flight, CountingRules rules) {
  if (flight.depart.minutes > rules.wakeMinutes) return flight.depart.date;
  return flight.depart.date.addDays(-1);
}

Stay _proposedStay({
  required FlightRecord flight,
  required LocalDate start,
  required LocalDate end,
  required PresenceRole role,
  required String country,
  required InferenceKind inference,
  required String timezone,
  required String notes,
}) {
  return Stay(
    id: 'proposal-${flight.id}-${role.wire}-${start.iso}-${end.iso}',
    countryCode: country,
    start: start,
    end: end,
    role: role,
    evidenceStatus: 'inferred',
    inference: inference,
    phase: TripPhase.actual,
    timezone: timezone,
    notes: 'Inference until you accept it. $notes',
    externalId: '',
    source: RecordSource.flightReview,
  );
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
