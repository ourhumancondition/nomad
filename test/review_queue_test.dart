import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomadic_residence/engine/local_date.dart';
import 'package:nomadic_residence/engine/models.dart';
import 'package:nomadic_residence/engine/review_queue.dart';
import 'package:nomadic_residence/state/app_controller.dart';
import 'package:nomadic_residence/ui/nomadic_app.dart';
import 'package:nomadic_residence/ui/review_copy.dart';

void main() {
  final today = LocalDate(2026, 11, 8);
  const rules = CountingRules.standard;
  final statuses = defaultEvidenceStatuses;

  Stay stay({
    required String id,
    required String country,
    required String start,
    required String end,
    String evidence = 'inferred',
    InferenceKind inference = InferenceKind.none,
    TripPhase phase = TripPhase.actual,
    String notes = 'Fictional stay.',
  }) {
    return Stay(
      id: id,
      countryCode: country,
      start: LocalDate.parse(start),
      end: LocalDate.parse(end),
      role: PresenceRole.primary,
      evidenceStatus: evidence,
      inference: inference,
      phase: phase,
      timezone: 'Etc/UTC',
      notes: notes,
      externalId: id,
    );
  }

  FlightRecord flight({
    required String id,
    required String number,
    required String from,
    required String to,
    required String depart,
    required String arrive,
    String fromIata = 'LIR',
    String toIata = 'YYZ',
    FlightReviewState review = FlightReviewState.pending,
    String evidence = 'booking_only',
    String notes = 'Fictional flight.',
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
      departTimezone: 'America/Costa_Rica',
      arriveTimezone: 'America/Toronto',
      evidenceStatus: evidence,
      inference: InferenceKind.none,
      reviewState: review,
      notes: notes,
      externalId: id,
    );
  }

  test('inferred and planned stays join the flight queue, in date order', () {
    final rows = [
      stay(
        id: 'pt',
        country: 'PT',
        start: '2026-01-01',
        end: '2026-01-10',
        evidence: 'confirmed',
      ),
      stay(id: 'us', country: 'US', start: '2026-05-12', end: '2026-05-17'),
      stay(
        id: 'ph-plan',
        country: 'PH',
        start: '2026-02-01',
        end: '2026-02-03',
        phase: TripPhase.planned,
      ),
      stay(
        id: 'fr-book',
        country: 'FR',
        start: '2026-08-01',
        end: '2026-08-02',
        evidence: 'booking_only',
      ),
      stay(
        id: 'fr-mark',
        country: 'FR',
        start: '2026-08-03',
        end: '2026-08-04',
        evidence: 'confirmed',
        inference: InferenceKind.inferredItinerary,
      ),
    ];
    final tickets = [
      flight(
        id: 'later',
        number: 'EX900',
        from: 'US',
        to: 'CA',
        depart: '2026-06-01T15:30',
        arrive: '2026-06-01T21:50',
      ),
      flight(
        id: 'done',
        number: 'EX100',
        from: 'PT',
        to: 'ES',
        depart: '2026-01-02T09:00',
        arrive: '2026-01-02T11:00',
        fromIata: 'LIS',
        toIata: 'MAD',
        review: FlightReviewState.accepted,
        evidence: 'confirmed',
      ),
    ];
    final before = rows.map((item) => item.evidenceStatus).toList();
    final queue = reviewQueue(flights: tickets, stays: rows);
    expect(rows.map((item) => item.evidenceStatus), before);
    expect(queue.map((item) => item.id), ['ph-plan', 'us', 'later']);
    expect(reviewYears(queue), [2026]);
    expect(reviewQueueCount(flights: tickets, stays: rows), 3);
  });

  test(
    'a flight card says the city, the day, and the morning it would count',
    () {
      final ticket = flight(
        id: 'ac',
        number: 'EX187',
        from: 'CR',
        to: 'CA',
        depart: '2025-01-12T15:30',
        arrive: '2025-01-12T21:50',
        notes: 'Source https://example.com/mail/ex187 Passenger Example Traveler verified from booking. All clocks are scheduled local clocks from source (not verified actual landing times). No stays generated; needs manual review.',
      );
      final title = flightHeadline(ticket);
      expect(title, contains('Liberia, Costa Rica'));
      expect(title, contains('Toronto, Canada'));
      expect(title, contains('12 Jan 2025'));
      expect(title, contains('3:30 PM'));
      expect(title, contains('9:50 PM'));
      expect(title, isNot(contains('T15:30')));
      expect(title, isNot(contains('America/')));
      final effect = flightConfirmSentence(
        flight: ticket,
        stays: const [],
        flights: [ticket],
        rules: rules,
        statuses: statuses,
        today: today,
      );
      expect(effect, 'Counts 13 Jan 2025 as Canada.');
      final brief = evidenceBrief(ticket.notes);
      expect(brief.text, contains('From an email booking.'));
      expect(brief.text, contains('Passenger Example Traveler.'));
      expect(brief.text, isNot(contains('http')));
      expect(brief.text.toLowerCase(), isNot(contains('iana')));
      expect(brief.sourceUrl, 'https://example.com/mail/ex187');
    },
  );

  test('a stay card names the country, the dates, and a replacement', () {
    final china = stay(
      id: 'cn',
      country: 'CN',
      start: '2026-03-22',
      end: '2026-04-01',
      evidence: 'confirmed',
    );
    final philippines = stay(
      id: 'ph',
      country: 'PH',
      start: '2026-03-22',
      end: '2026-04-01',
      notes: 'Calendar event, example only. Strength: strong. Conflicts with the China stay. https://example.com/calendar/workshop',
    );
    expect(
      stayHeadline(philippines),
      'Stay: Philippines, 22 Mar 2026 – 1 Apr 2026 (11 days)',
    );
    expect(
      stayConfirmSentence(
        stay: philippines,
        stays: [china, philippines],
        flights: const [],
        rules: rules,
        statuses: statuses,
        today: today,
      ),
      'Changes 22 Mar 2026 – 1 Apr 2026 from China to Philippines.',
    );
    final brief = evidenceBrief(philippines.notes);
    expect(brief.text, contains('From a calendar event.'));
    expect(brief.text, contains('Strong match.'));
    expect(brief.text, contains('Conflicts with the China stay.'));
    expect(brief.text, isNot(contains('http')));
    expect(brief.sourceUrl, 'https://example.com/calendar/workshop');
    expect(
      evidenceBrief('Hours log, example only. Strength: weak.').text,
      'From an hours log. Weak match.',
    );
  });

  test(
    'confirming an inferred stay adds its days and leaves the others',
    () async {
      final controller = AppController(clock: () => today);
      controller.openExample();
      final united = stay(
        id: 'us',
        country: 'US',
        start: '2026-05-12',
        end: '2026-05-17',
      );
      final planned = stay(
        id: 'ph-plan',
        country: 'PH',
        start: '2026-02-01',
        end: '2026-02-03',
        phase: TripPhase.planned,
      );
      controller.stays = [united, planned];
      controller.flights = [];
      expect(controller.tally.primaryDays.containsKey('US'), isFalse);
      expect(controller.tally.primaryDays.containsKey('PH'), isFalse);

      final failure = await controller.confirmStay(united);
      expect(failure, isNull);
      final saved = controller.stays.singleWhere((item) => item.id == 'us');
      expect(saved.evidenceStatus, 'confirmed');
      expect(saved.phase, TripPhase.actual);
      expect(controller.tally.primaryDays['US'], 6);
      final stillPlanned = controller.stays.singleWhere(
        (item) => item.id == 'ph-plan',
      );
      expect(stillPlanned.evidenceStatus, 'inferred');
      expect(stillPlanned.phase, TripPhase.planned);
      expect(controller.tally.primaryDays.containsKey('PH'), isFalse);
    },
  );

  test(
    'confirming a planned stay counts it and a conflict replaces the country',
    () async {
      final controller = AppController(clock: () => today);
      controller.openExample();
      final china = stay(
        id: 'cn',
        country: 'CN',
        start: '2026-01-01',
        end: '2026-01-31',
        evidence: 'confirmed',
      );
      final philippines = stay(
        id: 'ph',
        country: 'PH',
        start: '2026-01-10',
        end: '2026-01-12',
        phase: TripPhase.planned,
      );
      controller.stays = [china, philippines];
      expect(controller.tally.primaryDays['CN'], 31);
      expect(controller.tally.primaryDays.containsKey('PH'), isFalse);

      final failure = await controller.confirmStay(philippines);
      expect(failure, isNull);
      final saved = controller.stays.singleWhere((item) => item.id == 'ph');
      expect(saved.evidenceStatus, 'confirmed');
      expect(saved.phase, TripPhase.actual);
      expect(controller.tally.primaryDays['PH'], 3);
      expect(controller.tally.primaryDays['CN'], 28);
      expect(
        controller.stays.where((item) => item.countryCode == 'CN'),
        hasLength(2),
      );
      expect(controller.tally.overlapDays, 0);
    },
  );

  test('not right leaves the stay out of the total', () async {
    final controller = AppController(clock: () => today);
    controller.openExample();
    final united = stay(
      id: 'us',
      country: 'US',
      start: '2026-05-12',
      end: '2026-05-17',
    );
    controller.stays = [united];
    final failure = await controller.dismissStay(united);
    expect(failure, isNull);
    expect(controller.stays.single.evidenceStatus, 'unknown');
    expect(controller.tally.primaryDays.containsKey('US'), isFalse);
    expect(reviewQueueCount(flights: const [], stays: controller.stays), 0);
  });

  testWidgets(
    'the queue shows both kinds of stay and confirming refreshes the total',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = AppController(clock: () => today);
      controller.openExample();
      controller.stays = [
        stay(
          id: 'us',
          country: 'US',
          start: '2026-05-12',
          end: '2026-05-17',
          notes: 'Calendar event, example only. Strength: strong. https://example.com/calendar/workshop',
        ),
        stay(
          id: 'ph-plan',
          country: 'PH',
          start: '2026-02-01',
          end: '2026-02-03',
          phase: TripPhase.planned,
          notes: 'Hours log, example only. Strength: weak.',
        ),
      ];
      controller.flights = [
        flight(
          id: 'ac',
          number: 'EX187',
          from: 'CR',
          to: 'CA',
          depart: '2025-01-12T15:30',
          arrive: '2025-01-12T21:50',
          notes: 'Source https://example.com/mail/ex187 Passenger Example Traveler verified from booking. All clocks are scheduled local clocks from source. No stays generated; needs manual review.',
        ),
      ];
      await tester.pumpWidget(
        NomadicApp(controller: controller, initialSection: Section.days),
      );
      await tester.pumpAndSettle();
      expect(find.text('3 flights and stays need a check'), findsOneWidget);
      await tester.tap(find.byKey(const Key('open-review-queue')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('review-year-2025')), findsOneWidget);
      expect(find.byKey(const Key('review-year-2026')), findsOneWidget);
      expect(find.textContaining('Liberia, Costa Rica'), findsOneWidget);
      expect(find.textContaining('3:30 PM'), findsOneWidget);
      expect(find.text('Counts 13 Jan 2025 as Canada.'), findsOneWidget);
      expect(
        find.text('Stay: United States, 12 May 2026 – 17 May 2026 (6 days)'),
        findsOneWidget,
      );
      expect(
        find.text('Stay: Philippines, 1 Feb 2026 – 3 Feb 2026 (3 days)'),
        findsOneWidget,
      );
      expect(
        find.text('Counts 12 May 2026 – 17 May 2026 as United States.'),
        findsOneWidget,
      );
      expect(find.textContaining('https://'), findsNothing);
      expect(find.textContaining('America/'), findsNothing);
      expect(find.textContaining('booking_only'), findsNothing);
      expect(find.text('View source'), findsWidgets);
      expect(find.text('Keep these days out of the total'), findsNothing);
      await tester.tap(find.byKey(const Key('more-options-ac')));
      await tester.pumpAndSettle();
      expect(find.text('Keep these days out of the total'), findsOneWidget);
      expect(find.text('I was there, not only booked'), findsOneWidget);

      expect(controller.tally.primaryDays.containsKey('US'), isFalse);
      await tester.tap(find.byKey(const Key('confirm-stay-us')));
      await tester.pumpAndSettle();
      expect(
        controller.stays.singleWhere((item) => item.id == 'us').evidenceStatus,
        'confirmed',
      );
      expect(controller.tally.primaryDays['US'], 6);
      expect(find.byKey(const Key('stay-card-us')), findsNothing);
      expect(find.byKey(const Key('stay-card-ph-plan')), findsOneWidget);
      expect(
        controller.stays.singleWhere((item) => item.id == 'ph-plan').phase,
        TripPhase.planned,
      );
    },
  );
}
