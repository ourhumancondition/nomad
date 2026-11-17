import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomadic_residence/data/countries.dart';
import 'package:nomadic_residence/engine/local_date.dart';
import 'package:nomadic_residence/engine/models.dart';
import 'package:nomadic_residence/engine/today_presence.dart';
import 'package:nomadic_residence/state/app_controller.dart';
import 'package:nomadic_residence/ui/nomadic_app.dart';
import 'package:nomadic_residence/ui/theme.dart';
import 'package:nomadic_residence/ui/today_banner.dart';

/// Fictional records used only by these tests. Not a real trip.
final today = LocalDate(2026, 11, 17);

Stay stay(
  String id,
  String country,
  String start,
  String end, {
  String evidence = 'confirmed',
  PresenceRole role = PresenceRole.primary,
}) => Stay(
  id: id,
  countryCode: country,
  start: LocalDate.parse(start),
  end: LocalDate.parse(end),
  role: role,
  evidenceStatus: evidence,
  inference: InferenceKind.none,
  phase: TripPhase.actual,
  timezone: 'Etc/UTC',
  externalId: id,
);

FlightRecord flight(
  String id,
  String number,
  String from,
  String to,
  String depart,
  String arrive,
) => FlightRecord(
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
  evidenceStatus: 'confirmed',
  inference: InferenceKind.none,
  reviewState: FlightReviewState.accepted,
  externalId: id,
);

/// One fixture per banner state.
final scenarios =
    <TodayStatus, ({List<Stay> stays, List<FlightRecord> flights})>{
      TodayStatus.confirmed: (
        stays: [stay('ca', 'CA', '2026-11-09', '2026-11-30')],
        flights: const [],
      ),
      TodayStatus.fromFlights: (
        stays: const [],
        flights: [
          flight(
            'in',
            'AC5',
            'PT',
            'CA',
            '2026-11-09T10:00',
            '2026-11-09T14:00',
          ),
          flight(
            'out',
            'AC9',
            'CA',
            'MX',
            '2026-11-25T10:00',
            '2026-11-25T16:00',
          ),
        ],
      ),
      TodayStatus.inTransit: (
        stays: const [],
        flights: [
          flight(
            'ov',
            'MS1',
            'CA',
            'EG',
            '2026-11-16T22:00',
            '2026-11-17T15:00',
          ),
        ],
      ),
      TodayStatus.conflict: (
        stays: [
          stay('ca', 'CA', '2026-11-01', '2026-11-17'),
          stay('eg', 'EG', '2026-11-17', '2026-11-25'),
        ],
        flights: const [],
      ),
      TodayStatus.unknown: (stays: const [], flights: const []),
    };

AppController controllerFor(TodayStatus status) {
  final data = scenarios[status]!;
  final controller = AppController(clock: () => today);
  controller.kind = SessionKind.example;
  controller.year = 2026;
  controller.stays = List.of(data.stays);
  controller.flights = List.of(data.flights);
  return controller;
}

TodayPresence presenceFor(TodayStatus status) {
  final data = scenarios[status]!;
  return resolveTodayOn(
    today,
    stays: data.stays,
    flights: data.flights,
    rules: CountingRules.standard,
    statuses: defaultEvidenceStatuses,
  );
}

Future<void> setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

