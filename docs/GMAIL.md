# Gmail receipt import

Nomadic Residence can read airline and OTA flight receipts from a connected Gmail account, show a preview, and save the legs the traveler checks. A saved leg is booking-only and needs review. It is not accepted, and it does not add a wake-up day. A booking is planned travel, not proof the flight was taken.

The Google client secret and the refresh token never go in the Flutter bundle, the CSV sheet, or the flight notes. The receipt body is not stored. Provenance kept on a flight is the Gmail message id, the sender address, the message date, the booking reference, and the passenger name when the receipt states one.

This repository does not contain a Google OAuth client. The steps below are what the instance owner does. This change was not applied to https://nomad.pockethost.io.

## What the broker asks Google for

One scope:

```
https://www.googleapis.com/auth/gmail.readonly
```

That is the narrowest Gmail scope that includes message bodies and attachments. `gmail.metadata` does not include the body, so it cannot be parsed. The broker refuses a token whose granted scope is anything else, including `gmail.modify`, `gmail.send`, or `https://mail.google.com/`.

The OAuth request uses `access_type=offline` and `prompt=consent` so Google returns a refresh token, and `include_granted_scopes=false` so an older wider grant is not silently added.

Search is limited to the last five years and to a query that names Air Canada, EVA Air, Asiana, United, Trip.com, LOT, Shenzhen Airlines, and subjects such as itinerary, e-ticket, flight confirmation, booking confirmation, and schedule change. Messages that still do not look like a flight receipt are counted and their text is not returned. Each scan fetches at most 15 messages.

Time zones, clock times, and airports that are missing or ambiguous stay empty. An abbreviation such as EST or GMT is not converted. A city name is not turned into an airport code. A known three-letter code can supply the country from a fixed table. An unknown code does not.

Amendments keep a `supersedes` link to the earlier external id when one earlier flight matches. Cancellations do not create a flight. They can reject an earlier pending flight only when the traveler checks that action. An accepted flight is left as it is. Repeating a scan uses the Gmail message id in the external id, so a row that is already stored is skipped.

## Where the pieces run

- The Flutter page at `/gmail` shows the connection state, the preview, and the save button. It holds receipt text only in memory for that preview and does not render the raw body.
- Vercel functions under `/api/gmail/` perform the Google OAuth redirect, the token exchange, and the Gmail fetch. They encrypt the refresh token before it leaves the function.
- PocketBase stores the ciphertext in `gmail_links.token_ciphertext`. That collection’s records API is locked. `pb_hooks/gmail_vault.pb.js` reads it only when the request presents `NOMAD_VAULT_SECRET`, and only for the signed-in user. A request body cannot name a different user.

`vercel.json` keeps `/api/*` off the Flutter rewrite. The functions have no npm dependencies.

## PocketBase files to copy

Back up `pb_data` first. Do not run `migrate down` on a database you need to keep.

1. Copy `pb_migrations/1795000000_gmail_import.js` into the instance `pb_migrations` directory, next to the existing travel migration. The new file creates `gmail_links` and `gmail_pending` when those names are absent, and adds optional provenance fields on `flights` when those fields are absent. It does not change `users`, `stays`, or `counting_settings`.
2. Copy `pb_hooks/gmail_policy.js` and `pb_hooks/gmail_vault.pb.js` into the instance `pb_hooks` directory.
3. Set the instance environment variable `NOMAD_VAULT_SECRET` to the same value you will set on Vercel. Generate it with `openssl rand -base64 32`. If this variable is empty, the vault refuses every call.
4. Optionally set `NOMAD_PUBLIC_ORIGIN` to `https://nomad-taupe-omega.vercel.app`. That value is the default when the variable is absent. It is the allowlist root for the page the browser returns to after Google’s redirect.
5. Restart the instance so the migration runs and the hook loads.

Confirm in the PocketBase admin UI that `gmail_links` and `gmail_pending` exist and that their list/view/create/update/delete rules are locked (admin only). Confirm `flights` gained `gmail_message_id`, `gmail_from`, `gmail_date`, `itinerary_ref`, `passenger_name`, `supersedes_external_id`, and `receipt_kind`. Existing flight rows stay as they were.

This repository’s check of that migration used a disposable PocketBase 0.40.6 process. GitHub’s public releases did not include a 0.41.1 asset on 14 Nov 2026. The live instance reports 0.41.1. The migration uses the same collection API as the travel migration that is already on that instance. Apply it yourself. Do not point this repo’s script at the live database.

## Vercel environment

