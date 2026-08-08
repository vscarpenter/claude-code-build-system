# Getting started

This walkthrough takes a new repository from install to its first controller-authored pull request.

## 1. Prerequisites

Tier 1 needs Bash, Git, and jq plus any supported interactive harness. Tier 2 adds Node, an authenticated `gh`, and either Claude Code or Codex CLI for controller work. Tier 3 adds an always-on macOS/Linux runner or the hosted Claude workflow.

```bash
gh auth status
./install.sh --tier 2 --target /path/to/repo --dry-run
./install.sh --tier 2 --target /path/to/repo
```

The installer creates 19 labels when `gh` is ready; otherwise it prints exact `MANUAL:` commands. `INSTALL` writes a managed file, `SKIP` preserves an unowned collision, and `KEEP` preserves a managed local adaptation. Target writes and the manifest are rolled back together on commit-phase failure.

## 2. Configure the repository

Rewrite the example `CLAUDE.md` and make the inert Claude Stop hook useful for your stack. Then replace every placeholder in `.build-system.json`:

```json
{
  "config": {
    "repo": "owner/project",
    "defaultBranch": "main",
    "harness": "codex",
    "verifyCommands": ["npm test", "npm run lint", "npx tsc --noEmit"],
    "protectedPaths": ["deploy/**", "infra/**", "SECURITY.md"],
    "allowedPaths": ["src/**", "test/**", "package.json"],
    "requiredChecks": ["test", "lint"],
    "branchPrefix": "agent"
  }
}
```

Verification commands run under controller ownership. They do not need to be added to a model tool allowlist. `protectedPaths` supplements the controller's always-protected instructions, workflow, manifest, controller, and Git metadata paths.

The hosted Claude responder, reviewer, and builder need `CLAUDE_CODE_OAUTH_TOKEN`:

```bash
gh secret set CLAUDE_CODE_OAUTH_TOKEN
```

## 3. Prove readiness

```bash
node scripts/build-system.cjs doctor --harness all
node scripts/build-system.cjs run --harness claude --dry-run
node scripts/build-system.cjs status --json
```

Tier 1 can also be exercised interactively with `/qspec`, `/tdd`, and `/qcheck`; other harnesses discover the same sources under `.agents/skills`.

`doctor=READY` is necessary but not the production release proof. In a sandbox using the actual automation credential, demonstrate that direct default-branch push, force-push, and merge are rejected. GitHub rulesets and bypass identities can make settings look stricter than effective access.

## 4. First contract

1. Open the **New Change** issue form. Supply acceptance criteria, constraints, out of scope, rollback, and risk.
2. Risk automation leaves the lifecycle at `needs-triage`. Replace it with `ready-for-agent` only when the contract is complete.
3. Run `node scripts/build-system.cjs run --harness <claude|codex>`.
4. For feature/risky work, inspect the plan and approve with `node scripts/build-system.cjs approve --issue N`. For revision, move to `plan:revise` and explain why.
5. Run the controller again. It acquires the remote lease, creates a unique worktree, invokes the bounded worker, audits the real diff, verifies, confirms Gate 2 rules, and creates the PR.
6. Review and merge manually. Then use `node scripts/build-system.cjs reconcile --apply` to mark an exactly matched merged delivery `done`.

Docs and chore risk may auto-approve Gate 1 by repository policy. Editing contract-bearing issue content invalidates readiness and is rechecked before any worker starts.

## 5. Tier 3 scheduling

The installer prints a collision-resistant runtime config path such as:

```text
~/.build-system/repos/project-4b9ac7c3d2e1/config.json
```

The immutable runtime lives under `~/.local/libexec/claude-code-build-system/3.0.0/` with a hash manifest. Verify it without spending a provider call:

```bash
~/.local/libexec/claude-code-build-system/3.0.0/builder-run.sh \
  --config ~/.build-system/repos/<repo-id>/config.json --check
```

Copy the plist templates from `scripts/build-system/`, replace `{{RUNTIME_PATH}}` and `{{RUNTIME_CONFIG}}`, and load them with `launchctl`; Linux users can translate the documented immutable-runtime command to cron. The installer never starts a scheduler for you.

Night shift is now deterministic diagnosis only. It reports failing PRs whose exact branch and head SHA match controller provenance; it does not invoke a model or write a fix.

## 6. Operate and recover

`builder:paused` blocks new runs and delivery. `triage:paused` blocks diagnosis. Both fail closed when GitHub state cannot be read.

Run evidence is private under `${XDG_STATE_HOME:-~/.local/state}/build-system/<repo-id>/`. Use `reconcile` read-only first; add `--apply` only after reviewing expired leases and delivery provenance. See the [runbook](runbook.md) for the failure matrix and [the explainer](build-system-explainer.html) for the complete visual flow.

Upgrade with `./install.sh --upgrade --target /path/to/repo`. Locally adapted files remain `KEEP` across repeated upgrades; use `--force` only when you intend to replace them.
