import 'package:flutter/material.dart';

import '../engine/flight_archive.dart';
import '../engine/models.dart';
import '../engine/review_queue.dart';
import '../platform/open_link.dart';
import '../state/app_controller.dart';
import 'flight_editor.dart';
import 'review_copy.dart';
import 'stay_editor.dart';

class FlightsPage extends StatefulWidget {
  const FlightsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<FlightsPage> createState() => _FlightsPageState();
}

class _FlightsPageState extends State<FlightsPage> {
  final TextEditingController _archiveSearch = TextEditingController();
  bool _archiveOpen = false;

  @override
  void dispose() {
    _archiveSearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final queue = reviewQueue(
      flights: controller.flights,
      stays: controller.stays,
    );
    final years = reviewYears(queue);
    final split = splitFlights(
      controller.flights,
      unarchivedIds: controller.unarchivedFlightIds,
    );
    final archivedMatches = split.archived
        .where((flight) => flightMatchesQuery(flight, _archiveSearch.text))
        .toList();
    final query = _archiveSearch.text.trim();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Row(
          children: [
            Text('To check', style: Theme.of(context).textTheme.headlineSmall),
            if (queue.isNotEmpty) ...[
              const SizedBox(width: 10),
              _CountBadge(
                count: queue.length,
                badgeKey: const Key('review-count'),
              ),
            ],
            const Spacer(),
            FilledButton.icon(
              onPressed: () => _editFlight(context, null),
              icon: const Icon(Icons.add),
              label: const Text('Add flight'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Flights and stays that are not in the day total yet. Confirm adds the days. Not right leaves them out.',
        ),
        const SizedBox(height: 4),
        const Text(
          'Times are the local times written on the ticket. The list is every year, oldest first.',
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('preview-between-flights'),
          onPressed: () => _previewBetween(context),
          child: const Text('Preview days between flights'),
        ),
        const SizedBox(height: 16),
        Column(
          key: const Key('review-queue'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (queue.isEmpty && controller.flights.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No flights yet. Add one, or import a sheet.'),
                ),
              )
            else if (queue.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Nothing is waiting for a check.'),
                ),
              )
            else
              for (final year in years) ...[
                Text(
                  '$year',
                  key: Key('review-year-$year'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                for (final entry in queue.where((item) => item.year == year))
                  if (entry.flight != null)
                    _FlightCard(
                      controller: controller,
                      flight: entry.flight!,
                      onEdit: () => _editFlight(context, entry.flight),
                    )
                  else
                    _StayCard(
                      controller: controller,
                      stay: entry.stay!,
                      onEdit: () => _editStay(context, entry.stay!),
                    ),
              ],
          ],
        ),
        if (split.broughtBack.isNotEmpty)
          Column(
            key: const Key('brought-back'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Text(
                'Back on this list (${split.broughtBack.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              const Text(
                'These stay accepted. Archive returns one to the collapsed list without changing it.',
              ),
              const SizedBox(height: 8),
              for (final flight in split.broughtBack)
                _FlightCard(
                  controller: controller,
                  flight: flight,
                  onEdit: () => _editFlight(context, flight),
                  onArchive: () => controller.rearchiveFlight(flight.id),
                ),
            ],
          ),
        if (split.archived.isNotEmpty) ...[
          const SizedBox(height: 8),
          Card(
            child: InkWell(
              key: const Key('archive-toggle'),
              onTap: () => setState(() => _archiveOpen = !_archiveOpen),
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(_archiveOpen ? Icons.expand_less : Icons.expand_more),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Archived (${split.archived.length})',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Accepted flights. Un-archive shows one here again and does not change it.',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_archiveOpen)
            Column(
              key: const Key('archive-body'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                TextField(
                  key: const Key('archive-search'),
                  controller: _archiveSearch,
                  decoration: const InputDecoration(
                    labelText: 'Search archived flights',
                    hintText: 'Number, airport, country, or date',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                if (query.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Showing ${archivedMatches.length} of ${split.archived.length}.',
                  ),
                ],
                if (archivedMatches.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('No archived flights match that search.'),
                  ),
                for (final flight in archivedMatches)
                  _FlightCard(
                    controller: controller,
                    flight: flight,
                    onEdit: () => _editFlight(context, flight),
                    onUnarchive: () => controller.unarchiveFlight(flight.id),
                  ),
              ],
            ),
        ],
      ],
    );
  }

  Future<void> _editFlight(BuildContext context, FlightRecord? flight) async {
    final edited = await showFlightEditor(
      context,
      existing: flight,
      statuses: widget.controller.statuses,
    );
    if (edited == null || !context.mounted) return;
    final failure = await widget.controller.saveFlight(edited);
    if (failure != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure)));
    }
  }

