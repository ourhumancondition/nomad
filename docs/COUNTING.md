# Counting rules

Dates are civil dates, `YYYY-MM-DD`, as written. They are not converted through UTC. A flight’s departure and arrival clocks are wall times, `YYYY-MM-DDTHH:MM`, each with its own IANA time zone. Overnight means the arrival civil date is after the departure civil date. A backward civil date is left for manual entry.

The wake time defaults to 08:00 and can be changed. These behaviors stay on:

- The main day belongs to the country you are in at the wake time.
- A layover on that date is listed separately and is not added to the wake-up total.
- A night on an overnight flight is marked in transit and is not added to the wake-up country.
- A wake-up spent in the air is an in-transit main day, and that day is inside the identity total.
- Two wake-up countries on one date stay unresolved. Neither is chosen.
- A date with no countable stay stays unknown.
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

## Flight review

Proposals are created as inferences with evidence status `inferred`, so they do not count until you accept them. Accepting can clear the inference mark or keep it. A booking-only flight asks you to confirm that you are recording presence. A gap of more than one day between flights is not filled.
