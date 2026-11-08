import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';

import '../engine/local_date.dart';
import '../engine/models.dart';
import '../platform/local_store.dart';
import 'instance_endpoint.dart';

const instanceOriginKey = 'nomadic.instanceOrigin';

class GatewayException implements Exception {
  GatewayException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class TravelSnapshot {
  const TravelSnapshot({
    required this.email,
    required this.origin,
    required this.stays,
    required this.flights,
    required this.rules,
    required this.statuses,
    this.warnings = const [],
  });

  final String email;
  final String origin;
  final List<Stay> stays;
  final List<FlightRecord> flights;
  final CountingRules rules;
  final List<EvidenceStatusDef> statuses;
  final List<String> warnings;
}

/// Talks only to an already allowlisted PocketBase origin.
///
/// Requests that redirect are refused. The auth token is stored in
/// [LocalStore] and is never written to logs by this class.
class PocketBaseGateway {
  PocketBaseGateway({LocalStore? store}) : store = store ?? createLocalStore();

  final LocalStore store;
  PocketBase? _client;
  InstanceEndpoint? endpoint;

  String? savedOrigin() => store.read(instanceOriginKey);

  void rememberOrigin(InstanceEndpoint value) {
    store.write(instanceOriginKey, value.origin.toString());
  }

  void forgetOrigin() {
    final current = endpoint;
    if (current != null) store.remove(_authKey(current));
    store.remove(instanceOriginKey);
  }

  Future<void> checkHealth(InstanceEndpoint target) async {
    final client = PocketBase(
      target.origin.toString(),
      httpClientFactory: _NoRedirectClient.new,
    );
    try {
      final health = await client.health.check();
      if (health.code != 200) {
        throw GatewayException(
          'The health check for ${target.displayHost} did not report a healthy API.',
          statusCode: health.code,
        );
      }
    } catch (error) {
      throw _wrap(error);
    }
  }

  Future<TravelSnapshot> signIn(
    InstanceEndpoint target,
    String email,
    String password,
  ) async {
    final client = _open(target, initial: store.read(_authKey(target)));
    try {
      await client.collection('users').authWithPassword(email.trim(), password);
      _adopt(target, client);
      rememberOrigin(target);
      return await _load();
    } catch (error) {
      throw _wrap(error);
    }
  }

  Future<TravelSnapshot> signUp(
    InstanceEndpoint target,
    String email,
    String password,
  ) async {
    final client = _open(target);
    try {
      await client
          .collection('users')
          .create(
            body: {
              'email': email.trim(),
              'password': password,
              'passwordConfirm': password,
            },
          );
      await client.collection('users').authWithPassword(email.trim(), password);
      _adopt(target, client);
      rememberOrigin(target);
      return await _load();
    } catch (error) {
      throw _wrap(error);
    }
  }

  /// Returns null when the instance is healthy and no usable session exists.
  Future<TravelSnapshot?> restore(InstanceEndpoint target) async {
    await checkHealth(target);
    final initial = store.read(_authKey(target));
    if (initial == null || initial.isEmpty) return null;
    final client = _open(target, initial: initial);
    if (!client.authStore.isValid) {
      client.authStore.clear();
      return null;
    }
    _adopt(target, client);
    try {
      return await _load();
    } catch (error) {
      throw _wrap(error);
    }
  }

  void signOut() {
    _client?.authStore.clear();
    _client = null;
    forgetOrigin();
    endpoint = null;
  }

  Future<Stay> createStay(Stay stay) async {
    final client = _required();
    final record = await client
        .collection('stays')
        .create(body: _stayBody(stay, _userId(client)));
    return _stayFrom(record.toJson());
  }

  Future<Stay> updateStay(Stay stay) async {
    final client = _required();
    final record = await client
        .collection('stays')
        .update(stay.id, body: _stayBody(stay, _userId(client)));
    return _stayFrom(record.toJson());
  }

  Future<void> deleteStay(String id) async {
    final client = _required();
    await client.collection('stays').delete(id);
  }

  Future<FlightRecord> createFlight(FlightRecord flight) async {
    final client = _required();
    final record = await client
        .collection('flights')
        .create(body: _flightBody(flight, _userId(client)));
    return _flightFrom(record.toJson());
  }

  Future<FlightRecord> updateFlight(FlightRecord flight) async {
    final client = _required();
    final record = await client
        .collection('flights')
        .update(flight.id, body: _flightBody(flight, _userId(client)));
    return _flightFrom(record.toJson());
  }

  Future<void> deleteFlight(String id) async {
    final client = _required();
    await client.collection('flights').delete(id);
  }

