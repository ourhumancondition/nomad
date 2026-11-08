import 'local_date.dart';

/// How a record occupies a calendar day.
enum PresenceRole {
  primary('primary'),
  layover('layover'),
  transitWake('transit_wake'),
  transitNight('transit_night');

  const PresenceRole(this.wire);
  final String wire;

  String get label => switch (this) {
    PresenceRole.primary => 'Wake-up country',
    PresenceRole.layover => 'Layover',
    PresenceRole.transitWake => 'In transit at wake-up',
    PresenceRole.transitNight => 'Overnight in transit',
  };

  static PresenceRole? tryParse(String raw) {
    for (final role in PresenceRole.values) {
      if (role.wire == raw) return role;
    }
    return null;
  }
}

/// Whether a record was observed or produced by an explicit inference.
enum InferenceKind {
  none('none'),
  inferredItinerary('inferred_itinerary'),
  inferredConnection('inferred_connection'),
  inferredGap('inferred_gap');

  const InferenceKind(this.wire);
  final String wire;

  String get label => switch (this) {
    InferenceKind.none => 'Observed',
    InferenceKind.inferredItinerary => 'Inferred from itinerary',
    InferenceKind.inferredConnection => 'Inferred connection',
    InferenceKind.inferredGap => 'Inferred gap',
  };

  bool get isInference => this != InferenceKind.none;

  static InferenceKind? tryParse(String raw) {
    for (final value in InferenceKind.values) {
      if (value.wire == raw) return value;
    }
    return null;
  }
}

enum TripPhase {
  actual('actual'),
  planned('planned');

  const TripPhase(this.wire);
  final String wire;

  String get label => switch (this) {
    TripPhase.actual => 'Actual',
    TripPhase.planned => 'Planned',
  };

  static TripPhase? tryParse(String raw) {
    for (final value in TripPhase.values) {
      if (value.wire == raw) return value;
    }
    return null;
  }
}

enum RecordSource {
  manual('manual'),
  csv('csv'),
  flightReview('flight_review');

  const RecordSource(this.wire);
  final String wire;

  static RecordSource parse(String raw) {
    for (final value in RecordSource.values) {
      if (value.wire == raw) return value;
    }
    return RecordSource.manual;
  }
}

enum FlightReviewState {
  pending('pending'),
  accepted('accepted'),
  rejected('rejected'),
  needsManual('needs_manual');

  const FlightReviewState(this.wire);
  final String wire;

  String get label => switch (this) {
    FlightReviewState.pending => 'Needs review',
    FlightReviewState.accepted => 'Accepted',
    FlightReviewState.rejected => 'Rejected',
    FlightReviewState.needsManual => 'Needs a manual stay',
  };

  static FlightReviewState? tryParse(String raw) {
    for (final value in FlightReviewState.values) {
      if (value.wire == raw) return value;
    }
    return null;
  }
}

/// A status the traveler can edit. Counting follows [countsAsActual].
class EvidenceStatusDef {
  const EvidenceStatusDef({
    required this.id,
    required this.label,
    required this.countsAsActual,
  });

  final String id;
  final String label;
  final bool countsAsActual;

  EvidenceStatusDef copyWith({String? label, bool? countsAsActual}) =>
      EvidenceStatusDef(
        id: id,
        label: label ?? this.label,
        countsAsActual: countsAsActual ?? this.countsAsActual,
      );

  Map<String, Object> toJson() => {
    'id': id,
    'label': label,
    'countsAsActual': countsAsActual,
  };

  static EvidenceStatusDef? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final label = raw['label'];
    final counts = raw['countsAsActual'];
    if (id is! String || label is! String || counts is! bool) return null;
    if (!statusIdPattern.hasMatch(id)) return null;
    return EvidenceStatusDef(id: id, label: label, countsAsActual: counts);
  }
}

final statusIdPattern = RegExp(r'^[a-z][a-z0-9_]{0,40}$');

const defaultEvidenceStatuses = <EvidenceStatusDef>[
  EvidenceStatusDef(id: 'confirmed', label: 'Confirmed', countsAsActual: true),
  EvidenceStatusDef(
    id: 'corroborated',
    label: 'Corroborated',
    countsAsActual: true,
  ),
  EvidenceStatusDef(
    id: 'booking_only',
    label: 'Booking only',
    countsAsActual: false,
  ),
  EvidenceStatusDef(id: 'inferred', label: 'Inferred', countsAsActual: false),
  EvidenceStatusDef(id: 'unknown', label: 'Unknown', countsAsActual: false),
];

