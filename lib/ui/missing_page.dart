import 'package:flutter/material.dart';

import '../data/countries.dart';
import '../engine/local_date.dart';
import '../engine/models.dart';
import '../state/app_controller.dart';
import 'country_presence.dart';
import 'format.dart';
import 'gap_facts.dart';

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
          for (final tile in describeUnknownTiles(
            ranges: presence.unknownRanges,
            stays: controller.stays,
            flights: controller.flights,
            statuses: controller.statuses,
          ))
            _GapTile(controller: controller, tile: tile),
      ],
    );
  }
}

class _GapTile extends StatelessWidget {
  const _GapTile({required this.controller, required this.tile});

  final AppController controller;
  final UnknownTile tile;

  @override
  Widget build(BuildContext context) {
    final range = tile.range;
    return Card(
      key: Key('missing-${range.start.iso}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              shortRange(range.start, range.end),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text('${range.length} ${range.length == 1 ? 'day' : 'days'}'),
            if (tile.hint != null) ...[
              const SizedBox(height: 10),
              Text(
                tile.hint!,
                key: Key('gap-hint-${range.start.iso}'),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ],
            for (final fact in tile.facts) ...[
              const SizedBox(height: 10),
              _FactBlock(
                fact: fact,
                id: '${fact.heading}-${range.start.iso}-${fact.countryCode}',
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final suggestion in tile.suggestions)
                  OutlinedButton(
                    key: Key(
                      'suggest-${suggestion.countryCode}-${range.start.iso}',
                    ),
                    onPressed: () => _add(
                      context,
                      controller,
                      range,
                      country: suggestion.countryCode,
                    ),
                    child: Text(suggestion.label),
                  ),
                FilledButton(
                  key: Key('add-where-${range.start.iso}'),
                  onPressed: () => _add(context, controller, range),
                  child: const Text('Add where I was'),
                ),
                for (final flight in _flightsToConfirm(tile))
                  TextButton(
                    key: Key('confirm-flight-${flight.id}'),
                    onPressed: () => _confirm(context, controller, flight),
                    child: Text('Confirm ${flight.flightNumber}'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FactBlock extends StatelessWidget {
  const _FactBlock({required this.fact, required this.id});

  final GapFact fact;
  final String id;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: Key('gap-fact-$id'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(fact.heading, style: const TextStyle(color: Color(0xFF5C564E))),
        const SizedBox(height: 2),
        Text(fact.detail),
        if (fact.note != null) ...[
          const SizedBox(height: 2),
          Text(
            fact.note!,
            key: Key('gap-note-$id'),
            style: const TextStyle(color: Color(0xFF5C564E)),
          ),
        ],
      ],
    );
  }
}

List<FlightRecord> _flightsToConfirm(UnknownTile tile) {
  final flights = <FlightRecord>[];
  final seen = <String>{};
  for (final fact in tile.facts) {
    final flight = fact.flight;
    if (flight == null || !fact.canConfirm) continue;
    if (seen.add(flight.id)) flights.add(flight);
  }
  return flights;
}

Future<void> _add(
  BuildContext context,
  AppController controller,
  DateRange range, {
  String? country,
}) async {
  final stay = await showWhereWereYou(
    context,
    start: range.start,
    end: range.end,
    initialCountry: country,
  );
  if (stay == null) return;
  final failure = await controller.saveStay(stay);
  if (failure != null && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(failure)));
  }
}

Future<void> _confirm(
  BuildContext context,
  AppController controller,
  FlightRecord flight,
) async {
  final failure = await controller.saveFlight(
    flight.copyWith(reviewState: FlightReviewState.accepted),
  );
  if (failure != null && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(failure)));
  }
}

Future<Stay?> showWhereWereYou(
  BuildContext context, {
  required LocalDate start,
  required LocalDate end,
  String? initialCountry,
}) {
  return showDialog<Stay>(
    context: context,
    builder: (context) =>
        _WhereDialog(start: start, end: end, initialCountry: initialCountry),
  );
}

class _WhereDialog extends StatefulWidget {
  const _WhereDialog({
    required this.start,
    required this.end,
    this.initialCountry,
  });

  final LocalDate start;
  final LocalDate end;
  final String? initialCountry;

  @override
  State<_WhereDialog> createState() => _WhereDialogState();
}

class _WhereDialogState extends State<_WhereDialog> {
  late String country;
  String? problem;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialCountry ?? '';
    country = RegExp(r'^[A-Z]{2}$').hasMatch(initial) ? initial : '';
  }

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
              initialValue: TextEditingValue(
                text: country.isEmpty ? '' : countryName(country),
              ),
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
                    final trimmed = value.trim();
                    if (country.isNotEmpty &&
                        trimmed.toLowerCase() ==
                            countryName(country).toLowerCase()) {
                      return;
                    }
                    final code = trimmed.toUpperCase();
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
