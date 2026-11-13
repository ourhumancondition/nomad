import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomadic_residence/engine/local_date.dart';
import 'package:nomadic_residence/engine/models.dart';
import 'package:nomadic_residence/state/app_controller.dart';
import 'package:nomadic_residence/ui/nomadic_app.dart';

/// Fictional days used only by this test. Not an account and not a real trip.
void main() {
  final today = LocalDate(2026, 11, 13);

  Stay stay({
    required String id,
    required String country,
    required String start,
    required String end,
    String evidence = 'confirmed',
    InferenceKind inference = InferenceKind.none,
    PresenceRole role = PresenceRole.primary,
  }) {
    return Stay(
      id: id,
      countryCode: country,
      start: LocalDate.parse(start),
      end: LocalDate.parse(end),
      role: role,
      evidenceStatus: evidence,
      inference: inference,
      phase: TripPhase.actual,
      timezone: 'Etc/UTC',
      notes: 'Fixture stay. Fictional.',
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
    String evidence = 'confirmed',
    FlightReviewState review = FlightReviewState.accepted,
  }) {
    return FlightRecord(
      id: id,
      flightNumber: number,
      fromIata: 'AAA',
      toIata: 'BBB',
      fromCountry: from,
      toCountry: to,
      depart: WallTime.parse(depart),
      arrive: WallTime.parse(arrive),
      departTimezone: 'Etc/UTC',
      arriveTimezone: 'Etc/UTC',
      evidenceStatus: evidence,
      inference: InferenceKind.none,
      reviewState: review,
      notes: 'Fixture flight. Fictional.',
      externalId: id,
    );
  }

  AppController load() {
    final controller = AppController(clock: () => today);
    controller.kind = SessionKind.example;
    controller.year = 2026;
    controller.stays = [
      stay(id: 'pt', country: 'PT', start: '2026-01-01', end: '2026-01-14'),
      stay(id: 'mx', country: 'MX', start: '2026-06-01', end: '2026-06-03'),
      stay(
        id: 'fr-guess',
        country: 'FR',
        start: '2026-03-01',
        end: '2026-03-10',
        evidence: 'inferred',
        inference: InferenceKind.inferredItinerary,
      ),
      stay(
        id: 'it-booking',
        country: 'IT',
        start: '2026-07-01',
        end: '2026-07-04',
        evidence: 'booking_only',
      ),
      stay(
        id: 'sg-stop',
        country: 'SG',
        start: '2026-01-05',
        end: '2026-01-05',
        role: PresenceRole.layover,
      ),
      stay(id: 'jp', country: 'JP', start: '2025-01-01', end: '2025-01-20'),
      stay(id: 'de', country: 'DE', start: '2025-02-01', end: '2025-02-05'),
      stay(id: 'us', country: 'US', start: '2025-12-01', end: '2025-12-10'),
    ];
    controller.flights = [
      flight(
        id: 'ca-in',
        number: 'CA100',
        from: 'PT',
        to: 'CA',
        depart: '2026-08-07T09:00',
        arrive: '2026-08-07T18:00',
      ),
      flight(
        id: 'ca-out',
        number: 'CA200',
        from: 'CA',
        to: 'US',
        depart: '2026-09-10T11:00',
        arrive: '2026-09-10T22:00',
      ),
      flight(
        id: 'pt-in',
        number: 'PT100',
        from: 'FR',
        to: 'PT',
        depart: '2026-05-02T09:00',
        arrive: '2026-05-02T18:00',
      ),
      flight(
        id: 'pt-out',
        number: 'PT200',
        from: 'PT',
        to: 'FR',
        depart: '2026-05-06T11:00',
        arrive: '2026-05-06T18:00',
      ),
      flight(
        id: 'es-in',
        number: 'ES100',
        from: 'PT',
        to: 'ES',
        depart: '2026-10-01T09:00',
        arrive: '2026-10-01T18:00',
        evidence: 'booking_only',
        review: FlightReviewState.pending,
      ),
      flight(
        id: 'es-out',
        number: 'ES200',
        from: 'ES',
        to: 'FR',
        depart: '2026-10-11T11:00',
        arrive: '2026-10-11T18:00',
        evidence: 'booking_only',
        review: FlightReviewState.pending,
      ),
      flight(
        id: 'lone',
        number: 'LN100',
        from: 'FR',
        to: 'TN',
        depart: '2026-09-01T12:00',
        arrive: '2026-09-01T14:00',
        evidence: 'booking_only',
        review: FlightReviewState.pending,
      ),
    ];
    return controller;
  }

  Future<void> pump(WidgetTester tester, AppController controller) async {
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(NomadicApp(controller: controller));
    await tester.pumpAndSettle();
  }

  void expectOrder(WidgetTester tester, List<String> codes) {
    var previous = -1.0;
    for (final code in codes) {
      final top = tester.getTopLeft(find.byKey(Key('country-row-$code'))).dy;
      expect(top, greaterThan(previous), reason: code);
      previous = top;
    }
  }

  void expectNoJargon(WidgetTester tester) {
    const forbidden = [
      'evidence',
      'inferred',
      'corroborated',
      'wake-up',
      'wake up',
      'needs_manual',
      'pocketbase',
      'phase',
    ];
    final blob = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
        .join('\n')
        .toLowerCase();
    for (final word in forbidden) {
      expect(blob.contains(word), isFalse, reason: word);
    }
  }

  testWidgets('countries sort by days and combine stays with flights', (
    tester,
  ) async {
    final controller = load();
    await pump(tester, controller);

    expect(find.byKey(const Key('days-title')), findsOneWidget);
    expect(find.text('2026'), findsOneWidget);
    expect(controller.tally.stayPrimaryDays['PT'], 14);
    expect(controller.tally.flightBracketDays['PT'], 4);
    expect(controller.tally.primaryDays['PT'], 18);
    expect(controller.tally.primaryDays['CA'], 34);
    expect(controller.tally.flightBracketDays['CA'], 34);
    expect(find.byKey(const Key('country-days-CA')), findsOneWidget);
    expect(find.text('34'), findsOneWidget);
    expect(find.text('18'), findsOneWidget);
    expect(find.text('3'), findsWidgets);
    expect(controller.tally.flightBracketDays['FR'], 86);
    expect(controller.tally.stayPrimaryDays.containsKey('FR'), isFalse);
    expect(find.byKey(const Key('country-days-FR')), findsOneWidget);
    expect(find.text('86'), findsOneWidget);
    expect(find.byKey(const Key('country-row-IT')), findsNothing);
    expect(find.byKey(const Key('country-row-ES')), findsNothing);
    expect(find.textContaining('from stays'), findsNothing);
    expectOrder(tester, ['FR', 'CA', 'PT', 'MX']);

    expect(find.byKey(const Key('known-days')), findsOneWidget);
    expect(find.text('141 days in a country'), findsOneWidget);
    expect(
      find.text("We don't know where you were on 176 days"),
      findsOneWidget,
    );
    expect(controller.tally.gapDays, 176);

    await tester.tap(find.text('How is this counted?'));
    await tester.pumpAndSettle();
    expect(find.textContaining('only a guess'), findsOneWidget);
    expect(
      find.textContaining('bookings you have not confirmed'),
      findsOneWidget,
    );
    expect(find.textContaining('stopover'), findsOneWidget);
    expect(
      find.textContaining('we counted these days as France'),
      findsOneWidget,
    );
    expect(
      find.text('from flights (left from Portugal)'),
      findsOneWidget,
    );
    expectNoJargon(tester);

    await tester.tap(find.byKey(const Key('fill-unknown')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('missing-title')), findsOneWidget);
    expect(find.textContaining('15 Jan 2026'), findsWidgets);
    expect(find.textContaining('Evidence'), findsNothing);
    await tester.tap(find.byKey(const Key('add-where-2026-01-15')));
    await tester.pumpAndSettle();
    expect(find.text('Where were you?'), findsOneWidget);
    expect(find.text('Evidence status'), findsNothing);
    expect(find.textContaining('Inference'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('back-to-list')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('days-title')), findsOneWidget);
  });

  testWidgets('the year control changes the list and the unknown count', (
    tester,
  ) async {
    final controller = load();
    await pump(tester, controller);

    await tester.tap(find.byKey(const Key('year-previous')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('year-label')), findsOneWidget);
    expect(find.text('2025'), findsOneWidget);
    expect(controller.year, 2025);
    expect(find.text('20'), findsOneWidget);
    expect(find.text('10'), findsWidgets);
    expect(find.text('5'), findsWidgets);
    expectOrder(tester, ['JP', 'US', 'DE']);
    expect(find.byKey(const Key('country-row-CA')), findsNothing);
    expect(
      find.text("We don't know where you were on 330 days"),
      findsOneWidget,
    );
    expect(controller.tally.gapDays, 330);
    expect(controller.tally.primaryDays['JP'], 20);

    await tester.tap(find.byKey(const Key('year-next')));
    await tester.pumpAndSettle();
    expect(find.text('2026'), findsOneWidget);
    expect(find.byKey(const Key('country-row-CA')), findsOneWidget);
    expect(find.byKey(const Key('country-row-JP')), findsNothing);
  });

  testWidgets('last 12 months keeps recent days and drops the earlier year', (
    tester,
  ) async {
    final controller = load();
    await pump(tester, controller);

    await tester.tap(find.byKey(const Key('period-rolling')));
    await tester.pumpAndSettle();
    expect(find.text('Last 12 months'), findsWidgets);
    expect(find.byKey(const Key('country-days-US')), findsOneWidget);
    expect(find.text('10'), findsWidgets);
    expect(find.byKey(const Key('country-days-CA')), findsOneWidget);
    expect(find.text('34'), findsOneWidget);
    expect(find.byKey(const Key('country-row-JP')), findsNothing);
    expect(find.byKey(const Key('country-row-DE')), findsNothing);
    expect(
      find.text("We don't know where you were on 214 days"),
      findsOneWidget,
    );
    expect(find.byKey(const Key('country-days-FR')), findsOneWidget);
    expectOrder(tester, ['FR', 'CA', 'PT', 'US', 'MX']);
  });

  testWidgets('confirming the waiting trips adds their days as one number', (
    tester,
  ) async {
    final controller = load();
    await pump(tester, controller);

    expect(find.text('Confirm 2 trips to count more days'), findsOneWidget);
    expect(find.textContaining('LN100'), findsNothing);
    await tester.tap(find.byKey(const Key('confirm-trips')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('trip-es-in')), findsOneWidget);
    expect(find.byKey(const Key('trip-es-out')), findsOneWidget);
    expect(find.byKey(const Key('trip-lone')), findsNothing);
    expect(find.textContaining('evidence'), findsNothing);
    expect(find.textContaining('booking'), findsNothing);

    await tester.tap(find.byKey(const Key('trip-yes-es-in')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('trip-yes-es-out')));
    await tester.pumpAndSettle();

    expect(
      controller.flights
          .singleWhere((flight) => flight.id == 'es-in')
          .reviewState,
      FlightReviewState.accepted,
    );
    expect(controller.stays.where((stay) => stay.countryCode == 'ES'), isEmpty);
    expect(find.textContaining('No trips are waiting'), findsOneWidget);

    await tester.tap(find.byKey(const Key('back-to-list')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('country-days-ES')), findsOneWidget);
    expect(controller.tally.primaryDays['ES'], 10);
    expect(find.text('10'), findsWidgets);
    expect(find.byKey(const Key('confirm-trips')), findsNothing);
    expectOrder(tester, ['CA', 'PT', 'ES', 'MX']);
  });

  testWidgets('a mismatched flight counts as the country he landed in', (
    tester,
  ) async {
    final controller = AppController(clock: () => today);
    controller.kind = SessionKind.example;
    controller.year = 2026;
    controller.flights = [
      FlightRecord(
        id: 'tg612',
        flightNumber: 'TG612',
        fromIata: 'BKK',
        toIata: 'PEK',
        fromCountry: 'TH',
        toCountry: 'CN',
        depart: WallTime.parse('2026-01-27T22:00'),
        arrive: WallTime.parse('2026-01-28T06:00'),
        departTimezone: 'Etc/UTC',
        arriveTimezone: 'Etc/UTC',
        evidenceStatus: 'confirmed',
        inference: InferenceKind.none,
        reviewState: FlightReviewState.accepted,
        notes: 'Fixture flight. Fictional.',
        externalId: 'tg612',
      ),
      FlightRecord(
        id: 'tg621',
        flightNumber: 'TG621',
        fromIata: 'MNL',
        toIata: 'SIN',
        fromCountry: 'PH',
        toCountry: 'SG',
        depart: WallTime.parse('2026-03-02T11:00'),
        arrive: WallTime.parse('2026-03-02T15:00'),
        departTimezone: 'Etc/UTC',
        arriveTimezone: 'Etc/UTC',
        evidenceStatus: 'confirmed',
        inference: InferenceKind.none,
        reviewState: FlightReviewState.accepted,
        notes: 'Fixture flight. Fictional.',
        externalId: 'tg621',
      ),
    ];
    await pump(tester, controller);

    expect(controller.tally.primaryDays['CN'], 34);
    expect(controller.tally.flightBracketDays['CN'], 34);
    expect(controller.tally.stayPrimaryDays.containsKey('CN'), isFalse);
    expect(find.byKey(const Key('country-days-CN')), findsOneWidget);
    expect(find.text('34'), findsOneWidget);
    expect(find.text('China'), findsOneWidget);

    await tester.tap(find.text('How is this counted?'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'You landed in China on 28 Jan 2026 and next flew out of Philippines on 2 Mar 2026; we counted these days as China.',
      ),
      findsOneWidget,
    );
    expect(find.text('from flights (left from Philippines)'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('change-mismatch-TG612-TG621-CN-PH')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Where were you?'), findsOneWidget);
    expect(find.textContaining('28 Jan 2026'), findsWidgets);
    expect(find.text('Evidence status'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(controller.stays, isEmpty);
  });

  testWidgets('fixture shots of the country list at desktop and phone width', (
    tester,
  ) async {
    await _loadShotFonts();
    final controller = load();
    await _shoot(tester, controller, const Size(1280, 1100), 'days-desktop');
    await _shoot(tester, controller, const Size(390, 1100), 'days-phone');
  });
}

Future<void> _shoot(
  WidgetTester tester,
  AppController controller,
  Size size,
  String name,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    RepaintBoundary(
      key: const Key('days-shot'),
      child: NomadicApp(
        controller: controller,
        fontFamily: 'Inter',
        fontFamilyFallback: const ['Noto Color Emoji'],
      ),
    ),
  );
  await tester.pumpAndSettle();
  final boundary = tester.renderObject(
    find.byKey(const Key('days-shot')),
  ) as RenderRepaintBoundary;
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 2));
  if (image == null) return;
  final bytes = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  );
  if (bytes == null) return;
  final dir = Directory('/opt/cursor/artifacts');
  try {
    dir.createSync(recursive: true);
  } catch (_) {
    return;
  }
  final file = File('${dir.path}/$name.png');
  file.writeAsBytesSync(bytes.buffer.asUint8List());
  expect(file.existsSync(), isTrue);
  expect(file.lengthSync(), greaterThan(1000));
}

Future<void> _loadShotFonts() async {
  const faces = <String, List<String>>{
    'Inter': [
      '/usr/share/fonts/truetype/macos/Inter-Regular.ttf',
      '/usr/share/fonts/truetype/macos/Inter-Medium.ttf',
      '/usr/share/fonts/truetype/macos/Inter-SemiBold.ttf',
      '/usr/share/fonts/truetype/macos/Inter-Bold.ttf',
    ],
    'Noto Color Emoji': ['/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf'],
  };
  for (final entry in faces.entries) {
    if (!File(entry.value.first).existsSync()) continue;
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      final bytes = File(path).readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
}
