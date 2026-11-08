import 'package:flutter/material.dart';

import '../engine/models.dart';
import '../state/app_controller.dart';

class RulesPage extends StatefulWidget {
  const RulesPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<RulesPage> createState() => _RulesPageState();
}

class _RulesPageState extends State<RulesPage> {
  late int wakeHour;
  late int wakeMinute;
  late bool includeInferred;
  late final TextEditingController marker;
  late List<EvidenceStatusDef> statuses;
  final _newId = TextEditingController();
  final _newLabel = TextEditingController();
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final rules = widget.controller.rules;
    wakeHour = rules.wakeHour;
    wakeMinute = rules.wakeMinute;
    includeInferred = rules.includeInferred;
    marker = TextEditingController(
      text: rules.personalDayMarker?.toString() ?? '',
    );
    statuses = widget.controller.statuses
        .map(
          (status) => EvidenceStatusDef(
            id: status.id,
            label: status.label,
            countsAsActual: status.countsAsActual,
          ),
        )
        .toList();
  }

  @override
  void dispose() {
    marker.dispose();
    _newId.dispose();
    _newLabel.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final rawMarker = marker.text.trim();
    int? personal;
    if (rawMarker.isNotEmpty) {
      personal = int.tryParse(rawMarker);
      if (personal == null || personal < 1 || personal > 366) {
        setState(
          () => _message =
              'A personal marker is a whole number from 1 to 366, or blank.',
        );
        return;
      }
    }
    final failure = await widget.controller.saveRules(
      nextRules: CountingRules(
        wakeHour: wakeHour,
        wakeMinute: wakeMinute,
        includeInferred: includeInferred,
        personalDayMarker: personal,
      ),
      nextStatuses: statuses,
    );
    if (!mounted) return;
    setState(() => _message = failure ?? 'Rules saved in this dataset.');
  }

  void _addStatus() {
    final id = _newId.text.trim();
    final label = _newLabel.text.trim();
    if (!statusIdPattern.hasMatch(id) || label.isEmpty) {
      setState(() {
        _message = 'New statuses need a lowercase id and a label.';
      });
      return;
    }
    setState(() {
      statuses = [
        ...statuses,
        EvidenceStatusDef(id: id, label: label, countsAsActual: false),
      ];
      _newId.clear();
      _newLabel.clear();
      _message = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bookingCounts = statuses.any(
      (status) => status.id == 'booking_only' && status.countsAsActual,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text(
          'Counting rules',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Wake time and evidence are yours to change. The list below stays fixed so empty days, overlaps, and future dates are not quietly rewritten.',
        ),
        const SizedBox(height: 12),
        for (final statement in lockedRuleStatements)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('• $statement'),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: wakeHour,
                decoration: const InputDecoration(labelText: 'Wake hour'),
                items: [
                  for (var hour = 0; hour < 24; hour++)
                    DropdownMenuItem(
                      value: hour,
                      child: Text(hour.toString().padLeft(2, '0')),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => wakeHour = value ?? wakeHour),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: wakeMinute,
                decoration: const InputDecoration(labelText: 'Wake minute'),
                items: [
                  for (final minute in [0, 15, 30, 45])
                    DropdownMenuItem(
                      value: minute,
                      child: Text(minute.toString().padLeft(2, '0')),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => wakeMinute = value ?? wakeMinute),
              ),
            ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: includeInferred,
          onChanged: (value) => setState(() => includeInferred = value),
          title: const Text('Count records that are still marked as inference'),
          subtitle: const Text(
            'Observed records are unchanged. An inference mark stays visible either way.',
          ),
        ),
        TextField(
          controller: marker,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Personal day marker',
            helperText: 'Optional. Highlights a country when its wake-up days reach this number. It is a reminder you chose. It is not a legal test.',
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Evidence statuses',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (bookingCounts)
          const Text(
            'Booking only is set to count. Uncorroborated bookings will enter the actual total.',
          ),
        for (var index = 0; index < statuses.length; index++)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: statuses[index].countsAsActual,
            title: Text('${statuses[index].label} (${statuses[index].id})'),
            subtitle: lockedStatusIds.contains(statuses[index].id)
                ? const Text('Built-in status')
                : TextButton(
                    onPressed: () => setState(() {
                      statuses = [...statuses]..removeAt(index);
                    }),
                    child: const Text('Remove'),
                  ),
            onChanged: (value) => setState(() {
              statuses[index] = statuses[index].copyWith(countsAsActual: value);
            }),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _newId,
                decoration: const InputDecoration(labelText: 'New status id'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _newLabel,
                decoration: const InputDecoration(labelText: 'Label'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: _addStatus, child: const Text('Add status')),
        const SizedBox(height: 16),
        FilledButton(onPressed: _save, child: const Text('Save rules')),
        if (_message != null) ...[const SizedBox(height: 12), Text(_message!)],
        const SizedBox(height: 24),
        Text(
          widget.controller.isConnected
              ? 'Connected to ${widget.controller.instanceOrigin}. Sign out from the header when you want this database closed.'
              : 'Rules in the example dataset stay in this tab.',
          style: const TextStyle(color: Color(0xFF5C564E)),
        ),
        if (widget.controller.isConnected)
          TextButton(
            onPressed: widget.controller.signOut,
            child: const Text('Sign out'),
          ),
      ],
    );
  }
}
