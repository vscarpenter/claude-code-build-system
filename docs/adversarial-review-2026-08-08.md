# Adversarial review — 2026-08-08

## Verdict

The release-blocking architecture findings were implemented in version 3. The
model is no longer the controller: a provider-neutral Node controller owns
selection, atomic leases, contract/plan/approval digests, per-run worktrees,
diff policy, verification, Git/GitHub delivery, lifecycle transitions,
reconciliation, budgets, and evidence. Claude and Codex are bounded worker
adapters without GitHub credentials or Git/GitHub delivery tools.

The remaining release gates are external proof, not unimplemented local
mechanism: run a real issue-to-PR smoke for each enabled harness, test the
hosted workflow if used, and prove with the actual automation credential that
GitHub rejects direct push, force-push, and merge. OpenCode and Copilot remain
Context/Interactive surfaces; no autonomous parity is claimed.

## Version 3 implementation status

| Original blocker | Current state |
|---|---|
| Model owned policy and delivery | Controller-owned; worker has no transport credential or Bash/Git/GitHub tool |
| Non-atomic label claim | Atomic remote Git-ref lease with CAS expiry takeover and release |
| Stale contract/plan approval | Canonical contract and plan digests bound to Gate 1 |
| Tier 2 active-checkout edits | Unique controller-created worktree for every run |
| Prompt-only protected paths and verification | Real Git diff policy plus controller-run commands before delivery |
| Model-authored `OPENED_PR` telemetry | Removed; PR outcome comes from exact GitHub head/base postconditions |
| Mutable scheduled code | Versioned libexec runtime with a SHA-256 manifest |
| Unsafe autonomous night shift | Replaced by read-only, provenance-bound diagnosis |
| Partial installer writes | Staged payload and rollback journal; manifest commits atomically |
| Claude-only autonomous shape | Claude and Codex adapters share one strict `AgentResult` contract |

Everything below records the evidence and findings from the pre-controller
snapshot. Its “open” language is retained as audit history; the table above and
the current source are the implementation status.

## Proof collected

- The original 46-test suite passed on macOS.
- Disposable-repository probes reproduced upgrade data loss, silent tier
  downgrade, writes through symlinked destination parents, partial installs,
  executable-mode drift, Git-subdirectory installs, and shell injection through
  the generated Tier 3 environment file.
- Static and runtime inspection covered every shipped Bash and Node program,
  every workflow, every prompt, the installer, the manifest, and the operator
  documentation.
- Claude Code 2.1.225, Codex CLI 0.147.0, and OpenCode 1.18.15 were inspected
  locally. GitHub Copilot behavior was checked against current official docs.
- No live issue-to-PR run, hosted Actions run, scheduler run, branch-ruleset
  check, or non-Claude autonomous run was performed. Those remain separate
  proof gates.
- After version 3 remediation, shell syntax, workflow YAML, JSON, diff, and
  browser interaction checks passed. The Bash harness passes 56 scenarios in
  two bounded shards; its controller suite contains 13 additional Node tests.

## Remediated in this pass

1. **Durable local adaptations.** A `KEEP` now retains the last installer-owned
   hash rather than rebasing the manifest onto local bytes. Repeated installs
   no longer erase an adapted file.
2. **Monotonic adoption tiers.** A Tier 3 target cannot silently become a Tier 1
   manifest while Tier 3 artifacts remain behind.
3. **Destination containment.** The installer rejects symlink destinations,
   symlinked parents, path traversal, and non-directory ancestors before its
   first payload write.
4. **Safer writes.** The full plan is preflighted, managed modes are restored
   with `cp -p`, and the manifest is written to a same-directory temporary file
   then renamed atomically.
5. **Repository identity.** The target must be the Git top level, not an
   arbitrary nested directory.
6. **Safe machine config serialization.** Tier 3 uses non-executable JSON under
   a canonical-path-hashed repo identity; files are mode `0600`.
7. **Parallel-safe upgrade test.** The suite mutates a private copy of the
   distribution instead of shared source files.
8. **Fail-closed pause checks.** Local and hosted runners refuse to invoke the
   model when pause state cannot be established; the hosted runner now honors
   `builder:paused` and skips idle schedules.
9. **Portable interactive workflows.** Tier 1 installs `AGENTS.md`; all five
   workflows are emitted from one source into both Claude commands and
   `.agents/skills` for Codex, OpenCode, and supported Copilot surfaces.
10. **Continuous approved execution.** `/tdd` no longer asks for approval after
    every red test when the design/spec has already been approved.
11. **Split privilege.** Verification moved to the controller. Workers receive
    no Bash, Git, or GitHub transport capability and inherit an allowlisted
    environment rather than arbitrary runner secrets.
12. **Private evidence by default.** Scheduled runners set `umask 077`; run
    artifacts live outside the repository with private directory/file modes.
13. **Required payload inventory.** A damaged distribution can no longer report
    success after omitting a core instruction, schema, controller module, or
    runner.

## Critical work identified in the original snapshot

### 1. Put deterministic enforcement around the model

The runner must own queue selection, atomic claims, worktree identity,
protected-path validation, verification execution, branch validation, delivery,
and state cleanup. The model should receive a bounded work order and return a
structured result. Until then, “never merge,” “never force-push,” and
`protectedPaths` are policy statements, not security boundaries.

