#!/usr/bin/env python3
"""Disposable two-instance PocketBase API-rule check.

This does not touch https://nomad.pockethost.io. Superuser passwords exist
only in this process and are not printed.
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


class Failure(Exception):
    pass


def request(method: str, url: str, body: dict | None = None, token: str | None = None):
    data = None if body is None else json.dumps(body).encode()
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = token
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
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
        if isinstance(parsed, dict) and "token" in parsed:
            parsed = {"message": "token redacted", "status": error.code}
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
    raise Failure(f"health failed for {base}\n{log_path.read_text()[-4000:]}")


class Instance:
    def __init__(self, name: str, port: int, work: Path, migrations: bool):
        self.name = name
        self.base = f"http://127.0.0.1:{port}"
        self.dir = work / name
        self.dir.mkdir(parents=True)
        (self.dir / "pb_migrations").mkdir()
        (self.dir / "pb_hooks").mkdir()
        (self.dir / "pb_public").mkdir()
        if migrations:
            for path in MIGRATIONS.glob("*.js"):
                shutil.copy(path, self.dir / "pb_migrations" / path.name)
        self.log_path = self.dir / "server.log"
        self.proc: subprocess.Popen[str] | None = None

    def start(self) -> None:
        self.log = self.log_path.open("a")
        self.proc = subprocess.Popen(
            [
                str(PB),
                "serve",
                "--http",
                self.base.removeprefix("http://"),
                "--dir",
                str(self.dir / "pb_data"),
                "--migrationsDir",
                str(self.dir / "pb_migrations"),
                "--hooksDir",
                str(self.dir / "pb_hooks"),
                "--hooksWatch=false",
                "--automigrate=false",
                "--publicDir",
                str(self.dir / "pb_public"),
            ],
            stdout=self.log,
            stderr=subprocess.STDOUT,
            text=True,
        )
        try:
            wait_health(self.base, self.log_path)
        except Exception:
            self.stop()
            raise

    def stop(self) -> None:
        if self.proc and self.proc.poll() is None:
            self.proc.send_signal(signal.SIGTERM)
            try:
                self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.proc.kill()
        if hasattr(self, "log"):
            self.log.close()

    def superuser(self, email: str, password: str) -> str:
        subprocess.run(
            [
                str(PB),
                "superuser",
                "upsert",
                email,
                password,
                "--dir",
                str(self.dir / "pb_data"),
                "--automigrate=false",
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        # upsert while serving may not be visible until restart; restart after.
        self.stop()
        self.start()
        status, payload = request(
            "POST",
            f"{self.base}/api/collections/_superusers/auth-with-password",
            {"identity": email, "password": password},
        )
        if status != 200 or "token" not in payload:
            raise Failure(f"{self.name} superuser auth failed with {status}")
        return payload["token"]


def main() -> None:
    if not PB.exists():
        raise SystemExit(f"PocketBase binary not found at {PB}")
    work = Path(tempfile.mkdtemp(prefix="nomadic-pb-"))
    instances: list[Instance] = []
    try:
        alpha = Instance("alpha", 18091, work, migrations=False)
        bravo = Instance("bravo", 18092, work, migrations=True)
        instances.extend([alpha, bravo])
        alpha.start()
        bravo.start()
        super_password = "local-disposable-super-password"
        user_password = "local-disposable-user-password"
        alpha_super = alpha.superuser("super-a@example.test", super_password)
        status, body = request(
            "POST",
            f"{alpha.base}/api/collections",
            {
                "name": "kept_marker",
                "type": "base",
                "fields": [{"name": "title", "type": "text", "required": False}],
            },
            alpha_super,
        )
        if status not in (200, 201):
            raise Failure(f"could not create kept_marker: {status} {body.get('message')}")
        alpha.stop()
        for path in MIGRATIONS.glob("*.js"):
            shutil.copy(path, alpha.dir / "pb_migrations" / path.name)
        alpha.start()
        alpha_super = alpha.superuser("super-a@example.test", super_password)
        bravo_super = bravo.superuser("super-b@example.test", super_password)

        def collections(base: str, token: str) -> set[str]:
            status, payload = request("GET", f"{base}/api/collections", token=token)
            if status != 200:
                raise Failure(f"list collections failed {status} {payload.get('message')}")
            items = payload if isinstance(payload, list) else payload.get("items", [])
            return {item["name"] for item in items}

        alpha_names = collections(alpha.base, alpha_super)
        for name in ("stays", "flights", "counting_settings", "kept_marker", "users"):
            if name not in alpha_names:
                raise Failure(f"alpha is missing {name}; has {sorted(alpha_names)}")
        bravo_names = collections(bravo.base, bravo_super)
        if "kept_marker" in bravo_names:
            raise Failure("bravo unexpectedly has alpha's kept_marker collection")
        if "stays" not in bravo_names:
            raise Failure("bravo migration did not create stays")

        def make_user(base: str, super_token: str, email: str) -> tuple[str, str]:
            status, payload = request(
                "POST",
                f"{base}/api/collections/users/records",
                {
                    "email": email,
                    "password": user_password,
                    "passwordConfirm": user_password,
                    "verified": True,
                },
                super_token,
            )
            if status not in (200, 201):
                raise Failure(f"create {email} failed {status} {payload.get('message')}")
            status, auth = request(
                "POST",
                f"{base}/api/collections/users/auth-with-password",
                {"identity": email, "password": user_password},
            )
            if status != 200 or "token" not in auth or "record" not in auth:
                raise Failure(f"auth {email} failed {status}")
            return auth["token"], auth["record"]["id"]

        token_a, user_a_id = make_user(alpha.base, alpha_super, "user-a@example.test")
        token_b, user_b_id = make_user(alpha.base, alpha_super, "user-b@example.test")
        token_c, _user_c_id = make_user(bravo.base, bravo_super, "user-c@example.test")

        def stay_body(user_id: str) -> dict:
            return {
                "user": user_id,
                "country_code": "PT",
                "start_date": "2026-01-01",
                "end_date": "2026-01-03",
                "role": "primary",
                "evidence_status": "confirmed",
                "inference": "none",
                "phase": "actual",
                "timezone": "Europe/Lisbon",
                "notes": "fixture",
                "external_id": "fixture-a",
                "source": "manual",
            }

        status, created = request(
            "POST",
            f"{alpha.base}/api/collections/stays/records",
            stay_body(user_a_id),
            token_a,
        )
        if status not in (200, 201):
            raise Failure(f"user A create failed {status} {created.get('message')}")
        stay_id = created["id"]

        def assert_no_leak(status: int, payload: dict, label: str) -> None:
            items = payload.get("items", []) if isinstance(payload, dict) else []
            if any(isinstance(item, dict) and item.get("id") == stay_id for item in items):
                raise Failure(f"{label} leaked the stay")
            if isinstance(payload, dict) and payload.get("id") == stay_id:
                raise Failure(f"{label} leaked the stay")
            if status == 200 and items:
                raise Failure(f"{label} returned records")
            if status not in (200, 401, 403, 404):
                raise Failure(f"{label} unexpected status {status}")

        status, payload = request("GET", f"{alpha.base}/api/collections/stays/records")
        assert_no_leak(status, payload, "anonymous list")
        status, payload = request("GET", f"{alpha.base}/api/collections/stays/records/{stay_id}")
        assert_no_leak(status, payload, "anonymous view")
        if status not in (401, 403, 404):
            raise Failure(f"anonymous view should fail closed, got {status}")
        status, payload = request(
            "POST",
            f"{alpha.base}/api/collections/stays/records",
            stay_body(user_a_id),
        )
        if status in (200, 201):
            raise Failure("anonymous create succeeded")

        status, payload = request(
            "GET",
            f"{alpha.base}/api/collections/stays/records",
            token=token_b,
        )
        assert_no_leak(status, payload, "user B list")
        status, payload = request(
            "GET",
            f"{alpha.base}/api/collections/stays/records/{stay_id}",
            token=token_b,
        )
        if status not in (401, 403, 404):
            raise Failure(f"user B view returned {status}")
        status, payload = request(
            "PATCH",
            f"{alpha.base}/api/collections/stays/records/{stay_id}",
            {"notes": "changed", "user": user_b_id},
            token_b,
        )
        if status not in (401, 403, 404):
            raise Failure(f"user B update returned {status}")
        status, payload = request(
            "DELETE",
            f"{alpha.base}/api/collections/stays/records/{stay_id}",
            token=token_b,
        )
        if status not in (401, 403, 404):
            raise Failure(f"user B delete returned {status}")
        status, payload = request(
            "POST",
            f"{alpha.base}/api/collections/stays/records",
            stay_body(user_a_id),
            token_b,
        )
        if status in (200, 201):
            raise Failure("user B created a stay owned by user A")

        status, payload = request(
            "PATCH",
            f"{alpha.base}/api/collections/stays/records/{stay_id}",
            {"notes": "owner edit", "user": user_a_id},
            token_a,
        )
        if status != 200:
            raise Failure(f"owner update failed {status} {payload.get('message')}")

        status, payload = request(
            "GET",
            f"{bravo.base}/api/collections/stays/records",
            token=token_a,
        )
        assert_no_leak(status, payload, "alpha token listing bravo")
        status, payload = request(
            "POST",
            f"{bravo.base}/api/collections/users/auth-refresh",
            token=token_a,
        )
        if status != 401:
            raise Failure(f"alpha token was accepted by bravo auth-refresh ({status})")
        status, payload = request(
            "POST",
            f"{bravo.base}/api/collections/stays/records",
            stay_body(user_a_id),
            token_a,
        )
        if status in (200, 201):
            raise Failure("alpha token created a stay on bravo")
        status, payload = request(
            "GET",
            f"{bravo.base}/api/collections/stays/records",
            token=bravo_super,
        )
        items = payload.get("items", []) if isinstance(payload, dict) else []
        if items:
            raise Failure("bravo superuser can see stays that were written only to alpha")
        status, payload = request(
            "GET",
            f"{alpha.base}/api/collections/stays/records",
            token=token_c,
        )
        assert_no_leak(status, payload, "bravo token listing alpha")
        status, payload = request(
            "POST",
            f"{alpha.base}/api/collections/users/auth-refresh",
            token=token_c,
        )
        if status != 401:
            raise Failure(f"bravo token was accepted by alpha auth-refresh ({status})")

        alpha.stop()
        alpha.start()
        alpha_super = alpha.superuser("super-a@example.test", super_password)
        names = collections(alpha.base, alpha_super)
        if "kept_marker" not in names or "stays" not in names:
            raise Failure("restart dropped a collection")
        status, payload = request(
            "GET",
            f"{alpha.base}/api/collections/stays/records/{stay_id}",
            token=alpha_super,
        )
        if status != 200 or payload.get("country_code") != "PT":
            raise Failure("restart lost the fixture stay")
        anon_list, _ = request("GET", f"{alpha.base}/api/collections/stays/records")
        anon_view, _ = request(
            "GET",
            f"{alpha.base}/api/collections/stays/records/{stay_id}",
        )
        foreign_list, _ = request(
            "GET",
            f"{bravo.base}/api/collections/stays/records",
            token=token_a,
        )
        print(
            "auth rules ok: "
            f"anonymous list {anon_list}, anonymous view {anon_view}, "
            f"foreign-instance list {foreign_list}, foreign auth-refresh 401, "
            "cross-user view/update/delete denied, separate SQLite files"
        )
    finally:
        for instance in instances:
            instance.stop()
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    try:
        main()
    except Failure as error:
        raise SystemExit(str(error))
