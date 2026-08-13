# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A **distribution**, not an application. It packages an issue → agent → PR delivery pipeline as three cumulative adoption tiers that `install.sh` copies into *someone else's* repo. Since v3 that pipeline is a deterministic Node controller with Claude and Codex as bounded workers, so treat anything Claude-specific in the payload as a bug unless it is an adapter.

The consequence, and the thing to internalize first: **almost everything under `tiers/` is payload.** Those files are not this repo's configuration — they are artifacts shipped to adopters.

- `.github/workflows/ci.yml` is this repo's CI. `tiers/2-pipeline/.github/workflows/*.yml` are payload, and never run here.
- `tiers/1-session/CLAUDE.md` is a **template for adopters**, not instructions for working in this repo. This file is.
- `tiers/1-session/.claude/` is payload. This repo has no `.claude/` of its own.
- `standards/coding-standards.md` is payload too — the one shipped file that lives outside `tiers/`.
- Payload is *partly* prose and config, and that part is reviewed by reading. The Bash suite checks that files exist, install to the right place, and contain the strings other pieces depend on. The nine shipped `.cjs` files are different: they carry the controller's real logic, and `tests/controller-tests.cjs` exercises them as a dedicated Node suite that `test_controller_node_suite` shells out to. Changing anything under `tiers/2-pipeline/scripts/` means running that suite, not reading a diff.

Shipped code is bash, jq, and a little Node (`.cjs`). No package manager, no build step, no dependencies beyond `jq`.

## Commands

```bash
bash tests/run-tests.sh                      # the whole suite; CI runs exactly this. Needs jq and node
node tests/controller-tests.cjs              # just the controller suite, when iterating on scripts/
./install.sh --tier 1 --target /tmp/somerepo # install (tiers cumulative: 2 includes 1)
./install.sh --tier 1 --target X --dry-run   # print the plan, write nothing
./install.sh --tier 1 --target X --force     # adopt/overwrite files the manifest does not track
./install.sh --upgrade --target X            # re-sync unmodified files, KEEP modified ones
bash -n tiers/3-ops/local/builder-run.sh     # syntax-check a shipped script
```

**Running one test.** `main()` discovers every `test_*` function via `declare -F` and filters on `TEST_FILTER`, so `TEST_FILTER=test_upgrade bash tests/run-tests.sh` runs just the upgrade tests. The default is `^test_`. Do not edit the trailing `main` call to narrow a run; the harness resolves `ROOT` from `$0`, so the script must stay in `tests/`.

Each test builds a throwaway git repo via `make_target_repo`. `gh` is stubbed with `make_gh_mock`, so no test touches the network or a real GitHub repo.

## Architecture: the installer contract

`install.sh` is the whole product surface. Three ideas carry it.

**1. Destination is position.** `plan_files()` walks a tier directory and emits `src<TAB>dest` where `dest` is the path *relative to the tier root*, because the tier trees mirror target-repo layout. There is no path table to update. A new shipped file's destination is decided by where you put it under `tiers/`. The exceptions are one emit ahead of the tree walk and six arms in the `case`.

| Source | Destination | Why |
|---|---|---|
| `standards/coding-standards.md` | `coding-standards.md` (tier 1) | the only source outside `tiers/`; keeps one canonical copy |
| `tiers/2-pipeline/labels.json` | *(not installed)* | installer input, read by `apply_labels()` |
| `tiers/{1,2}/.claude/commands/*.md` | **both** `.claude/commands/*.md` and `.agents/skills/<name>/SKILL.md` | one source, two discovery paths, so a workflow cannot drift by harness |
| `tiers/3-ops/local/*` | `scripts/build-system/*` | drivers live under the target's `scripts/` |
| `tiers/3-ops/actions/*` | `.github/workflows/*` | the hosted builder variant |
| `tiers/3-ops/docs/*` | `docs/*` | operating spec |

The commands row is the one that surprises people: **a single source file emits two `src<TAB>dest` lines**, so adding a command adds two manifest entries. Claude Code reads the legacy path; Codex, OpenCode, and Copilot read the Agent Skill. Emit both or the multi-harness claim quietly becomes false for that command.

Tier 3 installs **only** those mapped paths; an unmapped file under `tiers/3-ops/` is silently skipped.

