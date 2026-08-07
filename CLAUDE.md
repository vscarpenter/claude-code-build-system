# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A **distribution**, not an application. It packages an issue → Claude → PR delivery pipeline as three cumulative adoption tiers that `install.sh` copies into *someone else's* repo.

The consequence, and the thing to internalize first: **almost everything under `tiers/` is payload.** Those files are not this repo's configuration — they are artifacts shipped to adopters.

- `.github/workflows/ci.yml` is this repo's CI. `tiers/2-pipeline/.github/workflows/*.yml` are payload, and never run here.
- `tiers/1-session/CLAUDE.md` is a **template for adopters**, not instructions for working in this repo. This file is.
- `tiers/1-session/.claude/` is payload. This repo has no `.claude/` of its own.
- `standards/coding-standards.md` is payload too — the one shipped file that lives outside `tiers/`.
- Payload is prose and config, so most changes are reviewed by reading, not by running. The test suite checks that files exist, install to the right place, and contain the strings other pieces depend on.

Shipped code is bash, jq, and a little Node (`.cjs`). No package manager, no build step, no dependencies beyond `jq`.

## Commands

```bash
bash tests/run-tests.sh                      # the whole suite (~6s, 21 tests); CI runs exactly this
./install.sh --tier 1 --target /tmp/somerepo # install (tiers cumulative: 2 includes 1)
./install.sh --tier 1 --target X --dry-run   # print the plan, write nothing
./install.sh --tier 1 --target X --force     # adopt/overwrite files the manifest does not track
./install.sh --upgrade --target X            # re-sync unmodified files, KEEP modified ones
bash -n tiers/3-ops/local/builder-run.sh     # syntax-check a shipped script
```

**Running one test.** There is no filter flag — `main()` discovers every `test_*` function via `declare -F`. The suite is fast enough to run whole. To iterate on one, temporarily replace the trailing `main` call (last line) with `run_test test_<name>`; the harness resolves `ROOT` from `$0`, so the script must stay in `tests/`.

Each test builds a throwaway git repo via `make_target_repo`. `gh` is stubbed with `make_gh_mock`, so no test touches the network or a real GitHub repo.

## Architecture: the installer contract

`install.sh` is the whole product surface. Three ideas carry it.

**1. Destination is position.** `plan_files()` walks a tier directory and emits `src<TAB>dest` where `dest` is the path *relative to the tier root*, because the tier trees mirror target-repo layout. There is no path table to update — a new shipped file's destination is decided by where you put it under `tiers/`. Five exceptions: one emitted ahead of the tree walk, four in the `case`.

| Source | Destination | Why |
|---|---|---|
| `standards/coding-standards.md` | `coding-standards.md` (tier 1) | the only source outside `tiers/`; keeps one canonical copy |
| `tiers/2-pipeline/labels.json` | *(not installed)* | installer input — read by `apply_labels()` |
| `tiers/3-ops/local/*` | `scripts/build-system/*` | drivers live under the target's `scripts/` |
| `tiers/3-ops/actions/*` | `.github/workflows/*` | the hosted builder variant |
| `tiers/3-ops/docs/*` | `docs/*` | operating spec |

Tier 3 installs **only** those mapped paths; an unmapped file under `tiers/3-ops/` is silently skipped.

**2. The manifest is three-way merge state.** `.build-system.json` in the target records the system version, tier, a `config` block, and a sha256 per managed file. Every install decides one of three actions per file by comparing the recorded hash to the file on disk:

- `INSTALL` — absent, or tracked and unmodified (re-sync), or `--force`
- `KEEP` — tracked but locally modified (adaptations survive upgrades)
- `SKIP` — present but untracked (never clobber a file the installer did not write)

`config` (`verifyCommands`, `protectedPaths`, `branchPrefix`) is preserved across upgrades once filled in, and is read **at runtime** by `/build-next` and `/triage-prs`. The agents refuse to act while it still contains `REPLACE:`.

**3. Upgrade is install, minus the version guard.** `do_upgrade()` reads the tier from the manifest and calls `do_install()`. Do not grow a second code path for it (see `tasks/lessons.md`).

## Architecture: the system being shipped

Read `docs/architecture.md` for the narrative. The shape, so you can place a change:

