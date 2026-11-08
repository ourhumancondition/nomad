/// Additive travel schema for one PocketBase instance (one SQLite file).
///
/// Creates stays, flights, and counting_settings only when those names are
/// absent. It does not change the users collection, existing collections,
/// fields, or records.
///
/// The down function deletes those three collections. Do not run
/// `migrate down` on a database that holds records you need, including
/// https://nomad.pockethost.io.

migrate(
  (app) => {
    const users = app.findCollectionByNameOrId("users");

    if (!findOptional(app, "stays")) {
      app.save(
        new Collection({
          type: "base",
          name: "stays",
          listRule: '@request.auth.id != "" && user = @request.auth.id',
          viewRule: '@request.auth.id != "" && user = @request.auth.id',
          createRule:
            '@request.auth.id != "" && @request.body.user = @request.auth.id',
          updateRule:
            '@request.auth.id != "" && user = @request.auth.id && @request.body.user = @request.auth.id',
          deleteRule: '@request.auth.id != "" && user = @request.auth.id',
          fields: [
            relation(users.id, "user"),
            text("country_code", false, 0, 2),
            text("start_date", true, 10, 10),
            text("end_date", true, 10, 10),
            select("role", [
              "primary",
              "layover",
              "transit_wake",
              "transit_night",
            ]),
            text("evidence_status", true, 1, 40),
            select("inference", [
              "none",
              "inferred_itinerary",
              "inferred_connection",
              "inferred_gap",
            ]),
            select("phase", ["actual", "planned"]),
            text("timezone", true, 1, 64),
            text("notes", false, 0, 2000),
            text("external_id", false, 0, 80),
            select("source", ["manual", "csv", "flight_review"]),
          ],
          indexes: [
            "CREATE INDEX idx_stays_user_start ON stays (user, start_date)",
          ],
        }),
      );
    }

    if (!findOptional(app, "flights")) {
      app.save(
        new Collection({
          type: "base",
          name: "flights",
          listRule: '@request.auth.id != "" && user = @request.auth.id',
          viewRule: '@request.auth.id != "" && user = @request.auth.id',
          createRule:
            '@request.auth.id != "" && @request.body.user = @request.auth.id',
          updateRule:
            '@request.auth.id != "" && user = @request.auth.id && @request.body.user = @request.auth.id',
          deleteRule: '@request.auth.id != "" && user = @request.auth.id',
          fields: [
            relation(users.id, "user"),
            text("flight_number", true, 2, 8),
            text("from_iata", true, 3, 3),
            text("to_iata", true, 3, 3),
            text("from_country", true, 2, 2),
            text("to_country", true, 2, 2),
            text("depart_local", true, 16, 16),
            text("arrive_local", true, 16, 16),
            text("depart_timezone", true, 1, 64),
            text("arrive_timezone", true, 1, 64),
            text("evidence_status", true, 1, 40),
            select("inference", [
              "none",
              "inferred_itinerary",
              "inferred_connection",
              "inferred_gap",
            ]),
            select("review_state", [
              "pending",
              "accepted",
              "rejected",
              "needs_manual",
            ]),
            text("notes", false, 0, 2000),
            text("external_id", false, 0, 80),
          ],
          indexes: [
            "CREATE INDEX idx_flights_user_depart ON flights (user, depart_local)",
          ],
        }),
      );
    }

    if (!findOptional(app, "counting_settings")) {
      app.save(
        new Collection({
          type: "base",
          name: "counting_settings",
          listRule: '@request.auth.id != "" && user = @request.auth.id',
          viewRule: '@request.auth.id != "" && user = @request.auth.id',
          createRule:
            '@request.auth.id != "" && @request.body.user = @request.auth.id',
          updateRule:
            '@request.auth.id != "" && user = @request.auth.id && @request.body.user = @request.auth.id',
          deleteRule: '@request.auth.id != "" && user = @request.auth.id',
          fields: [
            relation(users.id, "user"),
            {
              name: "wake_hour",
              type: "number",
              required: true,
              min: 0,
              max: 23,
              onlyInt: true,
            },
            {
              name: "wake_minute",
              type: "number",
              required: true,
              min: 0,
              max: 59,
              onlyInt: true,
            },
            { name: "include_inferred", type: "bool", required: false },
            {
              name: "personal_day_marker",
              type: "number",
              required: false,
              min: 0,
              max: 366,
              onlyInt: true,
            },
            text("statuses_json", true, 2, 8000),
          ],
          indexes: [
            "CREATE UNIQUE INDEX idx_counting_settings_user ON counting_settings (user)",
          ],
        }),
      );
    }
  },
  (app) => {
    // Destructive. Do not run against a database you need to keep.
    for (const name of ["stays", "flights", "counting_settings"]) {
      const collection = findOptional(app, name);
      if (collection) app.delete(collection);
    }
  },
);

function findOptional(app, name) {
  try {
    return app.findCollectionByNameOrId(name);
  } catch (err) {
    return null;
  }
}

function relation(usersId, name) {
  return {
    name: name,
    type: "relation",
    required: true,
    collectionId: usersId,
    cascadeDelete: true,
    maxSelect: 1,
  };
}

function text(name, required, min, max) {
  return {
    name: name,
    type: "text",
    required: required,
    min: min,
    max: max,
  };
}

function select(name, values) {
  return {
    name: name,
    type: "select",
    required: true,
    maxSelect: 1,
    values: values,
  };
}
