import 'package:flutter_test/flutter_test.dart';
import 'package:nomadic_residence/engine/local_date.dart';

void main() {
  test('leap days and year lengths follow the civil calendar', () {
    expect(LocalDate.isLeapYear(2024), isTrue);
    expect(LocalDate.isLeapYear(2000), isTrue);
    expect(LocalDate.isLeapYear(1900), isFalse);
    expect(LocalDate.isLeapYear(2026), isFalse);
    expect(LocalDate.lengthOfYear(2024), 366);
    expect(LocalDate.lengthOfYear(2026), 365);
    expect(LocalDate.parse('2024-02-29').iso, '2024-02-29');
    expect(() => LocalDate.parse('2025-02-29'), throwsFormatException);
    expect(() => LocalDate.parse('2026-02-31'), throwsFormatException);
    expect(() => LocalDate(2025, 2, 29), throwsArgumentError);
  });

  test('adding days crosses months, years, and leap day', () {
    expect(LocalDate.parse('2024-02-28').addDays(1).iso, '2024-02-29');
    expect(LocalDate.parse('2024-02-29').addDays(1).iso, '2024-03-01');
    expect(LocalDate.parse('2025-02-28').addDays(1).iso, '2025-03-01');
    expect(LocalDate.parse('1900-02-28').addDays(1).iso, '1900-03-01');
    expect(LocalDate.parse('2000-02-28').addDays(1).iso, '2000-02-29');
    expect(LocalDate.parse('2026-12-31').addDays(1).iso, '2027-01-01');
    expect(
      LocalDate.parse('2026-11-08')
              .differenceInDays(LocalDate.parse('2026-01-01')) +
          1,
      312,
    );
  });

  test('weekday uses the civil date and matches 1 January 1970', () {
    expect(LocalDate(1970, 1, 1).weekday, DateTime.thursday);
    expect(LocalDate(2024, 2, 29).weekday, DateTime.utc(2024, 2, 29).weekday);
    expect(LocalDate(2026, 1, 1).weekday, DateTime.utc(2026, 1, 1).weekday);
  });

  test('wall times reject impossible clocks and keep the written date', () {
    final time = WallTime.parse('2026-04-20T22:40');
    expect(time.date.iso, '2026-04-20');
    expect(time.hour, 22);
    expect(time.minute, 40);
    expect(() => WallTime.parse('2026-04-20T24:00'), throwsFormatException);
    expect(() => WallTime.parse('2026-04-20 22:40:00'), throwsFormatException);
  });
}