**2. The manifest is three-way merge state.** `.build-system.json` in the target records the system version, tier, a `config` block, and a sha256 per managed file. Every install decides one of three actions per file by comparing the recorded hash to the file on disk:

- `INSTALL` — absent, or tracked and unmodified (re-sync), or `--force`
- `KEEP` — tracked but locally modified (adaptations survive upgrades)
- `SKIP` — present but untracked (never clobber a file the installer did not write)

`config` is preserved across upgrades once filled in, and the controller reads it **at runtime**. It is no longer three keys: v3 carries sixteen, covering identity (`repo`, `defaultBranch`, `harness`), policy (`verifyCommands`, `protectedPaths`, `allowedPaths`, `requiredChecks`, `branchPrefix`), and bounds (`leaseMinutes`, the two timeouts, `maxChangedFiles`, `maxDiffBytes`, `dailyRunLimit`, `maxConsecutiveFailures`, `maxBudgetUsd`).

`loadConfig()` in `lib/system.cjs` throws when `verifyCommands` or `protectedPaths` still hold a `REPLACE:` string. That refusal is a hard failure in the loader, not a prompt instruction the model chooses to honor, and it fires before any provider is invoked. Keep it that way; a prompt-level guard here would be a regression.

**3. Upgrade is install, minus the version guard.** `do_upgrade()` reads the tier from the manifest and calls `do_install()`. Do not grow a second code path for it (see `tasks/lessons.md`).

## Architecture: the system being shipped

Read `docs/architecture.md` for the narrative. The shape, so you can place a change:

A GitHub issue form (`change_request.yml`) forces a contract: acceptance criteria, constraints, rollback, risk tier. `apply-risk-label.yml` parses the risk dropdown via `parse-risk-tier.cjs` and applies one of four `risk:*` labels. From there **the controller owns everything**, and this is the part most likely to be misremembered from v2.

`node scripts/build-system.cjs run` selects the queue, wins an atomic lease on `refs/heads/<prefix>/leases/issue-N`, builds a `WorkOrder`, and invokes a bounded worker inside a per-run worktree. The worker plans or edits ordinary files. It holds no GitHub token and no Git delivery tools. The controller then audits the real diff, runs verification, confirms Gate 2 branch protection, commits, pushes, opens the PR, re-queries GitHub to confirm head branch, head SHA, and base, and writes hash-chained evidence. **Provider prose is never evidence.** Success is derived from controller observations only.

**Gate 1 is a command, not a label swap.** `approve()` in `build-system.cjs` verifies the actor's maintainer permission, re-derives the contract digest, rejects a plan that is not bound to the current contract bytes, posts a marker comment, and only then moves `plan:pending` → `plan:approved`. The label is the receipt. `risk:docs` and `risk:chore` auto-approve via `build-system.cjs:260`. **Gate 2** (the merge) is always human.

`triage` **diagnoses and mutates nothing.** It reports failing PRs only when repository, PR number, branch, and head SHA all match controller-authored provenance. The v2 night shift that patched failing PRs is gone. Do not reintroduce a repair path that skips the lease, policy, and delivery contract.

Tier-3 drivers (`builder-run.sh`, `triage-run.sh`) verify an integrity manifest over the immutable runtime copy, then `exec` the controller. They no longer pre-check labels themselves; the controller does deterministic selection with `gh` before any provider call. The hosted `actions-builder.yml` keeps its own `gh` preflight because a skipped Actions job is cheaper than a started one.

**Labels are the durable state.** The 19 in `labels.json` are the entire protocol between human and agent: lifecycle, four `risk:*`, and two `*:paused`. A label alone is never a lock, though. The lease is the lock. Prose in a comment is invisible to the fleet.

**Two safety invariants govern anything you add here:** the controller alone decides outcomes, and every agent output re-enters the same gates. Nothing in this system merges. Nothing runs `--dangerously-skip-permissions`. Keep it that way, and preserve the fail-safe defaults (a `gh` failure counts as *no work*, ambiguous PR provenance counts as *untrusted*, an ambiguous risk section counts as *no tier*, unverifiable branch protection counts as *stop*).

## Constraints that are easy to violate

