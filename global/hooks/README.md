# Global hooks

Three shell scripts that fire deterministically on Claude Code lifecycle events. They live in `~/.claude/hooks/` and register against events in `~/.claude/settings.json`.

## Installation

```bash
# Copy the scripts and make them executable
mkdir -p ~/.claude/hooks
cp audit-command.sh capture-decision.sh persist-memory.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/*.sh

# Copy the settings file (or merge into your existing one)
cp ../settings.json ~/.claude/settings.json
```

## What each hook does

### `audit-command.sh`

**Event:** `PreToolUse`
**Matcher:** `Bash`
**Cost:** Negligible (no API calls)
**What it does:** Logs every Bash command Claude proposes to `~/.claude/audit/audit-YYYY-MM-DD.log`. Pattern-matches against high-risk shapes (`curl | sh`, `eval`, `git push --force`, etc.) and routes risky commands to a separate `flagged-` log.
**Why it matters:** You don't need to do anything with the log on day one. You'll be glad it exists the first time something breaks and you need to retrace what happened.

### `capture-decision.sh`

**Event:** `PostToolUse`
**Matcher:** `Edit|Write|MultiEdit`
**Cost:** One `git diff --stat` per file mutation
**What it does:** Captures the file path, session ID, tool name, and a `git diff --stat` snapshot to `~/.claude/decisions/decisions-YYYY-MM-DD.log` after every file mutation.
**Why it matters:** When a regression shows up two weeks later, scroll back through the log to find the likely cause.

### `persist-memory.sh`

**Event:** `SessionEnd`
**Matcher:** none
**Cost:** At most one nested `claude --print` call per session end, capped at 64 KB of transcript tail. Sessions that didn't edit any files skip the call entirely (see "Activity gate" below).
**What it does:** Reads the session transcript at `transcript_path`, pipes it into a fresh `claude --print` invocation, asks the model to extract 1-3 reusable learnings, and appends them to `~/.claude/lessons.md`.
**Why it matters:** Over weeks, that file becomes an institutional memory of patterns and gotchas you would otherwise forget.

**Activity gate.** Before calling `claude --print`, the hook checks `~/.claude/decisions/` (populated by `capture-decision.sh`) for any entries tagged with the current `session_id`. If the session produced no Edit/Write events, it exits 0 without making an API call. Read-only or trivial sessions cost nothing.

**Recursion guard.** The nested `claude --print` invocation is itself a Claude Code session, and its SessionEnd would re-fire this hook. To prevent the loop, the hook exports `CLAUDE_PERSIST_MEMORY_RUNNING=1` before calling out; any nested invocation sees the sentinel and exits immediately. Without this guard, a single SessionEnd could chain into multiple paid API calls.

## Verification

After installing, exit a Claude Code session and check the log files:

```bash
# Should have entries from your most recent session
ls -la ~/.claude/audit/
ls -la ~/.claude/decisions/

# Check the persist-memory output
tail -20 ~/.claude/lessons.md
```

If `~/.claude/lessons.md` doesn't grow after a session that produced clear decisions, the most likely culprit is the `claude --print` call failing or the `transcript_path` not resolving. Run the hook manually to debug:

```bash
echo '{"session_id":"test","transcript_path":"/path/to/recent/session.jsonl"}' | \
  ~/.claude/hooks/persist-memory.sh
```

## Customization

Each hook reads from environment variables for its output paths, so you can override them per machine:

```bash
export CLAUDE_AUDIT_DIR=/custom/audit/path
export CLAUDE_DECISION_DIR=/custom/decision/path
export CLAUDE_MEMORY_FILE=/custom/lessons.md
```

## Failure modes

Hooks fail silently when they break. The first sign is something missing from the logs. If a hook stops working:

1. Run the hook manually with sample input (see Verification above).
2. Check `claude --debug` output for hook execution errors.
3. Verify `jq` is installed and on `PATH`.
4. Verify the hook script is executable (`chmod +x`).

Hooks that error during execution emit stderr to the Claude Code transcript, but only when stderr is non-empty. Silent failures are the norm.