A GitHub issue form (`change_request.yml`) forces a contract: acceptance criteria, constraints, rollback, risk tier. `apply-risk-label.yml` parses the risk dropdown via `parse-risk-tier.cjs` and applies one of four `risk:*` labels. `/build-next` plans, stops at **Gate 1** (`plan:pending` → human swaps to `plan:approved`) unless the tier is docs/chore, then builds test-first in an isolated worktree and opens a PR. **Gate 2** (the merge) is always human. `/triage-prs` clears mechanical CI failures nightly. Tier-3 drivers (`builder-run.sh`, `triage-run.sh`) pre-check labels with `gh` and exit without spending a token when there is no work.

**Labels are the durable state** — the 15 in `labels.json` are the entire protocol between human and agent. Prose in a comment is invisible to the fleet.

**Two safety invariants govern anything you add to the agent commands:** a fix that does not verify locally is reverted and escalated, and every agent output re-enters the same gates. Nothing in this system merges. Nothing runs `--dangerously-skip-permissions`. Keep it that way — and preserve the fail-safe defaults (a `gh` failure counts as *no work*, ambiguous PR provenance counts as *untrusted*).

## Constraints that are easy to violate

- **Bash 3.2 (macOS default).** No associative arrays, no `${var^^}`. Lookups go through `jq` or temp files.
- **`test_generalized_artifacts_have_no_gsd_residue`** greps all of `tiers/` for `gsd|cloudfront|taskmanager`. The payload was extracted from a production repo; anything you copy in must be generalized first. The test fails loudly if not.
- **The standards ship from outside the tier tree.** `standards/coding-standards.md` is the only copy, emitted directly by `plan_files()` for tier 1; `test_standards_have_exactly_one_copy_in_the_repo` fails if a duplicate reappears under `tiers/`. If you add another out-of-tree source, emit it **before** the tree walk: as a trailing `[ "$1" = N ] && printf`, a false test returns 1 and aborts the install for every other tier under `set -e` + `pipefail`.
- **Bumping `VERSION` touches four files:** `VERSION`, the literal `assert_eq "2.0.0"` in `tests/run-tests.sh`, the distribution header in `standards/coding-standards.md`, and `CHANGELOG.md`.
- **Tests that mutate `$ROOT`** (VERSION bumps, upstream-file edits) must restore it before asserting — a failing test otherwise poisons the working tree for every later test. See `test_upgrade_resyncs_unmodified_and_preserves_modified`.
- **Cross-file vocabulary.** Risk tier names must match in `labels.json`, the `change_request.yml` dropdown, `RISK_TIERS` in `parse-risk-tier.cjs`, and `build-next.md`. Label names are referenced by name across both agent commands, the workflows, and the docs. Renaming is one deliberate pass, not a local edit.
- **`branchPrefix` is configurable except in one place.** `failing-agent-prs.cjs` hardcodes `claude/` in `isAgentBranch()`, so a target repo using a custom prefix gets a night-shift pre-check that always reports zero work. Touch this only deliberately.
- **Shipped shell scripts need the exec bit in git**, and `chmod` is denied by the permission config. Use `git update-index --chmod=+x <path>`. (`tiers/1-session/.claude/hooks/*.sh` are `100755`; `tiers/3-ops/local/*.sh` are currently `100644`.)

## Conventions

- **Commits:** Conventional Commits with a scope — `docs(tasks):`, `chore(release):`, `feat(installer):`. One logical unit per commit.
- **Working memory** lives in `tasks/`: `todo.md` carries a "Resuming From Here" block (done / next / blockers / assumptions), `lessons.md` carries durable gotchas. Read both when resuming. `tasks/spec-*.md` and `tasks/plan-*.md` are the v2 build's frozen record — historical, not live instructions.
- **Docs style** (enforced by review, per `README.md`): every new pattern gets a "what it does, why it exists, what it costs" paragraph. Keep examples minimal and commented; this repo is a teaching tool, not a kitchen sink.
- **Comments in shipped code explain the trap**, not the mechanism — why the PATH is appended rather than prepended, why a `gh` failure fails safe to zero. Match that density.
- `docs/` splits by audience: `architecture` (how it works) · `adoption` (tiers, manifest) · `runbook` (operating it, failure modes, cost) · `customizing` (adapting it) · `rationale` (why, including what was deliberately cut).
