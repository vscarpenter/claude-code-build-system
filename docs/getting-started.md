# Getting started

This walkthrough has two stopping points: a Tier 1 interactive workflow and a
Tier 2 controller-authored pull request. Tier 3 scheduling comes last. Follow
only the path you intend to use.

## 1. Choose the outcome

| Outcome | Tier | Required locally |
|---|---:|---|
| Shared spec, TDD, and review workflows inside an interactive harness | 1 | Bash, Git, jq, and Claude Code, Codex, OpenCode, or a supported Copilot surface |
| A GitHub issue delivered as a bounded Claude- or Codex-authored PR | 2 | Tier 1 plus Node, authenticated `gh`, a GitHub remote, and one Claude Code or Codex CLI |
| Scheduled local or hosted execution | 3 | Tier 2 plus an always-on macOS/Linux machine or the hosted Claude workflow |

Tiers are cumulative. If you are unsure, start with Tier 1 and stop after
section 3. The [adoption guide](adoption.md) explains the trust added by each
tier.

## 2. Set the source and target once

Clone the distribution beside—not inside—the Git repository that will adopt
it. Use absolute paths so the installer repository and target repository never
get confused:

```bash
git clone https://github.com/vscarpenter/claude-code-build-system
BUILD_SYSTEM_DIR="$PWD/claude-code-build-system"
TARGET_REPO="/absolute/path/to/your/repo"
TIER=1

git -C "$TARGET_REPO" rev-parse --show-toplevel
```

The target must already be a Git repository, and `--target` must name its root.
If the distribution is already cloned, set `BUILD_SYSTEM_DIR` to that existing
absolute path instead. For Tier 2 or 3, select a controller harness and confirm
the target's authenticated GitHub remote:

```bash
TIER=2        # use 3 when adding scheduled operation
HARNESS=codex # or claude
gh auth status
git -C "$TARGET_REPO" remote get-url origin
```

Preview, install, and then deliberately change into the target:

```bash
"$BUILD_SYSTEM_DIR/install.sh" --tier "$TIER" --target "$TARGET_REPO" --dry-run
"$BUILD_SYSTEM_DIR/install.sh" --tier "$TIER" --target "$TARGET_REPO"
cd "$TARGET_REPO"
```

`INSTALL` writes a managed file, `SKIP` preserves an unowned collision, and
`KEEP` preserves a managed local adaptation. Tier 2 creates 19 labels when `gh`
is authenticated; otherwise the installer prints exact `MANUAL:` commands.

## 3. Finish Tier 1

Tier 1 ships a deliberately detailed example, not project truth. Before using
it:

1. Rewrite `CLAUDE.md` with the target repository's stack, structure, commands,
   and gotchas.
2. Review `coding-standards.md` and the two specialist profiles under
   `.claude/agents/`; remove examples that do not fit the project.
3. In `.claude/settings.json`, either leave the inert Stop hook as `true` or
   replace it with a fast command that exists in this project.
4. Commit `.build-system.json` and the installed files.

Claude Code exposes `/qspec`, `/tdd`, and `/qcheck`. Codex, OpenCode, and
supported Copilot surfaces discover `qspec`, `tdd`, and `qcheck` under
`.agents/skills/`; invoke them using that harness's Agent Skill syntax.

Stop here if you installed Tier 1. The remaining sections are for the
issue-to-PR controller.

## 4. Configure Tier 2

Open `.build-system.json`. Replace every `REPLACE:` value and confirm every
policy field before the first run. This complete example shows the expected
shape; keep the installer-generated `schemaVersion`, `systemVersion`, `tier`,
and `files` fields around it:

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
    "branchPrefix": "agent",
    "leaseMinutes": 90,
    "runTimeoutSeconds": 3600,
    "verifyTimeoutSeconds": 900,
    "maxChangedFiles": 100,
    "maxDiffBytes": 1048576,
    "dailyRunLimit": 20,
    "maxConsecutiveFailures": 3,
    "maxBudgetUsd": 10
  }
}
```

Use the exact repository identity returned by:

```bash
gh repo view --json nameWithOwner --jq .nameWithOwner
```

`verifyCommands` run under controller ownership after the worker finishes.
`allowedPaths` bounds ordinary edits; `protectedPaths` adds repository-specific
restrictions to the controller's always-protected control-plane paths. Set
`requiredChecks` to the exact GitHub check names already produced by CI. An
empty array is accepted for a repository with no checks, but it does not prove
CI protection. The [customization guide](customizing.md) includes stack-specific
verification examples.

Choose `branchPrefix` before the first run. Changing it later does not transfer
existing leases, branches, or provenance.

## 5. Configure GitHub and commit the installation

Follow [GitHub setup](github-setup.md) to configure branch protection, required
checks, workflow permissions, and the live Gate 2 proof. Then commit and push
the installed files so GitHub can see the issue form and workflows:

```bash
git status --short
jq -r '.files[].path' .build-system.json |
  while IFS= read -r path; do git add -- "$path"; done
