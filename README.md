# Claude Code Build System

*A reference configuration for treating Claude Code as a build system, not a chatbot.*

This repo is the companion to [Claude Code Is a Build System, Not a Chatbot](https://vinny.dev/blog/2026-04-25-claude-code-build-system/). It contains the hooks, subagents, slash commands, settings, and templates the post describes. Fork it. Take what's useful. Skip the rest.

**Last updated:** April 25, 2026
**Tested on:** macOS, Claude Code v2.1.111+
**License:** MIT

---

## What's in here

```
claude-code-build-system/
├── .claude/              Drop into your project root
│   ├── settings.json     Team-baseline permissions and project hooks
│   ├── agents/           Specialist subagents (a11y, migrations)
│   └── commands/         Slash commands (/qspec, /tdd, /qcheck)
├── global/               Goes in ~/.claude/ on your machine
│   ├── settings.json     Personal denylist and allowlist
│   └── hooks/            Cross-project hooks (audit, capture, memory)
├── templates/            Starting points you customize per project
│   ├── CLAUDE.md         Project context loaded every session
│   ├── coding-standards.md
│   ├── lessons.md        Project-specific gotchas
│   └── todo.md           In-flight work
└── docs/                 Walkthroughs and rationale
```

---

## Quickstart: 15 minutes to a working setup

This mirrors the "What changes Monday" section of the post. Five steps, in order.

### 1. Add a CLAUDE.md to your project

```bash
cp templates/CLAUDE.md /path/to/your/project/CLAUDE.md
```

Edit it to reflect your stack, conventions, and the gotchas Claude needs to know on every session. Keep it under roughly 200 lines. This single file delivers more value than any other piece of configuration.

### 2. Add a fast typecheck hook

```bash
mkdir -p /path/to/your/project/.claude
cp .claude/settings.json /path/to/your/project/.claude/settings.json
```

Open the file and replace `bun typecheck` with whatever's fast in your stack: `tsc --noEmit`, `mypy`, `cargo check`, `swift build`. The point is to catch the obvious stuff before the conversation ends.

### 3. Add a project lessons file

```bash
mkdir -p /path/to/your/project/tasks
cp templates/lessons.md /path/to/your/project/tasks/lessons.md
cp templates/todo.md /path/to/your/project/tasks/todo.md
```

Reference `tasks/lessons.md` from your `CLAUDE.md` so Claude reads it at the start of every session. When something bites you twice, add a line.

### 4. Install one slash command

```bash
mkdir -p /path/to/your/project/.claude/commands
cp .claude/commands/qcheck.md /path/to/your/project/.claude/commands/qcheck.md
```

Now `/qcheck` runs a skeptical staff-engineer review of every changed file. Pick the command you'd use weekly. Add the others when you feel their absence.

### 5. Install the audit hook

```bash
mkdir -p ~/.claude/hooks
cp global/hooks/audit-command.sh ~/.claude/hooks/audit-command.sh
chmod +x ~/.claude/hooks/audit-command.sh
cp global/settings.json ~/.claude/settings.json
```

Every Bash command Claude proposes now gets logged to `~/.claude/audit/`. Risky shapes (`curl | sh`, `eval`, `git push --force`) get routed to a separate `flagged-` file. You don't need to do anything with the log on day one. You'll be glad it exists the first time something breaks.

That's the minimum viable setup. Add the rest when you feel their absence.

---

## How this maps to the principles

| Principle | What's in the repo |
|---|---|
| 1. Standards once, referenced everywhere | `templates/CLAUDE.md`, `templates/coding-standards.md` |
| 2. Make the right thing automatic | `global/hooks/`, `.claude/settings.json` |
| 3. Specialists beat generalists | `.claude/agents/` |
| 4. Rituals deserve commands | `.claude/commands/` |
| 5. Memory is a feature | `templates/lessons.md`, `templates/todo.md`, `global/hooks/persist-memory.sh` |
| 6. Permissions are safety equipment | `global/settings.json`, `.claude/settings.json` |

Each directory has its own README walking through the details.

---

## Per-piece walkthrough

### Global hooks (`global/hooks/`)

Three shell scripts, all designed to be cheap and deterministic.

- **`audit-command.sh`** fires on `PreToolUse` for Bash. Logs every command. Flags risky shapes to a separate file. Never blocks.
- **`capture-decision.sh`** fires on `PostToolUse` for Edit and Write. Logs every file mutation with a `git diff --stat` snapshot.
- **`persist-memory.sh`** fires on `SessionEnd`. Reads the transcript, extracts one to three durable learnings via `claude --print`, appends them to `~/.claude/lessons.md`.

See `global/hooks/README.md` for installation and event registration details.

### Project subagents (`.claude/agents/`)

- **`a11y-reviewer.md`** reviews changed `.tsx` files against WCAG AA. Read-only.
- **`pg-migration-reviewer.md`** reviews changes under `db/migrations/**` against documented PostgreSQL gotchas. Read-only.

Both run on Sonnet by default. Subagents have their own context window, which keeps the main session focused on the broader feature work.

### Project commands (`.claude/commands/`)

- **`/qspec <feature>`** generates a Spec-Driven Development spec to `tasks/spec.md`, including empty test stubs that map to acceptance criteria.
- **`/tdd <behavior>`** runs a strict red, green, refactor cycle. Auto-invokes the relevant reviewer subagent based on the files touched.
- **`/qcheck`** runs a skeptical staff-engineer review of every changed file in the session.

The flow is `/qspec` to think, `/tdd` to build, `/qcheck` to ship.

### Settings (`.claude/settings.json`, `global/settings.json`)

- The **project** `settings.json` defines team-baseline permissions, project hooks (`PreToolUse`, `PostToolUse`, `Stop`), and the agent and command paths.
- The **global** `settings.json` defines a personal denylist (`rm`, `sudo`, `chmod`, `.env*`, secrets), the allowlist for common dev tools, and the global hook registrations.

You'll also want a `settings.local.json` (gitignored) for personal allowances that don't belong in the team file. There's no example here because it's intentionally yours alone.

---

## What's intentionally missing

Three things you won't find in this repo:

1. **A 753-line `coding-standards.md`.** The template is a skeleton with section headers and a few worked examples. Your real standards doc is yours to build.
2. **Project-specific `lessons.md` content.** The example file shows the format. Your gotchas come from your projects.
3. **A `settings.local.json`.** That file is personal, gitignored, and varies by user. Build your own as you go.

The repo gives you the system. The content goes in over time.

---

## Disclaimer

This is a solo-developer perspective. Team-scale configuration adds governance concerns (subagent ownership, command versioning, shared standards stewardship, audit aggregation) that aren't solved here.

Hooks are bash. Windows users will need WSL or PowerShell equivalents.

The `claude --print` invocation in `persist-memory.sh` makes a nested API call. Budget for it.

---

## Contributing

Issues and PRs welcome. Two principles:

1. Keep examples minimal and well-commented. The repo is a teaching tool, not a kitchen sink.
2. Match the documentation style. New patterns need a "what it does, why it exists, what it costs" paragraph.

If you're adding a new hook, subagent, or command pattern, include the lifecycle event it registers against and a one-paragraph rationale.

---

## License

MIT. See [LICENSE](LICENSE).

---

*Companion repo to [vinny.dev/blog](https://vinny.dev/blog). Fork it. Take what's useful. Skip the rest.*
