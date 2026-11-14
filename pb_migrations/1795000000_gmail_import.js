/// Additive Gmail import schema.
///
/// Creates gmail_links and gmail_pending when those names are absent, and
/// adds provenance fields to flights when those fields are absent.
/// It does not change users, stays, counting_settings, or existing flight
/// values. The records API for the two new collections is locked. The
/// gmail_vault hook is the only reader of token_ciphertext.
///
/// Do not apply this file to https://nomad.pockethost.io from an agent run.
/// Copy it into the instance pb_migrations directory and restart PocketBase.
/// The down migration removes the new collections and the new flight fields.
/// Do not run migrate down on a database you need to keep.

migrate(
  (app) => {
    const users = app.findCollectionByNameOrId("users");

    if (!findOptional(app, "gmail_links")) {
      app.save(
        new Collection({
          type: "base",
          name: "gmail_links",
          listRule: null,
          viewRule: null,
          createRule: null,
          updateRule: null,
          deleteRule: null,
          fields: [
            relation(users.id, "user"),
            select("status", ["disconnected", "connected", "revoked"]),
            text("google_email", false, 0, 200),
            text("scope", false, 0, 300),
            text("connected_at", false, 0, 40),
            hiddenText("token_ciphertext", 8000),
          ],
          indexes: [
            "CREATE UNIQUE INDEX idx_gmail_links_user ON gmail_links (user)",
          ],
        }),
      );
    }

    if (!findOptional(app, "gmail_pending")) {
      app.save(
        new Collection({
          type: "base",
          name: "gmail_pending",
          listRule: null,
          viewRule: null,
          createRule: null,
          updateRule: null,
          deleteRule: null,
          fields: [
            relation(users.id, "user"),
            text("nonce", true, 32, 80),
            text("return_to", true, 1, 200),
            text("expires_at", true, 1, 20),
            { name: "consumed", type: "bool", required: false },
          ],
          indexes: [
            "CREATE UNIQUE INDEX idx_gmail_pending_nonce ON gmail_pending (nonce)",
          ],
        }),
      );
    }

    const flights = findOptional(app, "flights");
    if (flights) {
      addText(flights, "gmail_message_id", 64);
      addText(flights, "gmail_from", 200);
      addText(flights, "gmail_date", 40);
      addText(flights, "itinerary_ref", 16);
      addText(flights, "passenger_name", 120);
      addText(flights, "supersedes_external_id", 80);
      if (!flights.fields.getByName("receipt_kind")) {
        flights.fields.add(
          new SelectField({
            name: "receipt_kind",
            required: false,
            maxSelect: 1,
            values: ["booking", "amendment", "cancellation"],
          }),
        );
      }
      app.save(flights);
    }
  },
  (app) => {
    const flights = findOptional(app, "flights");
    if (flights) {
      for (const name of [
        "gmail_message_id",
        "gmail_from",
        "gmail_date",
        "itinerary_ref",
        "passenger_name",
        "supersedes_external_id",
        "receipt_kind",
      ]) {
        if (flights.fields.getByName(name)) {
          flights.fields.removeByName(name);
        }
      }
      app.save(flights);
    }
    for (const name of ["gmail_links", "gmail_pending"]) {
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

function hiddenText(name, max) {
  return {
    name: name,
    type: "text",
    required: false,
    hidden: true,
    min: 0,
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

function addText(collection, name, max) {
  if (collection.fields.getByName(name)) return;
  collection.fields.add(
    new TextField({
      name: name,
      required: false,
      min: 0,
      max: max,
    }),
  );
}
