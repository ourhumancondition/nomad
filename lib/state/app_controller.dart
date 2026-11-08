import 'package:flutter/foundation.dart';

import '../data/instance_endpoint.dart';
import '../data/pocketbase_gateway.dart';
import '../demo/example_dataset.dart';
import '../engine/csv_codec.dart';
import '../engine/day_engine.dart';
import '../engine/flight_proposals.dart';
import '../engine/local_date.dart';
import '../engine/models.dart';

enum SessionKind { unconfigured, example, connected }

class AppController extends ChangeNotifier {
  AppController({
    LocalDate Function()? clock,
    PocketBaseGateway? gateway,
    bool? allowLocalEndpoints,
  }) : clock = clock ?? LocalDate.todayDevice,
       gateway = gateway ?? PocketBaseGateway(),
       allowLocalEndpoints =
           allowLocalEndpoints ??
           (kDebugMode ||
               const bool.fromEnvironment('ALLOW_LOCAL_POCKETBASE')) {
    year = this.clock().year;
  }

  final LocalDate Function() clock;
  final PocketBaseGateway gateway;
  final bool allowLocalEndpoints;

  SessionKind kind = SessionKind.unconfigured;
  int year = 2026;
  CountingRules rules = CountingRules.standard;
  List<EvidenceStatusDef> statuses = List<EvidenceStatusDef>.of(
    defaultEvidenceStatuses,
  );
  List<Stay> stays = [];
  List<FlightRecord> flights = [];
  String? accountEmail;
  String? instanceOrigin;
  InstanceEndpoint? pendingEndpoint;
  String? statusMessage;
  String? errorMessage;
  bool busy = false;
  int _sequence = 0;

  bool get isExample => kind == SessionKind.example;
  bool get isConnected => kind == SessionKind.connected;
  bool get canEdit => kind != SessionKind.unconfigured;

  YearTally get tally => DayEngine.tally(
    stays: stays,
    year: year,
    today: clock(),
    rules: rules,
    statuses: statuses,
  );

  List<int> get years {
    final values = <int>{year, clock().year};
    for (final stay in stays) {
      values.add(stay.start.year);
      values.add(stay.end.year);
    }
    for (final flight in flights) {
      values.add(flight.depart.date.year);
      values.add(flight.arrive.date.year);
    }
    final sorted = values.toList()..sort((a, b) => b.compareTo(a));
    return sorted;
  }

  void openExample() {
    final dataset = buildExampleDataset();
    kind = SessionKind.example;
    stays = dataset.stays;
    flights = dataset.flights;
    rules = CountingRules.standard;
    statuses = List<EvidenceStatusDef>.of(defaultEvidenceStatuses);
    year = ExampleDataset.storyYear;
    accountEmail = null;
    pendingEndpoint = null;
    errorMessage = null;
    statusMessage = 'Example dataset. These fictional rows stay in this tab and are not sent to PocketBase.';
    notifyListeners();
  }

  void leaveExample() {
    if (kind != SessionKind.example) return;
    kind = SessionKind.unconfigured;
    stays = [];
    flights = [];
    rules = CountingRules.standard;
    statuses = List<EvidenceStatusDef>.of(defaultEvidenceStatuses);
    year = clock().year;
    statusMessage = null;
    notifyListeners();
  }

  Future<String?> checkHealth(String rawUrl) async {
    final endpoint = InstanceEndpoint.tryParse(
      rawUrl,
      allowLocal: allowLocalEndpoints,
    );
    if (endpoint == null) {
      try {
        InstanceEndpoint.parse(rawUrl, allowLocal: allowLocalEndpoints);
      } on FormatException catch (error) {
        return error.message;
      }
      return 'That URL is not an allowed database origin.';
    }
    return _guard(() async {
      await gateway.checkHealth(endpoint);
      pendingEndpoint = endpoint;
      errorMessage = null;
      statusMessage =
          'Health check passed for ${endpoint.displayHost}. Sign in to that database.';
    });
  }

  Future<String?> signIn(String email, String password) {
    final endpoint = pendingEndpoint;
    if (endpoint == null) {
      return Future.value('Check the database health before signing in.');
    }
    return _guard(() async {
      final snapshot = await gateway.signIn(endpoint, email, password);
      _applySnapshot(snapshot);
    });
  }

  Future<String?> signUp(String email, String password) {
    final endpoint = pendingEndpoint;
    if (endpoint == null) {
      return Future.value(
        'Check the database health before creating an account.',
      );
    }
    if (password.length < 8) {
      return Future.value('Use a password of at least 8 characters.');
    }
    return _guard(() async {
      final snapshot = await gateway.signUp(endpoint, email, password);
      _applySnapshot(snapshot);
    });
  }

