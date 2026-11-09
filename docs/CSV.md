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

An export from the example dataset uses the filename `nomadic-residence-EXAMPLE-dataset.csv` and a meta row that says `EXAMPLE DATASET`.
