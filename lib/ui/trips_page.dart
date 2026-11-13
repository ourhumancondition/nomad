import 'package:flutter/material.dart';

import '../data/countries.dart';
import '../engine/models.dart';
import '../state/app_controller.dart';
import 'country_presence.dart';
import 'format.dart';

class TripsPage extends StatelessWidget {
  const TripsPage({super.key, required this.controller, required this.rolling});

  final AppController controller;
  final bool rolling;

  @override
  Widget build(BuildContext context) {
    final trips = tripsToConfirm(
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
          'Confirm trips',
          key: const Key('trips-title'),
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          trips.isEmpty
              ? 'No trips are waiting. The country list already includes the days we can count.'
              : 'Yes adds the days from that trip. No leaves the trip out.',
        ),
        const SizedBox(height: 16),
        for (final flight in trips)
          _TripCard(controller: controller, flight: flight),
      ],
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.controller, required this.flight});

  final AppController controller;
  final FlightRecord flight;

  @override
  Widget build(BuildContext context) {
    final from = countryName(flight.fromCountry);
    final to = countryName(flight.toCountry);
    final fromFlag = countryFlag(flight.fromCountry);
    final toFlag = countryFlag(flight.toCountry);
    return Card(
      key: Key('trip-${flight.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${fromFlag.isEmpty ? '' : '$fromFlag '}$from  →  ${toFlag.isEmpty ? '' : '$toFlag '}$to',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text('${shortDate(flight.depart.date)} · ${flight.flightNumber}'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  key: Key('trip-yes-${flight.id}'),
                  onPressed: () => _answer(context, accept: true),
                  child: const Text('Yes, count it'),
                ),
                OutlinedButton(
                  key: Key('trip-no-${flight.id}'),
                  onPressed: () => _answer(context, accept: false),
                  child: const Text('No'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _answer(BuildContext context, {required bool accept}) async {
    final failure = accept
        ? await controller.saveFlight(
            flight.copyWith(reviewState: FlightReviewState.accepted),
          )
        : await controller.rejectFlight(flight);
    if (failure != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure)));
    }
  }
}
