# Changelog

## 2.0.0 — unreleased

The repo grows from a session-level reference configuration into the full
installable issue → Claude → PR build system: three cumulative adoption tiers,
an idempotent manifest-stamping installer (`install.sh`), versioned
coding-standards distribution, generalized pipeline commands and ops drivers
extracted from a production pipeline, and a hosted GitHub Actions builder
variant. v1 content survives under `tiers/1-session/` and `global/`; see the
v1 → v2 map in the README.

Adopter-facing additions: `docs/getting-started.md` walks the first run from
install to merged PR, and `install.sh` prints the next steps for the tier it
just installed. Two rough edges are fixed alongside them. The tier-1 Stop hook
ships inert instead of hardcoding `bun typecheck`, and the tier-3 drivers
install executable so the plist's documented cron line works.
