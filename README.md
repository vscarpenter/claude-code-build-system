# Claude Code Build System

*The installable version of an issue → Claude → PR delivery pipeline, in three adoption tiers.*

This repo started as the companion to [Claude Code Is a Build System, Not a Chatbot](https://vinny.dev/blog/2026-04-25-claude-code-build-system/): session-level configuration you copied by hand. Version 2 is the whole system. [Two Gates and a Night Shift](https://vinny.dev/blog/2026-07-06-two-gates-and-a-night-shift/) described the pipeline running in production on one repo; this repo makes it installable in yours. Fork it. Take the tier you trust. Grow when you feel the ceiling.

**Version:** 2.0.0 (see `VERSION` and `CHANGELOG.md`)
**Tested on:** macOS and Linux, Claude Code v2.1.111+
**License:** MIT

---

## The system in one paragraph

A change enters as a contract: a GitHub issue form that requires acceptance criteria, constraints, rollback, and a risk tier. A builder agent plans it, and the plan waits at **Gate 1** for your approval unless the risk tier is trivial. On approval the agent builds test-first in an isolated worktree, to a written standard, and opens a PR it can never merge. Review and CI gate the PR, and **Gate 2** (the merge) stays human. A night-shift agent clears mechanical CI failures while you sleep, and everything it does re-enters the same gates. Labels are the durable state, and two label kill switches stop the fleet from your phone. The full narrative is in [docs/architecture.md](docs/architecture.md).

## Install

```bash
git clone https://github.com/vscarpenter/claude-code-build-system
cd claude-code-build-system
./install.sh --tier 1 --target /path/to/your/repo
```

| Tier | What you get | Time |
|---|---|---|
| `--tier 1` **Session** | `CLAUDE.md`, `/qspec` `/tdd` `/qcheck`, protective hooks, review subagents, versioned `coding-standards.md` | 15 min |
| `--tier 2` **Pipeline** | The change-contract issue form, 15-label state machine, risk automation, `@claude` + PR-review workflows, `/build-next`, `/triage-prs` | 30 min |
| `--tier 3` **Ops** | Scheduled builder + night-shift drivers, worktree isolation, kill switches, hosted Actions variant | 1 hour |

Tiers are cumulative. Add `--dry-run` to preview, `--force` to adopt files you already have. The installer writes a `.build-system.json` manifest recording the version and a hash of every file it manages; `./install.sh --upgrade` later re-syncs what you have not modified and keeps what you have. Details in [docs/adoption.md](docs/adoption.md).

**What happens after the install** is in [docs/getting-started.md](docs/getting-started.md): what to configure, how to verify it took, and one change tracked from the issue form to a merged PR. The installer prints the short version of those steps when it finishes.

Tier 2 and up will not run until you fill in the `config` block of `.build-system.json` (verify commands, protected paths, branch prefix). The agents read it at runtime and escalate rather than run unconfigured.

## What's in here

```
claude-code-build-system/
├── install.sh            The tiered installer (bash + jq, nothing else)
├── standards/            Canonical coding-standards.md, versioned, synced by --upgrade
├── tiers/
│   ├── 1-session/        Mirrors your repo: CLAUDE.md, .claude/, tasks/
│   ├── 2-pipeline/       Mirrors your repo: .github/, agent commands + labels.json
│   └── 3-ops/            Drivers, plist templates, night-shift spec, hosted variant
├── global/               Goes in ~/.claude/ on your machine (unchanged from v1)
├── docs/                 getting-started · architecture · adoption · runbook · rationale · customizing
└── tests/                The installer's test suite (plain bash, runs in CI)
```

## How this maps to the principles

| Principle | Where it lives now |
|---|---|
| 1. Standards once, referenced everywhere | `standards/coding-standards.md` + manifest version stamps |
| 2. Make the right thing automatic | `global/hooks/`, `tiers/1-session/.claude/settings.json`, the label automation |
| 3. Specialists beat generalists | `tiers/1-session/.claude/agents/`, the builder and night-shift roles |
| 4. Rituals deserve commands | `/qspec`, `/tdd`, `/qcheck`, `/build-next`, `/triage-prs` |
| 5. Memory is a feature | `tasks/lessons.md`, `tasks/todo.md`, `global/hooks/persist-memory.sh` |
| 6. Permissions are safety equipment | scoped `--allowedTools` in the drivers, hard-limits blocks, `protectedPaths` |

## v1 → v2 map

Readers arriving from the April post: everything survived, most of it moved.

| v1 path | v2 home |
|---|---|
| `templates/CLAUDE.md` | `tiers/1-session/CLAUDE.md` |
| `templates/lessons.md`, `templates/todo.md` | `tiers/1-session/tasks/` |
| `templates/coding-standards.md` (skeleton) | `tiers/1-session/docs/coding-standards-skeleton.md` |
| `examples/coding-standards.md` | superseded by `standards/coding-standards.md` |
| `.claude/` (project baseline) | `tiers/1-session/.claude/` |
| `global/` | `global/` (unchanged) |
| `docs/RATIONALE.md` | `docs/rationale.md`, extended with v2 decisions |

## Operating it

Day-to-day operation is two label swaps and a merge button: approve plans at Gate 1 (`plan:pending` → `plan:approved`), release at Gate 2, and pause everything with the `builder:paused` / `triage:paused` labels when you want quiet. Start with [getting started](docs/getting-started.md) for the first run end to end. The [runbook](docs/runbook.md) covers telemetry, failure modes, and costs; [customizing](docs/customizing.md) covers adapting the pieces to your stack.

## What's intentionally missing

No npm package, no marketplace plugin, no Windows-native scripts, no telemetry dashboard. The reasoning for each cut is in [docs/rationale.md](docs/rationale.md). Project-specific content (your `lessons.md` entries, your `settings.local.json`) stays yours to write, same as v1.

## Disclaimer

This is a solo-developer system published for adaptation. Team-scale governance (command ownership, shared standards stewardship, audit aggregation) is not solved here. Hooks and drivers are bash; Windows users need WSL. The agents run under scoped tool allowlists, never `--dangerously-skip-permissions`, and nothing in this system merges a PR. Keep it that way.

## Contributing

Issues and PRs welcome. Two principles:

1. Keep examples minimal and well-commented. The repo is a teaching tool, not a kitchen sink.
2. Match the documentation style. New patterns need a "what it does, why it exists, what it costs" paragraph.

Run `bash tests/run-tests.sh` before opening a PR; CI runs the same suite.

## License

MIT. See [LICENSE](LICENSE).

---

*Companion repo to [vinny.dev/blog](https://vinny.dev/blog). Fork it. Take what's useful. Skip the rest.*