git add .build-system.json
git diff --cached --stat
git commit -m "chore: adopt deterministic build system"
git push
```

The hosted Claude responder, reviewer, and Tier 3 builder require
`CLAUDE_CODE_OAUTH_TOKEN`:

```bash
gh secret set CLAUDE_CODE_OAUTH_TOKEN
```

That secret is not required for a local Claude or Codex controller. If you do
not use the hosted Claude responder or reviewer, disable
`.github/workflows/claude.yml` and
`.github/workflows/claude-code-review.yml` before committing them rather than
leaving workflows that will fail when triggered.

## 6. Prove one harness is ready

Run `doctor` for the one controller adapter you intend to use:

```bash
node scripts/build-system.cjs doctor --harness "$HARNESS"
node scripts/build-system.cjs status --json
```

Do not continue until the final line is `READY`. `--harness all` is optional
and intentionally requires both Claude Code and Codex to be installed and
authenticated; it is a compatibility audit, not a first-run requirement.

`doctor=READY` is necessary but not production release proof. In a disposable
sandbox, use the actual automation credential to demonstrate that direct
default-branch push, force-push, and merge are rejected. GitHub rulesets,
bypass identities, and token settings can make configuration look stricter
than the credential's effective access. Record that result outside the
model-generated evidence.

## 7. Deliver the first contract

1. Open the **New Change** issue form. Supply acceptance criteria, constraints,
   out of scope, rollback, and risk. The form applies `needs-triage`; the risk
   workflow separately applies one `risk:*` label.
2. Replace `needs-triage` with `ready-for-agent` only after the contract is
   complete.
3. Preview queue selection without invoking a provider:

   ```bash
   node scripts/build-system.cjs run --harness "$HARNESS" --issue 42 --dry-run
   ```

4. Run the controller once to create the plan:

   ```bash
   node scripts/build-system.cjs run --harness "$HARNESS" --issue 42
   ```

5. For feature or risky work, inspect the posted plan and bind Gate 1 to it:

   ```bash
   node scripts/build-system.cjs approve --issue 42
   ```

   Docs and chore plans auto-approve by repository policy. To request a
   revision, move the issue to `plan:revise`, explain the required change, and
   run the controller again.
6. Run the controller again. It acquires the remote lease, creates an isolated
   worktree, invokes the bounded worker, audits the real diff, verifies it,
   confirms Gate 2 rules, commits, pushes, and opens the PR.
7. Review and merge manually. The controller never merges.
8. Reconcile read-only first, then apply the exact matched transition:

   ```bash
   node scripts/build-system.cjs reconcile
   node scripts/build-system.cjs reconcile --apply
   ```

Editing contract-bearing issue content invalidates readiness and is rechecked
before any worker starts.

## 8. Add Tier 3 scheduling

The installer prints a collision-resistant `RUNTIME_CONFIG` path such as:

```text
~/.build-system/repos/project-4b9ac7c3d2e1/config.json
```

Select its harness, then verify the immutable runtime without spending a
provider call:

```bash
~/.local/libexec/claude-code-build-system/3.0.0/builder-run.sh \
  --config ~/.build-system/repos/<repo-id>/config.json --check
```

Copy the plist templates from `scripts/build-system/`, replace
`{{RUNTIME_PATH}}` and `{{RUNTIME_CONFIG}}`, and load them with `launchctl`.
Linux users can run the same immutable-runtime command from cron. The installer
never starts a scheduler for you.

Night shift is deterministic diagnosis only. It reports failing PRs whose
exact branch and head SHA match controller provenance; it does not invoke a
model or write a fix.

## 9. Operate, recover, and upgrade

`builder:paused` blocks new runs and delivery. `triage:paused` blocks diagnosis.
Both fail closed when GitHub state cannot be read.

Run evidence is private under
`${XDG_STATE_HOME:-~/.local/state}/build-system/<repo-id>/`. Use `reconcile`
read-only first; add `--apply` only after reviewing expired leases and delivery
provenance. See the [runbook](runbook.md) for the failure matrix.

Run upgrades from the distribution repository while keeping the target path
explicit:

```bash
"$BUILD_SYSTEM_DIR/install.sh" --upgrade --target "$TARGET_REPO" --dry-run
"$BUILD_SYSTEM_DIR/install.sh" --upgrade --target "$TARGET_REPO"
```

Locally adapted files remain `KEEP` across repeated upgrades. Use `--force`
only when you intend to replace them.
