# Adoption guide

Adopt the system in tiers. Each tier is useful on its own, each includes everything below it, and each asks for more trust than the last. Start at 1. Grow when you feel the ceiling.

## The tiers

| Tier | What you get | What you need | Time |
|---|---|---|---|
| **1 Session** | `CLAUDE.md` + `AGENTS.md`, spec/TDD/review workflows as Claude commands and shared Agent Skills, Claude hooks and subagents, standards, task memory | Claude Code, Codex, OpenCode, or a supported Copilot surface; guardrails vary | 15 minutes |
| **2 Pipeline** | Contract issue form, 19-label lifecycle, deterministic controller, Claude/Codex adapters, leases, per-run worktrees, policy and evidence | Tier 1, a GitHub repo, `gh`, Node | 30 minutes |
| **3 Ops** | Integrity-checked immutable runtime, scheduled builder, provenance-bound diagnosis, hosted Claude adapter | Tier 2 and an always-on machine or hosted runner | an hour |

```bash
BUILD_SYSTEM_DIR="/absolute/path/to/claude-code-build-system"
TARGET_REPO="/absolute/path/to/your/repo"
"$BUILD_SYSTEM_DIR/install.sh" --tier 1 --target "$TARGET_REPO"
cd "$TARGET_REPO"
```

Tiers are cumulative: `--tier 2` installs tier 1 as well. Add `--dry-run` to see the plan first.

This page covers what each tier contains and how the installer decides what to
write. For copy-pasteable source/target commands and the first successful run,
read [Getting started](getting-started.md). Tier 2 and 3 adopters must also
complete [GitHub setup](github-setup.md).

## What the installer will not do

It never overwrites a file it did not install. If you already have a `CLAUDE.md`, the installer skips it, tells you, and moves on. Pass `--force` to adopt existing files into management. It also never loads launchd jobs or starts services; tier 3 prints the instructions and leaves the last step to you.

## The manifest

The installer writes `.build-system.json` at your repo root. It records the system version, the tier, a `config` block, and a sha256 hash for every file it manages. Two things read it:

- **The controller.** `build-system.cjs` reads repository identity, verification,
  path policy, required checks, branch prefix, timeouts, and budgets at runtime.
  Fill the placeholders after installing; it refuses to run unconfigured.
  Claude exposes slash entry points while other harnesses discover the same
  sources under `.agents/skills/`.
- **The upgrade path.** `./install.sh --upgrade` compares each managed file's current hash to the recorded one. Unmodified files re-sync to the new version. Files you adapted stay untouched, with a `KEEP` notice, unless you pass `--force`.

Commit the manifest. It is how a repo knows which version of the system it carries.

## Standards without drift

`standards/coding-standards.md` is the canonical copy, and every install stamps a versioned copy into the target repo. When the standards evolve, bump once here and run `--upgrade` in each repo. Before this existed, my standards doc drifted across 28 repos at three different versions. One command now closes that gap per repo.

If you would rather write your own standards, start from `docs/coding-standards-skeleton.md` (installed with tier 1) and keep the same file name so the commands still find it.

## Growing from tier to tier

Tier 1 changes daily sessions: shared spec, TDD, and review workflows give every supported harness a common contract; Claude additionally gets the shipped hooks and specialist profiles. Tier 2 changes authority: requirements become contracts and `scripts/build-system.cjs` owns claims, policy, verification, delivery, and evidence while Claude or Codex only plans or edits. Tier 3 schedules an immutable copy of that same controller. Night shift is intentionally diagnosis-only.

Do not add model tool permissions to make verification work. Verification is
controller-owned and comes from `config.verifyCommands`. Machine-local Tier 3
settings are JSON data under `~/.build-system/repos/<repo-id>/config.json`, not
a sourced shell file. The model receives no Bash, Git, or GitHub delivery
capability; the controller runs the configured commands after auditing the diff.

Trust the output at each tier before adopting the next. The gates exist so that trust is earned, not assumed.
