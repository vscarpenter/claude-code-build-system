# Runbook

How to operate the pipeline day to day: the gates, the switches, and what to do when something goes sideways. If you have not run a change through it yet, start with [getting-started.md](getting-started.md) and come back here.

## Gate 1: approving plans

A `plan:pending` issue has a plan comment waiting on you. Three moves:

- **Approve:** swap the label to `plan:approved`. The builder claims it on its next wake-up.
- **Request changes:** comment `/revise <what should change>` and swap the label to `plan:revise`. The builder re-plans and hands it back as `plan:pending`.
- **Take it yourself:** swap to `ready-for-human` and the fleet leaves it alone.

Label swaps are the whole protocol. The builder cannot see your intent in prose alone; a `plan:pending` issue with an unlabeled "looks good" comment waits forever.

## Gate 2: releasing

Gate 2 is the merge button, deliberately manual. Verify the PR against the acceptance criteria from the contract, confirm the rollback plan is real, then merge. No rollback path means no approval. The builder filled the PR body with the verification steps and the rollback plan from the issue, so the review is a checklist, not archaeology.

## Pausing the fleet

- `builder:paused` on any open issue stops the builder loop.
- `triage:paused` on any open issue stops the night shift. Convention: keep one pinned "Night Shift Control" issue that carries the switch and receives the nightly self-audit reports.
- Both switches work from a phone, with no code change and no shell access. Remove the label to resume.

## Reading the telemetry

Every builder run ends with `OPENED_PR=<n>` or `OPENED_PR=none`. The local driver pairs that line with the run's token usage and posts a hidden comment marker (`<!-- build-system-tokens ... -->`) on the PR it opened. Run logs land in `BS_LOG_DIR` (default `docs/ops/agent-logs/`): JSON output per builder run, a text log per night-shift run, and `gh-errors.log` when the pre-checks cannot reach GitHub.

## Failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| Builder never wakes with work waiting | `gh` auth expired; pre-check fails safe to idle | `gh auth status`, then check `gh-errors.log` |
| Builder escalates every issue | `config` still has `REPLACE:` placeholders | fill in `.build-system.json` |
| Runs start but produce nothing | `claude` CLI missing from the scheduler's PATH | check the PATH append in the driver |
| Worktree in a weird state | an interrupted run | delete it; the driver recreates it from the default branch |
| Labels missing on a new repo | `gh` was unauthenticated during install | run the printed `MANUAL:` commands |
| Night shift opens no fix PRs | nothing failing, or every failure needs judgment | read the self-audit report |
| Issue gets no `risk:*` label | the body carries more than one "Risk tier" section, so the parser refuses to guess | edit the body, or apply the label yourself; an unlabeled issue is planned as `risk:feature` and stops at Gate 1 |

## Cost notes

Idle wake-ups are free by design: the drivers pre-check labels with `gh` before invoking Claude. What costs tokens is planning, building, and triage. The risk tiers hold the spend down where it matters least: docs and chore work skips the second planning round-trip, and the night shift caps itself at three fix PRs per run. The hosted variant costs more per unit of work because every trigger is a full Claude run with no cheap pre-check in front of it.

## When the agent goes wrong

The failure you will actually see is an escalation: `ready-for-human` plus a comment saying exactly what blocked it. That is the system working. The failure to watch for is a PR that passes checks but misreads the contract, which is what Gate 2 is for. If a bad PR gets close to merging, tighten the contract fields on the issue form before tightening the agent; a vague contract produces a plausible plan for the wrong problem.
