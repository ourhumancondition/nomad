import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/auth_errors.dart';
import '../data/connection_country.dart';
import '../data/gmail_client.dart';
import '../data/instance_endpoint.dart';
import '../data/pocketbase_gateway.dart';
import '../demo/example_dataset.dart';
import '../engine/between_flights.dart';
import '../engine/csv_codec.dart';
import '../engine/day_engine.dart';
import '../engine/flight_proposals.dart';
import '../engine/gmail_access.dart';
import '../engine/gmail_fixtures.dart';
import '../engine/gmail_receipts.dart';
import '../engine/local_date.dart';
import '../engine/models.dart';
import '../engine/review_queue.dart';
import '../engine/today_presence.dart';
import '../platform/browser_location.dart';

enum SessionKind { unconfigured, example, connected }

class AppController extends ChangeNotifier {
  AppController({
    LocalDate Function()? clock,
    PocketBaseGateway? gateway,
    bool? allowLocalEndpoints,
    GmailClient? gmail,
    void Function(String url)? openAuthorizeUrl,
    ConnectionCountryLookup? whereLookup,
  }) : clock = clock ?? LocalDate.todayDevice,
       whereLookup = whereLookup ?? HttpConnectionCountryLookup(),
       gateway = gateway ?? PocketBaseGateway(),
       allowLocalEndpoints =
           allowLocalEndpoints ??
           (kDebugMode || const bool.fromEnvironment('ALLOW_LOCAL_POCKETBASE')),
       gmail = gmail ?? HttpGmailClient(),
       openAuthorizeUrl = openAuthorizeUrl ?? assignBrowserLocation {
    year = this.clock().year;
  }

  final LocalDate Function() clock;
  final PocketBaseGateway gateway;
  final bool allowLocalEndpoints;
  final GmailClient gmail;
  final void Function(String url) openAuthorizeUrl;
  final ConnectionCountryLookup whereLookup;

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

  GmailConnectionStatus gmailConnection = const GmailConnectionStatus.missing();
  GmailImportPlan? gmailPlan;
  String? gmailNotice;
  String gmailPageToken = '';
  int gmailSkipped = 0;

  /// Receipt text for the current preview. Not shown and cleared on sign-out.
  final List<ReceiptMessage> _gmailMessages = <ReceiptMessage>[];

  String get sessionOwnerId {
    if (isConnected) return gateway.currentUserId() ?? '';
    if (isExample) return 'example';
    return '';
  }

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

  /// Today's country, read from the same engine as the year totals.
  TodayPresence get today => resolveTodayOn(
    clock(),
    stays: stays,
    flights: flights,
    rules: rules,
    statuses: statuses,
  );

  /// Counting stays in a country other than [country] that cover today.
  /// Saving [country] for today takes today out of these.
  List<Stay> todayStaysElsewhere(String country) {
    final date = clock();
    return [
      for (final stay in stays)
        if (stay.covers(date) &&
            stay.role == PresenceRole.primary &&
            stay.countryCode.isNotEmpty &&
            stay.countryCode != country &&
            DayEngine.countsAsActual(stay, rules, statuses))
          stay,
    ];
  }

  /// Records that the traveler woke up in [country] today.
  ///
  /// Extends an adjacent confirmed, observed stay in the same country by one
  /// day, or saves a new confirmed stay for today only.
  ///
  /// When a counting stay in another country also covers today, nothing is
  /// written unless [replaceOthers] is true; the result lists those stays so
  /// the caller can ask first. With [replaceOthers], today is taken out of
  /// each of them (shortened, split around today, or removed when it was
  /// today only), so today does not become a conflict.
  ///
  /// Every write goes through [saveStay] or [deleteStay], so the same API
  /// rules apply. Flights and flight proposals are never touched. The undo
  /// reverses every step of this write and nothing else.
  Future<TodayWriteResult> saveTodayStay(
    String country, {
    String note = '',
    bool replaceOthers = false,
  }) async {
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(country)) {
      return const TodayWriteResult(failure: 'Choose a country.');
    }
    final date = clock();
    final yesterday = date.addDays(-1);
    final tomorrow = date.addDays(1);
    final trimmed = note.trim();

    var covered = false;
    Stay? adjacent;
    for (final stay in stays) {
      if (stay.phase != TripPhase.actual) continue;
      if (stay.role != PresenceRole.primary) continue;
      if (stay.countryCode != country) continue;
      if (stay.evidenceStatus != 'confirmed') continue;
      if (stay.inference.isInference) continue;
      if (stay.covers(date)) covered = true;
      if (stay.end == yesterday) {
        adjacent = stay;
      } else if (stay.start == tomorrow) {
        adjacent ??= stay;
      }
    }

