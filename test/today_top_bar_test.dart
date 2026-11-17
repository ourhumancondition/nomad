import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nomadic_residence/data/connection_country.dart';
import 'package:nomadic_residence/engine/local_date.dart';
import 'package:nomadic_residence/engine/models.dart';
import 'package:nomadic_residence/engine/today_presence.dart';
import 'package:nomadic_residence/state/app_controller.dart';
import 'package:nomadic_residence/ui/nomadic_app.dart';

import 'today_banner_test.dart' show flight, stay, today, setSize;

/// Fictional records and a fake connection. No network, no real account.
class FakeLookup implements ConnectionCountryLookup {
  FakeLookup(this.code);
  String? code;
  int calls = 0;

  @override
  Future<String?> country() async {
    calls += 1;
    return code;
  }
}

Future<AppController> load({
  List<Stay> stays = const [],
  List<FlightRecord> flights = const [],
  String? connection,
}) async {
  final controller = AppController(
    clock: () => today,
    whereLookup: FakeLookup(connection),
  );
  controller.kind = SessionKind.example;
  controller.year = 2026;
  controller.stays = List.of(stays);
  controller.flights = List.of(flights);
  await controller.checkConnectionCountry();
  return controller;
}

Finder topTitle() => find.byKey(const Key('today-top-title'));

