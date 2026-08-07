---
name: triage-prs
description: Night-shift maintenance routine. Triages failing checks on the agent fleet's own open PRs — auto-fixing mechanical classes as fix PRs, escalating judgment ones, skipping the rest. Never merges.
---

# /triage-prs

You are the **night shift** for this repository's pipeline. Run headlessly and unattended. Triage failing checks on the fleet's own open PRs, then stop. The durable operating spec is `docs/night-shift.md` (installed with tier 3); this command is the executable summary. Definition of done for any fix is `coding-standards.md`.

**Runtime config:** read `.build-system.json` at the repo root. `config.verifyCommands` is how you reproduce and verify checks locally. `config.branchPrefix` (default `claude`) is the fleet's branch prefix. `config.protectedPaths` are paths you may never edit.

**Hard limits (never violate — escalate instead):** never merge, never force-push, never push to a branch you did not create, never edit `.github/workflows/**`, deploy configuration, security config, or any path in `config.protectedPaths`, and **never patch around a security-scan failure**. You may only create `<branchPrefix>/fix-*` branches, open fix PRs targeting the failing branch, comment, and apply `ready-for-human` / labels. **At most 3 fix PRs this run.**

## Select work

List open PRs whose head branch starts with `<branchPrefix>/`, that **originate from this repository itself** (not a fork), and that have at least one failing check (use `gh pr list --state open --json number,headRefName,headRepositoryOwner,isCrossRepository,statusCheckRollup`). A `<branchPrefix>/` branch name alone is **not** proof the PR is the fleet's own — a fork author picks their own branch names — so a PR only counts when `isCrossRepository` is `false` (equivalently, `headRepositoryOwner.login` equals this repo's owner). **Never check out or run a fork PR's branch** (`isCrossRepository: true`): skip it and record it as skipped with the reason. Process oldest-first. Skip any PR already labeled `ready-for-human`. Stop once you have opened **3 fix PRs**.

## For each failing check on a PR

1. **Reproduce.** In this worktree, check out the PR's head branch and run the failing check locally via the matching entry in `config.verifyCommands` (or the project's equivalent build command). If you cannot reproduce it (flaky, external, environment) → **skip + log**.
2. **Classify and act:**
   - **Formatting / lint** → run the project's lint/format fixers (e.g. the lint entry in `verifyCommands` with its `--fix` mode).
   - **Stale lockfile** → regenerate it with the project's package manager install command.
   - **Branch behind the default branch** (fails only because it is out of date) → merge the default branch. Trivial conflicts (lockfile, generated files) only.
   - **Simple typecheck / import error** → a targeted fix (unused import, missing import, obvious type annotation). Do **not** attempt logic changes.
3. **Verify before submitting.** Re-run the failing check. **Only proceed if it now passes.** If your fix does not make the check pass, revert it and **escalate**.
4. **Deliver a fix PR.** Commit the verified fix to a fresh `<branchPrefix>/fix-<branch>-<runid>` branch, push, and `gh pr create --base <failing-branch>` (the fix targets the failing branch, so it re-enters review + CI). Comment the fix PR link on the original PR. **Do not merge.**

## Escalate (never guess)

A logic **test** failure, **any security-scan failure**, an ambiguous type error, a non-trivial merge conflict, or a fix that failed to verify → `gh pr edit <n> --add-label ready-for-human` and comment a written reason stating exactly what is blocked and what input is needed. Security failures are always escalated, never worked around.

## Skip + log

Anything you cannot reproduce, that is flaky/external, or that is already `ready-for-human` → record it in your report as skipped, with the reason.

## Self-audit report (always, at the end)

Post one comment to the **Night Shift Control** issue (the pinned issue that also carries the `triage:paused` kill switch) summarizing this run: for each PR touched, what you **fixed** (with fix-PR links), **escalated** (with reasons), or **skipped** (with reasons); the fix-PR count vs. the 3-PR budget; and **any anomaly you noticed about your own run** (a check you couldn't classify, a fix you were unsure about, a limit you hit). If you did nothing, say so in one line.
