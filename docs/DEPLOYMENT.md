# Deployment

Vercel is the static host for the Flutter web build. PocketBase stays on PocketHost. `vercel.json` sets `framework` to null, `outputDirectory` to `build/web`, and a catch-all rewrite to `/index.html`. Vercel serves an existing file before applying rewrites ([Project configuration](https://vercel.com/docs/project-configuration/vercel-json)), so `main.dart.js` and the other build assets are not replaced by `index.html`.

`scripts/vercel_build_web.sh` downloads the official Flutter 3.47.9 Linux stable archive, checks its SHA-256 (`25ed8c3c29d51a7353f2a944310b478af8214920639524b19c50a19e6c044c5a`), and puts that SDK on `PATH` ahead of any other `flutter`. A binary already installed in the image is not used. On Amazon Linux 2023, the Vercel build image, the script installs `curl`, `git`, `xz`, `unzip`, or `sha256sum` with `dnf` only when a command is missing. `vercel.json` sets `installCommand` to an empty string so Vercel does not run a Node install; this repo has no `package.json`. The script then runs `flutter pub get` and:

```bash
flutter build web --release --base-href /
```

That command does not pass `ALLOW_LOCAL_POCKETBASE`. Release builds cannot register a loopback database.

The script was run on 8 Nov 2026 on a machine with no Flutter SDK installed. A decoy `flutter` was first on `PATH`. The script used Flutter 3.47.9 (framework revision `c197ca5199`, Dart 3.13.7) and produced `build/web`. The ELF binaries in that SDK reference GLIBC symbols no newer than 2.18. Amazon Linux 2023, the Vercel build image, provides a newer glibc, so the pin is compatible with that image. Docker was not available here, so the script was not executed inside Amazon Linux itself. This was not a Vercel deployment.

## Not deployed from this run

No Vercel project is linked and no deployment was created. This document does not claim a URL. Creating the Vercel project waits until this tree is on a ref Vercel can build. See [SOURCE_CONTROL.md](SOURCE_CONTROL.md).

The GitHub repository is https://github.com/ourhumancondition/nomad. Team `team_dEkroVVzFmqfZp6oTiqfyWm9` (Alex's projects, Hobby) has no nomad project yet.

To deploy after the code is on that GitHub repository:

1. In Vercel, create a project from `ourhumancondition/nomad` with the framework preset Other.
2. Leave the build command as `bash scripts/vercel_build_web.sh` and the output directory as `build/web`, matching `vercel.json`.
3. Do not add PocketHost superuser credentials as Vercel environment variables. The static site talks to PocketBase from the browser.
4. After the first deployment, add that origin to the PocketHost instance’s CORS Origins.

A local check of the release build is `python3 tool/serve_web.py --port 43123`.
