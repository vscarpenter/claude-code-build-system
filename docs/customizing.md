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

`protectedPaths` deserves thought. The builder and night shift already refuse `.github/workflows/**`; list everything else an unattended agent must never touch: deploy config, infrastructure, security policy, generated schemas. When in doubt, protect it. The agent escalates instead, which costs you a label swap, not an incident.

## Adapting managed files

Every installed file is yours to edit. The manifest's hashes exist precisely so `--upgrade` can tell your edits from stale copies: modified files are kept with a `KEEP` notice. Common adaptations that survive upgrades untouched:

- Rewriting `CLAUDE.md` for the project (expected; it ships as a template).
- Adding project-specific fixers to the night shift's mechanical-fix list in `triage-prs.md`.
- Tightening the issue form's placeholder examples to your domain.
- Swapping the review workflow's plugin or prompt.

The cost of adapting a file is that future upstream improvements to it stop flowing automatically. `--upgrade` prints which files it kept; review that list occasionally and re-adopt with `--force` where your edit is no longer worth the fork.

## Renaming the branch prefix

`branchPrefix` defaults to `claude`. Change it in the manifest and the commands follow; the label descriptions and docs use the generic `<branchPrefix>` form already. Pick the prefix before the first build run: the night shift identifies the fleet's own PRs by it, so changing it later strands open PRs under the old name.

## Renaming labels

The label vocabulary lives in `tiers/2-pipeline/labels.json` and is referenced by name inside `build-next.md`, `triage-prs.md`, the risk workflow, and the docs. Renaming is possible but crosses files; do it as one deliberate pass or keep the stock names. The `risk:*` values must additionally match the dropdown options in `change_request.yml` and the `RISK_TIERS` list in `parse-risk-tier.cjs`.

## Swapping runners

The local drivers and the hosted variant run the same `/build-next` contract, so you can move between them freely. Run both only with care: nothing prevents two builders from claiming different issues concurrently, but they will race on labels and worktrees if the schedules overlap. Pick one primary. The kill-switch labels stop either.

## Changing the schedule

Local: edit the `StartCalendarInterval` blocks in the plist templates (or your cron lines). The wake-ups are cheap, so err toward more frequent. Hosted: edit the `cron:` line in `actions-builder.yml`, or delete the schedule block and run label-triggered only.
