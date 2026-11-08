import 'package:flutter/material.dart';

import '../data/countries.dart';
import '../engine/local_date.dart';
import '../engine/models.dart';
import 'format.dart';

Future<FlightRecord?> showFlightEditor(
  BuildContext context, {
  FlightRecord? existing,
  required List<EvidenceStatusDef> statuses,
}) {
  return showDialog<FlightRecord>(
    context: context,
    builder: (context) => _FlightEditor(existing: existing, statuses: statuses),
  );
}

class _FlightEditor extends StatefulWidget {
  const _FlightEditor({required this.statuses, this.existing});

  final FlightRecord? existing;
  final List<EvidenceStatusDef> statuses;

  @override
  State<_FlightEditor> createState() => _FlightEditorState();
}

class _FlightEditorState extends State<_FlightEditor> {
  late final TextEditingController number;
  late final TextEditingController fromIata;
  late final TextEditingController toIata;
  late final TextEditingController notes;
  late final TextEditingController externalId;
  late String fromCountry;
  late String toCountry;
  late String departZone;
  late String arriveZone;
  late String evidence;
  late InferenceKind inference;
  late FlightReviewState review;
  late LocalDate departDate;
  late LocalDate arriveDate;
  late final TextEditingController departClock;
  late final TextEditingController arriveClock;
  String? problem;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final today = LocalDate.todayDevice();
    number = TextEditingController(text: existing?.flightNumber ?? '');
    fromIata = TextEditingController(text: existing?.fromIata ?? '');
    toIata = TextEditingController(text: existing?.toIata ?? '');
    notes = TextEditingController(text: existing?.notes ?? '');
    externalId = TextEditingController(text: existing?.externalId ?? '');
    fromCountry = existing?.fromCountry ?? '';
    toCountry = existing?.toCountry ?? '';
    departZone = existing?.departTimezone ?? 'Etc/UTC';
    arriveZone = existing?.arriveTimezone ?? 'Etc/UTC';
    evidence = existing?.evidenceStatus ?? 'booking_only';
    inference = existing?.inference ?? InferenceKind.none;
    review = existing?.reviewState ?? FlightReviewState.pending;
    departDate = existing?.depart.date ?? today;
    arriveDate = existing?.arrive.date ?? today;
    departClock = TextEditingController(
      text: existing == null
          ? '09:00'
          : '${existing.depart.hour.toString().padLeft(2, '0')}:${existing.depart.minute.toString().padLeft(2, '0')}',
    );
    arriveClock = TextEditingController(
      text: existing == null
          ? '12:00'
          : '${existing.arrive.hour.toString().padLeft(2, '0')}:${existing.arrive.minute.toString().padLeft(2, '0')}',
    );
  }

  @override
  void dispose() {
    number.dispose();
    fromIata.dispose();
    toIata.dispose();
    notes.dispose();
    externalId.dispose();
    departClock.dispose();
    arriveClock.dispose();
    super.dispose();
  }

  Future<void> _pick(bool departure) async {
    final current = departure ? departDate : arriveDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(current.year, current.month, current.day),
      firstDate: DateTime(1970),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      final date = LocalDate(picked.year, picked.month, picked.day);
      if (departure) {
        departDate = date;
      } else {
        arriveDate = date;
      }
    });
  }

  WallTime? _clock(LocalDate date, String raw) {
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(raw.trim());
    if (match == null) return null;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) return null;
    return WallTime(date: date, hour: hour, minute: minute);
  }

  void _save() {
    final depart = _clock(departDate, departClock.text);
    final arrive = _clock(arriveDate, arriveClock.text);
    if (depart == null || arrive == null) {
      setState(() => problem = 'Clock times use HH:MM.');
      return;
    }
    final flight = FlightRecord(
      id: widget.existing?.id ?? '',
      flightNumber: number.text.trim().toUpperCase(),
      fromIata: fromIata.text.trim().toUpperCase(),
      toIata: toIata.text.trim().toUpperCase(),
      fromCountry: fromCountry,
      toCountry: toCountry,
      depart: depart,
      arrive: arrive,
      departTimezone: departZone,
      arriveTimezone: arriveZone,
      evidenceStatus: evidence,
      inference: inference,
      reviewState: review,
      notes: notes.text.trim(),
      externalId: externalId.text.trim(),
    );
    final failure = validateFlight(flight);
    if (failure != null) {
      setState(() => problem = failure);
      return;
    }
    Navigator.of(context).pop(flight);
  }

  @override
  Widget build(BuildContext context) {
    final zones = {...commonTimezones, departZone, arriveZone}.toList()..sort();
    return AlertDialog(
      title: Text(
        widget.existing == null ? 'Add flight evidence' : 'Edit flight',
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: number,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Flight number'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _iata(fromIata, 'From airport')),
                  const SizedBox(width: 8),
                  Expanded(child: _iata(toIata, 'To airport')),
                ],
              ),
              const SizedBox(height: 12),
              _countryPicker(
                'From country',
                fromCountry,
                (value) => fromCountry = value,
              ),
              const SizedBox(height: 12),
              _countryPicker(
                'To country',
                toCountry,
                (value) => toCountry = value,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pick(true),
                      child: Text(shortDate(departDate)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: departClock,
                      decoration: const InputDecoration(labelText: 'Depart'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pick(false),
                      child: Text(shortDate(arriveDate)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: arriveClock,
                      decoration: const InputDecoration(labelText: 'Arrive'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _zone('Departure time zone', departZone, zones, (value) {
                setState(() => departZone = value);
              }),
              const SizedBox(height: 12),
              _zone('Arrival time zone', arriveZone, zones, (value) {
                setState(() => arriveZone = value);
              }),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue:
                    widget.statuses.any((status) => status.id == evidence)
                    ? evidence
                    : widget.statuses.first.id,
                decoration: const InputDecoration(labelText: 'Evidence status'),
                items: [
                  for (final status in widget.statuses)
                    DropdownMenuItem(
                      value: status.id,
                      child: Text(status.label),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => evidence = value ?? evidence),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<FlightReviewState>(
                initialValue: review,
                decoration: const InputDecoration(labelText: 'Review'),
                items: [
                  for (final value in FlightReviewState.values)
                    DropdownMenuItem(value: value, child: Text(value.label)),
                ],
                onChanged: (value) => setState(() => review = value ?? review),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: externalId,
                decoration: const InputDecoration(labelText: 'External id'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notes,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Notes'),
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
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save flight')),
      ],
    );
  }

  Widget _iata(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      textCapitalization: TextCapitalization.characters,
      decoration: InputDecoration(labelText: label),
    );
  }

  Widget _countryPicker(
    String label,
    String current,
    ValueChanged<String> onSelected,
  ) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(
        text: current.isEmpty ? '' : countryLabel(current),
      ),
      optionsBuilder: (value) {
        final query = value.text.trim().toLowerCase();
        return countryNames.entries
            .where(
              (entry) =>
                  query.isEmpty ||
                  entry.key.toLowerCase().contains(query) ||
                  entry.value.toLowerCase().contains(query),
            )
            .map((entry) => entry.key)
            .take(12);
      },
      displayStringForOption: countryLabel,
      onSelected: onSelected,
      fieldViewBuilder: (context, controller, focus, onSubmit) {
        return TextField(
          controller: controller,
          focusNode: focus,
          decoration: InputDecoration(labelText: label),
        );
      },
    );
  }

  Widget _zone(
    String label,
    String current,
    List<String> zones,
    ValueChanged<String> onChanged,
  ) {
    return DropdownButtonFormField<String>(
      initialValue: current,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final zone in zones)
          DropdownMenuItem(value: zone, child: Text(zone)),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}
