import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nomadic_residence/data/pocketbase_gateway.dart';
import 'package:nomadic_residence/engine/csv_codec.dart';
import 'package:nomadic_residence/engine/local_date.dart';
import 'package:nomadic_residence/engine/models.dart';
import 'package:nomadic_residence/platform/local_store_memory.dart';
import 'package:nomadic_residence/state/app_controller.dart';

void main() {
  final binary = File(Platform.environment['PB_BIN'] ?? '/tmp/pb041/pocketbase');

  test(
    'a stopped import does not accept existing flights or add blank stays',
    () async {
      final home = await Directory.systemTemp.createTemp('nomad-import-');
      await Directory('${home.path}/pb_migrations').create();
      await File(
        'pb_migrations/1794136000_create_travel_collections.js',
      ).copy(
        '${home.path}/pb_migrations/1794136000_create_travel_collections.js',
      );
      const port = 18221;
      final origin = 'http://127.0.0.1:$port';
      final process = await Process.start(binary.path, [
        'serve',
        '--dir',
        '${home.path}/pb_data',
        '--migrationsDir',
        '${home.path}/pb_migrations',
        '--http',
        '127.0.0.1:$port',
      ]);
      process.stdout.listen((_) {});
      process.stderr.listen((_) {});
      addTearDown(() async {
        process.kill();
        await process.exitCode.timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            process.kill(ProcessSignal.sigkill);
            return -1;
          },
        );
        await home.delete(recursive: true);
      });
      await _waitHealthy(origin);

      final gateway = _FlakyGateway(store: MemoryLocalStore());
      final controller = AppController(
        clock: () => LocalDate(2026, 11, 8),
        gateway: gateway,
        allowLocalEndpoints: true,
      );
      expect(await controller.checkHealth(origin), isNull);
      expect(
        await controller.signUp(
          'importer@example.test',
          'local-disposable-user-password',
          'local-disposable-user-password',
        ),
        isNull,
      );

      for (var i = 1; i <= 29; i++) {
        final day = LocalDate(2026, 1, 1).addDays(i);
        expect(
          await controller.saveStay(
            Stay(
              id: '',
              countryCode: 'PT',
              start: day,
              end: day,
              role: PresenceRole.primary,
              evidenceStatus: 'confirmed',
              inference: InferenceKind.none,
              phase: TripPhase.actual,
              timezone: 'Europe/Lisbon',
              externalId: 'old-stay-$i',
              source: RecordSource.manual,
            ),
          ),
          isNull,
        );
      }
      for (var i = 1; i <= 16; i++) {
        final overnight = i <= 4;
        expect(
          await controller.saveFlight(
            _flight(
              id: '',
              externalId: 'old-flight-$i',
              from: 'PT',
              to: 'JP',
              depart: overnight ? '2026-06-0${i}T22:00' : '2026-07-${i.toString().padLeft(2, '0')}T10:00',
              arrive: overnight ? '2026-06-0${i + 1}T10:00' : '2026-07-${i.toString().padLeft(2, '0')}T12:00',
              review: FlightReviewState.needsManual,
            ),
          ),
          isNull,
        );
      }
      expect(controller.stays, hasLength(29));
      expect(controller.flights, hasLength(16));
      expect(
        controller.flights.every(
          (flight) => flight.reviewState == FlightReviewState.needsManual,
        ),
        isTrue,
      );

      final incomingStays = [
        for (var i = 1; i <= 36; i++)
          Stay(
            id: '',
            countryCode: 'JP',
            start: LocalDate(2025, 1, 1).addDays(i),
            end: LocalDate(2025, 1, 1).addDays(i),
            role: PresenceRole.primary,
            evidenceStatus: 'confirmed',
            inference: InferenceKind.none,
            phase: TripPhase.actual,
            timezone: 'Asia/Tokyo',
            externalId: 'new-stay-$i',
            source: RecordSource.csv,
          ),
      ];
      final incomingFlights = [
        for (var i = 1; i <= 26; i++)
          _flight(
            id: '',
            externalId: 'new-flight-$i',
            from: 'JP',
            to: 'SG',
            depart: '2025-03-${i.toString().padLeft(2, '0')}T09:00',
            arrive: '2025-03-${i.toString().padLeft(2, '0')}T15:00',
            evidence: 'booking_only',
            review: FlightReviewState.needsManual,
          ),
      ];
      final preview = CsvCodec.parse(
        CsvCodec.encode(
          stays: incomingStays,
          flights: incomingFlights,
          exampleDataset: false,
        ),
      );
      expect(preview.errors, isEmpty);
      expect(preview.stays, hasLength(36));
      expect(preview.flights, hasLength(26));

      gateway.failOnFlightCreate = gateway.flightCreates + 12;
      final stopped = await controller.importRows(
        preview,
        allowExampleIntoConnected: false,
      );
      expect(stopped, contains('Saved 36 of 36 stays and 11 of 26 flights'));
      expect(stopped, contains('Stopped on flight new-flight-12'));
      expect(stopped, contains('did not finish'));
      expect(stopped, isNot(contains('could not be reached')));
      expect(controller.stays, hasLength(65));
      expect(controller.flights, hasLength(27));
      expect(
        controller.stays.where((stay) => stay.externalId.isEmpty),
        isEmpty,
      );
      expect(
        controller.flights
            .where((flight) => flight.externalId.startsWith('old-flight-'))
            .map((flight) => flight.reviewState),
        everyElement(FlightReviewState.needsManual),
      );
      expect(
        controller.flights.where(
          (flight) => flight.reviewState == FlightReviewState.accepted,
        ),
        isEmpty,
      );

      gateway.failOnFlightCreate = null;
      expect(
        await controller.importRows(
          preview,
          allowExampleIntoConnected: false,
        ),
        isNull,
      );
      expect(controller.stays, hasLength(65));
      expect(controller.flights, hasLength(42));
      expect(
        controller.flights
            .where((flight) => flight.externalId.startsWith('old-flight-')),
        hasLength(16),
      );
      expect(
        controller.flights
            .where((flight) => flight.externalId.startsWith('old-flight-'))
            .every(
              (flight) => flight.reviewState == FlightReviewState.needsManual,
            ),
        isTrue,
      );
      expect(
        controller.flights.where(
          (flight) => flight.externalId.startsWith('new-flight-'),
        ),
        hasLength(26),
      );
    },
    skip: binary.existsSync()
        ? false
        : 'PocketBase 0.41.1 binary is not on this machine',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