    final elsewhere = todayStaysElsewhere(country);
    if (elsewhere.isNotEmpty && !replaceOthers) {
      return TodayWriteResult(staysElsewhere: elsewhere);
    }
    if (covered && elsewhere.isEmpty) {
      return const TodayWriteResult(alreadySaved: true);
    }

    final undoSteps = <Future<String?> Function()>[];
    Future<String?> undoAll() async {
      String? first;
      for (final step in undoSteps.reversed) {
        final failure = await step();
        first ??= failure;
      }
      return first;
    }

    Future<String?> createAndTrack(Stay stay) async {
      final before = stays.map((item) => item.id).toSet();
      final failure = await saveStay(stay);
      if (failure != null) return failure;
      final created = stays
          .where((item) => item.id.isNotEmpty && !before.contains(item.id))
          .toList();
      if (created.length == 1) {
        final id = created.single.id;
        undoSteps.add(() => deleteStay(id));
      }
      return null;
    }

    Future<TodayWriteResult> fail(String failure) async {
      await undoAll();
      return TodayWriteResult(failure: failure);
    }

    for (final original in elsewhere) {
      String? failure;
      if (original.start == date && original.end == date) {
        failure = await deleteStay(original.id);
        if (failure == null) {
          undoSteps.add(() => saveStay(original.copyWith(id: '')));
        }
      } else if (original.start == date) {
        failure = await saveStay(original.copyWith(start: tomorrow));
        if (failure == null) undoSteps.add(() => saveStay(original));
      } else if (original.end == date) {
        failure = await saveStay(original.copyWith(end: yesterday));
        if (failure == null) undoSteps.add(() => saveStay(original));
      } else {
        failure = await saveStay(original.copyWith(end: yesterday));
        if (failure == null) {
          undoSteps.add(() => saveStay(original));
          failure = await createAndTrack(
            original.copyWith(id: '', start: tomorrow, externalId: ''),
          );
        }
      }
      if (failure != null) return fail(failure);
    }

