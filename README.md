# Build System

*A deterministic issue-to-PR controller with bounded AI workers and two human gates.*

This project began as the companion to [Claude Code Is a Build System, Not a Chatbot](https://vinny.dev/blog/2026-04-25-claude-code-build-system/). Version 3 keeps the useful harness workflows, but moves authority out of model prompts and into a provider-neutral controller.

**Version:** 3.0.0 · **Platforms:** macOS and Linux · **License:** MIT

> **Explore the system:** [Open the interactive Signal Ledger explainer](docs/build-system-explainer.html) to trace the seven custody handoffs, switch harness profiles, inject failure scenarios, and inspect the evidence chain.

[Architecture](docs/architecture.md) · [Harness compatibility](docs/harness-compatibility.md) · [Adversarial review](docs/adversarial-review-2026-08-08.md)

## What the system guarantees

A GitHub issue becomes a versioned work contract. A bounded Claude or Codex worker may propose a plan or edit ordinary files inside a unique worktree. The controller—and only the controller—claims work, validates Gate 1, checks paths and Git state, runs configured verification, commits, pushes, opens the PR, confirms the platform postcondition, moves labels, and writes evidence.

Three rules shape the design:

1. **The model proposes; the controller disposes.** Workers receive no GitHub token and no Git/GitHub delivery tools.
2. **Approval binds exact bytes.** Contract, plan, base commit, and delivery commit are connected by digests and immutable SHAs.
3. **Unknown is unsafe.** Missing branch protection, ambiguous state, stale approval, failed verification, or provenance drift stops delivery.

Gate 1 approves the plan. Gate 2 is the protected merge, kept human and enforced by repository rules. Atomic remote Git-ref leases prevent local and hosted schedulers from claiming the same issue. Crash reconciliation releases expired leases and verifies delivered PR provenance.

## Install

```bash
git clone https://github.com/vscarpenter/claude-code-build-system
cd claude-code-build-system
./install.sh --tier 1 --target /path/to/your/repo
```

| Tier | What it adds | Typical setup |
|---|---|---:|
| `--tier 1` **Session** | `CLAUDE.md`, `AGENTS.md`, shared spec/TDD/review skills, Claude hooks and reviewers, coding standards | 15 min |
| `--tier 2` **Pipeline** | Contract issue form, 19-label state machine, controller, Claude/Codex adapters, leases, worktrees, policy, evidence | 30 min |
| `--tier 3` **Ops** | Integrity-checked immutable runtime, scheduled builder, provenance-bound night-shift diagnosis, hosted Claude workflow | 1 hour |

Tiers are cumulative. `--dry-run` previews. `--force` explicitly adopts colliding files. `--upgrade` refreshes only installer-owned baselines and preserves local adaptations across repeated upgrades. Lower-tier installs cannot silently downgrade a higher-tier manifest.

Tier 2 and 3 require a completed `.build-system.json` config. Then run:

```bash
node scripts/build-system.cjs doctor --harness all
node scripts/build-system.cjs run --harness claude --dry-run
node scripts/build-system.cjs run --harness codex
node scripts/build-system.cjs approve --issue 42
node scripts/build-system.cjs reconcile
```

`doctor` is read-only and fails closed. A `READY` result means the local checks passed; it is not a substitute for the release-only live proof that the actual automation credential cannot push, force-push, or merge through Gate 2.

## Harness support

| Surface | Claude Code | Codex | OpenCode | GitHub Copilot |
|---|---|---|---|---|
| Repository context | Native | Native | Installed | Surface-dependent |
| Shared interactive skills | Native | Native | Installed | Supported surfaces |
| Bounded controller worker | Implemented | Implemented | Not implemented | Not implemented |
| Local autonomous controller | Implemented; live smoke required | Implemented; live smoke required | Unsupported | Unsupported |
| Hosted controller | Claude workflow; live smoke required | Unsupported | Unsupported | Unsupported |

“Installed” does not mean permission or headless parity. OpenCode and Copilot can discover the shared workflows, but this release does not claim autonomous delivery for them. See the [capability profiles](docs/harness-compatibility.md).

## Trust boundaries

The controller enforces the properties prompts cannot:

- one remote lease per issue, with a monotonically increasing fence;
- one controller-created worktree and branch per run;
- exact lifecycle transitions and stale-approval rejection;
- deny-by-default protected paths, symlinks, gitlinks, diff size, and file count;
- controller-owned verification with bounded time and output;
- verified default-branch protection before delivery;
- exact remote branch and GitHub PR head/base postconditions;
- private, hash-chained evidence and controller-authored provenance;
- daily run limits, a failure circuit breaker, and provider budget caps;
- pause checks before work and again before irreversible delivery.

The model still runs as the same local OS user. Claude tool denial and the Codex workspace sandbox reduce capability, but they are not a VM boundary. Use a container or disposable runner when the repository or issue content is untrusted.

## Repository map

```text
build-system/
├── install.sh                     transactional, tiered installer
├── standards/                     canonical coding standard
├── tiers/1-session/               instructions, skills, hooks, reviewers
├── tiers/2-pipeline/
│   ├── scripts/build-system.cjs    deterministic controller CLI
│   ├── scripts/lib/                protocol, policy, leases, adapters, evidence
│   └── .github/                    issue contract and risk workflows
├── tiers/3-ops/                   immutable runner and hosted adapter
├── docs/                           explainer, operations, adoption, rationale
└── tests/                          Bash + Node conformance and failure tests
```

## Operating model

Use labels as durable state, not as authority. `builder:paused` stops new builder work; `triage:paused` stops night-shift diagnosis. The controller verifies the current issue state before every transition. Night-shift diagnosis only reports failing PRs whose repository, PR, branch, and head SHA match the provenance ledger; it does not let a model patch, push, or open follow-up PRs.

Run `bash tests/run-tests.sh` before release. The suite exercises installer rollback and path safety, protocol digests and transitions, remote lease exclusion, isolated worktrees, policy enforcement, credential stripping, budgets, evidence chaining, and static scheduler constraints.

## Honest release gates

The repository can prove implementation and local tests. Before calling a deployment production-ready, separately prove:

- `doctor` reports `READY` against the intended repository;
- a real Claude and/or Codex issue-to-PR smoke succeeds with the pinned CLI version;
- the actual automation credential is rejected on direct push, force-push, and merge;
- the hosted workflow, if enabled, obeys pause, lease, budget, and recovery behavior;
- required CI checks named in `.build-system.json` exist and are enforced.

## v1 → v2 map

Readers arriving from the original article can still find every session artifact: `templates/CLAUDE.md` moved to `tiers/1-session/CLAUDE.md`, project `.claude/` moved under `tiers/1-session/`, canonical standards live in `standards/coding-standards.md`, and `global/` remains global. Version 3 adds the deterministic controller without removing those interactive workflows.

## Disclaimer

This is an adaptable solo-developer system, not a certification. Windows-native scripts and team-scale governance are not shipped. Branch protection and credential scope are platform controls you must configure and test. No prompt, skill, hook, or local test can replace that live proof.

MIT. See [LICENSE](LICENSE).
