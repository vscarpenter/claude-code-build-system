---
name: build-next
description: Run one deterministic issue-to-PR controller cycle. The harness may plan or edit; the controller alone claims, verifies, commits, pushes, opens PRs, and changes state.
argument-hint: "[--harness claude|codex] [--issue N] [--dry-run]"
---

# Build next

This workflow is an entry point to the deterministic controller. Do not
reimplement queue selection, label changes, Git operations, verification, or PR
delivery in the current model session.

1. Read `.build-system.json` and `AGENTS.md` or `CLAUDE.md`.
2. If `$ARGUMENTS` appears literally, ignore it. Otherwise pass only supported
   `--harness`, `--issue`, and `--dry-run` arguments through.
3. Run exactly one controller command from the repository root:

   ```bash
   node scripts/build-system.cjs run $ARGUMENTS
   ```

4. Report the controller-authored terminal JSON and its evidence path. Never
   infer success from model prose.

The controller provides these guarantees:

- an atomic remote Git-ref lease selects one worker;
- every run gets a unique worktree outside the active checkout;
- contract, plan, and Gate 1 approval digests must match;
- the harness receives no GitHub token and no Git/GitHub delivery capability;
- protected paths, branch identity, diff size, symlinks, and gitlinks are
  checked before delivery;
- configured verification runs under controller ownership;
- Gate 2 branch rules must be positively verified before push;
- the controller creates and independently resolves the PR;
- evidence and provenance come from controller/platform observations.

Use `node scripts/build-system.cjs doctor --harness all` when the controller
refuses to start, and `node scripts/build-system.cjs reconcile` to inspect stale
leases without changing them.
