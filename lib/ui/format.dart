import '../engine/local_date.dart';

const _months = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String shortDate(LocalDate date) =>
    '${date.day} ${_months[date.month - 1]} ${date.year}';

String shortClock(WallTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

/// Clock as a person would say it. Dates stay on [shortDate].
String spokenClock(WallTime time) {
  final suffix = time.hour < 12 ? 'AM' : 'PM';
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute $suffix';
}

String shortRange(LocalDate start, LocalDate end) =>
    start == end ? shortDate(start) : '${shortDate(start)} – ${shortDate(end)}';

String monthName(int month) => const <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
][month - 1];
