# Spec: claude-code-build-system v2 — the installable pipeline

**Status:** Approved (design approved 2026-08-07; per standing correction, approval covers spec → plan → implementation)
**Tier:** Non-trivial
**Date:** 2026-08-07

## Goal

Evolve this repo from a session-level reference configuration into the full, installable version of the issue → Claude → PR build system proven in `gsd-taskmanager`. Three adoption tiers, one idempotent installer, versioned coding-standards distribution, docs that are the canonical methodology, and a draft blog post. The origin pipeline (gsd-taskmanager) must be expressible as a consumer of this system — that is the test of generalization.

## Inputs

Source artifacts to extract and generalize (read, never modified, in place):

| Source | Becomes |
|---|---|
| `~/Projects/AI-Build-System/coding-standards.md` (v18.0) | `standards/coding-standards.md` (canonical) |
| `~/Projects/gsd-taskmanager/.github/ISSUE_TEMPLATE/change_request.yml` | `tiers/2-pipeline/github/ISSUE_TEMPLATE/change_request.yml` |
| `~/Projects/gsd-taskmanager/.github/workflows/apply-risk-label.yml` | `tiers/2-pipeline/github/workflows/apply-risk-label.yml` |
| `~/Projects/Barometer/.github/workflows/claude.yml`, `claude-code-review.yml` (newest copies) | `tiers/2-pipeline/github/workflows/` |
| `~/Projects/gsd-taskmanager/docs/agents/triage-labels.md` | `tiers/2-pipeline/labels.json` + `docs/architecture.md` |
| `~/Projects/gsd-taskmanager/.claude/commands/build-next.md`, `triage-prs.md` | `tiers/2-pipeline/claude/commands/` (generalized) |
| `~/Projects/gsd-taskmanager/docs/agents/{builder,night-shift,issue-tracker}.md` | `docs/architecture.md`, `docs/runbook.md`, tier-3 night-shift command |
| `~/Projects/gsd-taskmanager/scripts/{builder-run.sh,triage-run.sh}` | `tiers/3-ops/local/` (generalized) |
| Existing v1 content (`.claude/`, `templates/`, `global/`, `docs/RATIONALE.md`) | `tiers/1-session/`, `global/` (unchanged), `docs/rationale.md` |

## Outputs

### Repo structure (v2)

```
claude-code-build-system/
├── README.md                 # rewritten front door: tiers, quickstart, v1→v2 map
├── install.sh                # the installer
├── VERSION                   # 2.0.0 (semver); CHANGELOG.md alongside
├── standards/coding-standards.md
├── global/                   # unchanged from v1 (machine-level, one-time setup)
├── tiers/
│   ├── 1-session/            # → CLAUDE.md, .claude/{commands,hooks,agents,settings.json},
│   │                         #   coding-standards.md (from standards/), tasks/{lessons,todo}.md
│   ├── 2-pipeline/           # → .github/{ISSUE_TEMPLATE,workflows}, labels.json,
│   │                         #   .claude/commands/{build-next,triage-prs}.md
│   └── 3-ops/
│       ├── local/            # builder-run.sh, triage-run.sh, launchd plist template
│       ├── actions/          # actions-builder.yml (hosted variant, reference)
│       └── night-shift.md    # → .claude/commands/night-shift.md
├── docs/
│   ├── architecture.md       # three loops, two gates, label state machine (mermaid diagram)
│   ├── adoption.md           # tier guide: what you get / what you need / how to grow
│   ├── runbook.md            # gates, kill switches, failure modes, the two invariants
│   ├── rationale.md          # v1 RATIONALE + v2 decisions + deliberate cuts
│   └── customizing.md        # verify commands, protected paths, stacks, swapping runners
└── tests/run-tests.sh        # installer test harness + .github/workflows/ci.yml runs it
```

v1's `templates/` and `examples/` dissolve into `tiers/1-session/` and `standards/`. `global/` keeps its published path. README carries a "v1 → v2 map" table because the April post links to this repo.

### Installer contract

`./install.sh --tier <1|2|3> [--target <path>] [--dry-run] [--force]` and `./install.sh --upgrade [--target <path>] [--dry-run] [--force]`