  Future<void> saveSettings({
    required CountingRules rules,
    required List<EvidenceStatusDef> statuses,
  }) async {
    final client = _required();
    final userId = _userId(client);
    final body = {
      'user': userId,
      'wake_hour': rules.wakeHour,
      'wake_minute': rules.wakeMinute,
      'include_inferred': rules.includeInferred,
      'personal_day_marker': rules.personalDayMarker ?? 0,
      'statuses_json': jsonEncode(
        statuses.map((status) => status.toJson()).toList(),
      ),
    };
    final existing = await client
        .collection('counting_settings')
        .getList(
          page: 1,
          perPage: 1,
          filter: client.filter('user = {:user}', {'user': userId}),
        );
    if (existing.items.isEmpty) {
      await client.collection('counting_settings').create(body: body);
    } else {
      await client
          .collection('counting_settings')
          .update(existing.items.first.id, body: body);
    }
  }

  PocketBase _open(InstanceEndpoint target, {String? initial}) {
    return PocketBase(
      target.origin.toString(),
      authStore: AsyncAuthStore(
        save: (data) async {
          if (data.isEmpty) {
            store.remove(_authKey(target));
          } else {
            store.write(_authKey(target), data);
          }
        },
        clear: () async => store.remove(_authKey(target)),
        initial: initial,
      ),
      httpClientFactory: _NoRedirectClient.new,
    );
  }

  void _adopt(InstanceEndpoint target, PocketBase client) {
    _client = client;
    endpoint = target;
  }

  PocketBase _required() {
    final client = _client;
    if (client == null || !client.authStore.isValid || endpoint == null) {
      throw GatewayException(
        'No per-user database session is open. Records were not sent anywhere.',
      );
    }
    return client;
  }

  String _userId(PocketBase client) {
    final id = client.authStore.record?.id ?? '';
    if (id.isEmpty) {
      throw GatewayException(
        'The session has no user id. Records were not written.',
      );
    }
    return id;
  }

