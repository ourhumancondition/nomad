import 'package:flutter/material.dart';

import '../data/gmail_client.dart';
import '../engine/gmail_access.dart';
import '../engine/gmail_receipts.dart';
import '../engine/models.dart';
import '../state/app_controller.dart';

class GmailPage extends StatefulWidget {
  const GmailPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<GmailPage> createState() => _GmailPageState();
}

class _GmailPageState extends State<GmailPage> {
  final Set<String> _saves = <String>{};
  final Set<String> _rejects = <String>{};
  final Map<String, LegCorrection> _corrections = <String, LegCorrection>{};
  bool _allowFictional = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    if (widget.controller.isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.controller.refreshGmail();
      });
    }
  }

  void _resetSelection() {
    _saves.clear();
    _rejects.clear();
    _corrections.clear();
    _allowFictional = false;
    _message = null;
  }

  Future<void> _fictional() async {
    widget.controller.previewFictionalReceipts();
    setState(_resetSelection);
  }

  Future<void> _scan({bool older = false}) async {
    final failure = await widget.controller.scanGmail(older: older);
    if (!mounted) return;
    setState(() {
      if (!older) _resetSelection();
      _message = failure;
    });
  }

  Future<void> _save() async {
    final failure = await widget.controller.saveGmailSelection(
      GmailDraft(
        saveExternalIds: _saves,
        rejectExternalIds: _rejects,
        corrections: _corrections,
        allowFictionalIntoConnected: _allowFictional,
      ),
    );
    if (!mounted) return;
    setState(() {
      _message = failure ?? widget.controller.statusMessage;
      if (failure == null) {
        _saves.clear();
        _rejects.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final plan = controller.gmailPlan;
    final link = controller.gmailConnection;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text(
          'Gmail receipts',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'A booking is a plan. It is not proof you were in a country. Flights saved from Gmail stay booking-only and need review. They are not accepted, and they do not add a wake-up day.',
        ),
        const SizedBox(height: 8),
        const Text(
          'Connect uses Google’s read-only Gmail permission, gmail.readonly. Nomadic Residence can read mail. It cannot send, delete, or change mail. Disconnect asks Google to revoke that access. Receipt text is not stored.',
        ),
        if (controller.gmailNotice != null) ...[
          const SizedBox(height: 12),
          Text(
            controller.gmailNotice!,
            key: const Key('gmail-notice'),
          ),
        ],
        const SizedBox(height: 16),
        _ConnectionCard(
          controller: controller,
          link: link,
          onConnect: () async {
            final origin = Uri.base.origin;
            final failure = await controller.connectGmail(origin);
            if (!mounted) return;
            setState(() => _message = failure);
          },
          onDisconnect: () async {
            final failure = await controller.disconnectGmail();
            if (!mounted) return;
            setState(() {
              _message = failure ?? 'Gmail access was removed.';
              if (failure == null) _resetSelection();
            });
          },
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (link.state == GmailLinkState.connected)
              FilledButton(
                key: const Key('gmail-scan'),
                onPressed: controller.busy ? null : () => _scan(),
                child: const Text('Scan receipts'),
              ),
            if (link.state == GmailLinkState.connected &&
                controller.gmailPageToken.isNotEmpty)
              OutlinedButton(
                key: const Key('gmail-scan-older'),
                onPressed: controller.busy ? null : () => _scan(older: true),
                child: const Text('Scan older receipts'),
              ),
            OutlinedButton(
              key: const Key('gmail-fictional'),
              onPressed: _fictional,
              child: const Text('Review fictional receipts'),
            ),
          ],
        ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(_message!, key: const Key('gmail-message')),
        ],
        if (plan != null) ...[
          const SizedBox(height: 20),
          Text(
            'Review before saving',
            key: const Key('gmail-review'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            plan.source == GmailPlanSource.fictional
                ? 'These receipts are fictional. They are not from your mailbox. Checked rows are still booking-only.'
                : 'Check each leg you want to keep. Nothing is written until you save.',
          ),
          if (plan.withheld > 0) ...[
            const SizedBox(height: 8),
            Text(
              '${plan.withheld} receipt${plan.withheld == 1 ? '' : 's'} were cut short and were not imported.',
            ),
          ],
          if (controller.gmailSkipped > 0 &&
              plan.source == GmailPlanSource.mailbox) ...[
            const SizedBox(height: 8),
            Text(
              '${controller.gmailSkipped} messages were skipped because they did not look like flight receipts.',
            ),
          ],
          for (final leg in plan.legs)
            _LegCard(
              leg: leg,
              correction: _corrections[leg.externalId],
              selected: _saves.contains(leg.externalId),
              onCorrection: (value) => setState(() {
                _corrections[leg.externalId] = value;
                if (!resolveLeg(leg, value).saveable) {
                  _saves.remove(leg.externalId);
                }
              }),
              onSelected: (value) => setState(() {
                if (value) {
                  _saves.add(leg.externalId);
                } else {
                  _saves.remove(leg.externalId);
                }
              }),
            ),
          for (final cancel in plan.cancellations)
            _CancelCard(
              cancel: cancel,
              selected: _rejects.contains(cancel.targetExternalId),
              onSelected: cancel.blocked
                  ? null
                  : (value) => setState(() {
                      if (value) {
                        _rejects.add(cancel.targetExternalId);
                      } else {
                        _rejects.remove(cancel.targetExternalId);
                      }
                    }),
            ),
          if (plan.source == GmailPlanSource.fictional &&
              controller.isConnected) ...[
            const SizedBox(height: 8),
            CheckboxListTile(
              key: const Key('gmail-allow-fictional'),
              contentPadding: EdgeInsets.zero,
              value: _allowFictional,
              onChanged: (value) =>
                  setState(() => _allowFictional = value ?? false),
              title: const Text(
                'Copy these fictional bookings into this database',
              ),
            ),
          ],
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('gmail-save'),
            onPressed: _saves.isEmpty && _rejects.isEmpty ? null : _save,
            child: const Text('Save checked bookings'),
          ),
        ],
      ],
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.controller,
    required this.link,
    required this.onConnect,
    required this.onDisconnect,
  });

  final AppController controller;
  final GmailConnectionStatus link;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final connected = link.state == GmailLinkState.connected;
    final revoked = link.state == GmailLinkState.revoked;
    final canConnect = controller.isConnected && !controller.busy;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              connected
                  ? 'Gmail is connected'
                  : revoked
                  ? 'Gmail access was revoked'
                  : 'Gmail is not connected',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            if (connected) ...[
              Text(
                link.googleEmail.isEmpty
                    ? 'Read-only access is on.'
                    : 'Read-only access for ${link.googleEmail}.',
              ),
              const SizedBox(height: 4),
              Text(
                link.scope.isEmpty
                    ? 'Scope: gmail.readonly.'
                    : 'Scope: ${link.scope}.',
              ),
            ] else if (revoked)
              const Text(
                'The previous grant was removed. Connect again to read receipts. No mailbox is read until you do.',
              )
            else if (!controller.isConnected)
              const Text(
                'Sign in to your database before connecting Gmail. Practice data stays in this tab.',
              )
            else
              const Text(
                'You will be sent to Google to allow read-only access, then brought back here. Nothing is imported on that step.',
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  key: const Key('gmail-connect'),
                  onPressed: canConnect ? onConnect : null,
                  child: Text(connected ? 'Connect again' : 'Connect Gmail'),
                ),
                if (connected || revoked)
                  OutlinedButton(
                    key: const Key('gmail-disconnect'),
                    onPressed: controller.isConnected && !controller.busy
                        ? onDisconnect
                        : null,
                    child: const Text('Disconnect'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LegCard extends StatelessWidget {
  const _LegCard({
    required this.leg,
    required this.correction,
    required this.selected,
    required this.onCorrection,
    required this.onSelected,
  });

  final GmailLegProposal leg;
  final LegCorrection? correction;
  final bool selected;
  final ValueChanged<LegCorrection> onCorrection;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    final resolved = resolveLeg(leg, correction);
    final labels = resolved.flags.map(receiptFlagLabel).toSet();
    final current = correction ?? const LegCorrection();
    return Card(
      key: Key('gmail-leg-${leg.externalId}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              leg.duplicate
                  ? '${leg.flightNumber} already imported'
                  : '${leg.flightNumber} · ${resolved.fromIata.isEmpty ? '?' : resolved.fromIata} → ${resolved.toIata.isEmpty ? '?' : resolved.toIata}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(_kindLabel(leg.kind)),
            if (leg.passenger.isNotEmpty) Text('Passenger: ${leg.passenger}'),
            if (leg.itineraryRef.isNotEmpty) Text('Reference: ${leg.itineraryRef}'),
            if (leg.depart != null)
              Text(
                '${leg.depart!.iso} ${resolved.departTimezone.isEmpty ? 'time zone missing' : resolved.departTimezone}'
                ' → ${leg.arrive?.iso ?? 'arrival missing'}'
                ' ${resolved.arriveTimezone}',
              ),
            Text(
              'Message ${leg.messageId} from ${leg.fromAddress} on ${leg.receivedAt}.',
            ),
            if (leg.supersedesExternalId.isNotEmpty)
              Text('Earlier version: ${leg.supersedesExternalId}.'),
            if (leg.duplicate)
              Text(
                leg.duplicateOf.isEmpty
                    ? 'A repeat import will not add this flight again.'
                    : 'Matches ${leg.duplicateOf}. A repeat import will not add it again.',
              ),
            for (final label in labels) ...[
              const SizedBox(height: 4),
              Text(label),
            ],
            if (!leg.duplicate && leg.departTimezone.isEmpty)
              _zonePicker(
                'Departure time zone',
                current.departTimezone,
                (value) => onCorrection(
                  LegCorrection(
                    fromIata: current.fromIata,
                    toIata: current.toIata,
                    fromCountry: current.fromCountry,
                    toCountry: current.toCountry,
                    departTimezone: value,
                    arriveTimezone: current.arriveTimezone,
                  ),
                ),
              ),
            if (!leg.duplicate && leg.arriveTimezone.isEmpty)
              _zonePicker(
                'Arrival time zone',
                current.arriveTimezone,
                (value) => onCorrection(
                  LegCorrection(
                    fromIata: current.fromIata,
                    toIata: current.toIata,
                    fromCountry: current.fromCountry,
                    toCountry: current.toCountry,
                    departTimezone: current.departTimezone,
                    arriveTimezone: value,
                  ),
                ),
              ),
            if (leg.flags.contains('ambiguous_from_airport'))
              _codeField(
                'From airport',
                current.fromIata,
                3,
                (value) => onCorrection(
                  LegCorrection(
                    fromIata: value,
                    toIata: current.toIata,
                    fromCountry: current.fromCountry,
                    toCountry: current.toCountry,
                    departTimezone: current.departTimezone,
                    arriveTimezone: current.arriveTimezone,
                  ),
                ),
              ),
            if (leg.flags.contains('ambiguous_to_airport'))
              _codeField(
                'To airport',
                current.toIata,
                3,
                (value) => onCorrection(
                  LegCorrection(
                    fromIata: current.fromIata,
                    toIata: value,
                    fromCountry: current.fromCountry,
                    toCountry: current.toCountry,
                    departTimezone: current.departTimezone,
                    arriveTimezone: current.arriveTimezone,
                  ),
                ),
              ),
            if (leg.duplicate)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Nothing to save for this row.'),
              )
            else if (!resolved.saveable &&
                leg.flags.contains('ambiguous_time'))
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'This leg has no single clock time. Add the flight by hand if you want it on the list.',
                ),
              )
            else
              CheckboxListTile(
                key: Key('save-${leg.externalId}'),
                contentPadding: EdgeInsets.zero,
                value: selected,
                onChanged: resolved.saveable
                    ? (value) => onSelected(value ?? false)
                    : null,
                title: const Text('Save this booking for review'),
                subtitle: const Text(
                  'Booking only. It does not confirm the flight was taken.',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CancelCard extends StatelessWidget {
  const _CancelCard({
    required this.cancel,
    required this.selected,
    required this.onSelected,
  });

  final GmailCancelProposal cancel;
  final bool selected;
  final ValueChanged<bool>? onSelected;

  @override
  Widget build(BuildContext context) {
    final labels = cancel.flags.map(receiptFlagLabel).toSet();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cancellation',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(cancel.reason),
            Text(
              'Message ${cancel.messageId} from ${cancel.fromAddress} on ${cancel.receivedAt}.',
            ),
            for (final label in labels) Text(label),
            if (onSelected != null)
              CheckboxListTile(
                key: Key('cancel-${cancel.targetExternalId}'),
                contentPadding: EdgeInsets.zero,
                value: selected,
                onChanged: (value) => onSelected!(value ?? false),
                title: const Text('Reject the earlier pending flight'),
                subtitle: const Text(
                  'This does not mark the flight as taken, and it does not change an accepted flight.',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _kindLabel(ReceiptKind kind) => switch (kind) {
  ReceiptKind.booking => 'Booking',
  ReceiptKind.amendment => 'Amendment',
  ReceiptKind.cancellation => 'Cancellation',
};

Widget _zonePicker(String label, String value, ValueChanged<String> onChanged) {
  final zones = [...commonTimezones]..sort();
  return Padding(
    padding: const EdgeInsets.only(top: 8),
    child: DropdownButtonFormField<String>(
      key: ValueKey('$label-$value'),
      initialValue: zones.contains(value) ? value : null,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final zone in zones)
          DropdownMenuItem(value: zone, child: Text(zone)),
      ],
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
    ),
  );
}

Widget _codeField(
  String label,
  String value,
  int max,
  ValueChanged<String> onChanged,
) {
  return Padding(
    padding: const EdgeInsets.only(top: 8),
    child: TextFormField(
      initialValue: value,
      textCapitalization: TextCapitalization.characters,
      maxLength: max,
      decoration: InputDecoration(labelText: label),
      onChanged: onChanged,
    ),
  );
}
