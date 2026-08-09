# Build System

*A deterministic issue-to-PR controller with bounded AI workers and two human gates.*

This project began as the companion to [Claude Code Is a Build System, Not a Chatbot](https://vinny.dev/blog/2026-04-25-claude-code-build-system/). Version 3 keeps the useful harness workflows, but moves authority out of model prompts and into a provider-neutral controller.

**Version:** 3.0.0 · **Platforms:** macOS and Linux · **License:** MIT

> **Explore the system:** [Open the interactive Signal Ledger explainer](https://static.vinny.dev/build-system-explainer.html) to trace the seven custody handoffs, switch harness profiles, inject failure scenarios, and inspect the evidence chain.

[Getting started](docs/getting-started.md) · [Choose a tier](docs/adoption.md) · [GitHub setup](docs/github-setup.md) · [Customize](docs/customizing.md) · [Architecture](docs/architecture.md) · [Harness compatibility](docs/harness-compatibility.md)

## What the system guarantees

A GitHub issue becomes a versioned work contract. A bounded Claude or Codex worker may propose a plan or edit ordinary files inside a unique worktree. The controller—and only the controller—claims work, validates Gate 1, checks paths and Git state, runs configured verification, commits, pushes, opens the PR, confirms the platform postcondition, moves labels, and writes evidence.

Three rules shape the design:

1. **The model proposes; the controller disposes.** Workers receive no GitHub token and no Git/GitHub delivery tools.
2. **Approval binds exact bytes.** Contract, plan, base commit, and delivery commit are connected by digests and immutable SHAs.
3. **Unknown is unsafe.** Missing branch protection, ambiguous state, stale approval, failed verification, or provenance drift stops delivery.

Gate 1 approves the plan. Gate 2 is the protected merge, kept human and enforced by repository rules. Atomic remote Git-ref leases prevent local and hosted schedulers from claiming the same issue. Crash reconciliation releases expired leases and verifies delivered PR provenance.

## Choose a tier

Start with the smallest tier that solves today's problem. Tiers are cumulative,
so installing Tier 2 also installs Tier 1.

| Tier | Choose it when you want | What you need | Typical setup |
|---|---|---|---:|
| `--tier 1` **Session** | Repeatable spec, TDD, and review workflows inside an interactive harness | Bash, Git, jq, and Claude Code, Codex, OpenCode, or a supported Copilot surface | 15 min |
| `--tier 2` **Pipeline** | A GitHub issue to become a bounded Claude- or Codex-authored PR | Tier 1, Node, authenticated `gh`, a GitHub remote, and protected-branch setup | 30 min |
| `--tier 3` **Ops** | The Tier 2 controller to wake on a schedule | Tier 2 and an always-on macOS/Linux machine or the hosted Claude workflow | 1 hour |

If you are unsure, install Tier 1. Read the [adoption guide](docs/adoption.md)
before granting the controller or a scheduled runner more authority.

## Quick start

Clone this distribution beside—not inside—the repository you want to adopt.
Set the two paths once so every command makes its working directory explicit:

```bash
git clone https://github.com/vscarpenter/claude-code-build-system
BUILD_SYSTEM_DIR="$PWD/claude-code-build-system"
TARGET_REPO="/absolute/path/to/your/repo"

"$BUILD_SYSTEM_DIR/install.sh" --tier 1 --target "$TARGET_REPO" --dry-run
"$BUILD_SYSTEM_DIR/install.sh" --tier 1 --target "$TARGET_REPO"
cd "$TARGET_REPO"
```

Customize the installed `CLAUDE.md` and inert Stop hook, commit the installed
files, then use `/qspec`, `/tdd`, and `/qcheck` in Claude Code. Codex, OpenCode,
and supported Copilot surfaces discover the same workflows as Agent Skills.

For the issue-to-PR controller, choose Tier 2 instead and select exactly one
harness for the first readiness check:

```bash
"$BUILD_SYSTEM_DIR/install.sh" --tier 2 --target "$TARGET_REPO" --dry-run
"$BUILD_SYSTEM_DIR/install.sh" --tier 2 --target "$TARGET_REPO"
cd "$TARGET_REPO"

# Replace every REPLACE: value and confirm the rest of the config first.
${EDITOR:-vi} .build-system.json

HARNESS=codex # or claude
node scripts/build-system.cjs doctor --harness "$HARNESS"
```

Do not continue until `doctor` reports `READY`. Configure the required GitHub
controls with the [GitHub setup guide](docs/github-setup.md), then follow the
[first-PR walkthrough](docs/getting-started.md). `--harness all` is an optional
compatibility audit only when both Claude Code and Codex are installed and
authenticated; it is not a first-run requirement.

After an issue is labeled `ready-for-agent`, the controller loop is:

```bash
node scripts/build-system.cjs run --harness "$HARNESS" --issue 42 --dry-run
node scripts/build-system.cjs run --harness "$HARNESS" --issue 42
node scripts/build-system.cjs approve --issue 42 # feature and risky plans only
node scripts/build-system.cjs run --harness "$HARNESS" --issue 42
node scripts/build-system.cjs reconcile
```

`doctor` is read-only and fails closed. A `READY` result means the local checks passed; it is not a substitute for the release-only live proof that the actual automation credential cannot push, force-push, or merge through Gate 2.

`--dry-run` previews installation. `--force` explicitly adopts colliding files.
`--upgrade` refreshes only installer-owned baselines and preserves local
adaptations across repeated upgrades. Lower-tier installs cannot silently
downgrade a higher-tier manifest.

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
