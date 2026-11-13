import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import 'country_presence.dart';
import 'format.dart';
import 'missing_page.dart';
import 'theme.dart';

class DaysPage extends StatelessWidget {
  const DaysPage({
    super.key,
    required this.controller,
    required this.rolling,
    required this.onRolling,
    required this.onFillUnknown,
    required this.onConfirmTrips,
  });

  final AppController controller;
  final bool rolling;
  final ValueChanged<bool> onRolling;
  final VoidCallback onFillUnknown;
  final VoidCallback onConfirmTrips;

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
    final trips = tripsToConfirm(
      stays: controller.stays,
      flights: controller.flights,
      rules: controller.rules,
      statuses: controller.statuses,
      today: controller.clock(),
      year: controller.year,
      rolling: rolling,
    );
    final maxDays = presence.countries.isEmpty
        ? 1
        : presence.countries.first.days;
    final period = !presence.hasWindow
        ? 'This year has not started.'
        : '${shortDate(presence.start!)} – ${shortDate(presence.end!)}';
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
      children: [
        Text(
          'Days by country',
          key: const Key('days-title'),
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w700, height: 1.1),
        ),
        const SizedBox(height: 14),
        _PeriodBar(
          controller: controller,
          rolling: rolling,
          onRolling: onRolling,
        ),
        const SizedBox(height: 6),
        Text(period, style: const TextStyle(color: Color(0xFF5C564E))),
        const SizedBox(height: 18),
        Text(
          '${presence.knownDays} ${presence.knownDays == 1 ? 'day' : 'days'} in a country',
          key: const Key('known-days'),
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (presence.unknownDays > 0) ...[
          const SizedBox(height: 12),
          _Callout(
            color: const Color(0xFFF8EBE3),
            border: const Color(0xFFE4C2B2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  unknownSentence(presence.unknownDays),
                  key: const Key('unknown-days'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  key: const Key('fill-unknown'),
                  onPressed: onFillUnknown,
                  child: const Text('Fill these in'),
                ),
              ],
            ),
          ),
        ],
        if (trips.isNotEmpty) ...[
          const SizedBox(height: 12),
          _Callout(
            color: const Color(0xFFE5F2ED),
            border: const Color(0xFFB7D7CC),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  confirmTripsSentence(trips.length),
                  key: const Key('confirm-trips-label'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  key: const Key('confirm-trips'),
                  onPressed: onConfirmTrips,
                  child: const Text('Review trips'),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 22),
        if (presence.countries.isEmpty)
          const Text('No country yet for this period.')
        else
          for (final country in presence.countries)
            _CountryRow(country: country, maxDays: maxDays),
        const SizedBox(height: 8),
        _HowCounted(controller: controller, presence: presence),
        const SizedBox(height: 12),
        const Text(
          'This is a count of days, not a tax or immigration answer.',
          style: TextStyle(color: Color(0xFF5C564E)),
        ),
      ],
    );
  }
}

class _PeriodBar extends StatelessWidget {
  const _PeriodBar({
    required this.controller,
    required this.rolling,
    required this.onRolling,
  });

  final AppController controller;
  final bool rolling;
  final ValueChanged<bool> onRolling;

  @override
  Widget build(BuildContext context) {
    final label = rolling ? 'Last 12 months' : '${controller.year}';
    final style = Theme.of(context).textTheme.headlineSmall
        ?.copyWith(fontWeight: FontWeight.w700);
    final previous = IconButton(
      key: const Key('year-previous'),
      tooltip: 'Previous year',
      onPressed: rolling || controller.year <= 1
          ? null
          : () => controller.setYear(controller.year - 1),
      icon: const Icon(Icons.chevron_left),
    );
    final next = IconButton(
      key: const Key('year-next'),
      tooltip: 'Next year',
      onPressed: rolling ? null : () => controller.setYear(controller.year + 1),
      icon: const Icon(Icons.chevron_right),
    );
    final chip = ChoiceChip(
      key: const Key('period-rolling'),
      label: const Text('Last 12 months'),
      selected: rolling,
      onSelected: onRolling,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final title = Text(label, key: const Key('year-label'), style: style);
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  previous,
                  Expanded(child: title),
                  next,
                ],
              ),
              chip,
            ],
          );
        }
        return Row(children: [previous, title, next, const Spacer(), chip]);
      },
    );
  }
}

class _CountryRow extends StatelessWidget {
  const _CountryRow({required this.country, required this.maxDays});

  final CountryDays country;
  final int maxDays;

  @override
  Widget build(BuildContext context) {
    final days = '${country.days}';
    return Semantics(
      label: '${country.name}, $days days',
      child: Padding(
        key: Key('country-row-${country.code}'),
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _Flag(country: country),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    country.name,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      minHeight: 8,
                      value: country.days / maxDays,
                      color: countryColor(country.code),
                      backgroundColor: line,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  days,
                  key: Key('country-days-${country.code}'),
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
                Text(
                  country.days == 1 ? 'day' : 'days',
                  style: const TextStyle(color: Color(0xFF5C564E)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Flag extends StatelessWidget {
  const _Flag({required this.country});

  final CountryDays country;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: countryColor(country.code).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        country.flag.isEmpty ? country.code : country.flag,
        key: Key('country-flag-${country.code}'),
        style: TextStyle(
          fontSize: country.flag.isEmpty ? 14 : 28,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _HowCounted extends StatelessWidget {
  const _HowCounted({required this.controller, required this.presence});

  final AppController controller;
  final CountryPresence presence;

  @override
  Widget build(BuildContext context) {
    final notes = countingNotes(presence);
    return Card(
      child: ExpansionTile(
        key: const Key('how-counted'),
        title: const Text('How is this counted?'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          for (final note in notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Align(alignment: Alignment.centerLeft, child: Text(note)),
            ),
          for (final assumption in presence.flightAssumptions) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(assumption.sentence),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'from flights (left from ${assumption.leftName})',
                key: Key('mismatch-label-${assumption.id}'),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: Key('change-mismatch-${assumption.id}'),
                onPressed: () => _change(context, assumption),
                child: const Text('Change it'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _change(
    BuildContext context,
    FlightAssumption assumption,
  ) async {
    final stay = await showWhereWereYou(
      context,
      start: assumption.start,
      end: assumption.end,
    );
    if (stay == null) return;
    final failure = await controller.saveStay(stay);
    if (failure != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure)));
    }
  }
}

class _Callout extends StatelessWidget {
  const _Callout({
    required this.color,
    required this.border,
    required this.child,
  });

  final Color color;
  final Color border;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: child,
    );
  }
}
