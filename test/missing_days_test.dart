import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomadic_residence/engine/local_date.dart';
import 'package:nomadic_residence/engine/models.dart';
import 'package:nomadic_residence/state/app_controller.dart';
import 'package:nomadic_residence/ui/missing_page.dart';
import 'package:nomadic_residence/ui/theme.dart';

void main() {
  final today = LocalDate(2026, 11, 14);

  Stay stay({
    required String id,
    required String country,
    required String start,
    required String end,
    String notes = '',
  }) {
    return Stay(
      id: id,
      countryCode: country,
      start: LocalDate.parse(start),
      end: LocalDate.parse(end),
      role: PresenceRole.primary,
      evidenceStatus: 'confirmed',
      inference: InferenceKind.none,
      phase: TripPhase.actual,
      timezone: 'Etc/UTC',
      notes: notes,
      externalId: id,
      source: RecordSource.manual,
    );
  }

  FlightRecord flight({
    required String id,
    required String number,
    required String from,
    required String to,
    required String fromIata,
    required String toIata,
    required String depart,
    required String arrive,
    String evidence = 'confirmed',
    FlightReviewState review = FlightReviewState.accepted,
    String notes = '',
  }) {
    return FlightRecord(
      id: id,
      flightNumber: number,
      fromIata: fromIata,
      toIata: toIata,
      fromCountry: from,
      toCountry: to,
      depart: WallTime.parse(depart),
      arrive: WallTime.parse(arrive),
      departTimezone: 'Etc/UTC',
      arriveTimezone: 'Etc/UTC',
      evidenceStatus: evidence,
      inference: InferenceKind.none,
      reviewState: review,
      notes: notes,
      externalId: id,
    );
  }

  AppController load({
    required List<Stay> stays,
    required List<FlightRecord> flights,
  }) {
    final controller = AppController(clock: () => today);
    controller.kind = SessionKind.example;
    controller.year = 2026;
    controller.stays = stays;
    controller.flights = flights;
    return controller;
  }

  Future<void> pump(
    WidgetTester tester,
    AppController controller, {
    Size size = const Size(1280, 1400),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => Scaffold(
            body: MissingPage(controller: controller, rolling: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a same-country pair offers that country and can be confirmed', (
    tester,
  ) async {
    final controller = load(
      stays: [
        stay(id: 'pt', country: 'PT', start: '2026-01-24', end: '2026-02-06'),
      ],
      flights: [
        flight(
          id: 'in',
          number: 'AC100',
          from: 'GB',
          to: 'CA',
          fromIata: 'LHR',
          toIata: 'YYZ',
          depart: '2025-12-31T10:00',
          arrive: '2025-12-31T18:00',
          notes: 'Window seat',
        ),
        flight(
          id: 'out',
          number: 'AC200',
          from: 'CA',
          to: 'GB',
          fromIata: 'YYZ',
          toIata: 'LHR',
          depart: '2026-01-23T09:00',
          arrive: '2026-01-23T16:00',
          evidence: 'booking_only',
          review: FlightReviewState.pending,
        ),
      ],
    );
    await pump(tester, controller);

    expect(find.byKey(const Key('missing-2026-01-01')), findsOneWidget);
    expect(
      find.textContaining(
        'You landed in Canada on 31 Dec 2025 and next flew out of Canada on 23 Jan 2026.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('AC100'), findsOneWidget);
    expect(find.textContaining('LHR to YYZ'), findsOneWidget);
    expect(find.textContaining('18:00'), findsOneWidget);
    expect(find.textContaining('Window seat'), findsOneWidget);
    expect(find.textContaining('Not confirmed yet'), findsWidgets);
    expect(find.textContaining('AC200'), findsWidgets);

    expect(controller.stays.where((item) => item.countryCode == 'CA'), isEmpty);
    final rangeLabel = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(const Key('missing-2026-01-01')),
            matching: find.byType(Text),
          ),
        )
        .first
        .data!;
    await tester.tap(find.byKey(const Key('suggest-CA-2026-01-01')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Where were you?'), findsNothing);
    expect(find.text('Saved $rangeLabel as Canada'), findsOneWidget);
    final saved = controller.stays.singleWhere(
      (item) => item.countryCode == 'CA',
    );
    expect(saved.role, PresenceRole.primary);
    expect(saved.evidenceStatus, 'confirmed');
    expect(saved.inference, InferenceKind.none);
    expect(saved.phase, TripPhase.actual);
    expect(saved.timezone, 'Etc/UTC');
    expect(saved.notes, isEmpty);
    expect(saved.source, RecordSource.manual);
    expect(saved.start, LocalDate.parse('2026-01-01'));
    expect(find.byKey(const Key('missing-2026-01-01')), findsNothing);
    expect(controller.stays.where((item) => item.id == 'pt'), isNotEmpty);

    await tester.tap(find.text('Undo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(controller.stays.where((item) => item.countryCode == 'CA'), isEmpty);
    expect(controller.stays.where((item) => item.id == 'pt'), isNotEmpty);
    expect(find.byKey(const Key('missing-2026-01-01')), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-where-2026-01-01')));
    await tester.pumpAndSettle();
    expect(find.text('Where were you?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(controller.stays.where((item) => item.countryCode == 'CA'), isEmpty);

    final reloaded = load(
      stays: [
        stay(id: 'pt', country: 'PT', start: '2026-01-24', end: '2026-02-06'),
      ],
      flights: controller.flights,
    );
    await pump(tester, reloaded);
    await tester.tap(find.byKey(const Key('confirm-flight-out')));
    await tester.pumpAndSettle();
    expect(
      reloaded.flights.singleWhere((item) => item.id == 'out').reviewState,
      FlightReviewState.accepted,
    );
  });

  testWidgets('different countries explain the missing trip between them', (
    tester,
  ) async {
    final controller = load(
      stays: [
        stay(id: 'pt', country: 'PT', start: '2026-01-01', end: '2026-02-06'),
        stay(id: 'de', country: 'DE', start: '2026-03-10', end: '2026-03-20'),
      ],
      flights: [
        flight(
          id: 'cn',
          number: 'TG612',
          from: 'TH',
          to: 'CN',
          fromIata: 'BKK',
          toIata: 'PEK',
          depart: '2026-02-06T22:00',
          arrive: '2026-02-07T06:00',
          evidence: 'booking_only',
          review: FlightReviewState.pending,
        ),
        flight(
          id: 'ph',
          number: 'TG621',
          from: 'PH',
          to: 'SG',
          fromIata: 'MNL',
          toIata: 'SIN',
          depart: '2026-03-02T11:00',
          arrive: '2026-03-02T15:00',
          review: FlightReviewState.needsManual,
          notes: '{"raw_evidence_class":"Provisional - booking only","source":"https://docs.google.com/spreadsheets/d/abc/edit","count_qualified":false,"timezone_basis":"Derived from the stay city"} [],raw_class : Provisional - booking only',
        ),
      ],
    );
    await pump(tester, controller, size: const Size(390, 900));

    expect(
      find.textContaining(
        'You landed in China, and the next flight leaves from Philippines, so a trip between them is missing.',
      ),
      findsOneWidget,
    );
    expect(find.text('I was in China'), findsOneWidget);
    expect(find.text('I was in Philippines'), findsOneWidget);
    expect(find.textContaining('Not confirmed yet'), findsWidgets);
    expect(find.byKey(const Key('confirm-flight-cn')), findsOneWidget);
    expect(find.byKey(const Key('confirm-flight-ph')), findsNothing);
    expect(find.textContaining('raw_evidence_class'), findsNothing);
    expect(find.textContaining('https://'), findsNothing);
    expect(find.textContaining('{'), findsNothing);
    expect(find.textContaining('How it was recorded'), findsNothing);

    await tester.tap(find.text('More details'));
    await tester.pumpAndSettle();
    expect(
      find.text('How it was recorded: Provisional - booking only'),
      findsOneWidget,
    );
    expect(find.text('Where it came from: A spreadsheet'), findsOneWidget);
    expect(find.text('Counts toward the total: No'), findsOneWidget);
    expect(find.text('Time zone: Derived from the stay city'), findsOneWidget);
    expect(find.textContaining('raw_evidence_class'), findsNothing);
    expect(find.textContaining('https://'), findsNothing);
    expect(find.textContaining('docs.google.com'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed one-tap save leaves the days unchanged', (
    tester,
  ) async {
    final controller = load(stays: const [], flights: const []);
    controller.kind = SessionKind.unconfigured;
    controller.stays = [
      stay(id: 'pt', country: 'PT', start: '2026-01-24', end: '2026-02-06'),
    ];
    controller.flights = [
      flight(
        id: 'in',
        number: 'AC100',
        from: 'GB',
        to: 'CA',
        fromIata: 'LHR',
        toIata: 'YYZ',
        depart: '2025-12-31T10:00',
        arrive: '2025-12-31T18:00',
      ),
    ];
    await pump(tester, controller);
    final before = controller.stays.length;
    await tester.tap(find.byKey(const Key('suggest-CA-2026-01-01')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Where were you?'), findsNothing);
    expect(
      find.text('Couldn\'t save that stay. Nothing was added.'),
      findsOneWidget,
    );
    expect(controller.stays.length, before);
    expect(controller.stays.every((item) => item.countryCode != 'CA'), isTrue);
  });
}
