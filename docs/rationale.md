# Rationale

Why the repo is structured the way it is. This file is for readers who want the reasoning, not just the configuration.

If you only want to use the configuration, the README and the per-piece walkthroughs are enough. Skip this file.

---

## Why a `.claude/` directory at the project root

Claude Code looks for `.claude/settings.json`, `.claude/agents/`, and `.claude/commands/` at the project root. Drop the contents of this repo's `.claude/` directory into your project's root, and Claude Code finds them automatically. No path configuration. No environment variables.

The repo mirrors that convention so you can clone, copy, and run.

## Why `global/` is a sibling rather than nested

Global configuration lives in `~/.claude/`, not in any specific project. Putting it next to `.claude/` (rather than inside) makes the distinction obvious: project files go in the project, global files go in your home directory.

If `global/` were nested inside `.claude/`, readers would copy the wrong things into the wrong places.

## Why hooks are bash, not Node or Python

Hooks need to start fast. Bash starts in milliseconds. Node and Python add 100 to 500 ms of cold start, which compounds across a session.

Bash is also the lowest common denominator. Every developer machine has bash. Not every developer machine has the right Python version on `PATH`.

The trade-off is that bash is harder to write robustly than Node or Python. The hooks here lean on `jq` for JSON parsing rather than rolling their own.

## Why three hooks instead of one

Each hook does one thing. They run on different lifecycle events and have different cost profiles.

- `audit-command.sh` runs on every Bash invocation. It must be cheap. No API calls.
- `capture-decision.sh` runs on every file mutation. One `git diff --stat` per call is acceptable.
- `persist-memory.sh` runs once per session, at the end. It can afford an API call.

A single hook would either be too expensive (running an API call on every Bash command) or too coarse (skipping per-mutation capture to keep the cost down).

## Why subagents instead of inline reviews

The main Claude session is a generalist. Pushing specialist reviews into subagents accomplishes three things:

1. **Focus.** A subagent's context window is just the review prompt and the changed files. No feature-work clutter.
2. **Cost control.** Subagents can run on Sonnet while the main session runs on Opus.
3. **Reusability.** A subagent's prompt is a markdown file. Version it. Review it. Share it.

Trade-off: subagents add latency. A subagent invocation adds the time to spin up a new context plus the review itself. For trivial files, an inline review is faster. For files with hard, non-obvious constraints, the subagent's focused prompt outperforms a generalist pass.

## Why three slash commands instead of one super-command

`/qspec`, `/tdd`, and `/qcheck` correspond to three distinct cognitive moves: think, build, ship.

Combining them ("`/feature <description>`") would conflate the steps. The discipline is in the separation. Spec before test. Test before implementation. Review before merge.

## Why the project `settings.json` has both `permissions` and `hooks`

The post emphasizes that permissions are safety equipment and hooks are enforcement. The project `settings.json` is where both live for the team baseline.

Personal allowances (the things you, but not your teammates, want to allow) belong in `settings.local.json`, which is gitignored. There's no example in this repo for that file because it's intentionally yours alone.

## Why `tiers/` mirrors a target repo instead of a `templates/` folder (v2)

v1 kept a `templates/` directory you copied by hand. v2 replaces it with `tiers/`, where each tier's tree mirrors a target repo's layout exactly. The installer copies verbatim, which means the source tree *is* the documentation of where things land. There is no mapping table to keep in sync, and `diff -r tiers/1-session/ yourrepo/` answers "what would change" directly.

The old skeleton-versus-example split survives in spirit. `standards/coding-standards.md` is the fully populated doc the installer stamps into your repo, and `docs/coding-standards-skeleton.md` (installed with tier 1) is the empty shape for writing your own. A skeleton tells you the *shape*. A populated version tells you the *depth*.

## Why `lessons.md` uses one-line entries

Each lesson is a fact. Facts that need more than one line are usually two facts that should be split.

The flat format also makes the file scannable. A 50-entry `lessons.md` should still be readable in 90 seconds. Hierarchical organization adds overhead without adding value.

## Why no MCP servers in the starter kit

MCP servers are the next layer. They are powerful and they add complexity. Adding them to the starter kit before the basics are in place would obscure the principles.

