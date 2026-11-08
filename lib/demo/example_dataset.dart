import '../engine/local_date.dart';
import '../engine/models.dart';

/// Fictional presence used only when someone explicitly opens the example.
///
/// These rows are not a real itinerary, not an account, and not a connection
/// to PocketBase. Every note says so.
class ExampleDataset {
  const ExampleDataset({required this.stays, required this.flights});

  final List<Stay> stays;
  final List<FlightRecord> flights;

  static const storyYear = 2026;
  static final designedFor = LocalDate(2026, 11, 8);
}

ExampleDataset buildExampleDataset() {
  Stay stay({
    required String id,
    required String country,
    required String start,
    required String end,
    required PresenceRole role,
    required String evidence,
    InferenceKind inference = InferenceKind.none,
    TripPhase phase = TripPhase.actual,
    required String timezone,
    required String notes,
  }) {
    return Stay(
      id: id,
      countryCode: country,
      start: LocalDate.parse(start),
      end: LocalDate.parse(end),
      role: role,
      evidenceStatus: evidence,
      inference: inference,
      phase: phase,
      timezone: timezone,
      notes: notes,
      externalId: id,
      source: RecordSource.manual,
    );
  }

  final stays = <Stay>[
    stay(
      id: 'example-pt',
      country: 'PT',
      start: '2026-01-01',
      end: '2026-03-31',
      role: PresenceRole.primary,
      evidence: 'confirmed',
      timezone: 'Europe/Lisbon',
      notes: 'Example stay. Wake-ups in Portugal. Fictional.',
    ),
    stay(
      id: 'example-jp',
      country: 'JP',
      start: '2026-04-15',
      end: '2026-04-20',
      role: PresenceRole.primary,
      evidence: 'confirmed',
      timezone: 'Asia/Tokyo',
      notes: 'Example stay. Wake-ups in Japan. Fictional.',
    ),
    stay(
      id: 'example-night',
      country: '',
      start: '2026-04-20',
      end: '2026-04-20',
      role: PresenceRole.transitNight,
      evidence: 'confirmed',
      timezone: 'Asia/Tokyo',
      notes: 'Example overnight flight EX201. The night is in transit. The wake-up that morning stays Japan. Fictional.',
    ),
    stay(
      id: 'example-sg',
      country: 'SG',
      start: '2026-04-21',
      end: '2026-06-30',
      role: PresenceRole.primary,
      evidence: 'confirmed',
      timezone: 'Asia/Singapore',
      notes: 'Example stay. Wake-ups in Singapore. Fictional.',
    ),
    stay(
      id: 'example-qa',
      country: 'QA',
      start: '2026-05-02',
      end: '2026-05-02',
      role: PresenceRole.layover,
      evidence: 'confirmed',
      timezone: 'Asia/Qatar',
      notes: 'Example layover in Qatar on a day whose wake-up is Singapore. Fictional.',
    ),
    stay(
      id: 'example-gr',
      country: 'GR',
      start: '2026-07-01',
      end: '2026-07-10',
      role: PresenceRole.primary,
      evidence: 'confirmed',
      timezone: 'Europe/Athens',
      notes: 'Example stay. Overlaps the Italy example from 5 July. Fictional.',
    ),
    stay(
      id: 'example-it',
      country: 'IT',
      start: '2026-07-05',
      end: '2026-07-12',
      role: PresenceRole.primary,
      evidence: 'confirmed',
      timezone: 'Europe/Rome',
      notes: 'Example stay. Shares 5–10 July with Greece, so those dates stay unresolved. Fictional.',
    ),
    stay(
      id: 'example-fr-booking',
      country: 'FR',
      start: '2026-08-01',
      end: '2026-08-20',
      role: PresenceRole.primary,
      evidence: 'booking_only',
      timezone: 'Europe/Paris',
      notes: 'Example booking that was not corroborated. It stays out of the actual total. Fictional.',
    ),
    stay(
      id: 'example-fr-inference',
      country: 'FR',
      start: '2026-08-21',
      end: '2026-08-25',
      role: PresenceRole.primary,
      evidence: 'confirmed',
      inference: InferenceKind.inferredItinerary,
      timezone: 'Europe/Paris',
      notes: 'Example inference. The evidence status is confirmed, and the inference mark keeps it out until you opt in. Fictional.',
    ),
    stay(
      id: 'example-air',
      country: '',
      start: '2026-09-15',
      end: '2026-09-15',
      role: PresenceRole.transitWake,
      evidence: 'confirmed',
      timezone: 'Etc/UTC',
      notes: 'Example wake-up spent in the air. Fictional.',
    ),
    stay(
      id: 'example-mx',
      country: 'MX',
      start: '2026-10-01',
      end: '2026-11-08',
      role: PresenceRole.primary,
      evidence: 'confirmed',
      timezone: 'America/Mexico_City',
      notes: 'Example stay. Wake-ups in Mexico through 8 November 2026. Fictional.',
    ),
    stay(
      id: 'example-cl',
      country: 'CL',
      start: '2026-12-01',
      end: '2026-12-05',
      role: PresenceRole.primary,
      evidence: 'confirmed',
      timezone: 'America/Santiago',
      notes: 'Example future dates stored with an actual phase. They stay out of the actual total until those dates arrive. Fictional.',
    ),
    stay(
      id: 'example-nz',
      country: 'NZ',
      start: '2026-12-20',
      end: '2026-12-31',
      role: PresenceRole.primary,
      evidence: 'confirmed',
      phase: TripPhase.planned,
      timezone: 'Pacific/Auckland',
      notes: 'Example planned trip. Kept off the actual total. Fictional.',
    ),
    stay(
      id: 'example-is',
      country: 'IS',
      start: '2024-02-28',
      end: '2024-03-02',
      role: PresenceRole.primary,
      evidence: 'confirmed',
      timezone: 'Atlantic/Reykjavik',
      notes: 'Example leap-year stay, including 29 February 2024. Fictional.',
    ),
  ];

  FlightRecord flight({
    required String id,
    required String number,
    required String fromIata,
    required String toIata,
    required String fromCountry,
    required String toCountry,
    required String depart,
    required String arrive,
    required String departZone,
    required String arriveZone,
    required String evidence,
    required FlightReviewState review,
    required String notes,
  }) {
    return FlightRecord(
      id: id,
      flightNumber: number,
      fromIata: fromIata,
      toIata: toIata,
      fromCountry: fromCountry,
      toCountry: toCountry,
      depart: WallTime.parse(depart),
      arrive: WallTime.parse(arrive),
      departTimezone: departZone,
      arriveTimezone: arriveZone,
      evidenceStatus: evidence,
      inference: InferenceKind.none,
      reviewState: review,
      notes: notes,
      externalId: id,
    );
  }

  final flights = <FlightRecord>[
    flight(
      id: 'example-ex201',
      number: 'EX201',
      fromIata: 'NRT',
      toIata: 'SIN',
      fromCountry: 'JP',
      toCountry: 'SG',
      depart: '2026-04-20T22:40',
      arrive: '2026-04-21T04:10',
      departZone: 'Asia/Tokyo',
      arriveZone: 'Asia/Singapore',
      evidence: 'confirmed',
      review: FlightReviewState.accepted,
      notes: 'Example accepted flight. The resulting example stays are already listed. Fictional.',
    ),
    flight(
      id: 'example-ex512',
      number: 'EX512',
      fromIata: 'CDG',
      toIata: 'TUN',
      fromCountry: 'FR',
      toCountry: 'TN',
      depart: '2026-08-10T18:00',
      arrive: '2026-08-10T20:10',
      departZone: 'Europe/Paris',
      arriveZone: 'Africa/Tunis',
      evidence: 'booking_only',
      review: FlightReviewState.pending,
      notes: 'Example booking only. Proposals stay out of totals until you accept them. Fictional.',
    ),
    flight(
      id: 'example-ex440',
      number: 'EX440',
      fromIata: 'MEX',
      toIata: 'AKL',
      fromCountry: 'MX',
      toCountry: 'NZ',
      depart: '2026-12-19T22:00',
      arrive: '2026-12-21T06:30',
      departZone: 'America/Mexico_City',
      arriveZone: 'Pacific/Auckland',
      evidence: 'booking_only',
      review: FlightReviewState.pending,
      notes: 'Example future booking. The nights are not actual totals while the dates are still ahead. Fictional.',
    ),
  ];

  return ExampleDataset(stays: stays, flights: flights);
}
