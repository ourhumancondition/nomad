import 'package:flutter/material.dart';

import '../data/countries.dart';
import '../engine/day_engine.dart';
import '../engine/flight_brackets.dart';
import '../state/app_controller.dart';
import 'format.dart';
import 'theme.dart';

class SummaryPage extends StatelessWidget {
  const SummaryPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final tally = controller.tally;
    final entries = tally.primaryDays.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxDays = entries.isEmpty
        ? 1
        : entries.map((entry) => entry.value).reduce((a, b) => a > b ? a : b);
    final window = tally.windowStart == null
        ? 'This year is still ahead, so the actual total is empty.'
        : '${shortDate(tally.windowStart!)} through ${shortDate(tally.windowEnd!)}';
    final bookingCounts = controller.statuses.any(
      (status) => status.id == 'booking_only' && status.countsAsActual,
    );
    final showSources =
        tally.flightBracketDayCount > 0 ||
        tally.flightGaps.isNotEmpty ||
        tally.bracketConflicts.isNotEmpty ||
        tally.transitInterruptions.isNotEmpty;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text(
          '${tally.year} presence',
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(window),
        const SizedBox(height: 16),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${tally.primaryCountryDays} wake-up country days',
                key: const Key('primary-total'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                '${tally.primaryCountryDays} country days + ${tally.transitWakeDays} in-transit wake-ups + ${tally.gapDays} unknown days + ${tally.overlapDays} unresolved days = ${tally.windowLength} days in this window.',
                key: const Key('identity-line'),
              ),
              if (tally.flightBracketDayCount > 0) ...[
                const SizedBox(height: 8),
                Text(
                  '${tally.stayPrimaryDayCount} from stays · ${tally.flightBracketDayCount} from flights. Both are in this wake-up total.',
                  key: const Key('source-total'),
                ),
              ],
              if (!tally.identityHolds) ...[
                const SizedBox(height: 8),
                const Text(
                  'The day parts do not add up to the window. Treat this year as unreliable until that is fixed.',
                ),
              ],
            ],
          ),
        ),
        if (bookingCounts)
          const _Card(
            child: Text(
              'Booking-only records are set to count. That is your choice, and it treats an uncorroborated booking as presence.',
            ),
          ),
        if (controller.rules.includeInferred)
          const _Card(
            child: Text(
              'Records still marked as inference are included because that rule is on. A stay whose evidence status is Inferred is still left out.',
            ),
          ),
        if (controller.inferredCountryDays > 0)
          _Card(
            child: Text(
              '${controller.inferredCountryDays} inferred country day${controller.inferredCountryDays == 1 ? '' : 's'} are stored and kept out of the wake-up total. A morning bracketed by qualifying flights is already in the total above, even when an older inferred stay covers that date. Counting inferences does not add a stay whose evidence status is Inferred.',
              key: const Key('inferred-total'),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'Wake-up countries',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          const _Card(
            child: Text(
              'No wake-up country is assigned in this window. Unknown days are left empty.',
            ),
          )
        else
          for (final entry in entries)
            _CountryBar(
              code: entry.key,
              days: entry.value,
              fromStays: tally.stayPrimaryDays[entry.key] ?? 0,
              fromFlights: tally.flightBracketDays[entry.key] ?? 0,
              showSource: showSources,
              maxDays: maxDays,
              marker: controller.rules.personalDayMarker,
            ),
        if (showSources) ...[
          const SizedBox(height: 8),
          _FlightSources(tally: tally),
        ],
        const SizedBox(height: 16),
        Text(
          'Separate from the wake-up total',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Layovers',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              const Text(
                'These days already have a wake-up country in the total above. The layover is listed so it is not added again.',
              ),
              const SizedBox(height: 8),
              if (tally.layoverDays.isEmpty)
                const Text('No layover presence in this window.')
              else
                for (final entry in tally.layoverDays.entries)
                  Text(
                    '${countryLabel(entry.key)} · ${entry.value} day${entry.value == 1 ? '' : 's'}',
                  ),
              const SizedBox(height: 12),
              const Text(
                'Overnight nights in transit',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                '${tally.overnightNights} night${tally.overnightNights == 1 ? '' : 's'}. Kept out of the country total.',
              ),
              const SizedBox(height: 12),
              Text(
                'In-transit wake-ups: ${tally.transitWakeDays}. These are already inside the identity total.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _Card(child: Text(_outsideTotal(tally))),
        const SizedBox(height: 12),
        const Text(
          'These are day counts under the rules on the Rules page. They are not a tax, immigration, or legal determination.',
          style: TextStyle(color: Color(0xFF5C564E)),
        ),
      ],
    );
  }
}

class _CountryBar extends StatelessWidget {
  const _CountryBar({
    required this.code,
    required this.days,
    required this.fromStays,
    required this.fromFlights,
    required this.showSource,
    required this.maxDays,
    required this.marker,
  });

