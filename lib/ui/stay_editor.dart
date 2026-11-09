import 'package:flutter/material.dart';

import '../data/countries.dart';
import '../engine/local_date.dart';
import '../engine/models.dart';
import 'format.dart';

Future<Stay?> showStayEditor(
  BuildContext context, {
  Stay? existing,
  LocalDate? initialStart,
  LocalDate? initialEnd,
  required List<EvidenceStatusDef> statuses,
}) {
  return showDialog<Stay>(
    context: context,
    builder: (context) => _StayEditor(
      existing: existing,
      initialStart: initialStart,
      initialEnd: initialEnd,
      statuses: statuses,
    ),
  );
}

class _StayEditor extends StatefulWidget {
  const _StayEditor({
    required this.statuses,
    this.existing,
    this.initialStart,
    this.initialEnd,
  });

  final Stay? existing;
  final LocalDate? initialStart;
  final LocalDate? initialEnd;
  final List<EvidenceStatusDef> statuses;

  @override
  State<_StayEditor> createState() => _StayEditorState();
}

class _StayEditorState extends State<_StayEditor> {
  late PresenceRole role;
  late InferenceKind inference;
  late TripPhase phase;
  late String evidence;
  late String country;
  late String timezone;
  late LocalDate start;
  late LocalDate end;
  late final TextEditingController notes;
  late final TextEditingController externalId;
  String? problem;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final today = LocalDate.todayDevice();
    role = existing?.role ?? PresenceRole.primary;
    inference = existing?.inference ?? InferenceKind.none;
    phase = existing?.phase ?? TripPhase.actual;
    evidence = existing?.evidenceStatus ?? 'confirmed';
    country = existing?.countryCode ?? '';
    timezone = existing?.timezone ?? 'Etc/UTC';
    start = existing?.start ?? widget.initialStart ?? today;
    end = existing?.end ?? widget.initialEnd ?? start;
    notes = TextEditingController(text: existing?.notes ?? '');
    externalId = TextEditingController(text: existing?.externalId ?? '');
  }

  @override
  void dispose() {
    notes.dispose();
    externalId.dispose();
    super.dispose();
  }

  bool get needsCountry =>
      role == PresenceRole.primary || role == PresenceRole.layover;

  Future<void> _pick(bool isStart) async {
    final current = isStart ? start : end;
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(current.year, current.month, current.day),
      firstDate: DateTime(1970),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      final date = LocalDate(picked.year, picked.month, picked.day);
      if (isStart) {
        start = date;
        if (end < start) end = start;
      } else {
        end = date;
      }
    });
  }

  void _save() {
    final stay = Stay(
      id: widget.existing?.id ?? '',
      countryCode: needsCountry ? country : '',
      start: start,
      end: end,
      role: role,
      evidenceStatus: evidence,
      inference: inference,
      phase: phase,
      timezone: timezone,
      notes: notes.text.trim(),
      externalId: externalId.text.trim(),
      source: widget.existing?.source ?? RecordSource.manual,
    );
    final failure = validateStay(stay);
    if (failure != null) {
      setState(() => problem = failure);
      return;
    }
    Navigator.of(context).pop(stay);
  }

  @override
  Widget build(BuildContext context) {
    final zones = {...commonTimezones, timezone}.toList()..sort();
    final evidenceIds = widget.statuses.map((status) => status.id).toSet();
    final evidenceValue = evidenceIds.contains(evidence)
        ? evidence
        : widget.statuses.first.id;
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add a stay' : 'Edit stay'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<PresenceRole>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: [
                  for (final value in PresenceRole.values)
                    DropdownMenuItem(value: value, child: Text(value.label)),
                ],
                onChanged: (value) => setState(() => role = value ?? role),
              ),
              const SizedBox(height: 12),
              if (needsCountry)
                Autocomplete<String>(
                  initialValue: TextEditingValue(text: countryLabel(country)),
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
                  displayStringForOption: countryLabel,
                  onSelected: (code) => country = code,
                  fieldViewBuilder: (context, controller, focus, onSubmit) {
                    return TextField(
                      controller: controller,
                      focusNode: focus,
                      decoration: const InputDecoration(labelText: 'Country'),
                      onChanged: (value) {
                        final code = value.trim().toUpperCase();
                        if (RegExp(r'^[A-Z]{2}$').hasMatch(code)) {
                          country = code;
                        }
                      },
                    );
                  },
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pick(true),
                      child: Text('Start ${shortDate(start)}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pick(false),
                      child: Text('End ${shortDate(end)}'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: evidenceValue,
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
              DropdownButtonFormField<InferenceKind>(
                initialValue: inference,
                decoration: const InputDecoration(labelText: 'Inference'),
                items: [
                  for (final value in InferenceKind.values)
                    DropdownMenuItem(value: value, child: Text(value.label)),
                ],
                onChanged: (value) =>
                    setState(() => inference = value ?? inference),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<TripPhase>(
                initialValue: phase,
                decoration: const InputDecoration(labelText: 'Phase'),
                items: [
                  for (final value in TripPhase.values)
                    DropdownMenuItem(value: value, child: Text(value.label)),
                ],
                onChanged: (value) => setState(() => phase = value ?? phase),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: timezone,
                decoration: const InputDecoration(
                  labelText: 'Time zone of the dates',
                ),
                items: [
                  for (final zone in zones)
                    DropdownMenuItem(value: zone, child: Text(zone)),
                ],
                onChanged: (value) =>
                    setState(() => timezone = value ?? timezone),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: externalId,
                decoration: const InputDecoration(
                  labelText: 'External id',
                  helperText:
                      'Matches a row in your sheet when you import again.',
                ),
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
        FilledButton(onPressed: _save, child: const Text('Save stay')),
      ],
    );
  }
}