  Future<void> _editStay(BuildContext context, Stay stay) async {
    final edited = await showStayEditor(
      context,
      existing: stay,
      statuses: widget.controller.statuses,
    );
    if (edited == null || !context.mounted) return;
    final failure = await widget.controller.saveStay(edited);
    if (failure != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure)));
    }
  }

  Future<void> _previewBetween(BuildContext context) async {
    final plan = widget.controller.betweenFlightPlan();
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('between-flights-dialog'),
        title: const Text('Days between flights'),
        content: SizedBox(
          width: 480,
          height: MediaQuery.sizeOf(context).height * 0.55,
          child: ListView(
            children: [
              const Text(
                'Saving writes inferred stays. An inferred stay is not what the wake-up total uses. Qualifying flights are already counted on the Summary. A booking-only flight that has not been accepted stays booking-only and does not form a bracket.',
              ),
              const SizedBox(height: 12),
              Text(
                '${plan.savable.length} stay${plan.savable.length == 1 ? '' : 's'} can be saved.',
              ),
              const SizedBox(height: 8),
              for (final row in plan.rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(row.summary),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: plan.savable.isEmpty
                ? null
                : () => Navigator.of(context).pop(true),
            child: const Text('Save inferred stays'),
          ),
        ],
      ),
    );
    if (save != true || !context.mounted) return;
    final failure = await widget.controller.saveBetweenFlightPlan();
    if (failure != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure)));
    }
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.badgeKey});

  final int count;
  final Key badgeKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: badgeKey,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF8C4A32),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _FlightCard extends StatefulWidget {
  const _FlightCard({
    required this.controller,
    required this.flight,
    required this.onEdit,
    this.onUnarchive,
    this.onArchive,
  });

  final AppController controller;
  final FlightRecord flight;
  final VoidCallback onEdit;
  final VoidCallback? onUnarchive;
  final VoidCallback? onArchive;

  @override
  State<_FlightCard> createState() => _FlightCardState();
}

class _FlightCardState extends State<_FlightCard> {
  bool keepOut = false;
  bool presenceConfirmed = false;
  bool more = false;
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    final flight = widget.flight;
    final waiting =
        flight.reviewState == FlightReviewState.pending ||
        flight.reviewState == FlightReviewState.needsManual;
    final brief = evidenceBrief(flight.notes);
    final effect = waiting
        ? flightConfirmSentence(
            flight: flight,
            stays: widget.controller.stays,
            flights: widget.controller.flights,
            rules: widget.controller.rules,
            statuses: widget.controller.statuses,
            today: widget.controller.clock(),
            keepOut: keepOut,
          )
        : flight.reviewState == FlightReviewState.rejected
        ? 'You marked this as not right. It stays out of the total.'
        : 'Already checked.';
    return Card(
      key: Key('flight-card-${flight.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              flightHeadline(flight),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(flight.flightNumber),
            const SizedBox(height: 8),
            Text(
              effect,
              key: Key('effect-${flight.id}'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            if (brief.text.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                brief.text,
                style: const TextStyle(color: Color(0xFF5C564E)),
              ),
            ],
            if (brief.sourceUrl != null)
              TextButton(
                key: Key('source-${flight.id}'),
                onPressed: () => openExternalLink(brief.sourceUrl!),
                child: const Text('View source'),
              ),
            if (waiting) ...[
              TextButton(
                key: Key('more-options-${flight.id}'),
                onPressed: () => setState(() => more = !more),
                child: Text(more ? 'Hide options' : 'More options'),
              ),
              if (more) ...[
                CheckboxListTile(
                  key: Key('keep-out-${flight.id}'),
                  contentPadding: EdgeInsets.zero,
                  value: keepOut,
                  onChanged: (value) =>
                      setState(() => keepOut = value ?? false),
                  title: const Text('Keep these days out of the total'),
                  subtitle: const Text(
                    'They stay a guess. They are counted only when Settings counts those guesses.',
                  ),
                ),
                if (flight.evidenceStatus == 'booking_only')
                  CheckboxListTile(
                    key: Key('presence-${flight.id}'),
                    contentPadding: EdgeInsets.zero,
                    value: presenceConfirmed,
                    onChanged: (value) =>
                        setState(() => presenceConfirmed = value ?? false),
                    title: const Text('I was there, not only booked'),
                    subtitle: const Text(
                      'Confirming records that you took this flight.',
                    ),
                  ),
              ],
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    key: Key('confirm-flight-${flight.id}'),
                    onPressed: busy ? null : () => _confirm(context),
                    child: const Text('Confirm'),
                  ),
                  OutlinedButton(
                    key: Key('dismiss-flight-${flight.id}'),
                    onPressed: busy ? null : () => _reject(context),
                    child: const Text('Not right'),
                  ),
                  OutlinedButton(
                    key: Key('edit-${flight.id}'),
                    onPressed: widget.onEdit,
                    child: const Text('Edit'),
                  ),
                ],
              ),
            ] else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (widget.onUnarchive != null)
                    OutlinedButton(
                      key: Key('unarchive-${flight.id}'),
                      onPressed: widget.onUnarchive,
                      child: const Text('Un-archive'),
                    ),
                  if (widget.onArchive != null)
                    OutlinedButton(
                      key: Key('archive-${flight.id}'),
                      onPressed: widget.onArchive,
                      child: const Text('Archive'),
                    ),
                  OutlinedButton(
                    key: Key('edit-${flight.id}'),
                    onPressed: widget.onEdit,
                    child: const Text('Edit'),
                  ),
                ],
              ),
            TextButton(
              onPressed: () async {
                final failure = await widget.controller.deleteFlight(flight.id);
                if (failure != null && context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(failure)));
                }
              },
              child: const Text('Delete flight'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirm(BuildContext context) async {
    if (busy) return;
    var presence = presenceConfirmed;
    final booking = widget.flight.evidenceStatus == 'booking_only';
    if (booking && !presence) {
      final agreed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          key: const Key('booking-confirm-dialog'),
          title: const Text('Record this trip?'),
          content: const Text(
            'This is a booking, not proof you were there. Confirming records that you took this flight and counts the days shown.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      if (agreed != true || !context.mounted) return;
      presence = true;
    }
    setState(() => busy = true);
    final failure = await widget.controller.acceptFlight(
      widget.flight,
      keepInference: keepOut,
      presenceConfirmedDespiteBooking: presence,
    );
    if (!mounted) return;
    setState(() => busy = false);
    if (failure != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure)));
    }
  }

  Future<void> _reject(BuildContext context) async {
    if (busy) return;
    setState(() => busy = true);
    final failure = await widget.controller.rejectFlight(widget.flight);
    if (!mounted) return;
    setState(() => busy = false);
    if (failure != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure)));
    }
  }
}

