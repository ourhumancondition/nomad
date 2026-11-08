# PocketHost and PocketBase

## Verified from current docs

- Each PocketHost instance is real PocketBase in its own isolated container, started on demand ([How PocketHost Works](https://pockethost.io/docs/how-it-works), fetched 8 Nov 2026).
- Creating an instance is “Create New Instance” in the dashboard ([Creating an Instance](https://pockethost.io/docs/create)). The page does not document an API.
- The official CLI syncs files and tails logs. Its commands are login, logout, info, list, link, dev, deploy, sftp, and logs ([PocketHost CLI](https://pockethost.io/docs/cli)). There is no create-instance command. The renamed package is `pockethost` (the `phio` name is the previous CLI).
- CORS is open by default on PocketHost and should be limited to the site origins you choose. Static files in `pb_public` are cached; this app’s UI is meant to be hosted on Vercel instead.
- PocketBase migrations live in `pb_migrations` and run on serve ([Migrations](https://pocketbase.io/docs/js-migrations/)). API rules also filter lists ([API rules](https://pocketbase.io/docs/api-rules-and-filters/)). A list that fails its rule returns 200 with no items. A view that fails returns 404. A locked rule returns 403. Superusers bypass rules.
- Local tests used PocketBase 0.40.6. The Dart SDK is `pocketbase` 0.25.3.

## Manual setup for one traveler

1. Back up the instance’s `pb_data` before copying anything onto an instance that already has records. The PocketHost CLI can reach files over SFTP. This repo’s migration does not delete existing collections, and it still should not be the first write to a database you cannot restore.
2. In the PocketHost dashboard, create an instance for that traveler only if you intend to. This project did not create one. Do not put a second traveler on `nomad`.
3. Copy `pb_migrations/1794136000_create_travel_collections.js` into that instance’s `pb_migrations` directory and let PocketBase start so the migration can run. Do not run `migrate down` there.
4. Create a user in the PocketBase dashboard, or use in-app sign-up if that instance’s users create rule allows it. The migration does not change the users collection. The Flutter app never asks for the PocketHost password or a superuser token. PocketHost Admin Sync makes the PocketHost login a superuser; keep that credential out of the web app and out of Vercel.
5. In Nomadic Residence, enter `https://<instance>.pockethost.io`, check health, and sign in.
6. When the Vercel origin exists, set PocketHost CORS Origins to that origin.

`.pockethostconfig` is gitignored on purpose. A committed instance name would aim `pockethost deploy` at one database.

## Blocker for automatic per-user databases

There is no documented PocketHost API to create an instance, and the official CLI cannot create one either. This environment has no PocketHost username, password, or API token. Creating instances can also be a paid action; none were created. The app therefore only registers an instance URL that a person already has. If no URL is registered, travel calls fail closed. They do not fall back to `nomad` or to a shared collection.

The shared methods wiki at `https://github.com/ourhumancondition/methods` was checked again on 8 Nov 2026 with the GitHub credential that can read `ourhumancondition/nomad`. `GET /repos/ourhumancondition/methods` returned 404. The same 404 came back for `docs/MAINTENANCE.md`, `INDEX.md`, and `docs/pocketbase-schema-import.md` on `main` and on `cursor/shared-methods-wiki-ee4a`. `git ls-remote` reported “repository not found.” `GET /user` with that credential returned 403 “Resource not accessible by integration,” so the token is scoped to this repository. A 404 from it does not prove the wiki is missing for an account that can see other repositories. Nothing from that wiki was copied or edited. The steps above are from PocketHost and PocketBase’s own docs and from the local test run.