- Tiers are cumulative: `--tier 2` installs tier 1 + tier 2; `--tier 3` installs all.
- Copies tier artifacts to their target paths. No template rendering: files that need per-project content (CLAUDE.md) ship with human-fill placeholder sections, matching v1's approach. Machine-read config lives in the manifest, not in rendered files.
- Writes manifest `.build-system.json` at target root:
  `{ schemaVersion, systemVersion, tier, config: { verifyCommands[], protectedPaths[], branchPrefix }, files: [{ path, sha256 }] }`
  `config` starts with self-describing placeholder values (e.g. `"verifyCommands": ["REPLACE: e.g. bun run test"]`) the human edits — JSON carries no comments, so the placeholders must explain themselves; pipeline commands read it at runtime with `jq`.
- Tier 2 applies the label set from `labels.json` via `gh label create --force` when `gh` is installed and authenticated; otherwise prints the commands and continues (non-fatal).
- Tier 3 on darwin copies scripts + a launchd plist template and prints `launchctl` load instructions; on other platforms prints a cron stanza instead. Never loads/starts services itself.
- `--upgrade` compares each manifest-tracked file's current hash against the recorded hash: unmodified → re-sync from repo and restamp; locally modified → leave untouched, print diff summary, require `--force` to overwrite. Files present in the target but never manifest-tracked are skipped with a warning.
- Idempotent: same version, second run → zero changes, exit 0. `--dry-run` prints the change plan and writes nothing. Fail fast if target is not a git repo.
- Dependencies: bash, git, coreutils, `jq`. `gh` optional (labels step only). No network access except via `gh`.

### Generalization contract (the substance)

`build-next.md`, `triage-prs.md`, `night-shift.md`, `builder-run.sh`, `triage-run.sh` must contain **zero** gsd-specific content: no hardcoded repo paths, package-manager commands, CloudFront/deploy specifics, or gsd label prose. They read verify commands, protected paths, and branch prefix from `.build-system.json`. The hard-limits block survives verbatim as the non-negotiable core: never merge, never push to the default branch, never force-push, never edit `.github/workflows/**` or deploy config or files listed in `protectedPaths`, only commit to `<branchPrefix>/issue-<n>-*` branches, end with the machine-readable telemetry line. The night-shift invariants survive verbatim: "verify before submit" and "fixes re-enter the gate." Kill switches survive: the `triage:paused` label and a `WORKFLOW_KILLSWITCH` file check.

`tiers/3-ops/local/` scripts read a per-repo env file (`~/.build-system/<repo-name>.env`, created by the installer with commented defaults) for machine-local paths: worktree location, log directory, schedule notes.

`tiers/3-ops/actions/actions-builder.yml` is the hosted variant: triggered on `plan:approved` / `ready-for-agent` label events plus an optional schedule, runs `anthropics/claude-code-action@v1` with the `/build-next` prompt and `CLAUDE_CODE_OAUTH_TOKEN`. Documented as the less-battle-tested path; local-first is primary.

### Docs

`docs/architecture.md` retells the Two Gates pipeline generically (issue contract → risk label → plan → Gate 1 → build → PR → review + CI → Gate 2 → merge; night shift as the fourth loop), with a mermaid state diagram of the label machine. `docs/adoption.md` is the tier table and growth path. `docs/runbook.md` covers operating it: approving plans, the gates, kill switches, failure modes, token/cost notes. `docs/rationale.md` extends v1's RATIONALE with the v2 decisions (installer over plugin, manifest hashes, local-first) and the deliberate cuts. `docs/customizing.md` explains the manifest config, swapping stacks, and adapting hard limits. README is rewritten: what/why, tier quickstarts, v1→v2 map, links to both blog posts.

### Blog post

Draft at `~/Projects/VinnyThesis/2026-08-07-the-pipeline-becomes-a-package.md` (slug adjustable), written with the vinny-voice skill: the arc from one hand-fitted pipeline to an installable tiered system; links back to "Claude Code Is a Build System, Not a Chatbot" and "Two Gates and a Night Shift." Delivered as a draft; Vinny publishes.

## Constraints

- Evolve in place: git history continues; no force-pushes; work on a feature branch; commits follow Conventional Commits via the creating-git-commits skill.
- Don't break the published story: `global/` path survives; README maps v1 paths to v2 homes.
- Bash only for installer and hooks (RATIONALE: cold-start cost). Plain-bash tests, no bats dependency.
- Standards doc content is Vinny's v18.0 verbatim (plus a distribution header noting version + source); the skeleton template survives for bring-your-own-standards adopters.
- Source repos (gsd-taskmanager, Barometer, AI-Build-System) are read-only inputs this run. gsd-taskmanager migration to consumer status is future work, not this spec.
- Pilot pushes: installing tier 2 into `kanban-todos` locally is in scope; pushing pilot changes or filing real issues requires explicit confirmation at that moment (hard-to-reverse action rule; the design approval is not blanket push approval to other repos).

