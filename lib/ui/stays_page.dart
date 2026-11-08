import 'package:flutter/material.dart';

import '../data/countries.dart';
import '../engine/models.dart';
import '../state/app_controller.dart';
import 'format.dart';
import 'stay_editor.dart';

class StaysPage extends StatelessWidget {
  const StaysPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final rows = controller.stays.where((stay) {
      return stay.start.year <= controller.year &&
          stay.end.year >= controller.year;
    }).toList()..sort((a, b) => b.start.compareTo(a.start));
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Stays in ${controller.year}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            FilledButton.icon(
              onPressed: () => _edit(context, null),
              icon: const Icon(Icons.add),
              label: const Text('Add stay'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'A wake-up stay is the country of that morning. A layover stays beside it. Saving a stay with an evidence status that does not count leaves the days unknown.',
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No stays overlap this year.'),
            ),
          )
        else
          for (final stay in rows)
            Card(
              child: ListTile(
                title: Text(
                  stay.role == PresenceRole.primary ||
                          stay.role == PresenceRole.layover
                      ? countryLabel(stay.countryCode)
                      : stay.role.label,
                ),
                subtitle: Text(
                  '${shortRange(stay.start, stay.end)} · ${stay.role.label} · ${stay.evidenceStatus} · ${stay.inference.label} · ${stay.phase.label}',
                ),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      tooltip: 'Edit',
                      onPressed: () => _edit(context, stay),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: 'Delete',
                      onPressed: () => _delete(context, stay),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  Future<void> _edit(BuildContext context, Stay? stay) async {
    final edited = await showStayEditor(
      context,
      existing: stay,
      statuses: controller.statuses,
    );
    if (edited == null || !context.mounted) return;
    final failure = await controller.saveStay(edited);
    if (failure != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure)));
    }
  }

  Future<void> _delete(BuildContext context, Stay stay) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this stay?'),
        content: Text(shortRange(stay.start, stay.end)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final failure = await controller.deleteStay(stay.id);
    if (failure != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure)));
    }
  }
}