    var extended = false;
    if (!covered) {
      if (adjacent != null) {
        final original = adjacent;
        final notes = trimmed.isEmpty
            ? original.notes
            : (original.notes.isEmpty
                  ? trimmed
                  : '${original.notes}\n$trimmed');
        final grown = original.end == yesterday
            ? original.copyWith(end: date, notes: notes)
            : original.copyWith(start: date, notes: notes);
        final failure = await saveStay(grown);
        if (failure != null) return fail(failure);
        undoSteps.add(() => saveStay(original));
        extended = true;
      } else {
        final failure = await createAndTrack(
          Stay(
            id: '',
            countryCode: country,
            start: date,
            end: date,
            role: PresenceRole.primary,
            evidenceStatus: 'confirmed',
            inference: InferenceKind.none,
            phase: TripPhase.actual,
            timezone: 'Etc/UTC',
            notes: trimmed,
            source: RecordSource.manual,
          ),
        );
        if (failure != null) return fail(failure);
      }
    }
    return TodayWriteResult(
      extended: extended,
      replaced: elsewhere,
      undo: undoSteps.isEmpty ? null : undoAll,
    );
  }

  /// The country of the current connection, from [whereLookup]. A hint only.
  String? connectionCountry;
  final Set<String> _dismissedConnection = <String>{};

  /// Asks for the connection's country. Failures leave it unknown.
  Future<void> checkConnectionCountry() async {
    final code = await whereLookup.country();
    if (code == connectionCountry) return;
    connectionCountry = code;
    notifyListeners();
  }

  /// The connection's country when it is worth offering for today: today
  /// is unknown or in transit, or today's country is a different one.
  /// Null on a conflict day, where one more country would not settle it.
  String? get connectionOffer {
    final code = connectionCountry;
    if (code == null || !canEdit) return null;
    final presence = today;
    if (_dismissedConnection.contains('${presence.date.iso}|$code')) {
      return null;
    }
    return switch (presence.status) {
      TodayStatus.confirmed ||
      TodayStatus.fromFlights => presence.countryCode == code ? null : code,
      TodayStatus.inTransit || TodayStatus.unknown => code,
      TodayStatus.conflict => null,
    };
  }

  /// Hides the offer for this country for the rest of today.
  void dismissConnectionOffer() {
    final code = connectionCountry;
    if (code == null) return;
    _dismissedConnection.add('${clock().iso}|$code');
    notifyListeners();
  }

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
    _clearGmailSession();
    notifyListeners();
    unawaited(checkConnectionCountry());
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
    _clearGmailSession();
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
    connectionCountry = null;
    _dismissedConnection.clear();
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
    _clearGmailSession();
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

  /// Confirms a stay that was waiting on a decision.
  ///
  /// Sets evidence to confirmed. A planned stay becomes actual. A different
  /// country that already counts on those dates is trimmed so the morning
  /// has one country. The inference mark is left as stored.
  Future<String?> confirmStay(Stay stay) async {
    final next = stay.copyWith(
      evidenceStatus: 'confirmed',
      phase: TripPhase.actual,
    );
    final problem = validateStay(next);
    if (problem != null) return problem;
    if (!canEdit) {
      return 'Open the example dataset or a per-user database before saving.';
    }
    final carve = carveConflictingStays(
      incoming: next,
      stays: stays,
      rules: rules,
      statuses: statuses,
    );
    final undoSteps = <Future<String?> Function()>[];
    Future<String?> undoAll() async {
      String? first;
      for (final step in undoSteps.reversed) {
        final failure = await step();
        first ??= failure;
      }
      return first;
    }

    Future<String?> fail(String failure) async {
      final undoFailure = await undoAll();
      if (undoFailure == null) return failure;
      return '$failure $undoFailure';
    }

    Future<String?> createAndTrack(Stay row) async {
      final before = stays.map((item) => item.id).toSet();
      final failure = await saveStay(row);
      if (failure != null) return failure;
      final created = stays
          .where((item) => item.id.isNotEmpty && !before.contains(item.id))
          .toList();
      if (created.length == 1) {
        final id = created.single.id;
        undoSteps.add(() => deleteStay(id));
      }
      return null;
    }

    for (final id in carve.deleteIds) {
      Stay? original;
      for (final item in stays) {
        if (item.id == id) original = item;
      }
      if (original == null) continue;
      final failure = await deleteStay(id);
      if (failure != null) return fail(failure);
      final snapshot = original;
      undoSteps.add(() => saveStay(snapshot.copyWith(id: '')));
    }
    for (final row in carve.save) {
      if (row.id.isEmpty) {
        final failure = await createAndTrack(row);
        if (failure != null) return fail(failure);
        continue;
      }
      Stay? original;
      for (final item in stays) {
        if (item.id == row.id) original = item;
      }
      final failure = await saveStay(row);
      if (failure != null) return fail(failure);
      if (original != null) {
        final snapshot = original;
        undoSteps.add(() => saveStay(snapshot));
      }
    }
    final failure = await saveStay(next);
    if (failure != null) return fail(failure);
    return null;
  }

  /// Leaves an inferred stay out of the total without deleting it.
  Future<String?> dismissStay(Stay stay) {
    return saveStay(stay.copyWith(evidenceStatus: 'unknown'));
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

  void noteGmailReturn(String code) {
    gmailNotice = switch (code) {
      'connected' => 'Gmail is connected for read-only receipt search. Nothing has been imported.',
      'denied' => 'Gmail was not connected. No mailbox was read.',
      'scope' =>
        'Google offered more than read-only Gmail. Nothing was stored.',
      _ => 'Gmail authorization did not finish. No mailbox was read.',
    };
  }

  void previewFictionalReceipts() {
    _gmailMessages
      ..clear()
      ..addAll(fictionalGmailReceipts());
    gmailPageToken = '';
    gmailSkipped = 0;
    _publishGmailPlan(GmailPlanSource.fictional);
  }

  Future<String?> refreshGmail() async {
    if (!isConnected) {
      gmailConnection = const GmailConnectionStatus.missing();
      notifyListeners();
      return null;
    }
    final token = gateway.currentAuthToken();
    if (token == null) return 'Sign in again before using Gmail.';
    try {
      gmailConnection = await gmail.status(authToken: token);
      notifyListeners();
      return null;
    } on GmailClientException catch (error) {
      return error.message;
    }
  }

  Future<String?> connectGmail(String returnTo) async {
    if (!isConnected) {
      return 'Sign in to a database before connecting Gmail.';
    }
    if (!returnOriginAllowed(returnTo)) {
      return 'This page is not an allowed return address.';
    }
    final token = gateway.currentAuthToken();
    if (token == null) return 'Sign in again before connecting Gmail.';
    try {
      final url = await gmail.authorizeUrl(
        authToken: token,
        returnTo: returnTo,
      );
      openAuthorizeUrl(url);
      return null;
    } on GmailClientException catch (error) {
      return error.message;
    }
  }

  Future<String?> disconnectGmail() async {
    final token = gateway.currentAuthToken();
    if (token == null) return 'Sign in again before disconnecting Gmail.';
    try {
      gmailConnection = await gmail.disconnect(authToken: token);
      if (gmailPlan?.source == GmailPlanSource.mailbox) {
        gmailPlan = null;
        _gmailMessages.clear();
      }
      notifyListeners();
      return null;
    } on GmailClientException catch (error) {
      return error.message;
    }
  }

  Future<String?> scanGmail({bool older = false}) async {
    if (!isConnected) return 'Sign in to a database before reading Gmail.';
    final blocked = mailboxReadBlock(gmailConnection.state);
    if (blocked != null) return blocked;
    final token = gateway.currentAuthToken();
    final owner = gateway.currentUserId();
    if (token == null || owner == null || owner.isEmpty) {
      return 'Sign in again before reading Gmail.';
    }
    try {
      final batch = await gmail.scan(
        authToken: token,
        pageToken: older ? gmailPageToken : '',
      );
      if (!scanAllowed(batch.state)) {
        gmailConnection = GmailConnectionStatus(
          state: batch.state,
          googleEmail: gmailConnection.googleEmail,
          scope: gmailConnection.scope,
          connectedAt: gmailConnection.connectedAt,
        );
        gmailPlan = null;
        _gmailMessages.clear();
        notifyListeners();
        return mailboxReadBlock(batch.state);
      }
      if (!older) _gmailMessages.clear();
      _gmailMessages.addAll(batch.messages);
      gmailPageToken = batch.nextPageToken;
      gmailSkipped = batch.skipped;
      _publishGmailPlan(GmailPlanSource.mailbox);
      return null;
    } on GmailClientException catch (error) {
      if (error.code == 'revoked') {
        gmailConnection = const GmailConnectionStatus(
          state: GmailLinkState.revoked,
        );
        gmailPlan = null;
        _gmailMessages.clear();
        notifyListeners();
      }
      return error.message;
    }
  }

  Future<String?> saveGmailSelection(GmailDraft draft) async {
    final plan = gmailPlan;
    if (plan == null) return 'There is no Gmail preview to save.';
    if (!canEdit) {
      return 'Open the example dataset or a database before saving.';
    }
    final mutations = mutationsFor(
      plan: plan,
      draft: draft,
      sessionOwnerId: sessionOwnerId,
      connection: gmailConnection.state,
      connectedDatabase: isConnected,
      existing: flights,
    );
    if (mutations.refusal != null) return mutations.refusal;
    if (mutations.create.isEmpty && mutations.reject.isEmpty) {
      return 'Nothing was saved. Check a booking, or the rows are already imported.';
    }
    var saved = 0;
    var rejected = 0;
    for (final flight in mutations.create) {
      final failure = await saveFlight(flight);
      if (failure != null) return _gmailStop(saved, rejected, failure);
      saved += 1;
    }
    for (final flight in mutations.reject) {
      if (flight.reviewState != FlightReviewState.rejected) {
        return 'A cancellation tried to keep a flight. Nothing further was saved.';
      }
      final failure = await saveFlight(flight);
      if (failure != null) return _gmailStop(saved, rejected, failure);
      rejected += 1;
    }
    _publishGmailPlan(plan.source);
    final bookingWord = saved == 1 ? 'booking' : 'bookings';
    final rejectWord = rejected == 1 ? 'flight' : 'flights';
    statusMessage = rejected == 0
        ? 'Saved $saved $bookingWord for review. They are booking-only until you accept a flight yourself. No country day was added.'
        : 'Saved $saved $bookingWord for review and rejected $rejected earlier $rejectWord. No country day was added.';
    return null;
  }

  String _gmailStop(int saved, int rejected, String failure) {
    final migration = failure.contains('gmail_')
        ? ' Apply the Gmail migration on this database before importing.'
        : '';
    return 'Saved $saved bookings and rejected $rejected flights. Stopped. $failure$migration';
  }

  void _publishGmailPlan(GmailPlanSource source) {
    gmailPlan = planGmailImport(
      messages: _gmailMessages,
      existing: flights,
      ownerId: sessionOwnerId,
      source: source,
    );
    notifyListeners();
  }

  void _clearGmailSession() {
    gmailConnection = const GmailConnectionStatus.missing();
    gmailPlan = null;
    gmailNotice = null;
    gmailPageToken = '';
    gmailSkipped = 0;
    _gmailMessages.clear();
  }

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
    unawaited(checkConnectionCountry());
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

/// Outcome of [AppController.saveTodayStay].
class TodayWriteResult {
  const TodayWriteResult({
    this.failure,
    this.undo,
    this.extended = false,
    this.alreadySaved = false,
    this.staysElsewhere = const [],
    this.replaced = const [],
  });

  final String? failure;

  /// Reverses the write. Null when nothing was written.
  final Future<String?> Function()? undo;

  /// True when an adjacent stay grew by one day instead of a new stay.
  final bool extended;

  /// True when a confirmed stay already covered today, so nothing changed.
  final bool alreadySaved;

  /// Counting stays elsewhere that cover today. When this is not empty and
  /// [replaced] is, nothing was written: ask, then save with replaceOthers.
  final List<Stay> staysElsewhere;

  /// Stays that today was taken out of.
  final List<Stay> replaced;

  /// True when the caller must confirm before anything is written.
  bool get needsConfirmation => staysElsewhere.isNotEmpty;
}
