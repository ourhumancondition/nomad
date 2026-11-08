import 'local_date.dart';
import 'models.dart';

const csvColumns = <String>[
  'record_type',
  'external_id',
  'country_code',
  'start_date',
  'end_date',
  'role',
  'evidence_status',
  'inference',
  'phase',
  'timezone',
  'notes',
  'flight_number',
  'from_iata',
  'to_iata',
  'from_country',
  'to_country',
  'depart_local',
  'arrive_local',
  'depart_timezone',
  'arrive_timezone',
  'review_state',
];

class CsvImportPreview {
  const CsvImportPreview({
    required this.stays,
    required this.flights,
    required this.errors,
    required this.exampleDataset,
  });

  final List<Stay> stays;
  final List<FlightRecord> flights;
  final List<String> errors;
  final bool exampleDataset;

  bool get hasRows => stays.isNotEmpty || flights.isNotEmpty;
}

class CsvCodec {
  const CsvCodec();

  static String encode({
    required List<Stay> stays,
    required List<FlightRecord> flights,
    required bool exampleDataset,
  }) {
    final buffer = StringBuffer();
    buffer.writeln(_encodeRow(csvColumns));
    buffer.writeln(
      _encodeRow([
        'meta',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        exampleDataset
            ? 'EXAMPLE DATASET. Fictional Nomadic Residence rows. Not a connected account and not a legal or tax record.'
            : 'Nomadic Residence export. Day counts are not a legal or tax record.',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
      ]),
    );
    final stayRows = [...stays]..sort((a, b) => a.start.compareTo(b.start));
    for (final stay in stayRows) {
      buffer.writeln(
        _encodeRow([
          'stay',
          stay.externalId,
          stay.countryCode,
          stay.start.iso,
          stay.end.iso,
          stay.role.wire,
          stay.evidenceStatus,
          stay.inference.wire,
          stay.phase.wire,
          stay.timezone,
          stay.notes,
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
        ]),
      );
    }
    final flightRows = [...flights]..sort(compareFlights);
    for (final flight in flightRows) {
      buffer.writeln(
        _encodeRow([
          'flight',
          flight.externalId,
          '',
          '',
          '',
          '',
          flight.evidenceStatus,
          flight.inference.wire,
          '',
          '',
          flight.notes,
          flight.flightNumber,
          flight.fromIata,
          flight.toIata,
          flight.fromCountry,
          flight.toCountry,
          flight.depart.iso,
          flight.arrive.iso,
          flight.departTimezone,
          flight.arriveTimezone,
          flight.reviewState.wire,
        ]),
      );
    }
    return buffer.toString();
  }

  static CsvImportPreview parse(String raw) {
    var text = raw;
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    final rows = _parseRows(text)
        .where((row) => row.any((cell) => cell.trim().isNotEmpty))
        .toList();
    if (rows.isEmpty) {
      return const CsvImportPreview(
        stays: [],
        flights: [],
        errors: ['The file has no rows.'],
        exampleDataset: false,
      );
    }
    final header = rows.first.map((cell) => cell.trim()).toList();
    if (header.length != csvColumns.length ||
        !_sameHeader(header, csvColumns)) {
      return CsvImportPreview(
        stays: const [],
        flights: const [],
        errors: [
          'The header row must match the Nomadic Residence sheet: ${csvColumns.join(', ')}.',
        ],
        exampleDataset: false,
      );
    }
    final index = <String, int>{
      for (var i = 0; i < header.length; i++) header[i]: i,
    };
    final stays = <Stay>[];
    final flights = <FlightRecord>[];
    final errors = <String>[];
    var exampleDataset = false;
    var sequence = 0;

    for (var rowNumber = 1; rowNumber < rows.length; rowNumber++) {
      final row = rows[rowNumber];
      String cell(String name) {
        final at = index[name]!;
        return at < row.length ? row[at].trim() : '';
      }

      final type = cell('record_type');
      final line = rowNumber + 1;
      if (type == 'meta') {
        final notes = cell('notes');
        if (notes.contains('EXAMPLE DATASET')) exampleDataset = true;
        continue;
      }
      if (type == 'stay') {
        sequence += 1;
        final parsed = _stay(cell, sequence, line);
        if (parsed.error != null) {
          errors.add(parsed.error!);
        } else {
          stays.add(parsed.stay!);
        }
        continue;
      }
      if (type == 'flight') {
        sequence += 1;
        final parsed = _flight(cell, sequence, line);
        if (parsed.error != null) {
          errors.add(parsed.error!);
        } else {
          flights.add(parsed.flight!);
        }
        continue;
      }
      errors.add('Row $line has an unknown record_type "$type".');
    }

    return CsvImportPreview(
      stays: stays,
      flights: flights,
      errors: errors,
      exampleDataset: exampleDataset,
    );
  }

