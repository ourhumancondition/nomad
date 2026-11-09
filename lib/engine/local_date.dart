/// A civil calendar date with no time and no time zone.
///
/// Travel days are stored as the local date the traveler already means.
/// This type does not convert instants, so a value of 1 January never
/// slides into 31 December because of UTC.
class LocalDate implements Comparable<LocalDate> {
  LocalDate(this.year, this.month, this.day) {
    if (year < 1 ||
        year > 9999 ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > daysInMonth(year, month)) {
      throw ArgumentError('Invalid civil date $year-$month-$day.');
    }
  }

  final int year;
  final int month;
  final int day;

  static final RegExp _iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  static bool isLeapYear(int year) =>
      year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);

  static int daysInMonth(int year, int month) {
    const lengths = <int>[0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    if (month == 2 && isLeapYear(year)) return 29;
    return lengths[month];
  }

  static int lengthOfYear(int year) => isLeapYear(year) ? 366 : 365;

  factory LocalDate.parse(String raw) {
    final match = _iso.firstMatch(raw.trim());
    if (match == null) {
      throw FormatException('Use YYYY-MM-DD.', raw);
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    if (day > daysInMonth(year, month)) {
      throw FormatException('That calendar date does not exist.', raw);
    }
    return LocalDate(year, month, day);
  }

  static LocalDate? tryParse(String raw) {
    try {
      return LocalDate.parse(raw);
    } on FormatException {
      return null;
    }
  }

  factory LocalDate.fromDateTime(DateTime value) =>
      LocalDate(value.year, value.month, value.day);

  static LocalDate todayDevice() => LocalDate.fromDateTime(DateTime.now());

  /// Days since the Unix epoch civil date, using Howard Hinnant's algorithm.
  static int daysFromCivil(int year, int month, int day) {
    var y = year;
    y -= month <= 2 ? 1 : 0;
    final era = (y >= 0 ? y : y - 399) ~/ 400;
    final yoe = y - era * 400;
    final doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) ~/ 5 + day - 1;
    final doe = yoe * 365 + yoe ~/ 4 - yoe ~/ 100 + doy;
    return era * 146097 + doe - 719468;
  }

  static LocalDate civilFromDays(int z) {
    var days = z + 719468;
    final era = (days >= 0 ? days : days - 146096) ~/ 146097;
    final doe = days - era * 146097;
    final yoe = (doe - doe ~/ 1460 + doe ~/ 36524 - doe ~/ 146096) ~/ 365;
    final y = yoe + era * 400;
    final doy = doe - (365 * yoe + yoe ~/ 4 - yoe ~/ 100);
    final mp = (5 * doy + 2) ~/ 153;
    final d = doy - (153 * mp + 2) ~/ 5 + 1;
    final m = mp + (mp < 10 ? 3 : -9);
    return LocalDate(y + (m <= 2 ? 1 : 0), m, d);
  }

  int get ordinal => daysFromCivil(year, month, day);

  /// Monday = 1 … Sunday = 7 for this civil date.
  ///
  /// Uses the UTC calendar fields of the same year, month, and day.
  /// It does not convert a zoned instant into a different date.
  int get weekday => DateTime.utc(year, month, day).weekday;

  LocalDate addDays(int days) => civilFromDays(ordinal + days);

  int differenceInDays(LocalDate earlier) => ordinal - earlier.ordinal;

  bool operator <(LocalDate other) => compareTo(other) < 0;
  bool operator <=(LocalDate other) => compareTo(other) <= 0;
  bool operator >(LocalDate other) => compareTo(other) > 0;
  bool operator >=(LocalDate other) => compareTo(other) >= 0;

  @override
  int compareTo(LocalDate other) => ordinal.compareTo(other.ordinal);

  String get iso =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is LocalDate &&
      year == other.year &&
      month == other.month &&
      day == other.day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => iso;
}

class DateRange {
  const DateRange(this.start, this.end);

  final LocalDate start;
  final LocalDate end;

  int get length => end.differenceInDays(start) + 1;

  bool contains(LocalDate date) => date >= start && date <= end;

  @override
  String toString() => '${start.iso}..${end.iso}';
}

/// Wall-clock time as written on a ticket, without a zone conversion.
class WallTime {
  const WallTime({required this.date, required this.hour, required this.minute})
    : assert(hour >= 0 && hour <= 23),
      assert(minute >= 0 && minute <= 59);

  final LocalDate date;
  final int hour;
  final int minute;

  static final RegExp _pattern = RegExp(
    r'^(\d{4}-\d{2}-\d{2})[T ](\d{2}):(\d{2})$',
  );

  factory WallTime.parse(String raw) {
    final match = _pattern.firstMatch(raw.trim());
    if (match == null) {
      throw FormatException('Use YYYY-MM-DDTHH:MM.', raw);
    }
    final hour = int.parse(match.group(2)!);
    final minute = int.parse(match.group(3)!);
    if (hour > 23 || minute > 59) {
      throw FormatException('That clock time does not exist.', raw);
    }
    return WallTime(
      date: LocalDate.parse(match.group(1)!),
      hour: hour,
      minute: minute,
    );
  }

  int get minutes => hour * 60 + minute;

  String get iso =>
      '${date.iso}T${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is WallTime &&
      date == other.date &&
      hour == other.hour &&
      minute == other.minute;

  @override
  int get hashCode => Object.hash(date, hour, minute);

  @override
  String toString() => iso;
}
