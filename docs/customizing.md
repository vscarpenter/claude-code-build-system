# Customizing

The system ships generic. Three kinds of customization make it yours: the manifest config every repo must fill in, the adaptations the upgrade path protects, and the deeper renames you should do once and early.

## The manifest config (required)

After installing, open `.build-system.json` and replace the placeholders:

```json
"config": {
  "verifyCommands": ["bun run test", "bun run lint", "bun run typecheck"],
  "protectedPaths": ["deploy/**", "infra/**", "SECURITY.md"],
  "branchPrefix": "claude"
}
```

Per-stack starting points for `verifyCommands`:

| Stack | Commands |
|---|---|
| TypeScript + Bun | `bun run test`, `bun run lint`, `bun run typecheck` |
| Node + npm | `npm test`, `npm run lint`, `npx tsc --noEmit` |
| Rust | `cargo test`, `cargo clippy -- -D warnings`, `cargo fmt --check` |
| Swift | `swift test`, `swift build` |
| Java + Maven | `mvn -q verify` |
| Python | `pytest`, `ruff check .`, `mypy .` |

`protectedPaths` deserves thought. The controller always refuses its own manifest, agent instructions, Git metadata, workflow definitions, and controller runtime. Add deploy config, infrastructure, security policy, generated schemas, and any domain-specific crown jewels. The controller inspects the real Git diff, including both sides of renames, symlinks, and gitlinks.

## Adapting managed files

Every installed file is yours to edit. The manifest's hashes exist precisely so `--upgrade` can tell your edits from stale copies: modified files are kept with a `KEEP` notice. Common adaptations that survive upgrades untouched:

- Rewriting `CLAUDE.md` for the project (expected; it ships as a template).
- Adding deterministic diagnostic checks to the night shift without granting it write authority.
- Tightening the issue form's placeholder examples to your domain.
- Swapping the review workflow's plugin or prompt.

The cost of adapting a file is that future upstream improvements to it stop flowing automatically. `--upgrade` prints which files it kept; review that list occasionally and re-adopt with `--force` where your edit is no longer worth the fork.

## Renaming the branch prefix

`branchPrefix` defaults to `agent`. Pick it before the first build run. It is part of lease refs, controller-created delivery branches, and provenance records; changing it does not transfer old runs.

## Renaming labels

The label vocabulary lives in `tiers/2-pipeline/labels.json` and is referenced by name inside `build-next.md`, `triage-prs.md`, the risk workflow, and the docs. Renaming is possible but crosses files; do it as one deliberate pass or keep the stock names. The `risk:*` values must additionally match the dropdown options in `change_request.yml` and the `RISK_TIERS` list in `parse-risk-tier.cjs`.

## Swapping runners

The local and hosted variants enter the same controller. They may wake together: the per-issue remote Git-ref lease gives one winner, and per-run worktrees prevent checkout collisions. Keep one primary anyway so budgets and evidence live under one state root; the shipped local ledger is not a cross-host global budget.

## Changing the schedule

Local: edit the `StartCalendarInterval` blocks in the plist templates (or your cron lines). The wake-ups are cheap, so err toward more frequent. Hosted: edit the `cron:` line in `actions-builder.yml`, or delete the schedule block and run label-triggered only.
