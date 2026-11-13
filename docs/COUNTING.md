# Counting rules

Dates are civil dates, `YYYY-MM-DD`, as written. They are not converted through UTC. A flight’s departure and arrival clocks are wall times, `YYYY-MM-DDTHH:MM`, each with its own IANA time zone. Overnight means the arrival civil date is after the departure civil date. A backward civil date is left for manual entry.

The wake time defaults to 08:00 and can be changed. These behaviors stay on:

- The main day belongs to the country you are in at the wake time.
- A layover on that date is listed separately and is not added to the wake-up total.
- A night on an overnight flight is marked in transit and is not added to the wake-up country.
- A wake-up spent in the air is an in-transit main day, and that day is inside the identity total.
- Two wake-up countries on one date stay unresolved. Neither is chosen.
- A date with no countable stay and no qualifying flight bracket stays unknown.
- Planned trips stay on the Planned page.
- Dates after today stay out of the actual total. Today follows the browser’s local calendar date.
- Leap days stay in the year that contains them. 29 Feb 2024 is a real date. 29 Feb 2025 is rejected.

For a past or current year the parts add up:

`wake-up country days + in-transit wake-ups + unknown days + unresolved days = days from 1 January through today (or through 31 December if the year is already over)`

Layovers and overnight nights are outside that equation.

## What counts

A stay counts only when all of these are true:

- phase is actual
- the date is on or before today
- the evidence status exists in your list and is set to count
- if the inference mark is anything other than Observed, the “count inferences” rule is on

Defaults:

| Status | Counts |
| --- | --- |
| Confirmed | yes |
| Corroborated | yes |
| Booking only | no |
| Inferred | no |
| Unknown | no |

You can add statuses and change the count flag. An unknown status id does not count. Turning on “Booking only” is possible and the year page says so. There is no built-in day threshold. An optional personal marker only highlights a bar. It is not a legal test.

## Flight brackets

The year summary counts some mornings directly from flights. Nothing is written, and stored evidence is not changed. An inferred stay imported earlier, or saved from “Preview days between flights”, still has evidence `inferred`. It stays out of the total on its own. If a qualifying flight bracket covers that morning, the morning is in the total once, labeled **from flights**.

A bracket is a qualifying flight that arrives in country X, then the next recorded flight that is not a domestic flight inside X, when that next flight leaves X and also qualifies. Domestic flights inside X do not end the stay. The mornings are the existing wake-up window: the first wake in the arrival country through the last wake before the departure. Civil dates are used as written. Time zones are not converted. The arrival time zone on the ticket is the zone stored for a proposed stay; it does not shift the date.

These mornings are part of the wake-up country total, beside mornings from stored stays. The summary shows the split per country.

They do not count when:

- The next qualifying flight leaves a different country. Those days stay unknown, and the summary lists the pair.
- The next flight out of X is booking-only and has not been accepted, or it needs a manual stay. The days are not counted, and a later flight is not used to skip that departure. The summary lists it. A booking-only flight that does not leave X is ignored, the same way a domestic flight is.
- The flight is rejected, or it is a duplicate ticket. Rejected flights are ignored. Neither copy of a duplicate is used.
- The arrival civil date is before the departure civil date. No days are inferred from that ticket.
- An actual stay in a different country covers the date. The stay is kept, including when its evidence does not count, and the summary reports the overlap. Dates in the bracket that the stay does not cover can still count.
- A recorded in-transit wake-up falls inside the bracket. That morning stays in transit, and later mornings in the same pair are not counted from flights.
- The wake time falls while a qualifying flight is airborne. That morning is an in-transit wake-up, inside the identity total, and it is not a country day. An overnight night is not a country day.
- The same civil day is a connection and the wake time is not in the connection country. No wake-up day is added. A stored layover stays listed separately and is not added to the country total.
- There is no later flight. Days after the arrival are not filled.

A flight qualifies when it is not rejected, not marked “needs a manual stay”, and either its review state is accepted or its evidence status counts (Confirmed or Corroborated, unless you change those flags). Acceptance qualifies a booking-only flight, because that is the traveler saying the flight happened. A pending booking-only flight does not qualify. `needs_manual` does not qualify even if the evidence status would otherwise count, because that state asks for a stay entered by hand.

Accepting one flight still proposes only the immediate connection. A proposal is stored as evidence `inferred` and does not count until the inference mark is cleared or “count inferences” is on, and even then an evidence status of Inferred does not count. The summary’s flight brackets are separate from those saved proposals. Saving the preview does not add a second count.

## Flight review

Proposals are created as inferences with evidence status `inferred`, so they do not count until you accept them. Accepting can clear the inference mark or keep it. A booking-only flight asks you to confirm that you are recording presence. The proposal step still does not fill a gap of more than one day. The year summary’s flight brackets, above, are what count a longer same-country stay.
