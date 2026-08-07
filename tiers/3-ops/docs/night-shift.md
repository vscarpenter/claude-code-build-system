# Night shift — operating spec

The night shift is a **nightly, unattended** local Claude Code routine (the maintenance loop). Each evening it triages failing checks on the agent fleet's own open PRs, clearing mechanical failures before they cost you attention. It **never merges**. It is launched by `scripts/build-system/triage-run.sh`; its per-run instructions live in `.claude/commands/triage-prs.md`; this file is the durable operating spec both reference.

Runtime config (verify commands, protected paths, branch prefix) comes from `.build-system.json` at the repo root. Definition of done for any fix is `coding-standards.md`.

## The nightly loop

```
20:00 scheduler → triage-run.sh
   triage:paused set? → post one line, exit                       (kill switch)
   find open <branchPrefix>/* PRs with a failing check → none? exit
   else: worktree off the default branch → claude -p "/triage-prs"
         → for each failing agent PR (oldest first, ≤3 fix PRs):
              reproduce → classify → fix+verify → fix PR   |  escalate  |  skip
         → post self-audit report to the Night Shift Control issue
```

Scope is **the fleet's own PRs only** — branches matching `<branchPrefix>/*` that originate from this repository itself. It never touches hand-authored branches, and it never checks out a fork's branch (a fork author controls their own branch names, so the prefix alone proves nothing).

## Auto-fix / escalate / skip policy

| Failing check | Action |
|---|---|
| Lint / formatting drift | **Fix** — run the project's lint/format fixers |
| Stale lockfile | **Fix** — regenerate with the project's package manager |
| Branch behind the default branch (fails only for being out of date) | **Fix** — merge the default branch (trivial conflicts only) |
| Simple typecheck / import error (unused/missing import, obvious annotation) | **Fix** — targeted, no logic changes |
| Logic **test** failure | **Escalate** (`ready-for-human` + reason) |
| **Any security-scan failure** | **Escalate** — never patch around |
| Ambiguous type error / non-trivial conflict / a fix that didn't verify | **Escalate** |
| Can't reproduce / flaky / external / already `ready-for-human` | **Skip + log** |

Every fix is delivered as a fix PR on a fresh `<branchPrefix>/fix-<branch>-<runid>` branch **targeting the failing branch**, so it re-enters review + CI. The night shift never merges.

## The two safety invariants

The broad auto-fix set is safe only because both hold:

1. **Verify before submit.** After applying a fix, re-run the failing check. Open a fix PR **only if it now passes** locally. A fix that doesn't make the check green is reverted and escalated — a plausible-but-wrong fix never leaves the machine.
2. **Fixes re-enter the gate.** Fix PRs face the same CI-required + reviewer + thread-resolution gate as daytime work, and the night shift **never merges**. Nothing it produces reaches a branch without human/gate sign-off.

## Hard limits

Never: merge, force-push, push to a branch it did not create, edit `.github/workflows/**`, deploy configuration, security config, or any path in `config.protectedPaths`, or patch around a security-scan failure. Only: create `<branchPrefix>/fix-*` branches, open fix PRs targeting the failing branch, comment, and apply `ready-for-human` / labels. **≤3 fix PRs per run.** Operate only in the isolated worktree.

## Escalation

When a check needs judgment (logic test, security, ambiguity, non-trivial conflict) or a fix fails to verify: add `ready-for-human` to the PR and comment a written reason stating exactly what is blocked and what input is needed. Never guess; never silently proceed.

## Self-audit report

At the end of every run, post one comment to the **Night Shift Control** issue (pinned; also carries the `triage:paused` kill switch): what was **fixed** (fix-PR links), **escalated** (reasons), and **skipped** (reasons); the fix-PR count vs. the 3-PR budget; and **any anomaly the run noticed about itself** — a check it couldn't classify, a fix it was unsure about, a limit it hit. An unattended agent that files its own incident report is one you can leave alone at night. If it did nothing, it says so in one line.

## Kill switch

`triage-run.sh` checks for an open issue labeled `triage:paused` before doing anything and exits if found. To halt the night shift with no code change and no shell access, add `triage:paused` to the Night Shift Control issue; remove it to resume. The builder loop has the same switch under `builder:paused`.
