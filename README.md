# Nomadic Residence

A Flutter web app for counting the countries a frequent traveller is physically in during a calendar year.

Wake-up days, layovers, and nights in the air stay in separate totals. Unknown days stay empty unless a qualifying flight bracket covers them: an accepted or evidence-backed arrival into a country, then the next such departure from that country. Those mornings are in the wake-up total and labeled from flights. Stored inferred stays are not rewritten. Planned trips and future dates stay off the actual total. The counts are arithmetic under rules you can edit. They are not tax, immigration, or legal advice.

## Run locally

Install Flutter 3.47.9 (stable) and then:

```bash
flutter pub get
flutter analyze
flutter test
flutter build web --release --base-href /
python3 tool/serve_web.py --port 43123
```

Open http://127.0.0.1:43123 . The first screen does not load travel records. **Review the example dataset** keeps fictional rows in the browser tab. It does not call PocketBase.

`flutter run -d web-server --web-hostname 127.0.0.1 --web-port 43123` is the debug server. Debug builds may register a loopback PocketBase. Release builds, including the Vercel build, do not.

## Your database

Each traveler uses their own PocketBase instance and therefore their own SQLite file. Register that instance in the app after its `/api/health` check succeeds, then sign in on that instance.

https://nomad.pockethost.io is one instance. Pointing two travelers at it would put both of them in the same database. The app does not do that by default.

Setup, the provisioning blocker, and the local auth tests are in [docs/POCKETHOST.md](docs/POCKETHOST.md) and [docs/SECURITY_TESTS.md](docs/SECURITY_TESTS.md).

## Sheet

Import and export use the columns in [docs/CSV.md](docs/CSV.md). Import adds rows and updates a row only when its external id already exists. It does not delete rows.

## Status of this workspace

What is implemented, what was verified locally, what is connected to a live database, and what is deployed are separated in [docs/STATUS.md](docs/STATUS.md).