  Future<TravelSnapshot> _load() async {
    final client = _required();
    final userId = _userId(client);
    final warnings = <String>[];
    final stayRecords = await client
        .collection('stays')
        .getFullList(
          filter: client.filter('user = {:user}', {'user': userId}),
          sort: 'start_date',
        );
    final flightRecords = await client
        .collection('flights')
        .getFullList(
          filter: client.filter('user = {:user}', {'user': userId}),
          sort: 'depart_local',
        );
    final settings = await client
        .collection('counting_settings')
        .getList(
          page: 1,
          perPage: 1,
          filter: client.filter('user = {:user}', {'user': userId}),
        );
    final stays = <Stay>[];
    for (final record in stayRecords) {
      try {
        stays.add(_stayFrom(record.toJson()));
      } on FormatException catch (error) {
        warnings.add('A stay was skipped. ${error.message}');
      }
    }
    final flights = <FlightRecord>[];
    for (final record in flightRecords) {
      try {
        flights.add(_flightFrom(record.toJson()));
      } on FormatException catch (error) {
        warnings.add('A flight was skipped. ${error.message}');
      }
    }
    final parsed = settings.items.isEmpty
        ? (rules: CountingRules.standard, statuses: defaultEvidenceStatuses)
        : _settingsFrom(settings.items.first.toJson(), warnings);
    final email = client.authStore.record?.get<String>('email', '') ?? '';
    return TravelSnapshot(
      email: email,
      origin: endpoint!.origin.toString(),
      stays: stays,
      flights: flights,
      rules: parsed.rules,
      statuses: parsed.statuses,
      warnings: warnings,
    );
  }
}

String _authKey(InstanceEndpoint endpoint) => 'nomadic.auth.${endpoint.origin}';

Map<String, Object> _stayBody(Stay stay, String userId) => {
  'user': userId,
  'country_code': stay.countryCode,
  'start_date': stay.start.iso,
  'end_date': stay.end.iso,
  'role': stay.role.wire,
  'evidence_status': stay.evidenceStatus,
  'inference': stay.inference.wire,
  'phase': stay.phase.wire,
  'timezone': stay.timezone,
  'notes': stay.notes,
  'external_id': stay.externalId,
  'source': stay.source.wire,
};

Map<String, Object> _flightBody(FlightRecord flight, String userId) => {
  'user': userId,
  'flight_number': flight.flightNumber,
  'from_iata': flight.fromIata,
  'to_iata': flight.toIata,
  'from_country': flight.fromCountry,
  'to_country': flight.toCountry,
  'depart_local': flight.depart.iso,
  'arrive_local': flight.arrive.iso,
  'depart_timezone': flight.departTimezone,
  'arrive_timezone': flight.arriveTimezone,
  'evidence_status': flight.evidenceStatus,
  'inference': flight.inference.wire,
  'review_state': flight.reviewState.wire,
  'notes': flight.notes,
  'external_id': flight.externalId,
};

Stay _stayFrom(Map<String, dynamic> json) {
  final role = PresenceRole.tryParse(_string(json, 'role'));
  final inference = InferenceKind.tryParse(_string(json, 'inference'));
  final phase = TripPhase.tryParse(_string(json, 'phase'));
  if (role == null || inference == null || phase == null) {
    throw const FormatException(
      'A stay uses a role, inference, or phase this app does not know.',
    );
  }
  final stay = Stay(
    id: _string(json, 'id'),
    countryCode: _string(json, 'country_code').toUpperCase(),
    start: LocalDate.parse(_string(json, 'start_date')),
    end: LocalDate.parse(_string(json, 'end_date')),
    role: role,
    evidenceStatus: _string(json, 'evidence_status'),
    inference: inference,
    phase: phase,
    timezone: _string(json, 'timezone'),
    notes: _string(json, 'notes'),
    externalId: _string(json, 'external_id'),
    source: RecordSource.parse(_string(json, 'source')),
  );
  final problem = validateStay(stay);
  if (problem != null) throw FormatException(problem);
  return stay;
}

FlightRecord _flightFrom(Map<String, dynamic> json) {
  final inference = InferenceKind.tryParse(_string(json, 'inference'));
  final review = FlightReviewState.tryParse(_string(json, 'review_state'));
  if (inference == null || review == null) {
    throw const FormatException(
      'A flight uses an inference or review state this app does not know.',
    );
  }
  final flight = FlightRecord(
    id: _string(json, 'id'),
    flightNumber: _string(json, 'flight_number').toUpperCase(),
    fromIata: _string(json, 'from_iata').toUpperCase(),
    toIata: _string(json, 'to_iata').toUpperCase(),
    fromCountry: _string(json, 'from_country').toUpperCase(),
    toCountry: _string(json, 'to_country').toUpperCase(),
    depart: WallTime.parse(_string(json, 'depart_local')),
    arrive: WallTime.parse(_string(json, 'arrive_local')),
    departTimezone: _string(json, 'depart_timezone'),
    arriveTimezone: _string(json, 'arrive_timezone'),
    evidenceStatus: _string(json, 'evidence_status'),
    inference: inference,
    reviewState: review,
    notes: _string(json, 'notes'),
    externalId: _string(json, 'external_id'),
  );
  final problem = validateFlight(flight);
  if (problem != null) throw FormatException(problem);
  return flight;
}

({CountingRules rules, List<EvidenceStatusDef> statuses}) _settingsFrom(
  Map<String, dynamic> json,
  List<String> warnings,
) {
  final hour = _int(json, 'wake_hour', 8).clamp(0, 23);
  final minute = _int(json, 'wake_minute', 0).clamp(0, 59);
  final marker = _int(json, 'personal_day_marker', 0);
  final statuses = <EvidenceStatusDef>[];
  try {
    final raw = jsonDecode(_string(json, 'statuses_json'));
    if (raw is List) {
      for (final item in raw) {
        final parsed = EvidenceStatusDef.fromJson(item);
        if (parsed != null) statuses.add(parsed);
      }
    }
  } on FormatException {
    warnings.add(
      'Evidence statuses could not be read. The defaults are in use.',
    );
  }
  if (statuses.isEmpty) {
    statuses.addAll(defaultEvidenceStatuses);
    warnings.add('Evidence statuses were empty. The defaults are in use.');
  }
  return (
    rules: CountingRules(
      wakeHour: hour,
      wakeMinute: minute,
      includeInferred: json['include_inferred'] == true,
      personalDayMarker: marker > 0 ? marker : null,
    ),
    statuses: statuses,
  );
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return '';
  return value.toString();
}

int _int(Map<String, dynamic> json, String key, int fallback) {
  final value = json[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

GatewayException _wrap(Object error) {
  if (error is GatewayException) return error;
  if (error is ClientException) {
    final original = error.originalError?.toString() ?? '';
    if (original.toLowerCase().contains('redirect')) {
      return GatewayException(
        'The database URL redirected. The request was refused.',
      );
    }
    if (error.isAbort || error.statusCode == 0) {
      return GatewayException('The database could not be reached.');
    }
    final raw = error.response['message'];
    final safe =
        raw is String &&
            raw.isNotEmpty &&
            !raw.toLowerCase().contains('token') &&
            !raw.toLowerCase().contains('password')
        ? raw
        : '';
    final code = error.statusCode;
    final suffix = ' ($code)';
    if (safe.isEmpty) {
      return GatewayException(
        'The database refused the request$suffix.',
        statusCode: code,
      );
    }
    return GatewayException(
      'The database refused the request$suffix. $safe',
      statusCode: code,
    );
  }
  return GatewayException('The database could not be reached.');
}

class _NoRedirectClient extends http.BaseClient {
  _NoRedirectClient() : _inner = http.Client();

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.followRedirects = false;
    final response = await _inner.send(request);
    if (response.statusCode >= 300 && response.statusCode < 400) {
      await response.stream.drain<void>();
      throw http.ClientException('Refusing to follow a redirect.', request.url);
    }
    return response;
  }

  @override
  void close() => _inner.close();
}
