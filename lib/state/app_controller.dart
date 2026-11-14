import 'package:flutter/foundation.dart';

import '../data/auth_errors.dart';
import '../data/instance_endpoint.dart';
import '../data/pocketbase_gateway.dart';
import '../demo/example_dataset.dart';
import '../engine/between_flights.dart';
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

  /// Accepted flight ids the traveler pulled back onto the review list.
  /// Display only: not written to PocketBase and cleared when the session
  /// data is replaced.
  final Set<String> _unarchivedFlightIds = <String>{};
  String? accountEmail;
  String? instanceOrigin;
  InstanceEndpoint? pendingEndpoint;
  String? statusMessage;
  String? errorMessage;
  Map<String, String> fieldErrors = {};
  List<String> notices = [];
  bool preferSignIn = false;
  bool busy = false;

  /// True while a saved session is being opened. The login form stays hidden.
  bool restoring = false;
  int _sequence = 0;

  bool get isExample => kind == SessionKind.example;
  bool get isConnected => kind == SessionKind.connected;
  bool get canEdit => kind != SessionKind.unconfigured;

  /// Ids of accepted flights currently shown on the review list.
  Set<String> get unarchivedFlightIds =>
      Set<String>.unmodifiable(_unarchivedFlightIds);

  /// Shows an accepted flight on the review list until the page session
  /// replaces its data. Does not change the flight.
  void unarchiveFlight(String id) {
    if (id.isEmpty) return;
    if (_unarchivedFlightIds.add(id)) notifyListeners();
  }

  /// Puts a previously un-archived flight back in the archive section.
  /// Does not change the flight.
  void rearchiveFlight(String id) {
    if (_unarchivedFlightIds.remove(id)) notifyListeners();
  }

  YearTally get tally => DayEngine.tally(
    stays: stays,
    flights: flights,
    year: year,
    today: clock(),
    rules: rules,
    statuses: statuses,
  );

  /// Inferred primary mornings in this window that are not already in the
  /// wake-up total. A morning counted from a qualifying flight bracket is
  /// not included, even when an inferred stay still covers that date.
  int get inferredCountryDays => tally.inferredKeptOutDays;

  BetweenFlightPlan betweenFlightPlan() =>
      planContinuousCountry(flights: flights, existing: stays, rules: rules);

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
    _unarchivedFlightIds.clear();
    rules = CountingRules.standard;
    statuses = List<EvidenceStatusDef>.of(defaultEvidenceStatuses);
    year = ExampleDataset.storyYear;
    accountEmail = null;
    pendingEndpoint = null;
    notices = [];
    fieldErrors = {};
    errorMessage = null;
    statusMessage = 'Example dataset. These fictional rows stay in this tab and are not sent to PocketBase.';
    notifyListeners();
  }

  void leaveExample() {
    if (kind != SessionKind.example) return;
    kind = SessionKind.unconfigured;
    stays = [];
    flights = [];
    _unarchivedFlightIds.clear();
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
        return _localProblem(error.message);
      }
      return _localProblem('That URL is not an allowed database origin.');
    }
    return _guard(() async {
      await gateway.checkHealth(endpoint);
      gateway.rememberOrigin(endpoint);
      pendingEndpoint = endpoint;
      errorMessage = null;
      fieldErrors = {};
      statusMessage = null;
    });
  }

  Future<String?> signIn(String email, String password) {
    final emailProblem = _emailProblem(email);
    final passwordProblem = password.isEmpty ? 'Enter a password.' : null;
    if (emailProblem != null || passwordProblem != null) {
      return _localProblem(
        'Sign-in was not accepted. Fix the fields below.',
        email: emailProblem,
        password: passwordProblem,
      );
    }
    final endpoint = pendingEndpoint;
    if (endpoint == null) {
      return _localProblem('Choose a server before signing in.');
    }
    return _guard(() async {
      final snapshot = await gateway.signIn(endpoint, email, password);
      gateway.rememberEmail(email);
      _applySnapshot(snapshot);
    });
  }

  Future<String?> signUp(String email, String password, String confirm) {
    final emailProblem = _emailProblem(email);
    final passwordProblem = password.length < 8
        ? 'Use a password of at least 8 characters.'
        : null;
    final confirmProblem = password != confirm
        ? 'Those passwords do not match.'
        : null;
    if (emailProblem != null ||
        passwordProblem != null ||
        confirmProblem != null) {
      return _localProblem(
        'The account was not created. Fix the fields below.',
        email: emailProblem,
        password: passwordProblem,
        confirm: confirmProblem,
      );
    }
    final endpoint = pendingEndpoint;
    if (endpoint == null) {
      return _localProblem('Choose a server before creating an account.');
    }
    return _guard(() async {
      final snapshot = await gateway.signUp(endpoint, email, password);
      gateway.rememberEmail(email);
      _applySnapshot(snapshot);
    });
  }

  /// Remembers [raw] as the server and selects it. Does not sign in.
  String? useServer(String raw) {
    final endpoint = InstanceEndpoint.tryParse(
      raw,
      allowLocal: allowLocalEndpoints,
    );
    if (endpoint == null) {
      String message = 'That server address is not one this app can use.';
      try {
        InstanceEndpoint.parse(raw, allowLocal: allowLocalEndpoints);
      } on FormatException catch (error) {
        message = error.message;
      }
      errorMessage = message;
      notifyListeners();
      return message;
    }
    pendingEndpoint = endpoint;
    gateway.rememberOrigin(endpoint);
    errorMessage = null;
    notifyListeners();
    return null;
  }

  void clearAuthProblems() {
    errorMessage = null;
    fieldErrors = {};
    notifyListeners();
  }

  Future<void> restoreIfSaved() async {
    if (kind == SessionKind.example) return;
    var raw = gateway.savedOrigin();
    if (raw == null || raw.isEmpty) {
      gateway.rememberOrigin(
        InstanceEndpoint.parse(defaultInstanceUrl, allowLocal: false),
      );
      raw = gateway.savedOrigin();
    }
    final endpoint = InstanceEndpoint.tryParse(
      raw ?? '',
      allowLocal: allowLocalEndpoints,
    );
    if (endpoint == null) {
      gateway.forgetOrigin();
      errorMessage =
          'The saved server address cannot be used, so it was forgotten.';
      notifyListeners();
      return;
    }
    if (!gateway.hasSavedSession(endpoint)) {
      pendingEndpoint = endpoint;
      return;
    }
    restoring = true;
    notifyListeners();
    final failure = await _guard(() async {
      final snapshot = await gateway.restore(endpoint);
      if (snapshot == null) {
        pendingEndpoint = endpoint;
        return;
      }
      _applySnapshot(snapshot);
    });
    restoring = false;
    if (failure != null) {
      errorMessage = failure;
    }
    notifyListeners();
  }

  void signOut() {
    final origin = instanceOrigin ?? gateway.savedOrigin();
    gateway.signOut();
    kind = SessionKind.unconfigured;
    stays = [];
    flights = [];
    _unarchivedFlightIds.clear();
    accountEmail = null;
    instanceOrigin = null;
    notices = [];
    fieldErrors = {};
    errorMessage = null;
    preferSignIn = true;
    pendingEndpoint = origin == null
        ? null
        : InstanceEndpoint.tryParse(origin, allowLocal: allowLocalEndpoints);
    rules = CountingRules.standard;
    statuses = List<EvidenceStatusDef>.of(defaultEvidenceStatuses);
    year = clock().year;
    statusMessage = null;
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
      final stored = index >= 0 ? flight : flight.copyWith(id: _id('flight'));
      if (index >= 0) {
        flights = [...flights]..[index] = stored;
      } else {
        flights = [...flights, stored];
      }
      _releaseArchiveOverride(stored);
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
      _releaseArchiveOverride(saved);
    });
  }

  Future<String?> deleteFlight(String id) {
    if (kind == SessionKind.example) {
      flights = flights.where((flight) => flight.id != id).toList();
      _unarchivedFlightIds.remove(id);
      notifyListeners();
      return Future.value();
    }
    if (!isConnected) return Future.value('No per-user database is open.');
    return _guard(() async {
      await gateway.deleteFlight(id);
      flights = flights.where((flight) => flight.id != id).toList();
      _unarchivedFlightIds.remove(id);
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

  /// Saves inferred between-flight stays. Does not change the counting rule
  /// and does not rewrite a stay the traveler entered.
  Future<String?> saveBetweenFlightPlan() async {
    if (!canEdit) {
      return 'Open the example dataset or a per-user database before saving.';
    }
    final plan = betweenFlightPlan();
    var saved = 0;
    for (final stay in plan.savable) {
      final existing = _stayByExternalId(stay.externalId);
      if (existing != null && existing.source != RecordSource.flightReview) {
        continue;
      }
      final failure = await saveStay(
        existing == null
            ? stay.copyWith(id: '')
            : stay.copyWith(id: existing.id),
      );
      if (failure != null) return failure;
      saved += 1;
    }
    statusMessage = saved == 0
        ? 'No inferred stays were saved.'
        : 'Saved $saved inferred stay${saved == 1 ? '' : 's'}. The stay stays inferred. The Summary counts a morning from flights only when a qualifying arrival and departure bracket it.';
    notifyListeners();
    return null;
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
    var savedStays = 0;
    var savedFlights = 0;
    String stopped(String kind, String externalId, String failure) {
      final label = externalId.isEmpty
          ? 'a row with no external id'
          : externalId;
      return 'Saved $savedStays of ${preview.stays.length} stays and $savedFlights of ${preview.flights.length} flights. '
          'Stopped on $kind $label. $failure '
          'Rows already saved were kept. Importing this file again updates a matching external id and sends the rows that were not saved.';
    }

    for (final stay in preview.stays) {
      final existing = _stayByExternalId(stay.externalId);
      final failure = await saveStay(
        existing == null
            ? stay.copyWith(id: '')
            : stay.copyWith(id: existing.id),
      );
      if (failure != null) return stopped('stay', stay.externalId, failure);
      savedStays += 1;
    }
    for (final flight in preview.flights) {
      final existing = _flightByExternalId(flight.externalId);
      final failure = await saveFlight(
        existing == null
            ? flight.copyWith(id: '')
            : flight.copyWith(id: existing.id),
      );
      if (failure != null) {
        return stopped('flight', flight.externalId, failure);
      }
      savedFlights += 1;
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
    _unarchivedFlightIds.clear();
    rules = snapshot.rules;
    statuses = snapshot.statuses;
    accountEmail = snapshot.email;
    instanceOrigin = snapshot.origin;
    year = clock().year;
    errorMessage = null;
    fieldErrors = {};
    notices = List<String>.of(snapshot.warnings);
    statusMessage = snapshot.warnings.isEmpty
        ? null
        : snapshot.warnings.join(' ');
  }

  String? _emailProblem(String email) {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return 'Enter an email address.';
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(trimmed);
    if (!ok) return 'Enter a valid email address.';
    return null;
  }

  Future<String?> _localProblem(
    String summary, {
    String? email,
    String? password,
    String? confirm,
  }) {
    errorMessage = summary;
    final next = <String, String>{};
    if (email != null) next['email'] = email;
    if (password != null) next['password'] = password;
    if (confirm != null) next['passwordConfirm'] = confirm;
    fieldErrors = next;
    notifyListeners();
    return Future.value(summary);
  }

  Future<String?> _guard(Future<void> Function() action) async {
    busy = true;
    errorMessage = null;
    fieldErrors = {};
    notifyListeners();
    try {
      await action();
      busy = false;
      notifyListeners();
      return null;
    } catch (error) {
      busy = false;
      if (error is GatewayException) {
        errorMessage = error.message;
        fieldErrors = Map<String, String>.of(error.fields);
        if (error.accountExists) preferSignIn = true;
      } else if (error is FormatException) {
        errorMessage = 'A record could not be read. ${error.message}';
        fieldErrors = {};
      } else {
        errorMessage = 'The request did not finish. Later rows were not sent.';
        fieldErrors = {};
      }
      notifyListeners();
      return errorMessage;
    }
  }

  void _releaseArchiveOverride(FlightRecord flight) {
    if (flight.reviewState != FlightReviewState.accepted) {
      _unarchivedFlightIds.remove(flight.id);
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