class _FlakyGateway extends PocketBaseGateway {
  _FlakyGateway({required super.store});

  int? failOnFlightCreate;
  int flightCreates = 0;

  @override
  Future<FlightRecord> createFlight(FlightRecord flight) {
    flightCreates += 1;
    if (failOnFlightCreate != null && flightCreates == failOnFlightCreate) {
      throw const SocketException('connection timed out');
    }
    return super.createFlight(flight);
  }
}

FlightRecord _flight({
  required String id,
  required String externalId,
  required String from,
  required String to,
  required String depart,
  required String arrive,
  String evidence = 'confirmed',
  FlightReviewState review = FlightReviewState.needsManual,
}) {
  return FlightRecord(
    id: id,
    flightNumber: 'EX${externalId.hashCode.abs() % 10000}'.padLeft(4, 'E'),
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
    externalId: externalId,
  );
}

Future<void> _waitHealthy(String origin) async {
  final client = HttpClient();
  for (var attempt = 0; attempt < 40; attempt++) {
    try {
      final request = await client.getUrl(Uri.parse('$origin/api/health'));
      final response = await request.close();
      if (response.statusCode == 200) {
        await response.drain<void>();
        client.close(force: true);
        return;
      }
      await response.drain<void>();
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  client.close(force: true);
  throw StateError('disposable database did not become healthy');
}