const lockedStatusIds = <String>{
  'confirmed',
  'corroborated',
  'booking_only',
  'inferred',
  'unknown',
};

/// Rules the traveler can change. Safety invariants are not fields here.
class CountingRules {
  const CountingRules({
    this.wakeHour = 8,
    this.wakeMinute = 0,
    this.includeInferred = false,
    this.personalDayMarker,
  }) : assert(wakeHour >= 0 && wakeHour <= 23),
       assert(wakeMinute >= 0 && wakeMinute <= 59);

  static const standard = CountingRules();

  final int wakeHour;
  final int wakeMinute;
  final bool includeInferred;

  /// Empty when unset. A number here is a personal highlight, never a legal test.
  final int? personalDayMarker;

  int get wakeMinutes => wakeHour * 60 + wakeMinute;

  String get wakeLabel =>
      '${wakeHour.toString().padLeft(2, '0')}:${wakeMinute.toString().padLeft(2, '0')}';

  CountingRules copyWith({
    int? wakeHour,
    int? wakeMinute,
    bool? includeInferred,
    int? personalDayMarker,
    bool clearMarker = false,
  }) => CountingRules(
    wakeHour: wakeHour ?? this.wakeHour,
    wakeMinute: wakeMinute ?? this.wakeMinute,
    includeInferred: includeInferred ?? this.includeInferred,
    personalDayMarker: clearMarker
        ? null
        : (personalDayMarker ?? this.personalDayMarker),
  );
}

const lockedRuleStatements = <String>[
  'The main day belongs to the country you are in at the wake time.',
  'Layover presence is listed beside the main day and stays out of that total.',
  'A night spent on an overnight flight is marked In transit and stays out of the wake-up country total.',
  'A wake-up spent in the air is an in-transit main day.',
  'Two wake-up countries on the same date stay unresolved until you edit one of them.',
  'A date with no countable stay stays unknown. Empty dates are not filled in.',
  'Planned trips stay on their own list.',
  'Dates after today stay out of actual totals.',
  'A leap day remains in the year that contains it.',
  'Local dates are stored as written. They are not shifted through UTC.',
];

final timezonePattern = RegExp(r'^[A-Za-z0-9+\-]+(?:/[A-Za-z0-9._+\-]+)*$');

const commonTimezones = <String>[
  'Etc/UTC',
  'Atlantic/Reykjavik',
  'Europe/Lisbon',
  'Europe/London',
  'Europe/Paris',
  'Europe/Athens',
  'Europe/Rome',
  'Africa/Cairo',
  'Africa/Johannesburg',
  'Africa/Tunis',
  'Asia/Dubai',
  'Asia/Qatar',
  'Asia/Kolkata',
  'Asia/Bangkok',
  'Asia/Singapore',
  'Asia/Hong_Kong',
  'Asia/Shanghai',
  'Asia/Tokyo',
  'Asia/Seoul',
  'Australia/Sydney',
  'Pacific/Auckland',
  'Pacific/Honolulu',
  'America/Anchorage',
  'America/Los_Angeles',
  'America/Denver',
  'America/Chicago',
  'America/New_York',
  'America/Mexico_City',
  'America/Bogota',
  'America/Santiago',
  'America/Sao_Paulo',
  'America/Argentina/Buenos_Aires',
];

class Stay {
  const Stay({
    required this.id,
    required this.countryCode,
    required this.start,
    required this.end,
    required this.role,
    required this.evidenceStatus,
    required this.inference,
    required this.phase,
    required this.timezone,
    this.notes = '',
    this.externalId = '',
    this.source = RecordSource.manual,
  });

  final String id;
  final String countryCode;
  final LocalDate start;
  final LocalDate end;
  final PresenceRole role;
  final String evidenceStatus;
  final InferenceKind inference;
  final TripPhase phase;
  final String timezone;
  final String notes;
  final String externalId;
  final RecordSource source;

  bool covers(LocalDate date) => date >= start && date <= end;

  Stay copyWith({
    String? id,
    String? countryCode,
    LocalDate? start,
    LocalDate? end,
    PresenceRole? role,
    String? evidenceStatus,
    InferenceKind? inference,
    TripPhase? phase,
    String? timezone,
    String? notes,
    String? externalId,
    RecordSource? source,
  }) => Stay(
    id: id ?? this.id,
    countryCode: countryCode ?? this.countryCode,
    start: start ?? this.start,
    end: end ?? this.end,
    role: role ?? this.role,
    evidenceStatus: evidenceStatus ?? this.evidenceStatus,
    inference: inference ?? this.inference,
    phase: phase ?? this.phase,
    timezone: timezone ?? this.timezone,
    notes: notes ?? this.notes,
    externalId: externalId ?? this.externalId,
    source: source ?? this.source,
  );
}

