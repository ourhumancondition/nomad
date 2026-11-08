#!/usr/bin/env python3
"""Serve the Flutter web release with an SPA fallback for local checks."""

from __future__ import annotations

import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=43123)
    parser.add_argument("--root", type=Path, default=Path("build/web"))
    args = parser.parse_args()
    root = args.root.resolve()

    class Handler(SimpleHTTPRequestHandler):
        def __init__(self, *a, **k):
            super().__init__(*a, directory=str(root), **k)

        def do_GET(self) -> None:
            path = self.path.split("?", 1)[0]
            target = (root / path.lstrip("/")).resolve()
            if not str(target).startswith(str(root)) or not target.is_file():
                self.path = "/index.html"
            super().do_GET()

    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"serving {root} at http://127.0.0.1:{args.port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