## Edge Cases

1. Target already has `CLAUDE.md`, `.claude/settings.json`, or `coding-standards.md` (untracked by manifest) → skip each, warn, continue; `--force` adopts (overwrites and begins tracking).
2. Re-install at same version → no-op, exit 0. Re-install at higher version without `--upgrade` → error telling the user to run `--upgrade`.
3. `--upgrade` where both upstream and local changed → local wins, diff summary printed, `--force` required to take upstream.
4. `gh` missing or unauthenticated during tier 2 → labels step prints commands, exits 0.
5. Target not a git repo → fail fast with message, no writes.
6. Manifest corrupted/hand-edited invalid JSON → fail fast, point at the file, suggest `--force` reinstall.
7. Linux/WSL target for tier 3 → cron instructions instead of launchd; scripts themselves are portable bash.
8. `--dry-run` combined with any mode → full plan printed, zero writes (assert in tests).

## Out of Scope

npm/bun packaging; Claude Code marketplace plugin; Windows-native support; AGENTS.md/Codex variants; telemetry dashboards; multi-standards support; migrating gsd-taskmanager or the other 40+ repos (future work: the installer makes that a per-repo one-liner); publishing the blog post; changing gsd-taskmanager's live pipeline.

## Acceptance Criteria

1. Fresh temp git repo + `install.sh --tier 1` → CLAUDE.md, `.claude/{commands/{qspec,tdd,qcheck}.md,hooks,agents,settings.json}`, `coding-standards.md`, `tasks/{lessons,todo}.md`, valid `.build-system.json` (version 2.0.0, tier 1, correct sha256 per file).
2. `--tier 2` on the same repo → adds issue form, 3 workflows, `build-next.md`, `triage-prs.md`, `labels.json` handling per contract; manifest tier becomes 2.
3. `--tier 3` → adds ops scripts, night-shift command, platform-appropriate scheduler artifacts; scripts pass `bash -n`.
4. Second identical run → no file changes (hash-verified), exit 0.
5. Upgrade scenario: bump repo VERSION + change one tier file → `--upgrade` re-syncs unmodified files and restamps; a locally-edited file is untouched and warned; `--force` overwrites it.
6. `--dry-run` writes nothing (tree hash identical before/after).
7. Edge cases 1, 2, 4, 5, 6 have explicit tests; suite green locally and in CI (`ci.yml` on ubuntu).
8. `grep -riE 'gsd|cloudfront|taskmanager' tiers/` returns nothing; generalized commands/scripts reference `.build-system.json` for verify commands, protected paths, branch prefix.
9. Hard-limits block, two night-shift invariants, and kill-switch mechanisms present verbatim-in-substance in the generalized artifacts.
10. Docs exist and are internally consistent (tier names, paths, flags match the installer's actual behavior); README quickstart commands are copy-paste runnable; v1→v2 map present.
11. Tier-2 install into a local checkout of `kanban-todos` succeeds with warnings only for expected pre-existing files (nothing pushed without confirmation).
12. Blog draft exists in VinnyThesis and passes vinny-voice conventions.

## Test Stubs

```bash
# tests/run-tests.sh — each function creates its own temp git repo fixture
test_tier1_fresh_install_places_files_and_manifest()
test_tier2_is_cumulative_and_adds_pipeline_artifacts()
test_tier3_adds_ops_scripts_and_scheduler_artifacts()
test_reinstall_same_version_is_noop()
test_existing_untracked_claude_md_is_skipped_with_warning()
test_force_adopts_existing_untracked_file()
test_upgrade_resyncs_unmodified_file_and_restamps_version()
test_upgrade_preserves_locally_modified_file()
test_upgrade_force_overwrites_local_modification()
test_dry_run_writes_nothing()
test_non_git_target_fails_fast()
test_corrupt_manifest_fails_fast()
test_missing_gh_labels_step_is_nonfatal()
test_generalized_artifacts_have_no_gsd_residue()
test_ops_scripts_pass_bash_syntax_check()
```