class FlightRecord {
  const FlightRecord({
    required this.id,
    required this.flightNumber,
    required this.fromIata,
    required this.toIata,
    required this.fromCountry,
    required this.toCountry,
    required this.depart,
    required this.arrive,
    required this.departTimezone,
    required this.arriveTimezone,
    required this.evidenceStatus,
    required this.inference,
    required this.reviewState,
    this.notes = '',
    this.externalId = '',
  });

  final String id;
  final String flightNumber;
  final String fromIata;
  final String toIata;
  final String fromCountry;
  final String toCountry;
  final WallTime depart;
  final WallTime arrive;
  final String departTimezone;
  final String arriveTimezone;
  final String evidenceStatus;
  final InferenceKind inference;
  final FlightReviewState reviewState;
  final String notes;
  final String externalId;

  FlightRecord copyWith({
    String? id,
    FlightReviewState? reviewState,
    String? evidenceStatus,
    InferenceKind? inference,
    String? notes,
  }) => FlightRecord(
    id: id ?? this.id,
    flightNumber: flightNumber,
    fromIata: fromIata,
    toIata: toIata,
    fromCountry: fromCountry,
    toCountry: toCountry,
    depart: depart,
    arrive: arrive,
    departTimezone: departTimezone,
    arriveTimezone: arriveTimezone,
    evidenceStatus: evidenceStatus ?? this.evidenceStatus,
    inference: inference ?? this.inference,
    reviewState: reviewState ?? this.reviewState,
    notes: notes ?? this.notes,
    externalId: externalId,
  );
}

String? validateStay(Stay stay) {
  if (stay.end < stay.start) {
    return 'The end date is before the start date.';
  }
  final needsCountry =
      stay.role == PresenceRole.primary || stay.role == PresenceRole.layover;
  if (needsCountry && !RegExp(r'^[A-Z]{2}$').hasMatch(stay.countryCode)) {
    return 'Choose a two-letter country code.';
  }
  if (!needsCountry &&
      stay.countryCode.isNotEmpty &&
      !RegExp(r'^[A-Z]{2}$').hasMatch(stay.countryCode)) {
    return 'Leave the country empty for in-transit records, or use a two-letter code.';
  }
  if (!statusIdPattern.hasMatch(stay.evidenceStatus)) {
    return 'Evidence status ids use lowercase letters, numbers, and underscores.';
  }
  if (stay.timezone.isEmpty ||
      stay.timezone.length > 64 ||
      !timezonePattern.hasMatch(stay.timezone)) {
    return 'Use an IANA time zone such as Europe/Lisbon.';
  }
  if (stay.notes.length > 2000) return 'Notes are limited to 2000 characters.';
  if (stay.externalId.length > 80) {
    return 'External ids are limited to 80 characters.';
  }
  return null;
}

String? validateFlight(FlightRecord flight) {
  if (!RegExp(r'^[A-Z0-9]{2,8}$').hasMatch(flight.flightNumber)) {
    return 'Flight numbers use 2 to 8 letters or digits.';
  }
  if (!RegExp(r'^[A-Z]{3}$').hasMatch(flight.fromIata) ||
      !RegExp(r'^[A-Z]{3}$').hasMatch(flight.toIata)) {
    return 'Airports use three-letter codes.';
  }
  if (!RegExp(r'^[A-Z]{2}$').hasMatch(flight.fromCountry) ||
      !RegExp(r'^[A-Z]{2}$').hasMatch(flight.toCountry)) {
    return 'Choose a country for each airport.';
  }
  for (final zone in [flight.departTimezone, flight.arriveTimezone]) {
    if (zone.isEmpty || zone.length > 64 || !timezonePattern.hasMatch(zone)) {
      return 'Use an IANA time zone on both ends of the flight.';
    }
  }
  if (!statusIdPattern.hasMatch(flight.evidenceStatus)) {
    return 'Evidence status ids use lowercase letters, numbers, and underscores.';
  }
  if (flight.notes.length > 2000) {
    return 'Notes are limited to 2000 characters.';
  }
  return null;
}

int compareFlights(FlightRecord a, FlightRecord b) {
  final byDate = a.depart.date.compareTo(b.depart.date);
  if (byDate != 0) return byDate;
  final byTime = a.depart.minutes.compareTo(b.depart.minutes);
  if (byTime != 0) return byTime;
  return a.id.compareTo(b.id);
}
