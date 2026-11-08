import 'package:flutter/material.dart';

import '../data/countries.dart';
import '../engine/flight_proposals.dart';
import '../engine/models.dart';
import '../state/app_controller.dart';
import 'flight_editor.dart';
import 'format.dart';

class FlightsPage extends StatelessWidget {
  const FlightsPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final flights = [...controller.flights]..sort(compareFlights);
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
          'A flight is evidence. Proposed days stay inferences until you accept them. Booking-only flights stay out of the actual total until you confirm presence.',
        ),
        const SizedBox(height: 12),
        if (flights.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No flights yet. Add one, or import a sheet.'),
            ),
          ),
        for (final flight in flights)
          _FlightCard(controller: controller, flight: flight),
      ],
    );
  }

  Future<void> _edit(BuildContext context, FlightRecord? flight) async {
    final edited = await showFlightEditor(
      context,
      existing: flight,
      statuses: controller.statuses,
    );
    if (edited == null || !context.mounted) return;
    final failure = await controller.saveFlight(edited);
    if (failure != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure)));
    }
  }
}

class _FlightCard extends StatefulWidget {
  const _FlightCard({required this.controller, required this.flight});

  final AppController controller;
  final FlightRecord flight;

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
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
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