  static ({Stay? stay, String? error}) _stay(
    String Function(String) cell,
    int sequence,
    int line,
  ) {
    try {
      final role = PresenceRole.tryParse(cell('role'));
      final inference = InferenceKind.tryParse(cell('inference'));
      final phase = TripPhase.tryParse(cell('phase'));
      if (role == null || inference == null || phase == null) {
        return (
          stay: null,
          error:
              'Row $line has a role, inference, or phase this app does not know.',
        );
      }
      final stay = Stay(
        id: 'csv-stay-$sequence',
        countryCode: cell('country_code').toUpperCase(),
        start: LocalDate.parse(cell('start_date')),
        end: LocalDate.parse(cell('end_date')),
        role: role,
        evidenceStatus: cell('evidence_status'),
        inference: inference,
        phase: phase,
        timezone: cell('timezone'),
        notes: cell('notes'),
        externalId: cell('external_id'),
        source: RecordSource.csv,
      );
      final problem = validateStay(stay);
      if (problem != null) return (stay: null, error: 'Row $line: $problem');
      return (stay: stay, error: null);
    } on FormatException catch (error) {
      return (stay: null, error: 'Row $line: ${error.message}');
    }
  }

  static ({FlightRecord? flight, String? error}) _flight(
    String Function(String) cell,
    int sequence,
    int line,
  ) {
    try {
      final inference = InferenceKind.tryParse(cell('inference'));
      final review = FlightReviewState.tryParse(cell('review_state'));
      if (inference == null || review == null) {
        return (
          flight: null,
          error:
              'Row $line has an inference or review state this app does not know.',
        );
      }
      final flight = FlightRecord(
        id: 'csv-flight-$sequence',
        flightNumber: cell('flight_number').toUpperCase(),
        fromIata: cell('from_iata').toUpperCase(),
        toIata: cell('to_iata').toUpperCase(),
        fromCountry: cell('from_country').toUpperCase(),
        toCountry: cell('to_country').toUpperCase(),
        depart: WallTime.parse(cell('depart_local')),
        arrive: WallTime.parse(cell('arrive_local')),
        departTimezone: cell('depart_timezone'),
        arriveTimezone: cell('arrive_timezone'),
        evidenceStatus: cell('evidence_status'),
        inference: inference,
        reviewState: review,
        notes: cell('notes'),
        externalId: cell('external_id'),
      );
      final problem = validateFlight(flight);
      if (problem != null) return (flight: null, error: 'Row $line: $problem');
      return (flight: flight, error: null);
    } on FormatException catch (error) {
      return (flight: null, error: 'Row $line: ${error.message}');
    }
  }

  static bool _sameHeader(List<String> header, List<String> expected) {
    for (var i = 0; i < expected.length; i++) {
      if (header[i] != expected[i]) return false;
    }
    return true;
  }
}

String _encodeRow(List<String> cells) => cells.map(_escape).join(',');

String _escape(String value) {
  if (value.contains(',') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

List<List<String>> _parseRows(String text) {
  final rows = <List<String>>[];
  final row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (quoted) {
      if (char == '"') {
        final next = i + 1 < text.length ? text[i + 1] : '';
        if (next == '"') {
          cell.write('"');
          i += 1;
        } else {
          quoted = false;
        }
      } else {
        cell.write(char);
      }
      continue;
    }
    if (char == '"') {
      quoted = true;
      continue;
    }
    if (char == ',') {
      row.add(cell.toString());
      cell.clear();
      continue;
    }
    if (char == '\n') {
      row.add(cell.toString());
      cell.clear();
      rows.add(List<String>.of(row));
      row.clear();
      continue;
    }
    if (char == '\r') continue;
    cell.write(char);
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString());
    rows.add(List<String>.of(row));
  }
  return rows;
}