Set these on the Vercel project for Production and Preview. They are not PocketBase superuser credentials.

| Name | Value |
| --- | --- |
| `GOOGLE_OAUTH_CLIENT_ID` | Web client id from the step below |
| `GOOGLE_OAUTH_CLIENT_SECRET` | Web client secret |
| `GMAIL_TOKEN_KEY` | `openssl rand -base64 32` (32 bytes after base64 decode; this is the AES-256-GCM key) |
| `NOMAD_VAULT_SECRET` | The same secret as on PocketHost |
| `POCKETBASE_ORIGIN` | `https://nomad.pockethost.io` |
| `NOMAD_PUBLIC_ORIGIN` | `https://nomad-taupe-omega.vercel.app` |
| `GOOGLE_OAUTH_REDIRECT_URI` | `https://nomad-taupe-omega.vercel.app/api/gmail/callback` |

Redeploy after saving them. An empty client id makes `/api/gmail/status` return `not_configured` and the page says Gmail is not set up. No mailbox is read.

`GOOGLE_OAUTH_REDIRECT_URI` is the address Google redirects to. It stays on the production host even when the traveler starts from a preview. The signed state carries the preview origin, and the callback sends the browser back there only when that origin is the production host or a `nomad-taupe-omega-…vercel.app` preview host. The authorization code is not put on that second hop.

Google does not accept a wildcard redirect URI. You do not need to register each preview while `GOOGLE_OAUTH_REDIRECT_URI` is the production callback. Register a preview callback only if you clear that variable and want Google to redirect straight at the preview.

## Google Cloud OAuth client

1. Open [Google Cloud Console](https://console.cloud.google.com/) and create or choose a project.
2. Enable the Gmail API for that project (APIs & Services → Library → Gmail API).
3. APIs & Services → OAuth consent screen.
   - User type: External.
   - Publishing status: Testing. Leave it in Testing. A Testing app can only be used by listed test users, which avoids the restricted-scope verification review while you are the only traveler.
   - Add the Google account that owns the mailbox as a Test user.
   - App name can be Nomadic Residence. The support email is that same account.
   - Scopes: add only `https://www.googleapis.com/auth/gmail.readonly`. Do not add Gmail modify, send, or the full `https://mail.google.com/` scope.
4. APIs & Services → Credentials → Create credentials → OAuth client ID.
   - Application type: Web application.
   - Authorized redirect URIs, one per line, exactly:
     - `https://nomad-taupe-omega.vercel.app/api/gmail/callback`
     - A preview, only if that preview itself receives the Google redirect: `https://<preview-host>/api/gmail/callback`
     - A local broker, only if you run the Node functions yourself: `http://127.0.0.1:<port>/api/gmail/callback`
5. Copy the client id and client secret into the Vercel variables above. Do not commit them.

In Testing mode, Google shows an unverified-app warning because `gmail.readonly` is a restricted scope. The test user can continue. Production publishing would require Google’s restricted-scope verification. That is not required for the owner’s own test user.

## Using it

1. Sign in to the database on the site.
2. Open Records → Gmail receipts.
3. Connect Gmail. Google asks for read-only access. The return to the site does not import anything.
4. Scan receipts. Check the legs to keep. Fix a missing time zone yourself when the receipt did not state one. Save. The flights appear under Flights as “Needs review” and booking-only.
5. Disconnect removes the ciphertext and asks Google to revoke the refresh token. You can also remove Nomadic Residence at [Google Account permissions](https://myaccount.google.com/permissions).

Practice data can open “Review fictional receipts” without a mailbox. Those rows are labeled fictional. Copying them into a connected database needs an extra confirmation. They are not a substitute for the live scan.

## What was verified without a Google client

- Parser fixtures for Air Canada, EVA Air, Asiana, United, Trip.com, LOT, and Shenzhen Airlines, including an amendment, a cancellation, a duplicate, ambiguous times, ambiguous airports, and timezone abbreviations.
- Repeat imports do not create a second row and do not mark a flight accepted.
- A revoked or disconnected link does not call Gmail. A preview owned by another account is not saved.
- The vault hook on a disposable database: wrong secret is 403, the records API for `gmail_links` is 403, user B does not receive user A’s ciphertext, a replayed connection attempt is refused, and disconnect clears the ciphertext.
- Node tests for encryption, HTML script stripping, PDF text, the OAuth URL scope, and scan responses that omit the refresh token.

The live consent screen, the real Gmail API, and a scan of a real mailbox were not run. No Google client was created in this change, and no request was sent to the owner’s mailbox or to the owner’s travel records.