  Future<void> restoreIfSaved() async {
    final raw = gateway.savedOrigin();
    if (raw == null || raw.isEmpty || kind == SessionKind.example) return;
    final endpoint = InstanceEndpoint.tryParse(
      raw,
      allowLocal: allowLocalEndpoints,
    );
    if (endpoint == null) {
      gateway.forgetOrigin();
      errorMessage =
          'The saved database URL is not allowlisted, so it was forgotten.';
      notifyListeners();
      return;
    }
    final failure = await _guard(() async {
      final snapshot = await gateway.restore(endpoint);
      if (snapshot == null) {
        pendingEndpoint = endpoint;
        statusMessage =
            '${endpoint.displayHost} is healthy. Sign in to open that database.';
        return;
      }
      _applySnapshot(snapshot);
    });
    if (failure != null) {
      errorMessage = failure;
      notifyListeners();
    }
  }

  void signOut() {
    gateway.signOut();
    kind = SessionKind.unconfigured;
    stays = [];
    flights = [];
    accountEmail = null;
    instanceOrigin = null;
    pendingEndpoint = null;
    rules = CountingRules.standard;
    statuses = List<EvidenceStatusDef>.of(defaultEvidenceStatuses);
    year = clock().year;
    statusMessage = 'Signed out. No travel database is open.';
    notifyListeners();
  }

  void setYear(int value) {
    year = value;
    notifyListeners();
  }

  Future<String?> saveStay(Stay stay) {
    final problem = validateStay(stay);
    if (problem != null) return Future.value(problem);
    if (!canEdit) {
      return Future.value(
        'Open the example dataset or a per-user database before saving.',
      );
    }
    if (kind == SessionKind.example) {
      final index = stays.indexWhere((item) => item.id == stay.id);
      if (index >= 0) {
        stays = [...stays]..[index] = stay;
      } else {
        stays = [...stays, stay.copyWith(id: _id('stay'))];
      }
      notifyListeners();
      return Future.value();
    }
    return _guard(() async {
      final index = stays.indexWhere((item) => item.id == stay.id);
      final saved = index >= 0
          ? await gateway.updateStay(stay)
          : await gateway.createStay(stay);
      if (index >= 0) {
        stays = [...stays]..[index] = saved;
      } else {
        stays = [...stays, saved];
      }
    });
  }

  Future<String?> deleteStay(String id) {
    if (kind == SessionKind.example) {
      stays = stays.where((stay) => stay.id != id).toList();
      notifyListeners();
      return Future.value();
    }
    if (!isConnected) {
      return Future.value('No per-user database is open.');
    }
    return _guard(() async {
      await gateway.deleteStay(id);
      stays = stays.where((stay) => stay.id != id).toList();
    });
  }

  Future<String?> saveFlight(FlightRecord flight) {
    final problem = validateFlight(flight);
    if (problem != null) return Future.value(problem);
    if (!canEdit) {
      return Future.value(
        'Open the example dataset or a per-user database before saving.',
      );
    }
    if (kind == SessionKind.example) {
      final index = flights.indexWhere((item) => item.id == flight.id);
      if (index >= 0) {
        flights = [...flights]..[index] = flight;
      } else {
        flights = [...flights, flight.copyWith(id: _id('flight'))];
      }
      notifyListeners();
      return Future.value();
    }
    return _guard(() async {
      final index = flights.indexWhere((item) => item.id == flight.id);
      final saved = index >= 0
          ? await gateway.updateFlight(flight)
          : await gateway.createFlight(flight);
      if (index >= 0) {
        flights = [...flights]..[index] = saved;
      } else {
        flights = [...flights, saved];
      }
    });
  }

  Future<String?> deleteFlight(String id) {
    if (kind == SessionKind.example) {
      flights = flights.where((flight) => flight.id != id).toList();
      notifyListeners();
      return Future.value();
    }
    if (!isConnected) return Future.value('No per-user database is open.');
    return _guard(() async {
      await gateway.deleteFlight(id);
      flights = flights.where((flight) => flight.id != id).toList();
    });
  }

  Future<String?> acceptFlight(
    FlightRecord flight, {
    required bool keepInference,
    required bool presenceConfirmedDespiteBooking,
  }) async {
    if (flight.evidenceStatus == 'booking_only' &&
        !presenceConfirmedDespiteBooking) {
      return 'This flight is booking only. Confirm that you are recording presence before adding it to the calendar.';
    }
    final proposals = proposeItinerary([flight], rules);
    final concrete = proposals
        .where((proposal) => proposal.stay != null)
        .toList();
    if (concrete.isEmpty) {
      final manual = proposals.where((proposal) => proposal.needsManualReview);
      final updated = flight.copyWith(
        reviewState: FlightReviewState.needsManual,
        notes: flight.notes,
      );
      final failure = await saveFlight(updated);
      if (failure != null) return failure;
      return manual.isEmpty
          ? 'This flight did not produce a stay. Add the wake-up country yourself.'
          : manual.first.reason;
    }
    for (final proposal in concrete) {
      var stay = proposal.stay!;
      if (keepInference) {
        stay = stay.copyWith(evidenceStatus: 'confirmed');
      } else {
        stay = stay.copyWith(
          evidenceStatus: 'confirmed',
          inference: InferenceKind.none,
        );
      }
      stay = stay.copyWith(id: '', notes: _acceptanceNote(flight, stay.notes));
      final failure = await saveStay(stay);
      if (failure != null) return failure;
    }
    final needsManual = proposals.any((proposal) => proposal.needsManualReview);
    return saveFlight(
      flight.copyWith(
        reviewState: needsManual
            ? FlightReviewState.needsManual
            : FlightReviewState.accepted,
      ),
    );
  }

