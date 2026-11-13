import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomadic_residence/engine/day_engine.dart';
import 'package:nomadic_residence/engine/local_date.dart';
import 'package:nomadic_residence/engine/models.dart';
import 'package:nomadic_residence/state/app_controller.dart';
import 'package:nomadic_residence/ui/summary_page.dart';
import 'package:nomadic_residence/ui/theme.dart';

/// Fictional 2025 used for the summary screenshots.
///
/// Not an account and not derived from a real itinerary. The same stays and
/// flights are shown twice: once with flight brackets withheld, once with
/// the summary rule that counts them.
void main() {
  final today = LocalDate(2026, 11, 13);

  Stay stay({
    required String id,
    required String country,
    required String start,
    required String end,
    String evidence = 'confirmed',
    InferenceKind inference = InferenceKind.none,
  }) {
    return Stay(
      id: id,
      countryCode: country,
      start: LocalDate.parse(start),
      end: LocalDate.parse(end),
      role: PresenceRole.primary,
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

  void load(AppController controller) {
    controller.year = 2025;
    controller.stays = [
      stay(id: 'pt', country: 'PT', start: '2025-01-01', end: '2025-01-14'),
      stay(
        id: 'ca-inferred',
        country: 'CA',
        start: '2025-08-08',
        end: '2025-09-10',
        evidence: 'inferred',
        inference: InferenceKind.inferredItinerary,
      ),
      stay(
        id: 'fr-imported',
        country: 'FR',
        start: '2025-03-01',
        end: '2025-03-10',
        evidence: 'inferred',
        inference: InferenceKind.inferredGap,
      ),
      stay(id: 'mx', country: 'MX', start: '2025-11-02', end: '2025-11-04'),
    ];
    controller.flights = [
      flight(
        id: 'it-in',
        number: 'NB600',
        from: 'ES',
        to: 'IT',
        depart: '2025-03-31T22:00',
        arrive: '2025-04-01T07:00',
      ),
      flight(
        id: 'it-out',
        number: 'NB620',
        from: 'IT',
        to: 'DE',
        depart: '2025-04-15T12:00',
        arrive: '2025-04-15T15:00',
        evidence: 'booking_only',
        review: FlightReviewState.pending,
      ),
      flight(
        id: 'ca-in',
        number: 'NB100',
        from: 'PT',
        to: 'CA',
        depart: '2025-08-07T09:00',
        arrive: '2025-08-07T18:00',
      ),
      flight(
        id: 'ca-out',
        number: 'NB200',
        from: 'CA',
        to: 'PT',
        depart: '2025-09-10T11:00',
        arrive: '2025-09-10T22:00',
      ),
      flight(
        id: 'pt-block',
        number: 'NB201',
        from: 'PT',
        to: 'MX',
        depart: '2025-09-12T10:00',
        arrive: '2025-09-12T14:00',
        evidence: 'booking_only',
        review: FlightReviewState.pending,
      ),
      flight(
        id: 'us-in',
        number: 'NB410',
        from: 'GB',
        to: 'US',
        depart: '2025-10-31T09:00',
        arrive: '2025-10-31T16:00',
      ),
      flight(
        id: 'us-out',
        number: 'NB420',
        from: 'US',
        to: 'GB',
        depart: '2025-11-08T18:00',
        arrive: '2025-11-09T06:00',
      ),
      flight(
        id: 'gb-block',
        number: 'NB421',
        from: 'GB',
        to: 'IE',
        depart: '2025-11-10T12:00',
        arrive: '2025-11-10T14:00',
        evidence: 'booking_only',
        review: FlightReviewState.pending,
      ),
      flight(
        id: 'mismatch-in',
        number: 'NB310',
        from: 'MX',
        to: 'JP',
        depart: '2025-12-01T09:00',
        arrive: '2025-12-01T20:00',
      ),
      flight(
        id: 'mismatch-out',
        number: 'NB320',
        from: 'US',
        to: 'CL',
        depart: '2025-12-15T09:00',
        arrive: '2025-12-15T18:00',
      ),
    ];
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    final boundary = tester.renderObject(
      find.byKey(const Key('summary-shot')),
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
    File('${dir.path}/$name.png').writeAsBytesSync(bytes.buffer.asUint8List());
  }

  testWidgets('summary shows flight-bracketed days beside stays', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1040, 1880);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _loadInter();

    final before = _BracketToggle(applyBrackets: false, clock: () => today);
    load(before);
    await tester.pumpWidget(_frame(before, 'Fixture · previous rule'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('primary-total')), findsOneWidget);
    expect(find.text('17 wake-up country days'), findsOneWidget);
    expect(find.textContaining('44 inferred country days'), findsOneWidget);
    expect(find.text('Canada'), findsNothing);
    expect(find.byKey(const Key('flight-bracket-section')), findsNothing);
    expect(before.tally.identityHolds, isTrue);
    expect(before.tally.primaryCountryDays, 17);
    await shoot(tester, 'summary-before');

    final after = AppController(clock: () => today);
    load(after);
    await tester.pumpWidget(
      _frame(after, 'Fixture · flight brackets in the wake-up total'),
    );
    await tester.pumpAndSettle();

    expect(find.text('56 wake-up country days'), findsOneWidget);
    expect(find.byKey(const Key('source-total')), findsOneWidget);
    expect(
      find.text(
        '17 from stays · 39 from flights. Both are in this wake-up total.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('country-source-CA')), findsOneWidget);
    expect(find.text('34 from flights'), findsWidgets);
    expect(find.text('14 from stays'), findsOneWidget);
    expect(find.text('3 from stays'), findsOneWidget);
    expect(find.text('5 from flights'), findsWidgets);
    expect(find.textContaining('10 inferred country days'), findsOneWidget);
    expect(
      find.byKey(const Key('flight-mismatch-NB310-NB320')),
      findsOneWidget,
    );
    expect(find.textContaining('Those days stay unknown.'), findsOneWidget);
    expect(find.byKey(const Key('flight-conflict-US-MX')), findsOneWidget);
    expect(find.textContaining('The existing stay is kept.'), findsOneWidget);
    expect(
      find.byKey(const Key('flight-unqualified-NB600-NB620')),
      findsOneWidget,
    );
    expect(find.textContaining('NB620 is not accepted'), findsWidgets);
    expect(after.tally.identityHolds, isTrue);
    expect(after.tally.primaryDays['CA'], 34);
    expect(after.tally.flightBracketDays['CA'], 34);
    expect(after.tally.primaryDays['US'], 5);
    expect(after.tally.stayPrimaryDays['PT'], 14);
    expect(after.tally.stayPrimaryDays['MX'], 3);
    expect(after.tally.inferredKeptOutDays, 10);
    expect(
      after.stays
          .singleWhere((item) => item.id == 'ca-inferred')
          .evidenceStatus,
      'inferred',
    );
    await shoot(tester, 'summary-after');
  });
}

class _BracketToggle extends AppController {
  _BracketToggle({
    required this.applyBrackets,
    required LocalDate Function() clock,
  }) : super(clock: clock);

  final bool applyBrackets;

  @override
  YearTally get tally => DayEngine.tally(
    stays: stays,
    flights: applyBrackets ? flights : const [],
    year: year,
    today: clock(),
    rules: rules,
    statuses: statuses,
  );
}

Future<void> _loadInter() async {
  const paths = [
    '/usr/share/fonts/truetype/macos/Inter-Regular.ttf',
    '/usr/share/fonts/truetype/macos/Inter-Medium.ttf',
    '/usr/share/fonts/truetype/macos/Inter-Bold.ttf',
  ];
  if (!File(paths.first).existsSync()) return;
  final loader = FontLoader('Inter');
  for (final path in paths) {
    final bytes = File(path).readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

Widget _frame(AppController controller, String title) {
  final base = buildTheme();
  final text = base.textTheme.apply(fontFamily: 'Inter');
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: base.copyWith(textTheme: text, primaryTextTheme: text),
    home: RepaintBoundary(
      key: const Key('summary-shot'),
      child: Scaffold(
        backgroundColor: paper,
        appBar: AppBar(title: Text(title, style: text.titleLarge)),
        body: SummaryPage(controller: controller),
      ),
    ),
  );
}
