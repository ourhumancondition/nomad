import 'package:flutter_test/flutter_test.dart';
import 'package:nomadic_residence/engine/flight_proposals.dart';
import 'package:nomadic_residence/engine/local_date.dart';
import 'package:nomadic_residence/engine/models.dart';

void main() {
  const rules = CountingRules.standard;

  FlightRecord flight({
    required String id,
    required String from,
    required String to,
    required String depart,
    required String arrive,
  }) {
    return FlightRecord(
      id: id,
      flightNumber: 'EX100',
      fromIata: 'AAA',
      toIata: 'BBB',
      fromCountry: from,
      toCountry: to,
      depart: WallTime.parse(depart),
      arrive: WallTime.parse(arrive),
      departTimezone: 'Etc/UTC',
      arriveTimezone: 'Etc/UTC',
      evidenceStatus: 'confirmed',
      inference: InferenceKind.none,
      reviewState: FlightReviewState.pending,
    );
  }

  List<Stay> stays(List<FlightProposal> proposals, PresenceRole role) {
    return proposals
        .map((proposal) => proposal.stay)
        .whereType<Stay>()
        .where((stay) => stay.role == role)
        .toList();
  }

  test('a short overnight flight marks the night and the arrival morning', () {
    final proposals = proposeItinerary([
      flight(
        id: 'night',
        from: 'JP',
        to: 'SG',
        depart: '2026-04-20T22:40',
        arrive: '2026-04-21T04:10',
      ),
    ], rules);
    final nights = stays(proposals, PresenceRole.transitNight);
    final wakes = stays(proposals, PresenceRole.transitWake);
    final primary = stays(proposals, PresenceRole.primary);
    expect(nights.single.start, LocalDate(2026, 4, 20));
    expect(nights.single.end, LocalDate(2026, 4, 20));
    expect(wakes, isEmpty);
    expect(primary.single.countryCode, 'SG');
    expect(primary.single.start, LocalDate(2026, 4, 21));
    expect(primary.single.end, LocalDate(2026, 4, 21));
    expect(primary.single.evidenceStatus, 'inferred');
    expect(primary.single.inference.isInference, isTrue);
  });

  test('a long flight makes full airborne wake-ups and does not claim the departure morning', () {
    final proposals = proposeItinerary([
      flight(
        id: 'long',
        from: 'PT',
        to: 'NZ',
        depart: '2026-05-01T10:00',
        arrive: '2026-05-03T15:00',
      ),
    ], rules);
    final wakes = stays(proposals, PresenceRole.transitWake).single;
    expect(wakes.start, LocalDate(2026, 5, 2));
    expect(wakes.end, LocalDate(2026, 5, 3));
    final night = stays(proposals, PresenceRole.transitNight).single;
    expect(night.start, LocalDate(2026, 5, 1));
    expect(night.end, LocalDate(2026, 5, 2));
    expect(
      stays(proposals, PresenceRole.primary).single.start,
      LocalDate(2026, 5, 4),
    );
  });

  test('a same-day connection after wake time is a layover', () {
    final proposals = proposeItinerary([
      flight(
        id: 'in',
        from: 'SG',
        to: 'QA',
        depart: '2026-05-02T01:00',
        arrive: '2026-05-02T10:00',
      ),
      flight(
        id: 'out',
        from: 'QA',
        to: 'GB',
        depart: '2026-05-02T12:00',
        arrive: '2026-05-02T16:00',
      ),
    ], rules);
    final layover = stays(proposals, PresenceRole.layover).single;
    expect(layover.countryCode, 'QA');
    expect(layover.start, LocalDate(2026, 5, 2));
    expect(
      stays(
        proposals,
        PresenceRole.primary,
      ).where((stay) => stay.countryCode == 'QA'),
      isEmpty,
    );
  });

  test('waking up in the connection country is a main day', () {
    final proposals = proposeItinerary([
      flight(
        id: 'in',
        from: 'SG',
        to: 'QA',
        depart: '2026-05-02T01:00',
        arrive: '2026-05-02T06:00',
      ),
      flight(
        id: 'out',
        from: 'QA',
        to: 'GB',
        depart: '2026-05-02T09:00',
        arrive: '2026-05-02T14:00',
      ),
    ], rules);
    final primary = stays(
      proposals,
      PresenceRole.primary,
    ).singleWhere((stay) => stay.countryCode == 'QA');
    expect(primary.inference, InferenceKind.inferredConnection);
    expect(stays(proposals, PresenceRole.layover), isEmpty);
  });

  test('a multi-day hole between flights is not filled', () {
    final proposals = proposeItinerary([
      flight(
        id: 'in',
        from: 'PT',
        to: 'JP',
        depart: '2026-04-01T09:00',
        arrive: '2026-04-01T18:00',
      ),
      flight(
        id: 'out',
        from: 'JP',
        to: 'SG',
        depart: '2026-04-20T09:00',
        arrive: '2026-04-20T15:00',
      ),
    ], rules);
    expect(
      proposals.any((proposal) => proposal.reason.contains('stay unknown')),
      isTrue,
    );
    final japan = stays(
      proposals,
      PresenceRole.primary,
    ).where((stay) => stay.countryCode == 'JP');
    expect(japan.single.start, japan.single.end);
  });

  test('a backward civil date is manual review and creates no stay', () {
    final proposals = proposeItinerary([
      flight(
        id: 'back',
        from: 'US',
        to: 'WS',
        depart: '2026-06-02T12:00',
        arrive: '2026-06-01T18:00',
      ),
    ], rules);
    expect(proposals.single.needsManualReview, isTrue);
    expect(proposals.single.stay, isNull);
  });
}
