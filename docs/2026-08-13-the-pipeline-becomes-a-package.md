---
title: The Pipeline Becomes a Package
publishedAt: "2026-08-13"
tags: ["agentic-sdlc", "spec-driven-development", "claude-code", "engineering-leadership"]
excerpt: My issue-to-PR delivery pipeline ran beautifully in exactly one repository. Extracting it into an installable, tiered system exposed which parts were engineering and which parts were habit. The manifest, not the agent, turned out to be the hard part.
featured: false
---

One repository. That is where my delivery pipeline lived until last week, hand-fitted to a single project like a bespoke suit. [Two Gates and a Night Shift](https://vinny.dev/blog/2026-07-06-two-gates-and-a-night-shift/) described how it works: a GitHub issue as a contract, a builder agent that plans and waits for my approval, a PR it can never merge, and a night shift that cleans up failing checks while I sleep. The post ended with the system running. It did not mention the embarrassing part.

The embarrassing part: I could not install it anywhere else.

My other repositories, more than forty of them with Claude Code configured, ran a much thinner setup. Two stock workflow files, a `CLAUDE.md`, and a copy of my coding standards pasted in by hand. The copies of those standards had drifted across 28 repos, some of them four versions behind the current one. I had written an essay called [Claude Code Is a Build System, Not a Chatbot](https://vinny.dev/blog/2026-04-25-claude-code-build-system/) and then shipped the build system the way nobody ships build systems: as a folder you copy from, carefully, once, and never update.

So I spent a week turning the pipeline into a package. The result was version 2 of the [claude-code-build-system](https://github.com/vscarpenter/claude-code-build-system) repo: three adoption tiers, one installer, and an upgrade path that respects your edits. Version 3 landed while this essay sat in drafts; the closing section covers what it changed. The rest is about what the extraction taught me. The short version: *generalizing a system is how you find out which parts of it were real.*

## Three tiers, because trust is earned

The repo installs in tiers, and the tiers map to how much authority you are willing to hand over.

Tier 1 is the session layer: the `/qspec`, `/tdd`, and `/qcheck` workflows, protective hooks, two reviewer subagents, and a versioned coding-standards file. It ships `CLAUDE.md` and an `AGENTS.md` beside it, so Codex and OpenCode read the same instructions Claude Code does. This is roughly what the original repo shipped, and it changes how individual conversations go. Fifteen minutes, no new trust required.

Tier 2 changes how work enters. It installs the change-contract issue form, a nineteen-label protocol, the risk automation, and the controller that turns an approved issue into a pull request. Every change now arrives with acceptance criteria, constraints, a rollback plan, and a risk tier, because the form refuses anything less. You run the controller by hand whenever an issue is ready. The agent gains a defined job, but you still pull the trigger.

Tier 3 removes you from everything except the gates. A launchd or cron driver wakes the controller, which checks the label queue with `gh` before it spends a single provider token. You approve plans and releases. The fleet does the rest.

The ordering is deliberate. Nobody should install tier 3 on day one, including me. The gates exist so trust accumulates with evidence, and the tiers exist so adoption can follow the same curve.

## The hard part was not the agent

Here is what surprised me. The agent prompts generalized easily. The builder's contract, the priority order, the escalation rules, the night shift's fix-or-escalate table: all of it transferred almost verbatim once I replaced project specifics with three runtime facts. Which commands verify the work. Which paths are untouchable. Which branch prefix marks the fleet's output.

Those three facts now live in a manifest file, `.build-system.json`, that the installer writes into your repo. The system reads it at runtime, and if the config still contains its `REPLACE:` placeholders, the config loader throws before a model is ever invoked. An unconfigured pipeline is a judgment call, and judgment calls belong to humans.

That refusal is worth a second look, because it moved. In v2 the prompt told the builder to stop and escalate on an unconfigured manifest, and the builder complied. Today the check lives in a loader that has no capacity to reconsider. The behavior did not change. The reason you can count on it did.

The genuinely hard problem was upgrades. Installing into forty repositories is trivial; upgrading them six months later, after each one has adapted the files to its own needs, is where copy-paste distribution dies. My standards doc drifting four versions apart was exactly this failure. The fix is old and boring, which is why I trust it: the manifest records a content hash for every file it manages. At upgrade time, an unmodified file re-syncs silently. A file you changed stays put, with a notice. A `--force` flag states intent when you want the upstream version back. Homebrew and every dotfile manager converged on this shape years ago. I just had to admit my markdown files needed the same respect as packages.

Boring does not mean I got it right the first time. The v2 installer kept your edit on the next run, then re-hashed the file it had just decided not to touch. Your modified copy quietly became the new baseline, so the upgrade after that saw an unmodified file and overwrote it. The system preserved your work exactly once. There is now a test named for the second reinstall, because that is where the bug lived and nowhere else.

There is a lesson in where the difficulty landed. The impressive-looking part of an agentic pipeline is the agent. The load-bearing part is the plumbing that keeps forty copies of the truth from diverging. I have seen the same shape at enterprise scale more times than I can count: the demo is the model, and the product is the version control around it.

## What refused to generalize

Some things would not extract cleanly. Each one taught me something.

The night shift's trust rule survived only because it was never project-specific to begin with. A branch named `claude/anything` on a fork PR proves nothing, because fork authors pick their own branch names. The provenance check, which only trusts branches living in the repository itself, moved into the package untouched. Security properties that depend on the platform rather than the project travel well.

It also turned out to be the weakest thing that traveled. Branch location is a hint, not a proof. Version 3 replaced it with a matched record: repository, PR number, branch, and head SHA. All four must agree with what the controller wrote when it opened the PR. Extraction proved the rule was portable. Hardening proved it was thin.

The schedulers did not generalize. launchd is a Mac opinion, and my launchd plists encoded my machine. The package now ships plist templates plus cron equivalents, and a hosted GitHub Actions variant of the builder for people without an always-on machine. I documented the hosted path honestly: it works, I run the local path, and the local path is the one with months of scar tissue on it. Neither path pays a model to discover an empty queue. The local driver hands that question to the controller. The hosted variant answers it in a preflight step that gates the rest of the job.

And the two human gates refused to generalize into automation at all, which is the point. Gate 2 is still the merge button, and it still works from a phone. Gate 1 no longer does. Approving a plan now means running `build-system.cjs approve`. That command confirms your maintainer permission, then pins the approval to a digest of the exact contract and the exact plan bytes. The label still moves. It is now the receipt rather than the decision.

I did not enjoy giving that up. Approving a plan from a phone at a coffee shop was the best thing about running this system. I defended it for longer than the argument deserved. What killed it was a boring question I could not answer: if a label swap is the approval, what exactly did I approve? Issue text can be edited after I read it. A plan comment can be superseded. A label carries no memory of either. Convenience was doing work that only a digest can actually do.

## The origin repo becomes a consumer

The test I care about most is still ahead. The repository the pipeline was born in still runs its hand-fitted original, and over the coming weeks I will migrate it to consume the packaged version like any other adopter. If the extraction is honest, the migration is an install command and a config block. If it is not, the diff will tell me precisely which habits I mistook for architecture. Either outcome is information. I will report back.

That test is also why the whole exercise was worth a week. A system that runs in one place is indistinguishable from a lucky configuration. Packaging forces every implicit assumption into either the config schema or the documentation, and what cannot be forced there gets deleted. The repo now contains a rationale doc listing what it deliberately leaves out: no npm package, no plugin marketplace listing, no Windows-native scripts, no telemetry dashboard. Each cut has a reason. Restraint documented is restraint you can defend.

## What v3 changed

Version 3 reached main after I drafted this essay, so it is what you will find in the repo today. The extraction lesson held, then went further. Version 2 moved project facts out of prompts and into config. Version 3 moves authority out of prompts and into a deterministic controller. The model still plans and edits, inside a disposable worktree, but the controller alone claims work, runs verification, pushes, opens the PR, and writes hash-chained evidence. Workers never hold a GitHub token. Success comes from what the controller observed: real diffs, command exit codes, remote SHAs, and GitHub's own answer about the PR it just opened. The controller never accepts provider prose as proof that anything happened.

Two runners cannot race, either. Claiming an issue means winning an atomic push to a Git ref. The laptop and the hosted workflow compete for that same lease, and exactly one wins. The night shift lost its wrench in the same release. It now diagnoses failing PRs and mutates nothing. A repair loop earns its way back only under the same lease, policy, and delivery contract as the builder. The manifest kept growing too. The three runtime facts are now sixteen configuration keys, which is the hard part staying the hard part.

The change I respect most is a command that does nothing. `doctor` reads your branch protection and refuses to say READY unless required reviews, admin enforcement, and every named check are actually in place. It also refuses to overclaim. The README states plainly that READY is necessary and not sufficient. Only a live test with the real automation credential proves that credential cannot push or merge. Version 2 documented its restraint. Version 3 ships a command whose job is to tell you what it still cannot prove.

That honesty extends to the harness table. Claude Code and Codex have controller adapters and run as bounded workers. OpenCode and supported Copilot surfaces get `AGENTS.md` and the shared skills, and nothing more is claimed for them. Writing "not implemented" in a compatibility matrix costs nothing and saves someone a bad afternoon.

Version 3 deserves its own essay. This one is about the extraction that made it possible.

## Where to start

Start with tier 1 and a repo you care about: [github.com/vscarpenter/claude-code-build-system](https://github.com/vscarpenter/claude-code-build-system). Read the architecture doc before you install tier 3. If you would rather see it than read it, the [interactive explainer](https://static.vinny.dev/build-system-explainer.html) traces the seven custody handoffs and lets you inject failures. And if you port the hooks to PowerShell, the rationale doc already names the directory where they should live.

## Related reading

- [Claude Code Is a Build System, Not a Chatbot](https://vinny.dev/blog/2026-04-25-claude-code-build-system/)
- [Two Gates and a Night Shift](https://vinny.dev/blog/2026-07-06-two-gates-and-a-night-shift/)
- [The Spec Is the Product](https://vinny.dev/blog/2026-05-12-the-spec-is-the-product/)
