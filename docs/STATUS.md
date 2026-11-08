# Status

## Implemented

- Flutter web UI: year summary, calendar, stays, flight review, unknown and overlap review, planned and future dates, counting rules, CSV import and export.
- Date engine with leap days, year boundaries, overlaps, layovers, overnight nights, airborne wake-ups, gaps left empty, and future dates excluded.
- Opt-in fictional example dataset, labeled in the UI and in its CSV export. It is not uploaded.
- Allowlisted per-instance PocketBase client. The first screen connects one database, then offers either creating an account or signing in. There is no shared-data fallback and no administrator login.
- Additive PocketBase migration for `stays`, `flights`, and `counting_settings`.
- Vercel static config and Flutter web build script.

## Verified locally

- `flutter analyze`: no issues.
- `flutter test`: 27 tests passed (engine, proposals, CSV, allowlist, widget smoke).
- `python3 tool/auth_rules_check.py`: two disposable PocketBase 0.40.6 instances. See [SECURITY_TESTS.md](SECURITY_TESTS.md) for the status codes. That suite was not run again while landing this tree in GitHub.
- `flutter build web --release` succeeded. The release bundle was served at http://127.0.0.1:43123 and checked in a browser on a desktop width and a narrow width. The example banner, the 212 / Portugal 90 totals, the November calendar, the review gaps, and booking-only flight EX512 were visible. That server is local. That browser pass was not repeated for this GitHub landing.

Landing this tree re-ran `flutter analyze` (no issues) and `flutter test` (27 passed) with Flutter 3.47.9, Dart 3.13.7, framework revision `c197ca5199`. `scripts/vercel_build_web.sh` was run with no Flutter installed beforehand and with a decoy `flutter` first on `PATH`. It downloaded the pinned archive, matched the SHA-256, ignored the decoy, and wrote `build/web` with `<base href="/">`. These checks are local. They are not a production deployment or a production database test.

## Connected live

`https://nomad.pockethost.io` is PocketBase 0.41.1. The owner imported the merged collections file through the PocketBase UI. An independent comparison of the post-import export passed: the 6 existing collections were unchanged and the 3 new collections were `stays`, `flights`, and `counting_settings`, with zero normalizations. A native backup taken after that import was verified at 3:24:58 PM EST. The earlier backup was kept. This repository does not store backup paths or credentials.

The users collection has one account. This project did not create it. `stays`, `flights`, and `counting_settings` have no records. Signing up, signing in, and saving travel rows on that live database have not been verified. Do not use the PocketBase superuser as the app account.

## Deployed

A first Vercel deployment of the earlier commit is at https://nomad-taupe-omega.vercel.app (`dpl_CMX3ZgJYHTAhdibFeCWfVpoSTUYD`). It was labeled production while the pull request was still open. That deployment does not include the later onboarding changes. The static build config is in [DEPLOYMENT.md](DEPLOYMENT.md).
