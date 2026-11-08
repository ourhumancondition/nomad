import 'package:flutter_test/flutter_test.dart';
import 'package:nomadic_residence/data/instance_endpoint.dart';
import 'package:nomadic_residence/demo/example_dataset.dart';
import 'package:nomadic_residence/engine/csv_codec.dart';
import 'package:nomadic_residence/engine/models.dart';

void main() {
  test('csv round-trips the example and labels it', () {
    final dataset = buildExampleDataset();
    final raw = CsvCodec.encode(
      stays: dataset.stays,
      flights: dataset.flights,
      exampleDataset: true,
    );
    expect(raw.startsWith(csvColumns.join(',')), isTrue);
    expect(raw.contains('EXAMPLE DATASET'), isTrue);
    final preview = CsvCodec.parse(raw);
    expect(preview.errors, isEmpty);
    expect(preview.exampleDataset, isTrue);
    expect(preview.stays, hasLength(dataset.stays.length));
    expect(preview.flights, hasLength(dataset.flights.length));
    expect(
      preview.stays.map((stay) => stay.externalId),
      containsAll(dataset.stays.map((stay) => stay.externalId)),
    );
    final leap = preview.stays.singleWhere(
      (stay) => stay.externalId == 'example-is',
    );
    expect(leap.start.iso, '2024-02-28');
    expect(leap.end.iso, '2024-03-02');
  });

  test('quoted commas and a bad date are reported without dropping the good row', () {
    final header = csvColumns.join(',');
    const good =
        'stay,sheet-1,PT,2026-01-01,2026-01-02,primary,confirmed,none,actual,Europe/Lisbon,"Lisbon, example",,,,,,,,,,';
    const bad =
        'stay,sheet-2,PT,2026-02-31,2026-03-01,primary,confirmed,none,actual,Europe/Lisbon,bad,,,,,,,,,,';
    final preview = CsvCodec.parse('$header\n$good\n$bad\n');
    expect(preview.exampleDataset, isFalse);
    expect(preview.stays, hasLength(1));
    expect(preview.stays.single.notes, 'Lisbon, example');
    expect(preview.errors, hasLength(1));
  });

  test('allowlisted PocketHost origins are the only remote targets', () {
    InstanceEndpoint parse(String raw, {bool allowLocal = false}) {
      return InstanceEndpoint.parse(raw, allowLocal: allowLocal);
    }

    expect(
      parse('https://nomad.pockethost.io').origin.toString(),
      'https://nomad.pockethost.io',
    );
    expect(
      parse('https://nomad.pockethost.io/').healthUri.toString(),
      'https://nomad.pockethost.io/api/health',
    );
    expect(parse('https://AB.pockethost.io').displayHost, 'ab.pockethost.io');
    expect(
      parse('http://127.0.0.1:18091', allowLocal: true).origin.toString(),
      'http://127.0.0.1:18091',
    );
    expect(parse('http://localhost:8090/', allowLocal: true).loopback, isTrue);

    final rejected = <String>[
      'nomad.pockethost.io',
      'http://nomad.pockethost.io',
      'https://nomad.pockethost.io/api',
      'https://nomad.pockethost.io?x=1',
      'https://user:pass@nomad.pockethost.io',
      'https://nomad.pockethost.io.evil.com',
      'https://evil.com',
      'https://pockethost.io',
      'https://a.b.pockethost.io',
      'https://-bad.pockethost.io',
      'https://169.254.169.254/',
      'http://169.254.169.254/',
      'http://10.0.0.1/',
      'https://127.0.0.1:8090',
      'http://127.0.0.1:8090',
      'file:///etc/passwd',
      'javascript:alert(1)',
    ];
    for (final raw in rejected) {
      expect(
        InstanceEndpoint.tryParse(raw, allowLocal: false),
        isNull,
        reason: raw,
      );
    }
  });

  test('default rules do not embed a day threshold', () {
    expect(CountingRules.standard.personalDayMarker, isNull);
    expect(lockedRuleStatements.any((line) => line.contains('183')), isFalse);
  });
}
