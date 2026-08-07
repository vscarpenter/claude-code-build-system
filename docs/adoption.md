# Adoption guide

Adopt the system in tiers. Each tier is useful on its own, each includes everything below it, and each asks for more trust than the last. Start at 1. Grow when you feel the ceiling.

## The tiers

| Tier | What you get | What you need | Time |
|---|---|---|---|
| **1 Session** | `CLAUDE.md`, `/qspec` `/tdd` `/qcheck`, protective hooks, review subagents, `coding-standards.md`, `tasks/` memory files | Claude Code | 15 minutes |
| **2 Pipeline** | The change-contract issue form, 15-label state machine, risk automation, `@claude` + PR-review workflows, `/build-next` and `/triage-prs` | Tier 1, a GitHub repo, `gh` | 30 minutes |
| **3 Ops** | Scheduled builder and night-shift drivers, worktree isolation, kill switches, the hosted Actions variant | Tier 2, a machine that is usually on (or the hosted variant) | an hour |

```bash
./install.sh --tier 1 --target /path/to/your/repo
```

Tiers are cumulative: `--tier 2` installs tier 1 as well. Add `--dry-run` to see the plan first.

This page covers what each tier contains and how the installer decides what to write. For what to do once it finishes, read [getting-started.md](getting-started.md).

## What the installer will not do

It never overwrites a file it did not install. If you already have a `CLAUDE.md`, the installer skips it, tells you, and moves on. Pass `--force` to adopt existing files into management. It also never loads launchd jobs or starts services; tier 3 prints the instructions and leaves the last step to you.

## The manifest

The installer writes `.build-system.json` at your repo root. It records the system version, the tier, a `config` block, and a sha256 hash for every file it manages. Two things read it:

- **The pipeline commands.** `/build-next` and `/triage-prs` read `config.verifyCommands`, `config.protectedPaths`, and `config.branchPrefix` at runtime. Fill these in after installing; the placeholders say `REPLACE:` and the builder escalates rather than run unconfigured.
- **The upgrade path.** `./install.sh --upgrade` compares each managed file's current hash to the recorded one. Unmodified files re-sync to the new version. Files you adapted stay untouched, with a `KEEP` notice, unless you pass `--force`.

Commit the manifest. It is how a repo knows which version of the system it carries.

## Standards without drift

`standards/coding-standards.md` is the canonical copy, and every install stamps a versioned copy into the target repo. When the standards evolve, bump once here and run `--upgrade` in each repo. Before this existed, my standards doc drifted across 28 repos at three different versions. One command now closes that gap per repo.

If you would rather write your own standards, start from `docs/coding-standards-skeleton.md` (installed with tier 1) and keep the same file name so the commands still find it.

## Growing from tier to tier

Tier 1 changes daily sessions: the spec, TDD, and review commands plus the hooks give every conversation the same floor. Tier 2 changes how work enters: requirements become contracts, and you can run `/build-next` by hand whenever there is a `ready-for-agent` issue. Tier 3 removes you from the loop everywhere except the gates: the builder wakes on a schedule, plans, waits at Gate 1, builds on approval, and the night shift keeps the PR queue clean while you sleep.

Trust the output at each tier before adopting the next. The gates exist so that trust is earned, not assumed.