  Future<String?> rejectFlight(FlightRecord flight) {
    return saveFlight(flight.copyWith(reviewState: FlightReviewState.rejected));
  }

  Future<String?> saveRules({
    required CountingRules nextRules,
    required List<EvidenceStatusDef> nextStatuses,
  }) {
    if (nextStatuses.isEmpty) {
      return Future.value('Keep at least one evidence status.');
    }
    final ids = nextStatuses.map((status) => status.id).toSet();
    if (ids.length != nextStatuses.length) {
      return Future.value('Evidence status ids must be unique.');
    }
    if (kind == SessionKind.example || kind == SessionKind.unconfigured) {
      if (kind == SessionKind.unconfigured) {
        return Future.value(
          'Open the example dataset or a database before saving rules.',
        );
      }
      rules = nextRules;
      statuses = nextStatuses;
      notifyListeners();
      return Future.value();
    }
    return _guard(() async {
      await gateway.saveSettings(rules: nextRules, statuses: nextStatuses);
      rules = nextRules;
      statuses = nextStatuses;
    });
  }

  Future<String?> importRows(
    CsvImportPreview preview, {
    required bool allowExampleIntoConnected,
  }) async {
    if (!canEdit) {
      return 'Open the example dataset or a per-user database before importing.';
    }
    if (preview.exampleDataset && isConnected && !allowExampleIntoConnected) {
      return 'This file is labeled EXAMPLE DATASET. Confirm that you want it copied into this database.';
    }
    if (!preview.hasRows) {
      return preview.errors.isEmpty
          ? 'The file has no stay or flight rows.'
          : preview.errors.first;
    }
    for (final stay in preview.stays) {
      final existing = _stayByExternalId(stay.externalId);
      final failure = await saveStay(
        existing == null
            ? stay.copyWith(id: '')
            : stay.copyWith(id: existing.id),
      );
      if (failure != null) return failure;
    }
    for (final flight in preview.flights) {
      final existing = _flightByExternalId(flight.externalId);
      final failure = await saveFlight(
        existing == null
            ? flight.copyWith(id: '')
            : flight.copyWith(id: existing.id),
      );
      if (failure != null) return failure;
    }
    statusMessage = preview.exampleDataset
        ? 'Imported rows from a file labeled EXAMPLE DATASET.'
        : 'Imported ${preview.stays.length} stays and ${preview.flights.length} flights. Existing rows were left in place except where an external id matched.';
    notifyListeners();
    return null;
  }

  String exportCsv() => CsvCodec.encode(
    stays: stays,
    flights: flights,
    exampleDataset: isExample,
  );

  String exportFilename() => isExample
      ? 'nomadic-residence-EXAMPLE-dataset.csv'
      : 'nomadic-residence-export.csv';

  List<FlightProposal> proposalsFor(FlightRecord flight) =>
      proposeItinerary([flight], rules);

  Stay? _stayByExternalId(String externalId) {
    if (externalId.isEmpty) return null;
    for (final stay in stays) {
      if (stay.externalId == externalId) return stay;
    }
    return null;
  }

  FlightRecord? _flightByExternalId(String externalId) {
    if (externalId.isEmpty) return null;
    for (final flight in flights) {
      if (flight.externalId == externalId) return flight;
    }
    return null;
  }

  void _applySnapshot(TravelSnapshot snapshot) {
    kind = SessionKind.connected;
    stays = snapshot.stays;
    flights = snapshot.flights;
    rules = snapshot.rules;
    statuses = snapshot.statuses;
    accountEmail = snapshot.email;
    instanceOrigin = snapshot.origin;
    year = clock().year;
    errorMessage = null;
    statusMessage = snapshot.warnings.isEmpty
        ? 'Connected to ${Uri.parse(snapshot.origin).host} as ${snapshot.email}. This database should hold one traveler.'
        : snapshot.warnings.join(' ');
  }

  Future<String?> _guard(Future<void> Function() action) async {
    busy = true;
    errorMessage = null;
    notifyListeners();
    try {
      await action();
      busy = false;
      notifyListeners();
      return null;
    } catch (error) {
      busy = false;
      final message = error is GatewayException
          ? error.message
          : 'The database could not be reached.';
      errorMessage = message;
      notifyListeners();
      return message;
    }
  }

  String _id(String prefix) {
    _sequence += 1;
    return '$prefix-${clock().iso}-$_sequence';
  }

  String _acceptanceNote(FlightRecord flight, String proposalNote) {
    final booking = flight.evidenceStatus == 'booking_only'
        ? ' Accepted from booking-only flight ${flight.flightNumber} after an explicit presence confirmation.'
        : ' Accepted from flight ${flight.flightNumber}.';
    return '$proposalNote$booking';
  }
}