### 2. Replace labels-as-convention with validated transitions

Selection and claim are not atomic; a crash after `agent:building` strands an
issue; approval is not bound to an issue or plan digest; and there is no
explicit PR-open, retryable-failure, or fix-pending state. Add a transition
module with run IDs, leases, legal states, idempotency, and reconciliation.

### 3. Freeze the contract at human triage

The reporter controls the issue body and risk selection. An edit after triage
can change a feature into `risk:docs` or `risk:chore`, which currently
auto-approves. Snapshot the contract/risk digest when a maintainer marks work
ready; later edits must invalidate readiness.

### 4. Separate harness, transport, and scheduler adapters

Claude/Codex/OpenCode/Copilot have different discovery, hook, permission,
headless, output, auth, and hosted-execution models. The shared layer should be
work contracts, policy, state transitions, and normalized results. GitHub is a
transport; launchd/cron/Actions are schedulers; the model CLI is a harness.

### 5. Make Gate 2 real

The distribution does not install or verify branch protection, required
checks, review requirements, direct-push restrictions, or bypass policy. It can
truthfully say the agent is instructed not to merge; it cannot yet say the
agent can never merge.

## Additional high-risk findings

- **Tier 2 isolation is contradictory.** The manual walkthrough permits
  `build-next` in the active checkout, while the workflow assumes it already
  runs in a dedicated worktree. Isolation should be a pipeline invariant, not
  a Tier 3 convenience.
- **Multi-repository identity can collide.** Environment files, worktree
  defaults, launchd labels, and logs are keyed by repository basename or a
  fixed label. Two repositories named `api` can share or replace operating
  state. Use a remote slug plus canonical-path hash and validate it against the
  Git remote before mutation.
- **Same-repository branches are over-trusted.** Night shift treats a matching
  same-repository branch prefix as trusted enough to check out and verify, but
  does not bind the PR to a builder actor, recorded head SHA, or signed run
  record. Execute recorded immutable SHAs in a credential-free sandbox.
- **Scheduled code is mutable before isolation begins.** launchd executes the
  driver directly from the target repository, so a checkout or local edit can
  change privileged scheduled code before the driver creates its worktree.
  Install versioned drivers in a user-owned libexec directory and verify them.
- **Failure and cost reporting are incomplete.** The builder swallows the model
  process exit code, usage parsing is Claude-specific, and a model-authored
  `OPENED_PR` marker can attribute telemetry to the wrong PR. Resolve delivery
  state from GitHub and emit a versioned result envelope.
- **Public triggers can spend model budget.** The responder accepts broad
  `@claude` comment triggers and automatic review runs on PR updates. Add actor
  trust gates, per-item concurrency, cooldowns, and budget ceilings.
- **Supply-chain inputs move.** GitHub Actions use moving major tags, the review
  workflow installs a mutable plugin source, and the edit hook may execute
  `bunx` package resolution. Pin reviewed SHAs and use locked, locally installed
  formatters.
- **Installer lifecycle is incomplete.** Preflight prevents predictable
  partial installs and manifest replacement is atomic, but there is no rollback
  for interruption/disk failure, safe removal of upstream-deleted files,
  conflict merge, uninstall, or explicit downgrade.
- **Onboarding installs example state as if it were real.** The sample
  `tasks/todo.md`, `tasks/lessons.md`, stack-specific formatter behavior, and
  coding-standard thresholds need an initialization step or visibly inert
  placeholders.
- **Global memory is a separate trust boundary.** The optional persistence hook
  sends transcript excerpts to a nested model and appends model-selected text
  to durable instructions. Proposed learnings should be schema-validated and
  quarantined for review.

## Prioritized roadmap

1. Add a `doctor` command for dependencies, auth, config, instruction/skill
   discovery, branch rules, labels, pause state, scheduler wiring, and stale
   claims.
2. Define versioned `WorkContract`, `WorkOrder`, `AgentResult`, and
   `TransitionEvent` schemas.
3. Extract selection, claim, policy checks, verification, and delivery from the
   prompts into deterministic code.
4. Implement Claude and Codex adapters against one conformance suite.
5. Add OpenCode and Copilot CLI adapters; treat Copilot cloud and IDE support as
   separate capability profiles.
6. Replace long-lived shared worktrees with validated per-run worktrees and
   atomic locks; add stale-claim recovery.
7. Move raw run logs outside repositories, apply `umask 077`, redact secrets,
   rotate logs, and normalize provider usage without treating missing usage as
   zero cost.
8. Add live sandbox-repository proofs for each support level before claiming
   it publicly.

## Release bar for “harness-neutral”

- Two simultaneous runners produce one claim.
- A changed issue or plan invalidates old approval.
- A fake adapter that edits a protected path cannot push or open a PR.
- Verification failure prevents delivery.
- Missing CLI/auth/malformed output returns nonzero with an actionable report.
- Claude and Codex pass the same plan, revise, build, escalation, no-work, and
  crash-recovery fixtures.
- Every publicly supported harness has a real interactive smoke test; every
  autonomous support claim also has a real issue-to-PR test.
