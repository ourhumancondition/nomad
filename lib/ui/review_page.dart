import 'package:flutter/material.dart';

import '../data/countries.dart';
import '../engine/local_date.dart';
import '../state/app_controller.dart';
import 'format.dart';
import 'stay_editor.dart';

class ReviewPage extends StatelessWidget {
  const ReviewPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final tally = controller.tally;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text(
          'Review ${controller.year}',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Unknown days are not filled by themselves. Preview days between flights on the Flights page when an arrival and a later departure are the same country. That preview is inferred and stays out of this total until you change the evidence.',
        ),
        const SizedBox(height: 16),
        Text('Unknown', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (tally.gapRanges.isEmpty)
          const Text('No unknown days in this window.')
        else
          for (final range in tally.gapRanges)
            _Row(
              title: shortRange(range.start, range.end),
              detail:
                  '${range.length} day${range.length == 1 ? '' : 's'} with no countable wake-up.',
              action: 'Add a stay',
              onPressed: () => _add(context, range.start, range.end),
            ),
        const SizedBox(height: 16),
        Text(
          'Unresolved overlaps',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (tally.overlapSpans.isEmpty)
          const Text('No date has two wake-up countries.')
        else
          for (final span in tally.overlapSpans)
            _Row(
              title: shortRange(span.range.start, span.range.end),
              detail: span.countries.map(countryLabel).join(' and '),
              action: 'Edit on Stays',
              onPressed: _noop,
            ),
        const SizedBox(height: 16),
        Text(
          'Outside the actual total',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (tally.excluded.isEmpty)
          const Text(
            'Nothing in this window is waiting on an evidence or inference decision.',
          )
        else
          for (final item in tally.excluded)
            _Row(
              title: item.stay.countryCode.isEmpty
                  ? item.stay.role.label
                  : countryLabel(item.stay.countryCode),
              detail:
                  '${shortRange(item.stay.start, item.stay.end)} · ${item.daysInWindow} day${item.daysInWindow == 1 ? '' : 's'} in the window. ${item.reason}',
              action: 'Edit',
              onPressed: () async {
                final edited = await showStayEditor(
                  context,
                  existing: item.stay,
                  statuses: controller.statuses,
                );
                if (edited == null) return;
                final failure = await controller.saveStay(edited);
                if (failure != null && context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(failure)));
                }
              },
            ),
      ],
    );
  }

  Future<void> _add(
    BuildContext context,
    LocalDate start,
    LocalDate end,
  ) async {
    final edited = await showStayEditor(
      context,
      initialStart: start,
      initialEnd: end,
      statuses: controller.statuses,
    );
    if (edited == null) return;
    final failure = await controller.saveStay(
      edited.copyWith(evidenceStatus: edited.evidenceStatus),
    );
    if (failure != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure)));
    }
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    required this.detail,
    required this.action,
    required this.onPressed,
  });

  final String title;
  final String detail;
  final String action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text(detail),
        trailing: onPressed == _noop
            ? null
            : TextButton(onPressed: onPressed, child: Text(action)),
      ),
    );
  }
}

void _noop() {}
