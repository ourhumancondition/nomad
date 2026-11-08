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
