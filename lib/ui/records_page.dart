import 'package:flutter/material.dart';

import 'section.dart';

class RecordsPage extends StatelessWidget {
  const RecordsPage({super.key, required this.onOpen, this.toCheck = 0});

  final ValueChanged<Section> onOpen;
  final int toCheck;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        Text(
          'Records',
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'The day list is enough for most visits. These are the underlying records and tools.',
        ),
        const SizedBox(height: 16),
        _Link(
          key: const Key('open-stays'),
          title: 'Stays',
          detail: 'The days you entered by hand.',
          onTap: () => onOpen(Section.stays),
        ),
        _Link(
          key: const Key('open-flights'),
          title: 'To check',
          detail: toCheck == 0
              ? 'Flights and stays that still need a decision.'
              : '$toCheck flights and stays still need a decision.',
          badge: toCheck == 0 ? null : toCheck,
          onTap: () => onOpen(Section.flights),
        ),
        _Link(
          key: const Key('open-planned'),
          title: 'Planned trips',
          detail: 'Trips that have not happened yet.',
          onTap: () => onOpen(Section.planned),
        ),
        _Link(
          key: const Key('open-gmail'),
          title: 'Gmail receipts',
          detail: 'Read flight receipts, then review them before saving.',
          onTap: () => onOpen(Section.gmail),
        ),
        _Link(
          key: const Key('open-sheet'),
          title: 'Spreadsheet',
          detail: 'Import or export a file.',
          onTap: () => onOpen(Section.transfer),
        ),
        _Link(
          key: const Key('open-summary'),
          title: 'Year details',
          detail: 'The full breakdown for the year in the header.',
          onTap: () => onOpen(Section.summary),
        ),
        _Link(
          key: const Key('open-review'),
          title: 'Gaps and overlaps',
          detail: 'Dates that still need a decision.',
          onTap: () => onOpen(Section.review),
        ),
        _Link(
          key: const Key('open-rules'),
          title: 'Settings',
          detail: 'What time of day decides the country.',
          onTap: () => onOpen(Section.rules),
        ),
      ],
    );
  }
}

class _Link extends StatelessWidget {
  const _Link({
    super.key,
    required this.title,
    required this.detail,
    required this.onTap,
    this.badge,
  });

  final String title;
  final String detail;
  final VoidCallback onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        title: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(detail),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (badge != null)
              Container(
                key: const Key('records-to-check'),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF8C4A32),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '$badge',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
