import 'package:flutter/material.dart';

import '../data/countries.dart';
import '../engine/day_engine.dart';
import '../engine/local_date.dart';
import '../state/app_controller.dart';
import 'format.dart';
import 'theme.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late int month;

  @override
  void initState() {
    super.initState();
    final today = widget.controller.clock();
    month = today.year == widget.controller.year ? today.month : 1;
  }

  @override
  void didUpdateWidget(CalendarPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller.year != widget.controller.year) {
      final today = widget.controller.clock();
      month = today.year == widget.controller.year ? today.month : 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tally = widget.controller.tally;
    final byDate = {for (final day in tally.days) day.date: day};
    final first = LocalDate(widget.controller.year, month, 1);
    final leading = first.weekday - 1;
    final days = LocalDate.daysInMonth(widget.controller.year, month);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Row(
          children: [
            IconButton(
              onPressed: month == 1 ? null : () => setState(() => month -= 1),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                '${monthName(month)} ${widget.controller.year}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              onPressed: month == 12 ? null : () => setState(() => month += 1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Row(
          children: [
            _Dow('Mon'),
            _Dow('Tue'),
            _Dow('Wed'),
            _Dow('Thu'),
            _Dow('Fri'),
            _Dow('Sat'),
            _Dow('Sun'),
          ],
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
          ),
          itemCount: leading + days,
          itemBuilder: (context, index) {
            if (index < leading) return const SizedBox.shrink();
            final date = LocalDate(
              widget.controller.year,
              month,
              index - leading + 1,
            );
            final assignment = byDate[date];
            return _DayCell(
              assignment: assignment,
              onTap: assignment == null
                  ? null
                  : () => _show(context, assignment),
            );
          },
        ),
        const SizedBox(height: 16),
        const Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            _Legend(color: accent, label: 'Country'),
            _Legend(color: transit, label: 'In the air'),
            _Legend(color: Color(0xFFE7E0D6), label: 'Unknown'),
            _Legend(color: Color(0xFFF3D6C8), label: 'Two countries'),
            _Legend(color: layoverAmber, label: 'Stopover'),
          ],
        ),
      ],
    );
  }

  void _show(BuildContext context, DayAssignment day) {
    final kind = switch (day.kind) {
      DayKind.primaryCountry => countryName(day.primaryCountry ?? ''),
      DayKind.inTransit => 'You were in the air when this day started.',
      DayKind.gap => 'We don\'t know the country for this day.',
      DayKind.overlap =>
        'Two countries: ${day.overlapCountries.map(countryName).join(', ')}. Neither was chosen.',
      DayKind.future => 'This day is still ahead, so it is not counted yet.',
    };
    final extras = <String>[
      if (day.layoverCountries.isNotEmpty)
        'Stopover, not an extra day: ${day.layoverCountries.map(countryName).join(', ')}',
      if (day.fromFlights && day.kind == DayKind.primaryCountry)
        'Counted from a trip you confirmed${day.flightLabel == null ? '' : ' (${day.flightLabel})'}.',
      if (day.fromFlights && day.kind == DayKind.inTransit)
        'You were in the air on a trip you confirmed.',
      if (day.overnight) 'A night on a plane. Not added to a country.',
      if (day.plannedCountries.isNotEmpty)
        'Planned: ${day.plannedCountries.map(countryName).join(', ')}',
      if (day.futureActualCountries.isNotEmpty)
        'Saved for later, not counted yet: ${day.futureActualCountries.map(countryName).join(', ')}',
    ];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              shortDate(day.date),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(kind),
            for (final extra in extras) ...[
              const SizedBox(height: 6),
              Text(extra),
            ],
          ],
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.assignment, required this.onTap});

  final DayAssignment? assignment;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final day = assignment;
    Color background = const Color(0xFFE7E0D6);
    Border? border;
    if (day != null) {
      background = switch (day.kind) {
        DayKind.primaryCountry => countryColor(
          day.primaryCountry ?? '',
        ).withValues(alpha: 0.85),
        DayKind.inTransit => transit,
        DayKind.gap => const Color(0xFFE7E0D6),
        DayKind.overlap => const Color(0xFFF3D6C8),
        DayKind.future => card,
      };
      if (day.kind == DayKind.future &&
          (day.plannedCountries.isNotEmpty ||
              day.futureActualCountries.isNotEmpty)) {
        border = Border.all(color: const Color(0xFF8A734A), width: 1.4);
      }
    }
    final foreground =
        day?.kind == DayKind.primaryCountry || day?.kind == DayKind.inTransit
        ? Colors.white
        : ink;
    return Material(
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: border?.top ?? const BorderSide(color: line),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(6),
              child: Text(
                '${day?.date.day ?? ''}',
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (day != null && day.layoverCountries.isNotEmpty)
              const Positioned(
                right: 6,
                bottom: 6,
                child: Icon(Icons.circle, size: 8, color: layoverAmber),
              ),
            if (day != null && day.overnight)
              Positioned(
                left: 6,
                bottom: 4,
                child: Icon(
                  Icons.flight,
                  size: 12,
                  color: foreground.withValues(alpha: 0.9),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Dow extends StatelessWidget {
  const _Dow(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, color: Color(0xFF5C564E)),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}
