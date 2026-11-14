#!/usr/bin/env python3
"""Disposable PocketBase check for the Gmail vault.

This does not call Google and does not touch https://nomad.pockethost.io.
The vault secret and user passwords stay in this process and are not printed.
"""

from __future__ import annotations

import json
import os
import shutil
import signal
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PB = Path(os.environ.get("POCKETBASE_BIN", Path.home() / "sdk/pocketbase/pocketbase"))
MIGRATIONS = ROOT / "pb_migrations"
HOOKS = ROOT / "pb_hooks"
SECRET = "local-disposable-vault-secret"
ORIGIN = "https://nomad-taupe-omega.vercel.app"


class Failure(Exception):
    pass


def request(method: str, url: str, body: dict | None = None, headers: dict | None = None):
    data = None if body is None else json.dumps(body).encode()
    sent = {"Content-Type": "application/json"}
    if headers:
        sent.update(headers)
    req = urllib.request.Request(url, data=data, headers=sent, method=method)
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            raw = response.read().decode()
            parsed = json.loads(raw) if raw else {}
            return response.status, parsed
    except urllib.error.HTTPError as error:
        raw = error.read().decode()
        try:
            parsed = json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            parsed = {"message": "non-json error"}
        if isinstance(parsed, dict):
            parsed.pop("token", None)
            parsed.pop("ciphertext", None)
        return error.code, parsed


def wait_health(base: str, log_path: Path) -> None:
    for _ in range(80):
        try:
            status, payload = request("GET", f"{base}/api/health")
            if status == 200 and payload.get("code") == 200:
                return
        except Exception:
            pass
        time.sleep(0.1)
    raise Failure(f"health failed\n{log_path.read_text()[-4000:]}")


