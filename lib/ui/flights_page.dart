import 'package:flutter/material.dart';

import '../data/countries.dart';
import '../engine/flight_archive.dart';
import '../engine/flight_proposals.dart';
import '../engine/models.dart';
import '../state/app_controller.dart';
import 'flight_editor.dart';
import 'format.dart';

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
            Expanded(
              child: Text(
                'Flight evidence',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            FilledButton.icon(
              onPressed: () => _edit(context, null),
              icon: const Icon(Icons.add),
              label: const Text('Add flight'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'A flight is evidence. The year summary counts wake-ups between a qualifying arrival and the next qualifying departure from that same country, and labels them from flights. Accepting one flight still proposes only the immediate connection. This preview can save an inferred stay; that stay does not add a second count.',
        ),
        const SizedBox(height: 8),
        const Text(
          'Accepted flights sit in the archive so this page stays on what still needs review. Archiving does not change a flight. The preview still uses every flight, including archived ones.',
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('preview-between-flights'),
          onPressed: () => _previewBetween(context),
          child: const Text('Preview days between flights'),
        ),
        const SizedBox(height: 16),
        if (controller.flights.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No flights yet. Add one, or import a sheet.'),
            ),
          )
        else ...[
          Text(
            'Still to review (${split.needsReview.length})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (split.needsReview.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Nothing is waiting for review.'),
              ),
            )
          else
            for (final flight in split.needsReview)
              _FlightCard(
                controller: controller,
                flight: flight,
                onEdit: () => _edit(context, flight),
              ),
          if (split.broughtBack.isNotEmpty) ...[
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
                onEdit: () => _edit(context, flight),
                onArchive: () => controller.rearchiveFlight(flight.id),
              ),
          ],
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
                      Icon(
                        _archiveOpen ? Icons.expand_less : Icons.expand_more,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Archived (${split.archived.length})',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Accepted flights. Un-archive shows one here again and leaves its review status accepted.',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_archiveOpen) ...[
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
                  onEdit: () => _edit(context, flight),
                  onUnarchive: () => controller.unarchiveFlight(flight.id),
                ),
            ],
          ],
        ],
      ],
    );
  }

  Future<void> _edit(BuildContext context, FlightRecord? flight) async {
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
  bool keepInference = false;
  bool presenceConfirmed = false;

  @override
  Widget build(BuildContext context) {
    final flight = widget.flight;
    final proposals = widget.controller.proposalsFor(flight);
    final booking = flight.evidenceStatus == 'booking_only';
    return Card(
      key: Key('flight-card-${flight.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${flight.flightNumber} · ${flight.fromIata} ${countryLabel(flight.fromCountry)} → ${flight.toIata} ${countryLabel(flight.toCountry)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              '${flight.depart.iso} ${flight.departTimezone} → ${flight.arrive.iso} ${flight.arriveTimezone}',
            ),
            Text(
              '${flight.evidenceStatus} · ${flight.inference.label} · ${flight.reviewState.label}',
            ),
            if (flight.notes.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(flight.notes),
            ],
            if (flight.reviewState == FlightReviewState.pending ||
                flight.reviewState == FlightReviewState.needsManual) ...[
              const SizedBox(height: 10),
              const Text(
                'Proposals',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              if (proposals.isEmpty)
                const Text('No automatic proposal.')
              else
                for (final proposal in proposals)
                  _ProposalLine(proposal: proposal),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: keepInference,
                onChanged: (value) =>
                    setState(() => keepInference = value ?? false),
                title: const Text('Keep the inference mark after accepting'),
                subtitle: const Text(
                  'The days stay out of the actual total until inferences are counted.',
                ),
              ),
              if (booking)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: presenceConfirmed,
                  onChanged: (value) =>
                      setState(() => presenceConfirmed = value ?? false),
                  title: const Text(
                    'I am recording presence, not only a booking',
                  ),
                ),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: () => _accept(context),
                    child: const Text('Accept proposals'),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      final failure = await widget.controller.rejectFlight(
                        flight,
                      );
                      if (failure != null && context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(failure)));
                      }
                    },
                    child: const Text('Reject'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
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
                TextButton(
                  onPressed: () async {
                    final failure = await widget.controller.deleteFlight(
                      flight.id,
                    );
                    if (failure != null && context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(failure)));
                    }
                  },
                  child: const Text('Delete flight'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _accept(BuildContext context) async {
    final failure = await widget.controller.acceptFlight(
      widget.flight,
      keepInference: keepInference,
      presenceConfirmedDespiteBooking: presenceConfirmed,
    );
    if (failure != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure)));
    }
  }
}

class _ProposalLine extends StatelessWidget {
  const _ProposalLine({required this.proposal});

  final FlightProposal proposal;

  @override
  Widget build(BuildContext context) {
    final stay = proposal.stay;
    final title = stay == null
        ? 'Manual review'
        : '${stay.role.label} ${stay.countryCode.isEmpty ? '' : countryLabel(stay.countryCode)} ${shortRange(stay.start, stay.end)}';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(proposal.reason),
        ],
      ),
    );
  }
}