void main() {
  group('top bar', () {
    testWidgets('shows where I am today on every page', (tester) async {
      await setSize(tester, const Size(375, 1800));
      final controller = await load(
        stays: [stay('ca', 'CA', '2026-11-09', '2026-11-30')],
      );
      await tester.pumpWidget(
        NomadicApp(controller: controller, initialSection: Section.summary),
      );
      await tester.pump();
      expect(tester.widget<Text>(topTitle()).data, 'Today: Canada');
      expect(
        find.byKey(const Key('today-compact-chip-confirmed')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'Today you are in Canada, confirmed, day 9 this year',
        ),
        findsWidgets,
      );
      // Tapping it opens the Days page with the full banner.
      await tester.tap(find.byKey(const Key('today-top-bar')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('today-banner-confirmed')), findsOneWidget);
    });

    testWidgets('names each state', (tester) async {
      await setSize(tester, const Size(1280, 900));
      final cases = <String, AppController>{
        'Today: in transit': await load(
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
        'Today: two countries': await load(
          stays: [
            stay('ca', 'CA', '2026-11-01', '2026-11-17'),
            stay('eg', 'EG', '2026-11-17', '2026-11-25'),
          ],
        ),
        'Where am I today?': await load(),
      };
      for (final entry in cases.entries) {
        await tester.pumpWidget(NomadicApp(controller: entry.value));
        await tester.pump();
        expect(tester.widget<Text>(topTitle()).data, entry.key);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('names no country while loading', (tester) async {
      await setSize(tester, const Size(375, 1800));
      final controller = await load(
        stays: [stay('ca', 'CA', '2026-11-09', '2026-11-30')],
        connection: 'PH',
      );
      controller.restoring = true;
      await tester.pumpWidget(NomadicApp(controller: controller));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<Text>(topTitle()).data, 'Where I am today');
      expect(find.byKey(const Key('connection-offer')), findsNothing);
    });
  });

  group('connection offer', () {
    testWidgets('unknown day: offers the connection country and saves it', (
      tester,
    ) async {
      await setSize(tester, const Size(375, 1800));
      final controller = await load(connection: 'PH');
      await tester.pumpWidget(NomadicApp(controller: controller));
      await tester.pump();
      expect(
        find.text('🇵🇭 Your connection looks like it\'s in Philippines.'),
        findsOneWidget,
      );
      expect(controller.stays, isEmpty);
      await tester.tap(find.byKey(const Key('connection-offer-set')));
      await tester.pump();
      expect(controller.stays.single.countryCode, 'PH');
      expect(controller.stays.single.start, today);
      expect(controller.stays.single.end, today);
      expect(controller.today.status, TodayStatus.confirmed);
      expect(find.byKey(const Key('connection-offer')), findsNothing);
      expect(tester.widget<Text>(topTitle()).data, 'Today: Philippines');
      await tester.pump(const Duration(milliseconds: 750));
      await tester.tap(find.byKey(const Key('today-undo')));
      await tester.pump();
      expect(controller.stays, isEmpty);
    });

    testWidgets('hidden when the connection matches today', (tester) async {
      await setSize(tester, const Size(375, 1800));
      final controller = await load(
        stays: [stay('ca', 'CA', '2026-11-09', '2026-11-30')],
        connection: 'CA',
      );
      await tester.pumpWidget(NomadicApp(controller: controller));
      await tester.pump();
      expect(find.byKey(const Key('connection-offer')), findsNothing);
    });

    testWidgets('hidden when the connection is unknown', (tester) async {
      await setSize(tester, const Size(375, 1800));
      final controller = await load();
      await tester.pumpWidget(NomadicApp(controller: controller));
      await tester.pump();
      expect(find.byKey(const Key('connection-offer')), findsNothing);
    });

    testWidgets('hidden on a conflict day', (tester) async {
      await setSize(tester, const Size(375, 1800));
      final controller = await load(
        stays: [
          stay('ca', 'CA', '2026-11-01', '2026-11-17'),
          stay('eg', 'EG', '2026-11-17', '2026-11-25'),
        ],
        connection: 'PH',
      );
      await tester.pumpWidget(NomadicApp(controller: controller));
      await tester.pump();
      expect(find.byKey(const Key('connection-offer')), findsNothing);
    });

    testWidgets('"Not now" hides it without saving', (tester) async {
      await setSize(tester, const Size(375, 1800));
      final controller = await load(connection: 'PH');
      await tester.pumpWidget(NomadicApp(controller: controller));
      await tester.pump();
      await tester.tap(find.byKey(const Key('connection-offer-dismiss')));
      await tester.pump();
      expect(find.byKey(const Key('connection-offer')), findsNothing);
      expect(controller.stays, isEmpty);
    });

    testWidgets('from flights in another country: offered and overrides', (
      tester,
    ) async {
      await setSize(tester, const Size(375, 1800));
      final flights = [
        flight('in', 'AC5', 'PT', 'CA', '2026-11-09T10:00', '2026-11-09T14:00'),
        flight(
          'out',
          'AC9',
          'CA',
          'MX',
          '2026-11-25T10:00',
          '2026-11-25T16:00',
        ),
      ];
      final controller = await load(flights: flights, connection: 'US');
      await tester.pumpWidget(NomadicApp(controller: controller));
      await tester.pump();
      expect(
        find.text('🇺🇸 Your connection looks like United States, not Canada.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('connection-offer-set')));
      await tester.pump();
      expect(controller.today.countryCode, 'US');
      expect(controller.today.status, TodayStatus.confirmed);
      expect(controller.flights, flights);
    });

    testWidgets(
      'confirmed elsewhere: asks, splits that stay around today, undo restores',
      (tester) async {
        await setSize(tester, const Size(375, 1800));
        final ca = stay('ca', 'CA', '2026-11-09', '2026-11-30');
        final controller = await load(stays: [ca], connection: 'PH');
        await tester.pumpWidget(NomadicApp(controller: controller));
        await tester.pump();
        expect(
          find.text('🇵🇭 Your connection looks like Philippines, not Canada.'),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('connection-offer-set')));
        await tester.pumpAndSettle();
        // Asked first; nothing written yet.
        expect(find.byKey(const Key('today-replace-dialog')), findsOneWidget);
        expect(controller.stays, [ca]);
        await tester.tap(find.byKey(const Key('today-replace-confirm')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 750));

        final byCountry = <String, List<Stay>>{};
        for (final item in controller.stays) {
          byCountry.putIfAbsent(item.countryCode, () => []).add(item);
        }
        final canada = byCountry['CA']!
          ..sort((a, b) => a.start.compareTo(b.start));
        expect(canada, hasLength(2));
        expect(canada[0].start, LocalDate(2026, 11, 9));
        expect(canada[0].end, LocalDate(2026, 11, 16));
        expect(canada[1].start, LocalDate(2026, 11, 18));
        expect(canada[1].end, LocalDate(2026, 11, 30));
        expect(byCountry['PH']!.single.start, today);
        expect(controller.today.status, TodayStatus.confirmed);
        expect(controller.today.countryCode, 'PH');

        await tester.tap(find.byKey(const Key('today-undo')));
        await tester.pump();
        expect(controller.stays, hasLength(1));
        final back = controller.stays.single;
        expect(back.id, 'ca');
        expect(back.start, ca.start);
        expect(back.end, ca.end);
      },
    );

    testWidgets('cancelling the question changes nothing', (tester) async {
      await setSize(tester, const Size(375, 1800));
      final ca = stay('ca', 'CA', '2026-11-09', '2026-11-30');
      final controller = await load(stays: [ca], connection: 'PH');
      await tester.pumpWidget(NomadicApp(controller: controller));
      await tester.pump();
      await tester.tap(find.byKey(const Key('connection-offer-set')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(controller.stays, [ca]);
      expect(controller.today.countryCode, 'CA');
    });
  });

  group('taking today out of a stay elsewhere', () {
    test('a today-only stay is removed and undo puts it back', () async {
      final controller = await load(
        stays: [stay('ca', 'CA', '2026-11-17', '2026-11-17')],
      );
      final result = await controller.saveTodayStay('PH', replaceOthers: true);
      expect(result.failure, isNull);
      expect(controller.stays.map((s) => s.countryCode), ['PH']);
      await result.undo!();
      expect(controller.stays.map((s) => s.countryCode), ['CA']);
      expect(controller.today.countryCode, 'CA');
    });

    test('a stay starting today now starts tomorrow', () async {
      final controller = await load(
        stays: [stay('ca', 'CA', '2026-11-17', '2026-11-20')],
      );
      await controller.saveTodayStay('PH', replaceOthers: true);
      final ca = controller.stays.firstWhere((s) => s.countryCode == 'CA');
      expect(ca.start, LocalDate(2026, 11, 18));
      expect(ca.end, LocalDate(2026, 11, 20));
    });

    test('a stay ending today now ends yesterday', () async {
      final controller = await load(
        stays: [stay('ca', 'CA', '2026-11-10', '2026-11-17')],
      );
      await controller.saveTodayStay('PH', replaceOthers: true);
      final ca = controller.stays.firstWhere((s) => s.countryCode == 'CA');
      expect(ca.end, LocalDate(2026, 11, 16));
    });

    test('without replaceOthers nothing is written', () async {
      final original = stay('ca', 'CA', '2026-11-10', '2026-11-20');
      final controller = await load(stays: [original]);
      final result = await controller.saveTodayStay('PH');
      expect(result.needsConfirmation, isTrue);
      expect(result.staysElsewhere.single.id, 'ca');
      expect(controller.stays, [original]);
    });

    test('a non-counting stay elsewhere is left alone', () async {
      final booking = stay(
        'fr',
        'FR',
        '2026-11-10',
        '2026-11-20',
        evidence: 'booking_only',
      );
      final controller = await load(stays: [booking]);
      final result = await controller.saveTodayStay('PH');
      expect(result.needsConfirmation, isFalse);
      expect(controller.stays.first, booking);
      expect(controller.today.countryCode, 'PH');
    });
  });

  group('HttpConnectionCountryLookup', () {
    Future<String?> answer(http.Response response) =>
        HttpConnectionCountryLookup(
          origin: 'https://example.invalid',
          httpClient: MockClient((request) async {
            expect(request.url.toString(), 'https://example.invalid/api/where');
            expect(request.method, 'GET');
            return response;
          }),
        ).country();

    test('reads a known country', () async {
      expect(
        await answer(http.Response(jsonEncode({'country': 'ph'}), 200)),
        'PH',
      );
    });

    test('unknown, malformed, failed and unlisted answers are null', () async {
      expect(
        await answer(http.Response(jsonEncode({'country': null}), 200)),
        isNull,
      );
      expect(
        await answer(http.Response(jsonEncode({'country': 'ZZ'}), 200)),
        isNull,
      );
      expect(await answer(http.Response('not json', 200)), isNull);
      expect(await answer(http.Response('{}', 500)), isNull);
    });

    test('a network error is null', () async {
      final lookup = HttpConnectionCountryLookup(
        origin: 'https://example.invalid',
        httpClient: MockClient((_) async => throw http.ClientException('down')),
      );
      expect(await lookup.country(), isNull);
    });
  });
}
