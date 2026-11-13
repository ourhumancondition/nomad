import 'package:flutter/material.dart';

/// Screens after sign-in.
///
/// [primary] is the short menu. Everything else is reached from Records,
/// or from a button on the days list.
enum Section {
  days('/', 'Days', Icons.public),
  calendar('/calendar', 'Calendar', Icons.calendar_month),
  records('/records', 'Records', Icons.folder_outlined),
  missing('/missing', 'Missing days', Icons.event_busy),
  trips('/trips', 'Trips', Icons.flight_takeoff),
  summary('/summary', 'Year details', Icons.insights),
  stays('/stays', 'Stays', Icons.luggage),
  flights('/flights', 'Flights', Icons.flight),
  review('/review', 'Gaps', Icons.rule),
  planned('/planned', 'Planned', Icons.event_note),
  transfer('/transfer', 'Spreadsheet', Icons.table_chart),
  rules('/rules', 'Settings', Icons.tune);

  const Section(this.path, this.label, this.icon);

  final String path;
  final String label;
  final IconData icon;

  static const primary = <Section>[days, calendar, records];

  bool get isPrimary => primary.contains(this);

  /// Where the back control on this screen returns.
  Section? get backTo {
    if (isPrimary) return null;
    if (this == missing || this == trips) return days;
    return records;
  }

  static Section fromPath(String path) {
    final name = path.endsWith('/') && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;
    for (final section in Section.values) {
      if (section.path == name) return section;
    }
    return Section.days;
  }
}