double _luminance(Color color) {
  double channel(double c) =>
      c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

double contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  group('banner on the Days page', () {
    for (final status in TodayStatus.values) {
      for (final size in const [Size(375, 1800), Size(1280, 900)]) {
        testWidgets('${status.name} at ${size.width.toInt()}px', (
          tester,
        ) async {
          await setSize(tester, size);
          final controller = controllerFor(status);
          await tester.pumpWidget(NomadicApp(controller: controller));
          await tester.pump();
          expect(
            find.byKey(Key('today-banner-${status.name}')),
            findsOneWidget,
          );
          expect(find.byKey(Key('today-chip-${status.name}')), findsOneWidget);
          // The banner sits above the year totals.
          final banner = tester.getTopLeft(
            find.byKey(Key('today-banner-${status.name}')),
          );
          final totals = tester.getTopLeft(find.byKey(const Key('days-title')));
          expect(banner.dy, lessThan(totals.dy));
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('banner in light and dark', () {
    for (final brightness in Brightness.values) {
      for (final status in TodayStatus.values) {
        for (final width in const [375.0, 1280.0]) {
          testWidgets('${status.name} ${brightness.name} ${width.toInt()}px', (
            tester,
          ) async {
            await setSize(tester, Size(width, 900));
            final theme = brightness == Brightness.dark
                ? ThemeData(useMaterial3: true, brightness: Brightness.dark)
                : buildTheme();
            await tester.pumpWidget(
              MaterialApp(
                theme: theme,
                home: Scaffold(
                  body: Padding(
                    padding: const EdgeInsets.all(20),
                    child: TodayBanner(
                      presence: presenceFor(status),
                      onConfirm: (_) {},
                      onElsewhere: () {},
                      onOpenConflicts: () {},
                    ),
                  ),
                ),
              ),
            );
            expect(tester.takeException(), isNull);
            await expectLater(
              tester,
              meetsGuideline(androidTapTargetGuideline),
            );
            await expectLater(tester, meetsGuideline(textContrastGuideline));
          });
        }
      }
    }
  });

  testWidgets('confirmed text and semantic label', (tester) async {
    await setSize(tester, const Size(375, 1800));
    await tester.pumpWidget(
      NomadicApp(controller: controllerFor(TodayStatus.confirmed)),
    );
    final banner = find.byKey(const Key('today-banner-confirmed'));
    expect(
      find.descendant(
        of: banner,
        matching: find.text('Today you\'re in Canada'),
      ),
      findsOneWidget,
    );
    expect(
      find.text('Day 9 in Canada this year · here since Nov 9'),
      findsOneWidget,
    );
    expect(find.text('Confirmed stay'), findsOneWidget);
    expect(find.text('🇨🇦'), findsWidgets);
    expect(
      find.bySemanticsLabel(
        'Today you are in Canada, confirmed, day 9 this year',
      ),
      findsWidgets,
    );
    // Already confirmed: no "Yes, I'm here".
    expect(find.byKey(const Key('today-confirm')), findsNothing);
    expect(find.byKey(const Key('today-elsewhere')), findsOneWidget);
  });

  testWidgets('unknown state offers a country choice', (tester) async {
    await setSize(tester, const Size(375, 1800));
    await tester.pumpWidget(
      NomadicApp(controller: controllerFor(TodayStatus.unknown)),
    );
    final banner = find.byKey(const Key('today-banner-unknown'));
    expect(
      find.descendant(of: banner, matching: find.text('Where are you today?')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: banner, matching: find.text('🌍')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('today-choose')), findsOneWidget);
  });

  testWidgets('conflict state links to the overlapping records', (
    tester,
  ) async {
    await setSize(tester, const Size(375, 1800));
    await tester.pumpWidget(
      NomadicApp(controller: controllerFor(TodayStatus.conflict)),
    );
    expect(find.text('Two countries overlap today'), findsOneWidget);
    expect(find.text('Canada: 1 Nov 2026 – 17 Nov 2026'), findsOneWidget);
    expect(find.text('Egypt: 17 Nov 2026 – 25 Nov 2026'), findsOneWidget);
    await tester.tap(find.byKey(const Key('today-open-conflicts')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('today-banner-conflict')), findsNothing);
    expect(find.byKey(const Key('back-to-list')), findsOneWidget);
  });

  testWidgets('loading shows a skeleton and never a country', (tester) async {
    await setSize(tester, const Size(375, 1800));
    final controller = controllerFor(TodayStatus.confirmed)..restoring = true;
    await tester.pumpWidget(NomadicApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('today-skeleton')), findsOneWidget);
    // The year list below may name countries; the banner area must not.
    expect(find.byKey(const Key('today-headline')), findsNothing);
    expect(find.byKey(const Key('today-flag')), findsNothing);
    expect(find.byKey(const Key('today-compact')), findsNothing);
    expect(find.byKey(const Key('today-banner-confirmed')), findsNothing);
  });

  testWidgets('scrolling shows the slim sticky header', (tester) async {
    await setSize(tester, const Size(375, 1100));
    await tester.pumpWidget(
      NomadicApp(controller: controllerFor(TodayStatus.confirmed)),
    );
    double compactOpacity() => tester
        .widget<AnimatedOpacity>(
          find.ancestor(
            of: find.byKey(const Key('today-compact')),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .opacity;
    expect(compactOpacity(), 0);
    await tester.drag(find.byType(ListView).first, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(compactOpacity(), 1);
    expect(
      find.descendant(
        of: find.byKey(const Key('today-compact')),
        matching: find.text('Canada'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('today-compact')));
    await tester.pumpAndSettle();
    expect(compactOpacity(), 0);
  });

  group('one-tap actions', () {
    testWidgets('"Yes, I\'m here" saves today and undo removes it', (
      tester,
    ) async {
      await setSize(tester, const Size(375, 1800));
      final controller = controllerFor(TodayStatus.fromFlights);
      final flightsBefore = List.of(controller.flights);
      await tester.pumpWidget(NomadicApp(controller: controller));
      await tester.tap(find.byKey(const Key('today-confirm')));
      await tester.pump();
      expect(controller.stays, hasLength(1));
      final saved = controller.stays.single;
      expect(saved.countryCode, 'CA');
      expect(saved.start, today);
      expect(saved.end, today);
      expect(saved.evidenceStatus, 'confirmed');
      expect(saved.inference, InferenceKind.none);
      expect(controller.today.status, TodayStatus.confirmed);
      expect(controller.flights, flightsBefore);
      await tester.pump(const Duration(milliseconds: 750));
      expect(find.text('Saved today as Canada.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('today-undo')));
      await tester.pump();
      expect(controller.stays, isEmpty);
      expect(controller.flights, flightsBefore);
      expect(controller.today.status, TodayStatus.fromFlights);
    });

    testWidgets('undo snackbar goes away after 5 seconds', (tester) async {
      await setSize(tester, const Size(375, 1800));
      final controller = controllerFor(TodayStatus.fromFlights);
      await tester.pumpWidget(NomadicApp(controller: controller));
      await tester.tap(find.byKey(const Key('today-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));
      expect(find.byKey(const Key('today-undo')), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('today-undo')), findsNothing);
      expect(controller.stays, hasLength(1));
    });

    testWidgets('extends an adjacent confirmed stay, and undo restores it', (
      tester,
    ) async {
      await setSize(tester, const Size(375, 1800));
      final controller = AppController(clock: () => today)
        ..kind = SessionKind.example
        ..year = 2026
        ..stays = [stay('ca', 'CA', '2026-11-01', '2026-11-16')];
      await tester.pumpWidget(NomadicApp(controller: controller));
      // Unknown today, suggested from yesterday.
      expect(find.text('Yes, I\'m in Canada'), findsOneWidget);
      await tester.tap(find.byKey(const Key('today-confirm')));
      await tester.pump();
      expect(controller.stays, hasLength(1));
      expect(controller.stays.single.id, 'ca');
      expect(controller.stays.single.end, today);
      await tester.pump(const Duration(milliseconds: 750));
      expect(find.text('Added today to your Canada stay.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('today-undo')));
      await tester.pump();
      expect(controller.stays.single.end, LocalDate(2026, 11, 16));
    });

    testWidgets('"I\'m somewhere else" saves a confirmed stay with a note', (
      tester,
    ) async {
      await setSize(tester, const Size(375, 1800));
      final controller = controllerFor(TodayStatus.fromFlights);
      await tester.pumpWidget(NomadicApp(controller: controller));
      await tester.tap(find.byKey(const Key('today-elsewhere')));
      await tester.pumpAndSettle();
      // Recent countries come first.
      final first = tester.getTopLeft(find.byKey(const Key('today-option-MX')));
      final afghanistan = find.byKey(const Key('today-option-AF'));
      if (afghanistan.evaluate().isNotEmpty) {
        expect(first.dy, lessThan(tester.getTopLeft(afghanistan).dy));
      }
      await tester.enterText(find.byKey(const Key('today-search')), 'philipp');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('today-option-PH')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('today-note')), 'Ferry day');
      await tester.tap(find.byKey(const Key('today-elsewhere-save')));
      await tester.pumpAndSettle();
      final saved = controller.stays.single;
      expect(saved.countryCode, 'PH');
      expect(saved.start, today);
      expect(saved.end, today);
      expect(saved.notes, 'Ferry day');
      expect(controller.flights, hasLength(2));
      expect(controller.today.countryCode, 'PH');
      expect(controller.today.status, TodayStatus.confirmed);
    });
  });

  group('contrast', () {
    for (final brightness in Brightness.values) {
      final surface = brightness == Brightness.dark
          ? ThemeData(
              useMaterial3: true,
              brightness: Brightness.dark,
            ).colorScheme.surface
          : buildTheme().colorScheme.surface;
      test('chips meet 4.5:1 in ${brightness.name}', () {
        for (final status in TodayStatus.values) {
          final colors = todayChipColors(status, brightness);
          expect(
            contrast(colors.foreground, colors.background),
            greaterThanOrEqualTo(4.5),
            reason: status.name,
          );
        }
      });
      test('muted text meets 4.5:1 on every tint in ${brightness.name}', () {
        final muted = todayMutedText(brightness);
        for (final code in countryNames.keys) {
          final tinted = Color.alphaBlend(
            countryColor(code).withValues(alpha: todayAccentAlpha),
            surface,
          );
          expect(
            contrast(muted, tinted),
            greaterThanOrEqualTo(4.5),
            reason: code,
          );
        }
      });
    }
  });
}
