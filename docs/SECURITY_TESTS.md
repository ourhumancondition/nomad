# Local access tests

These tests used disposable PocketBase 0.40.6 processes on `127.0.0.1:18091` and `127.0.0.1:18092`, each with its own data directory. They do not validate the production instance. No request in this test carries a superuser token out of the process, and the passwords are not printed.

Command: `python3 tool/auth_rules_check.py`

Observed on 8 Nov 2026:

- The additive migration created `stays`, `flights`, and `counting_settings` and left a pre-existing `kept_marker` collection in place.
- The second data directory did not contain `kept_marker`. Its superuser list of `stays` was empty after a stay had been written on the first directory.
- Restarting the first process kept both `kept_marker` and the fixture stay.
- Anonymous `GET /api/collections/stays/records` returned **200** and an empty page. Anonymous `GET` of the fixture id returned **404**. Anonymous create did not succeed.
- A second user on the same instance could not view, update, or delete the first user’s stay, and could not create a stay whose `user` field was the first user. The owner could update their own stay.
- A user token from the first instance sent to the second instance’s `auth-refresh` returned **401**. The same token’s list of stays on the second instance returned **200** with an empty page, which is the guest list-rule behavior, and create did not succeed. The token was not accepted as that instance’s user.
- The reverse direction, second-instance token against the first instance, also failed `auth-refresh` with 401 and did not return the fixture stay.

Flutter unit and widget tests cover the date engine, flight proposals, CSV, the endpoint allowlist, and the example-dataset gate. `flutter analyze` reported no issues. Those tests do not open a network connection.

Production security was not validated. The only live call was `GET https://nomad.pockethost.io/api/health`, which returned HTTP 200 and `code` 200.
