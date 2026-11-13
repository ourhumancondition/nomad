import 'package:flutter/material.dart';

import '../data/countries.dart';
import '../engine/local_date.dart';
import '../engine/models.dart';
import '../state/app_controller.dart';
import 'country_presence.dart';
import 'format.dart';

class MissingPage extends StatelessWidget {
  const MissingPage({
    super.key,
    required this.controller,
    required this.rolling,
  });

  final AppController controller;
  final bool rolling;

  @override
  Widget build(BuildContext context) {
    final presence = summarizePresence(
      stays: controller.stays,
      flights: controller.flights,
      rules: controller.rules,
      statuses: controller.statuses,
      today: controller.clock(),
      year: controller.year,
      rolling: rolling,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text(
          'Days we don\'t know',
          key: const Key('missing-title'),
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          presence.unknownDays == 0
              ? 'Every day in this period has a country.'
              : 'Add the country for each stretch below.',
        ),
        const SizedBox(height: 16),
        if (presence.unknownRanges.isEmpty)
          const Text('Nothing is missing.')
        else
          for (final range in presence.unknownRanges)
            Card(
              key: Key('missing-${range.start.iso}'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shortRange(range.start, range.end),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${range.length} ${range.length == 1 ? 'day' : 'days'}',
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      key: Key('add-where-${range.start.iso}'),
                      onPressed: () => _add(context, range),
                      child: const Text('Add where I was'),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  Future<void> _add(BuildContext context, DateRange range) async {
    final stay = await showWhereWereYou(
      context,
      start: range.start,
      end: range.end,
    );
    if (stay == null) return;
    final failure = await controller.saveStay(stay);
    if (failure != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure)));
    }
  }
}

Future<Stay?> showWhereWereYou(
  BuildContext context, {
  required LocalDate start,
  required LocalDate end,
}) {
  return showDialog<Stay>(
    context: context,
    builder: (context) => _WhereDialog(start: start, end: end),
  );
}

class _WhereDialog extends StatefulWidget {
  const _WhereDialog({required this.start, required this.end});

  final LocalDate start;
  final LocalDate end;

  @override
  State<_WhereDialog> createState() => _WhereDialogState();
}

class _WhereDialogState extends State<_WhereDialog> {
  String country = '';
  String? problem;

  void _save() {
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(country)) {
      setState(() => problem = 'Choose a country.');
      return;
    }
    final stay = Stay(
      id: '',
      countryCode: country,
      start: widget.start,
      end: widget.end,
      role: PresenceRole.primary,
      evidenceStatus: 'confirmed',
      inference: InferenceKind.none,
      phase: TripPhase.actual,
      timezone: 'Etc/UTC',
      notes: '',
      source: RecordSource.manual,
    );
    final failure = validateStay(stay);
    if (failure != null) {
      setState(() => problem = 'Choose a country.');
      return;
    }
    Navigator.of(context).pop(stay);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Where were you?'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(shortRange(widget.start, widget.end)),
            const SizedBox(height: 12),
            Autocomplete<String>(
              optionsBuilder: (value) {
                final query = value.text.trim().toLowerCase();
                if (query.isEmpty) return countryNames.keys.take(8);
                return countryNames.entries
                    .where(
                      (entry) =>
                          entry.key.toLowerCase().contains(query) ||
                          entry.value.toLowerCase().contains(query),
                    )
                    .map((entry) => entry.key)
                    .take(12);
              },
              displayStringForOption: countryName,
              onSelected: (code) => country = code,
              fieldViewBuilder: (context, controller, focus, onSubmit) {
                return TextField(
                  key: const Key('where-country'),
                  controller: controller,
                  focusNode: focus,
                  decoration: const InputDecoration(labelText: 'Country'),
                  onChanged: (value) {
                    final code = value.trim().toUpperCase();
                    if (RegExp(r'^[A-Z]{2}$').hasMatch(code) &&
                        countryNames.containsKey(code)) {
                      country = code;
                    } else {
                      country = '';
                    }
                  },
                );
              },
            ),
            if (problem != null) ...[
              const SizedBox(height: 12),
              Text(
                problem!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('where-save'),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
