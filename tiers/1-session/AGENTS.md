# AGENTS.md

This repository uses the Build System's harness-neutral working contract. Codex,
OpenCode, and GitHub Copilot discover this file; Claude Code discovers
`CLAUDE.md`. Apply the same project rules regardless of harness.

## Start here

1. Read `CLAUDE.md` for the project's concrete stack, commands, structure, and
   gotchas. Its filename is a compatibility surface, not a vendor restriction.
2. Read `coding-standards.md` when planning, implementing, or reviewing work.
3. Read `.build-system.json` before pipeline work. Treat `verifyCommands`,
   `protectedPaths`, and `branchPrefix` as runtime policy.
4. Preserve unrelated working-tree changes. Never merge, force-push, push to
   the default branch, or edit a protected path on an unattended run.

## Portable workflows

Reusable workflows live under `.agents/skills/`:

- `qspec` turns a feature request into an executable spec.
- `tdd` runs an approved change through red, green, and refactor.
- `qcheck` performs an adversarial pre-ship review.

Tier 2 adds two controller workflows:

- `build-next` plans or builds one queued issue and never merges.
- `triage-prs` performs provenance-bound diagnosis and escalation.

Invoke skills using the syntax supported by the active harness. Claude Code
also exposes the same sources as slash commands under `.claude/commands/`.

## Proof and safety

Distinguish source inspection, passing tests, a successful build, a running
system, and a completed external action. Report only the strongest state that
was actually verified. Instructions and hooks are guardrails, not a security
boundary; unattended operation also depends on credentials, branch rules,
sandboxing, and deterministic runner checks.
