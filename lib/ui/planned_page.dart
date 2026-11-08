import 'package:flutter/material.dart';

import '../data/countries.dart';
import '../engine/models.dart';
import '../state/app_controller.dart';
import 'format.dart';

class PlannedPage extends StatelessWidget {
  const PlannedPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final tally = controller.tally;
    final planned = tally.planned.where((stay) {
      return stay.start.year <= controller.year &&
          stay.end.year >= controller.year;
    }).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text(
          'Planned and future',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Planned trips stay off the actual total. Dates after today also stay off that total, even when the phase says actual.',
        ),
        const SizedBox(height: 16),
        Text('Planned', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (planned.isEmpty)
          const Text('No planned stays overlap this year.')
        else
          for (final stay in planned) _StayLine(stay: stay),
        const SizedBox(height: 16),
        Text(
          'Actual phase, still ahead',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (tally.futureActual.isEmpty)
          const Text('No actual-phase stay reaches past today in this year.')
        else
          for (final stay in tally.futureActual)
            _StayLine(
              stay: stay,
              note: 'Days after today are excluded from the actual total.',
            ),
      ],
    );
  }
}

class _StayLine extends StatelessWidget {
  const _StayLine({required this.stay, this.note});

  final Stay stay;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final title = stay.countryCode.isEmpty
        ? stay.role.label
        : countryLabel(stay.countryCode);
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text(
          '${shortRange(stay.start, stay.end)} · ${stay.phase.label} · ${stay.evidenceStatus}${note == null ? '' : '\n$note'}',
        ),
      ),
    );
  }
}
