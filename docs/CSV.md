# CSV sheet

One header, in this order:

```
record_type,external_id,country_code,start_date,end_date,role,evidence_status,inference,phase,timezone,notes,flight_number,from_iata,to_iata,from_country,to_country,depart_local,arrive_local,depart_timezone,arrive_timezone,review_state
```

`record_type` is `stay`, `flight`, or `meta`. A `meta` row is skipped. If its notes contain `EXAMPLE DATASET`, the import is labeled as example data. Copying that file into a connected database requires an extra confirmation.

Dates are `YYYY-MM-DD`. Flight clocks are `YYYY-MM-DDTHH:MM` with no `Z` suffix. Time zones are separate columns.

Roles: `primary`, `layover`, `transit_wake`, `transit_night`.

Inference: `none`, `inferred_itinerary`, `inferred_connection`, `inferred_gap`.

Phase: `actual`, `planned`.

Review state: `pending`, `accepted`, `rejected`, `needs_manual`.

Import keeps every existing row. A row with an external id replaces the row that already has that id. Rows that fail validation are listed and skipped. Nothing is deleted.

The columns above are unchanged. A stay row still counts only under the evidence and inference rules in [COUNTING.md](COUNTING.md). A flight row is not a stay and is not rewritten on import. The year summary also counts wake-ups bracketed by qualifying flights. That count is computed when the year is shown. It is not a column, and importing a sheet does not change a stay’s evidence status. An inferred stay that is not bracketed by qualifying flights stays out of the wake-up total.

An export from the example dataset uses the filename `nomadic-residence-EXAMPLE-dataset.csv` and a meta row that says `EXAMPLE DATASET`.