- **Bash 3.2 (macOS default).** No associative arrays, no `${var^^}`. Lookups go through `jq` or temp files.
- **`test_generalized_artifacts_have_no_gsd_residue`** greps all of `tiers/` for `gsd|cloudfront|taskmanager`. The payload was extracted from a production repo; anything you copy in must be generalized first. The test fails loudly if not.
- **The standards ship from outside the tier tree.** `standards/coding-standards.md` is the only copy, emitted directly by `plan_files()` for tier 1; `test_standards_have_exactly_one_copy_in_the_repo` fails if a duplicate reappears under `tiers/`. If you add another out-of-tree source, emit it **before** the tree walk: as a trailing `[ "$1" = N ] && printf`, a false test returns 1 and aborts the install for every other tier under `set -e` + `pipefail`.
- **Bumping `VERSION` touches three files:** `VERSION`, the distribution header in `standards/coding-standards.md`, and `CHANGELOG.md`. The tests no longer pin a version literal (they read `$ROOT/VERSION`), so nothing fails when you forget the header. It shipped wrong for all of v3.0.0 for exactly that reason. Grep `grep -rn "$(cat VERSION)" standards/ CHANGELOG.md` after a bump.
- **Never mutate `$ROOT` from a test.** Copy the distribution to a temp dir and mutate the copy, as `test_upgrade_resyncs_unmodified_and_preserves_modified` does with `cp -R "$ROOT" "$dist"`. A test that edits `$ROOT/VERSION` in place poisons the working tree for every later test when it fails.
- **Cross-file vocabulary.** Risk tier names must match in **five** places: `labels.json`, the `change_request.yml` dropdown, `RISK_TIERS` in `parse-risk-tier.cjs`, the hardcoded duplicate at `lib/protocol.cjs:92`, and the `["docs", "chore"]` auto-approve test in `build-system.cjs:260`. `test_risk_tiers_match_the_issue_form_dropdown` pins only the dropdown against `RISK_TIERS`. `protocol.cjs` duplicates the list instead of importing it, so a rename there fails at runtime, not in CI. Label names are referenced by name across the controller, the workflows, and the docs. Renaming is one deliberate pass, not a local edit.
- **`branchPrefix` now resolves in exactly one place:** `sanitizeBranchPrefix(raw.branchPrefix || "agent")` in `lib/system.cjs`. The default is `agent`, not `claude`, and the installer seeds the same value. `sanitizeBranchPrefix` enforces `^[A-Za-z0-9._-]+$`, which is what stops a blank prefix from matching every branch in the repo. Keep that regex; it is the guard, and the old per-consumer fallbacks it replaced are gone.
- **Shipped shell scripts need the exec bit in both the index and the working tree**, and `chmod` is denied by the permission config. `git update-index --chmod=+x <path>` sets only the index bit, but `plan_files` installs with `cp`, which reads the working-tree mode. Follow it with `git checkout-index -f -- <path>` or the file installs non-executable while a fresh clone looks correct. All of `tiers/1-session/.claude/hooks/*.sh` and `tiers/3-ops/local/*.sh` are `100755`.

## Conventions

- **Commits:** Conventional Commits with a scope — `docs(tasks):`, `chore(release):`, `feat(installer):`. One logical unit per commit.
- **Working memory** lives in `tasks/`: `todo.md` carries a "Resuming From Here" block (done / next / blockers / assumptions), `lessons.md` carries durable gotchas. Read both when resuming. `tasks/spec-*.md` and `tasks/plan-*.md` are the v2 build's frozen record — historical, not live instructions.
- **Docs style** (enforced by review, per `README.md`): every new pattern gets a "what it does, why it exists, what it costs" paragraph. Keep examples minimal and commented; this repo is a teaching tool, not a kitchen sink.
- **Comments in shipped code explain the trap**, not the mechanism — why the PATH is appended rather than prepended, why a `gh` failure fails safe to zero. Match that density.
- `docs/` splits by audience: `getting-started` (first run, install to merged PR) · `architecture` (how it works) · `adoption` (tiers, manifest) · `runbook` (operating it, failure modes, cost) · `customizing` (adapting it) · `rationale` (why, including what was deliberately cut). A setup step that only the walkthrough carries belongs in `test_walkthrough_covers_the_undiscoverable_setup_steps`.
