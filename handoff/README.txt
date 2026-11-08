Nomadic Residence source handoff
Commit: cfbd577174e4738f97a4d4e8a9218ac249bc45a6
Parent: c0100dd9453ea82bc0eebce81243e95c7d3d4dee (seed README only)
Subject: Add the Nomadic Residence Flutter web app.

This archive is the completed implementation tree. It has no .git directory,
no Flutter build or SDK cache, no node_modules, and no secrets. pubspec.lock
is included. The fictional example dataset is source, not a connected account.

cfbd577.patch is git format-patch of that commit against the seed.
Applying it expects the seed README. Copying this tree into an empty
repository is the direct way to land the same files.

PocketBase schema: pb_migrations/1794136000_create_travel_collections.js
Tests: test/ and tool/auth_rules_check.py
Docs: docs/ and README.md