  final String code;
  final int days;
  final int fromStays;
  final int fromFlights;
  final bool showSource;
  final int maxDays;
  final int? marker;

  @override
  Widget build(BuildContext context) {
    final reached = marker != null && marker! > 0 && days >= marker!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(countryLabel(code))),
              Text('$days'),
            ],
          ),
          if (showSource)
            Text(
              _sourceLine(fromStays, fromFlights),
              key: Key('country-source-$code'),
              style: const TextStyle(color: Color(0xFF5C564E)),
            ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: days / maxDays,
              color: countryColor(code),
              backgroundColor: line,
            ),
          ),
          if (reached)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Reaches your marker of $marker. That marker is a reminder you chose.',
                style: const TextStyle(color: Color(0xFF5C564E)),
              ),
            ),
        ],
      ),
    );
  }
}

String _outsideTotal(YearTally tally) {
  final records = tally.excluded.length;
  final covered = tally.excluded
      .where(
        (item) =>
            item.daysInWindow > 0 &&
            item.morningsAlreadyCounted == item.daysInWindow,
      )
      .length;
  final recordWord = records == 1 ? 'record' : 'records';
  final verb = records == 1 ? 'is' : 'are';
  final coveredSentence = covered == 0
      ? ''
      : ' $covered of them ${covered == 1 ? 'is a stored record whose mornings are' : 'are stored records whose mornings are'} already in the wake-up total.';
  return '$records actual-phase $recordWord in this window $verb outside the total.$coveredSentence Planned trips: ${tally.planned.length}. Future-dated actual stays touching this year: ${tally.futureActual.length}.';
}

String _sourceLine(int fromStays, int fromFlights) {
  if (fromStays > 0 && fromFlights > 0) {
    return '$fromStays from stays · $fromFlights from flights';
  }
  if (fromFlights > 0) {
    return '$fromFlights from flights';
  }
  return '$fromStays from stays';
}

class _FlightSources extends StatelessWidget {
  const _FlightSources({required this.tally});

  final YearTally tally;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'From flights',
            key: Key('flight-bracket-section'),
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          const Text(
            'These mornings are in the wake-up total. They sit between a qualifying arrival and the next qualifying departure from the same country. An overnight wake-up in the air stays in transit. A layover stays listed separately. A stored stay of another country is kept.',
          ),
          if (tally.appliedBrackets.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final bracket in tally.appliedBrackets)
              Text(
                '${countryLabel(bracket.countryCode)} · ${shortRange(bracket.start, bracket.end)} · ${bracket.days} day${bracket.days == 1 ? '' : 's'} · ${bracket.arrivalNumber} to ${bracket.departureNumber}',
                key: Key(
                  'flight-bracket-${bracket.countryCode}-${bracket.start.iso}',
                ),
              ),
          ],
          if (tally.flightGaps.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Not counted from flights',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            for (final gap in tally.flightGaps)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  _gapText(gap),
                  key: Key(
                    'flight-${gap.kind.name}-${gap.arrivalNumber}-${gap.otherNumber}',
                  ),
                ),
              ),
          ],
          if (tally.bracketConflicts.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Existing stays kept',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            for (final conflict in tally.bracketConflicts)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${countryLabel(conflict.flightCountry)} from flights overlaps ${countryLabel(conflict.stayCountry)} on ${shortRange(conflict.range.start, conflict.range.end)}. The existing stay is kept.',
                  key: Key(
                    'flight-conflict-${conflict.flightCountry}-${conflict.stayCountry}',
                  ),
                ),
              ),
          ],
          if (tally.transitInterruptions.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final interruption in tally.transitInterruptions)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'An in-transit wake-up on ${shortDate(interruption.date)} ends the ${countryLabel(interruption.countryCode)} bracket from ${interruption.arrivalNumber} to ${interruption.departureNumber}. Later days in that pair are not counted from flights.',
                  key: const Key('flight-interruption'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

String _gapText(FlightGap gap) {
  final arrived = countryLabel(gap.arrivalCountry);
  final other = countryLabel(gap.otherCountry);
  final span = '${shortDate(gap.fromDate)} – ${shortDate(gap.toDate)}';
  switch (gap.kind) {
    case FlightGapKind.mismatch:
      return '${gap.arrivalNumber} arrives in $arrived and ${gap.otherNumber} leaves $other ($span). Those days stay unknown.';
    case FlightGapKind.unqualified:
      final why = gap.reason == 'needs_manual'
          ? '${gap.otherNumber} needs a manual stay'
          : '${gap.otherNumber} is not accepted and its evidence does not count';
      return '$why, so the days after ${gap.arrivalNumber} arrived in $arrived are not counted from flights ($span).';
    case FlightGapKind.noWake:
      return 'The wake time does not fall in $arrived between ${gap.arrivalNumber} and ${gap.otherNumber} ($span). No wake-up day is added.';
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}