class _StayCard extends StatefulWidget {
  const _StayCard({
    required this.controller,
    required this.stay,
    required this.onEdit,
  });

  final AppController controller;
  final Stay stay;
  final VoidCallback onEdit;

  @override
  State<_StayCard> createState() => _StayCardState();
}

class _StayCardState extends State<_StayCard> {
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    final stay = widget.stay;
    final brief = evidenceBrief(stay.notes);
    final effect = stayConfirmSentence(
      stay: stay,
      stays: widget.controller.stays,
      flights: widget.controller.flights,
      rules: widget.controller.rules,
      statuses: widget.controller.statuses,
      today: widget.controller.clock(),
    );
    return Card(
      key: Key('stay-card-${stay.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              stayHeadline(stay),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              effect,
              key: Key('effect-${stay.id}'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            if (brief.text.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                brief.text,
                style: const TextStyle(color: Color(0xFF5C564E)),
              ),
            ],
            if (brief.sourceUrl != null)
              TextButton(
                key: Key('source-${stay.id}'),
                onPressed: () => openExternalLink(brief.sourceUrl!),
                child: const Text('View source'),
              ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  key: Key('confirm-stay-${stay.id}'),
                  onPressed: busy ? null : () => _confirm(context),
                  child: const Text('Confirm'),
                ),
                OutlinedButton(
                  key: Key('dismiss-stay-${stay.id}'),
                  onPressed: busy ? null : () => _dismiss(context),
                  child: const Text('Not right'),
                ),
                OutlinedButton(
                  key: Key('edit-stay-${stay.id}'),
                  onPressed: widget.onEdit,
                  child: const Text('Edit'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirm(BuildContext context) async {
    if (busy) return;
    setState(() => busy = true);
    final failure = await widget.controller.confirmStay(widget.stay);
    if (!mounted) return;
    setState(() => busy = false);
    if (failure != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure)));
    }
  }

  Future<void> _dismiss(BuildContext context) async {
    if (busy) return;
    setState(() => busy = true);
    final failure = await widget.controller.dismissStay(widget.stay);
    if (!mounted) return;
    setState(() => busy = false);
    if (failure != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure)));
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Left out of the total. It is still in Stays.'),
        ),
      );
    }
  }
}