Once you have the five steps from "What changes Monday" working, MCP servers are a natural addition. Start with one (a calendar MCP, an issue tracker MCP, a search MCP). See what changes. Add the next.

## Why the audit log is plain text, not JSON

The audit log is read by humans, not parsers. Plain text greps cleanly with `grep`, `awk`, `sort`, and `tail`. JSON would require `jq` for every read.

If you ever need to aggregate audit logs across a team, convert at the aggregation layer. The local log stays text.

## Why the post recommends `--bare` for SDK calls but the hook script doesn't use it

`--bare` skips auto-discovery (hooks, skills, plugins, MCP servers, auto memory, CLAUDE.md). For most scripted calls, that's the right default.

For `persist-memory.sh` specifically, the nested `claude --print` call benefits from a fresh, lightweight invocation. Adding `--bare` would speed it up further. It's omitted from the example to keep the script readable, but you should add it if you want the lowest-latency version:

```bash
LEARNINGS=$(cat "$TRANSCRIPT_PATH" | claude --print --bare \
  "Review this Claude Code session transcript...")
```

## Why no Windows-specific scripts

The post's footnote covers this: hooks are bash. Windows users need WSL or PowerShell equivalents. The repo could include PowerShell ports, but they would diverge from the bash versions over time, and the bash versions are the ones actually tested in daily use.

If you port the hooks to PowerShell, send a PR. They'd live in `global/hooks/win/` or similar.

---

# v2 decisions

Everything below arrived with v2, when the repo grew from session configuration into the installable pipeline.

## Why an installer script instead of a Claude Code plugin

A plugin can carry commands, skills, and hooks. It cannot manage `.github/` files, issue templates, labels, or scheduler scripts, which is half the system. One installer with one mental model beat two distribution mechanisms with a seam down the middle. The installer is bash for the same reason the hooks are: it starts instantly and runs anywhere.

## Why a manifest with content hashes

The hard problem in "install into 40 existing repos" is not copying files. It is upgrading later without destroying what each repo changed on purpose. The manifest records a sha256 per managed file at install time, which gives `--upgrade` a three-way signal: unmodified files re-sync silently, modified files are kept with a notice, and `--force` states intent explicitly. Homebrew and every serious dotfile manager converged on the same shape. Git subtree or submodules could version the files too, but they entangle your repo's history with mine, and their failure modes are famously unfriendly.

## Why runtime config lives in the manifest, not in rendered templates

The agent commands need three project facts: verify commands, protected paths, and a branch prefix. Rendering them into the command text at install time would fork every command file per repo, and `--upgrade` would have to re-render instead of re-sync. Keeping the commands generic and reading `.build-system.json` with `jq` at runtime means one canonical command text everywhere, upgradable by hash. The placeholders self-describe (`REPLACE: e.g. bun run test`) because JSON has no comments, and the builder escalates rather than run unconfigured.

## Why local-first for the builder, with a hosted variant

The battle-tested loop runs on a Mac under launchd. Local execution gets you cheap pre-checks (a `gh` label count before any Claude run), your own credentials and toolchain, and worktree isolation next to the checkout you already trust. The hosted variant exists because "a machine that is usually on" is a real barrier for some adopters, but it is documented as the second path: every trigger is a full Claude run, and the tool allowlist and OAuth token live in repo settings instead of your keychain.

## Why labels are the state store

Labels survive process restarts, cost nothing to read, are visible in the GitHub UI, and can be flipped from a phone. That last property is the point: Gate 1 and both kill switches are label swaps, so operating the pipeline requires no shell. The alternative (state files in the repo, or a database) would be invisible in the UI and would put pipeline state in commits.

## What v2 deliberately leaves out

- **npm/bun packaging and a marketplace plugin.** Two more distribution channels to keep honest; the installer already covers both new and existing repos.
- **Windows-native support.** Same position as v1: bash under WSL works, native PowerShell ports would drift.
- **AGENTS.md / Codex variants.** The standards doc marks the Claude-specific part, but shipping parallel agent configs doubles the test surface.
- **Telemetry dashboards.** The token markers and run logs are grep-able; aggregation belongs to whoever needs it.
- **Multi-standards support.** One canonical standards doc plus a skeleton. A standards *registry* is complexity without a second user.
