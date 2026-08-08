# Runbook

## Before the first run

Fill every `REPLACE:` value in `.build-system.json`, then run:

```bash
node scripts/build-system.cjs doctor --harness all
node scripts/build-system.cjs run --harness claude --dry-run
```

`doctor` must report `READY` before autonomous use. Independently test the real automation credential against a sandbox repository: direct default-branch push, force-push, and merge must all be rejected. Record that live result outside the model-generated evidence.

## Gate 1

A `plan:pending` issue contains a controller marker binding the current contract digest to the proposed plan digest.

- Approve with `node scripts/build-system.cjs approve --issue N`. The controller verifies the current GitHub actor has write permission and records the exact digests.
- Request revision by moving the lifecycle label to `plan:revise` and explaining the change.
- Take over by moving it to `ready-for-human`.

Editing contract-bearing issue content invalidates readiness through the risk workflow. The build controller also recomputes the digest before it calls a worker.

## Gate 2

Gate 2 is the protected merge. Review acceptance criteria, rollback, controller verification evidence, and CI. The controller never merges. If effective rules are unknown, delivery stops before push.

## Pause and resume

- Any open issue with `builder:paused` blocks new builder work and is checked again before delivery.
- Any open issue with `triage:paused` blocks night-shift diagnosis.
- Removing the label resumes future runs. In-flight work may finish editing, but delivery is barred by the second builder pause check.

## Commands

```bash
node scripts/build-system.cjs status --json
node scripts/build-system.cjs run --harness codex --issue 42
node scripts/build-system.cjs triage --json
node scripts/build-system.cjs reconcile
node scripts/build-system.cjs reconcile --apply
```

`reconcile` is read-only unless `--apply` is present. Apply mode CAS-releases expired leases, makes stranded active work retryable, marks exactly matched merged deliveries done, and escalates provenance drift.

## Evidence

Run evidence lives under `${XDG_STATE_HOME:-~/.local/state}/build-system/<repo-id>/`, never in the working repository. Directories are mode `0700`; files are mode `0600`.

- `runs/<run-id>/work-order.json` — controller-owned bounds;
- `prompt.txt`, provider events, stderr, normalized `agent-result.json` — worker artifacts;
- `evidence.jsonl` — append-only, hash-chained controller events;
- `provenance/pr-N.json` — exact repository, PR, branch, base/head SHA, digests, and verification;
- `budget.json` — daily starts, consecutive failures, and observed provider cost.

Provider usage may be unavailable. Unknown is stored as unknown, not zero. PR identity comes from GitHub postconditions, never provider prose.

## Failure matrix

| Symptom | Meaning | Operator action |
|---|---|---|
| `UNSAFE gate-2` | branch protection unavailable or insufficient | fix rules; then perform live credential proof |
| `claimed-elsewhere` | another runner won the remote lease | wait; inspect `reconcile` if it outlives expiry |
| `agent:retryable` | safe pre-delivery failure | inspect evidence; rerun after cause is fixed |
| `ready-for-human` | policy/provenance/judgment boundary | inspect; never relabel blindly |
| adapter not ready | CLI, auth, instruction, or skill missing | run `doctor --harness <name>` interactively |
| protected path / symlink / gitlink | worker crossed delivery policy | review as a security event |
| verification failed or timed out | exact candidate was not proven | fix config/dependencies or retry; no PR was opened |
| remote branch exists | prior delivery or crash needs reconciliation | inspect remote branch and provenance; do not force |
| circuit breaker open | consecutive failures hit configured maximum | diagnose evidence and reset intentionally |
| triage `provenance_mismatch` | failing PR is not the exact controller artifact | handle manually; it is intentionally excluded |

## Night shift

Night shift is diagnosis-only. It does not invoke a model and does not mutate a PR. It reports failing same-repository PRs only when their PR number, branch, and current head SHA match the local controller provenance record. This protects against fork names, copied prefixes, and post-verification force updates.

## Cost and limits

No-work selection and deterministic triage invoke no provider. Every real run is reserved in the local ledger before adapter invocation. `dailyRunLimit`, `maxConsecutiveFailures`, `maxBudgetUsd`, run timeout, verification timeout, file count, and diff bytes are configured in `.build-system.json`.

The budget ledger is local to one state root; it is not a cross-host billing authority. Use provider-side caps for global spend and do not run multiple hosts with independent state roots if a single shared ceiling is required.
