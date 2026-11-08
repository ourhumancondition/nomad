# Architecture

## One SQLite file per traveler

PocketHost’s own description is that each instance runs in its own isolated container ([How PocketHost Works](https://pockethost.io/docs/how-it-works)). PocketHost’s maintainer has also described the process as `pocketbase serve --dir=/path/to/instance/pb_data`, with only that instance’s database reachable through its API ([discussion #143](https://github.com/pockethost/pockethost/discussions/143)). That is the isolation this app relies on: a different origin is a different PocketBase process and a different SQLite file.

The `user` relation and API rules inside one instance are a second check, so two accounts on a mis-shared instance still cannot read each other. They are not a substitute for separate databases. The app has no shared travel collection and no row-level tenant mode.

## What the client will call

`InstanceEndpoint` accepts only:

- `https://<single-label>.pockethost.io` on port 443
- loopback `http://127.0.0.1`, `http://localhost`, or `http://[::1]`, and only when `kDebugMode` is true or the build defines `ALLOW_LOCAL_POCKETBASE=true`

Userinfo, queries, fragments, paths, IP hosts, and extra labels are rejected before any request. The HTTP client sets `followRedirects` to false and treats a 3xx response as a failure. There is no server-side proxy in this app, so a rejected URL is not fetched by a backend.

`https://nomad.pockethost.io` can be typed in as one traveler’s instance. It is not the default, and it is not a control plane for other people’s stays. A public `GET /api/health` on 8 Nov 2026 returned `{"message":"API is healthy.","code":200,"data":{}}`. No other production endpoint was called. No superuser token is in the client, the repo, or the logs.

## Fail closed

Until health has succeeded and a user session exists on that origin, stays are not read or written. A missing session throws instead of falling back to another database. The example dataset is a separate in-memory mode. Leaving it drops those rows. Connecting does not upload them.

The auth token is stored in the browser’s `localStorage` under a key that includes the origin. It is not written to application logs.

## Provisioning

PocketHost documents instance creation as a dashboard action ([Creating an Instance](https://pockethost.io/docs/create)). The current CLI (`pockethost` / former `phio`) logs in, lists, links, and syncs files. It does not create instances. This environment has no PocketHost credentials, and no instance was created. Registration in the app is manual. Details and the exact blocker are in [POCKETHOST.md](POCKETHOST.md).

## Schema

`pb_migrations/1794136000_create_travel_collections.js` creates `stays`, `flights`, and `counting_settings` only when a collection of that name is absent. It does not alter `users` or any pre-existing collection. The down migration deletes those three collections and must not be run against a database you need to keep.

The migration was applied only to disposable local data directories by `tool/auth_rules_check.py`.
