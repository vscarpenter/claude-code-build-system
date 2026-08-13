# Changelog

## 3.0.0 - 2026-08-08

Version 3 replaces prompt-owned delivery with a deterministic controller. The
controller now owns queue selection, atomic remote-ref leases, per-run
worktrees, contract/plan/approval digests, protected-path policy, verification,
Git delivery, pull-request postconditions, label transitions, budgets,
reconciliation, and hash-chained evidence. Claude and Codex are bounded worker
adapters without GitHub credentials or Git/GitHub tools; provider prose is
never accepted as proof that a PR exists.

The installer now rejects repository subdirectories and symlink escapes,
preflights and rolls back target writes, preserves local modifications across
repeated upgrades, restores executable modes, refuses tier downgrades, and
writes collision-resistant JSON runtime configuration instead of sourcing
shell code. Tier 3 runs an integrity-checked immutable controller copy.

The former autonomous night-shift fixer is now provenance-bound diagnosis
only. It reports failing PRs only when repository, PR number, branch, and head
SHA match controller-authored evidence. This deliberate capability reduction
removes the last scheduled path that handed a model Git/GitHub delivery powers.

Portability is explicit: Claude and Codex have controller adapters; OpenCode
and supported GitHub Copilot surfaces receive `AGENTS.md` and shared Agent
Skills but are not advertised as autonomous until native adapters pass the
same conformance suite. A new interactive HTML explainer and flow visualization
make the trust boundaries and proof ledger inspectable.

First-run guidance now keeps the distribution and target repositories
explicit, separates Tier 1 from the issue-to-PR path, checks one selected
harness instead of requiring both, documents the complete manifest config and
GitHub protection setup, and gives installer output a stable walkthrough URL.

## 2.0.0 - 2026-08-07

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