def main() -> None:
    if not PB.exists():
        raise SystemExit(f"PocketBase binary not found at {PB}")
    work = Path(tempfile.mkdtemp(prefix="nomadic-gmail-"))
    base = "http://127.0.0.1:18093"
    directory = work / "pb"
    (directory / "pb_migrations").mkdir(parents=True)
    (directory / "pb_hooks").mkdir()
    (directory / "pb_public").mkdir()
    for path in MIGRATIONS.glob("*.js"):
        shutil.copy(path, directory / "pb_migrations" / path.name)
    for path in HOOKS.glob("*.js"):
        shutil.copy(path, directory / "pb_hooks" / path.name)
    log_path = directory / "server.log"
    log = log_path.open("w")
    env = os.environ.copy()
    env["NOMAD_VAULT_SECRET"] = SECRET
    env["NOMAD_PUBLIC_ORIGIN"] = ORIGIN
    proc = subprocess.Popen(
        [
            str(PB),
            "serve",
            "--http",
            "127.0.0.1:18093",
            "--dir",
            str(directory / "pb_data"),
            "--migrationsDir",
            str(directory / "pb_migrations"),
            "--hooksDir",
            str(directory / "pb_hooks"),
            "--hooksWatch=false",
            "--automigrate=false",
            "--publicDir",
            str(directory / "pb_public"),
        ],
        stdout=log,
        stderr=subprocess.STDOUT,
        text=True,
        env=env,
    )
    try:
        wait_health(base, log_path)
        password = "local-disposable-user-password"
        subprocess.run(
            [
                str(PB),
                "superuser",
                "upsert",
                "super@example.test",
                password,
                "--dir",
                str(directory / "pb_data"),
                "--automigrate=false",
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=env,
        )
        proc.send_signal(signal.SIGTERM)
        proc.wait(timeout=5)
        proc = subprocess.Popen(
            [
                str(PB),
                "serve",
                "--http",
                "127.0.0.1:18093",
                "--dir",
                str(directory / "pb_data"),
                "--migrationsDir",
                str(directory / "pb_migrations"),
                "--hooksDir",
                str(directory / "pb_hooks"),
                "--hooksWatch=false",
                "--automigrate=false",
                "--publicDir",
                str(directory / "pb_public"),
            ],
            stdout=log,
            stderr=subprocess.STDOUT,
            text=True,
            env=env,
        )
        wait_health(base, log_path)
        status, auth = request(
            "POST",
            f"{base}/api/collections/_superusers/auth-with-password",
            {"identity": "super@example.test", "password": password},
        )
        if status != 200 or "token" not in auth:
            raise Failure(f"superuser auth failed {status}")
        super_token = auth["token"]

        def make_user(email: str) -> tuple[str, str]:
            status, payload = request(
                "POST",
                f"{base}/api/collections/users/records",
                {
                    "email": email,
                    "password": password,
                    "passwordConfirm": password,
                    "verified": True,
                },
                {"Authorization": super_token},
            )
            if status not in (200, 201):
                raise Failure(f"create {email} failed {status} {payload.get('message')}")
            status, signed = request(
                "POST",
                f"{base}/api/collections/users/auth-with-password",
                {"identity": email, "password": password},
            )
            if status != 200 or "token" not in signed:
                raise Failure(f"auth {email} failed {status}")
            return signed["token"], signed["record"]["id"]

        token_a, user_a = make_user("owner-a@example.test")
        token_b, _user_b = make_user("owner-b@example.test")

        def vault(token: str | None, path: str, body: dict, secret: str = SECRET):
            headers = {"X-Nomad-Vault-Secret": secret}
            if token:
                headers["Authorization"] = token
            return request("POST", f"{base}{path}", body, headers)

        status, listed = request(
            "GET",
            f"{base}/api/collections/gmail_links/records",
            headers={"Authorization": token_a},
        )
        if status != 403:
            raise Failure(f"owner list of gmail_links returned {status}")
        if "ciphertext" in json.dumps(listed):
            raise Failure("gmail_links list exposed a ciphertext")

        status, denied = vault(
            token_a,
            "/api/nomad/gmail/vault",
            {"op": "status"},
            secret="wrong",
        )
        if status != 403:
            log.flush()
            tail = log_path.read_text()[-2500:]
            raise Failure(
                f"wrong secret returned {status} {denied.get('message')}\n{tail}"
            )

        nonce = "a" * 43
        status, begun = vault(
            token_a,
            "/api/nomad/gmail/vault",
            {
                "op": "begin",
                "nonce": nonce,
                "returnTo": ORIGIN,
                "user": user_a,
            },
        )
        if status != 200:
            raise Failure(f"begin failed {status} {begun.get('message')}")

        cipher = "A" * 40
        status, completed = vault(
            None,
            "/api/nomad/gmail/vault/complete",
            {
                "pendingId": nonce,
                "ciphertext": cipher,
                "googleEmail": "person@example.test",
                "scope": "https://www.googleapis.com/auth/gmail.readonly",
                "user": "someone-else",
            },
        )
        if status != 200 or completed.get("status") != "connected":
            raise Failure(f"complete failed {status} {completed.get('message')}")
        if "ciphertext" in completed:
            raise Failure("complete returned ciphertext")

        status, again = vault(
            None,
            "/api/nomad/gmail/vault/complete",
            {
                "pendingId": nonce,
                "ciphertext": cipher,
                "googleEmail": "person@example.test",
                "scope": "https://www.googleapis.com/auth/gmail.readonly",
            },
        )
        if status == 200:
            raise Failure("a consumed connection attempt was accepted again")

        status, own = vault(token_a, "/api/nomad/gmail/vault", {"op": "get"})
        if status != 200 or own.get("ciphertext") != cipher:
            raise Failure("owner could not read their own vault row")
        status, other = vault(token_b, "/api/nomad/gmail/vault", {"op": "get", "user": user_a})
        if status != 200:
            raise Failure(f"other owner get failed closed with {status}")
        if other.get("ciphertext"):
            raise Failure("other owner received ciphertext")
        if other.get("status") not in ("missing", "disconnected"):
            raise Failure(f"other owner saw status {other.get('status')}")

        status, created = request(
            "POST",
            f"{base}/api/collections/flights/records",
            {
                "user": user_a,
                "flight_number": "AC123",
                "from_iata": "YYZ",
                "to_iata": "LHR",
                "from_country": "CA",
                "to_country": "GB",
                "depart_local": "2026-03-02T18:40",
                "arrive_local": "2026-03-03T06:55",
                "depart_timezone": "America/Toronto",
                "arrive_timezone": "Europe/London",
                "evidence_status": "booking_only",
                "inference": "none",
                "review_state": "pending",
                "notes": "Gmail booking. Planned travel, not presence.",
                "external_id": "g:fixture:0",
                "gmail_message_id": "fixture",
                "gmail_from": "tickets@aircanada.example",
                "gmail_date": "2026-02-01T15:00:00Z",
                "itinerary_ref": "AB12CD",
                "passenger_name": "Jordan Example",
                "receipt_kind": "booking",
            },
            {"Authorization": token_a},
        )
        if status not in (200, 201):
            raise Failure(f"flight create failed {status} {created.get('message')}")
        if created.get("review_state") != "pending":
            raise Failure("imported flight was not pending")
        flight_id = created["id"]
        status, stolen = request(
            "GET",
            f"{base}/api/collections/flights/records/{flight_id}",
            headers={"Authorization": token_b},
        )
        if status != 404:
            raise Failure(f"other owner read the flight with {status}")

        status, revoked = vault(token_a, "/api/nomad/gmail/vault", {"op": "disconnect"})
        if status != 200 or revoked.get("status") != "revoked":
            raise Failure(f"disconnect failed {status}")
        if revoked.get("ciphertext"):
            raise Failure("disconnect returned ciphertext")
        status, after = vault(token_a, "/api/nomad/gmail/vault", {"op": "get"})
        if after.get("ciphertext"):
            raise Failure("revoked vault still returned ciphertext")
        if after.get("status") != "revoked":
            raise Failure("revoked status was not stored")
        print("gmail vault rules passed")
    finally:
        if proc.poll() is None:
            proc.send_signal(signal.SIGTERM)
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
        log.close()
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    try:
        main()
    except Failure as error:
        raise SystemExit(str(error)) from error
