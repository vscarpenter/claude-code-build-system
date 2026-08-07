# Getting started

The other docs explain what the system is. This one covers what you do after `install.sh` finishes, in the order you do it, through your first merged PR.

## Before you install

| You need | For |
|---|---|
| `jq` | the installer itself |
| Claude Code | every tier |
| A GitHub repo and an authenticated `gh` | tier 2 and up |
| A machine that is usually on | tier 3, unless you run the hosted variant |

Run `gh auth status` before installing tier 2. The installer creates the 15 pipeline labels with `gh`. From an unauthenticated shell, that step degrades to a list of `MANUAL:` commands you paste yourself.

## 1. Install

```bash
git clone https://github.com/vscarpenter/claude-code-build-system
cd claude-code-build-system

./install.sh --tier 1 --target /path/to/your/repo --dry-run  # print the plan
./install.sh --tier 1 --target /path/to/your/repo            # write it
```

Every line of output is one file and one decision:

- `INSTALL` wrote the file.
- `SKIP` found a file the installer did not write, so it left yours alone. Pass `--force` to adopt it.
- `KEEP` found a tracked file you edited and preserved your version.

The installer finishes by printing the next steps for the tier it installed. Those are the same steps as sections 2 through 5 below, in short form.

Start at tier 1 even if you want the whole pipeline. Tier 1 is where you find out whether the standards and the review commands fit your project. That answer changes what you write into the tier 2 config.

## 2. Configure what the system cannot infer

Four settings need your input. The first two apply to every tier, and the last two arrive with tier 2.

**The Stop hook, in `.claude/settings.json`.** It ships inert, as `"command": "true"`. Replace it with the fastest type check in your stack:

```json
"command": "npm run typecheck 2>&1 | tail -10"
```

The hook runs at the end of every session, which is why it ships empty. A command naming a toolchain you do not have would fire every time you stop. Keep the `tail` so a long error list does not bury the end of the session.

**`CLAUDE.md`.** It ships as a filled-in Bun and Prisma example rather than a blank outline. A skeleton shows you the shape; a populated file shows you the depth. Rewrite it for your project and delete what does not apply.

**The `config` block in `.build-system.json`.**

```json
"config": {
  "verifyCommands": ["npm test", "npm run lint", "npx tsc --noEmit"],
  "protectedPaths": ["deploy/**", "infra/**", "SECURITY.md"],
  "branchPrefix": "claude"
}
```

`/build-next` and `/triage-prs` read this at runtime, so the values take effect without reinstalling. While any of them still contains `REPLACE:`, the agents escalate instead of running. That refusal is deliberate: an unconfigured builder that guessed at your test command would open PRs it never verified.

Pick `branchPrefix` now. The night shift identifies the fleet's own PRs by that prefix, so renaming it later strands every open agent PR under the old name. [customizing.md](customizing.md) has starting `verifyCommands` for six stacks.

**The `CLAUDE_CODE_OAUTH_TOKEN` repo secret.** Tier 2 installs two GitHub Actions workflows: the `@claude` responder and the PR reviewer. Both authenticate with that secret, and both fail on their first run without it.

```bash
gh secret set CLAUDE_CODE_OAUTH_TOKEN   # paste the token when prompted
```

Generate the token with `claude setup-token` on a machine where Claude Code is already authenticated.

## 3. Verify the install took

**Tier 1.** Open Claude Code in the target repo and run `/qcheck` against a dirty working tree. You should get a skeptical review, not a "what would you like me to look at?" To confirm the hooks are live, ask Claude to edit a `.env` file. `protect-files.sh` should block it.

**Tier 2.** `gh label list` should show the 15 pipeline labels. If the install printed `MANUAL:` lines, run them now.

**Tier 3.** The drivers pre-check before they spend anything, so you can exercise the whole path for free:

```bash
bash scripts/build-system/builder-run.sh --check    # reads labels, prints WORK or NO_WORK
bash scripts/build-system/builder-run.sh --dry-run  # also names the worktree it would use
```

Then commit `.build-system.json` along with the installed files. The manifest is how the repo records which version of the system it carries, and `--upgrade` reads it later.

## 4. Your first change, end to end

### At tier 1: the session loop

Three commands map to three moves: think, build, ship.

```
/qspec add rate limiting to the login endpoint
```

Writes `tasks/spec.md`: acceptance criteria plus empty test stubs, one per criterion. The stubs are the point. They make the spec executable instead of descriptive.

```
/tdd reject the sixth login attempt inside 60 seconds
```

Writes the failing test first and pauses for your approval before implementing. Confirm the test fails for the reason you expect, then let it go green.

```
/qcheck
```

Reviews every file changed this session against `coding-standards.md` and `CLAUDE.md`, starting from "this is not ready to ship."

### At tier 2 and up: the pipeline

| # | Move | Who | Label state after |
|---|---|---|---|
| 1 | File the change on the issue form | You | `needs-triage` |
| 2 | Parse the risk dropdown, apply the tier | Actions | `needs-triage` + `risk:feature` |
| 3 | **Triage it in** | **You** | `ready-for-agent` |
| 4 | Plan, at a depth scaled to risk | Builder | `plan:pending` (Gate 1) |
| 5 | **Approve the plan** | **You** | `plan:approved` |
| 6 | Build test-first, open a PR | Builder | `agent:building`, then cleared |
| 7 | **Merge** | **You** | Gate 2, the issue closes |

**Step 1.** Open a new issue and choose "New Change." The form requires six fields: summary, acceptance criteria, constraints, out of scope, rollback considerations, and a risk tier. Write it like a spec. A vague contract produces a plausible plan for the wrong problem.

**Step 2** runs on its own. `apply-risk-label.yml` fires when an issue opens or gets edited, reads the risk dropdown, and applies one of `risk:docs`, `risk:chore`, `risk:feature`, or `risk:risky`. An issue that stays unlabeled means the parser found more than one "Risk tier" heading and refused to guess. Fix the body or apply the label yourself.

**Step 3 is the one people miss.** The form applies `needs-triage` and stops there. Nothing moves until you swap that for `ready-for-agent`. That swap is you saying the contract is complete. It is what keeps a half-written issue from reaching an agent.

**Step 4.** At tier 2, run `/build-next` in Claude Code whenever you want. At tier 3, the schedule does it for you. Either way the builder takes the oldest `ready-for-agent` issue and posts a plan comment.

What happens next depends on the risk tier. `risk:docs` and `risk:chore` auto-approve and continue straight into the build in the same run. `risk:feature` and `risk:risky` post the plan, swap the label to `plan:pending`, and stop.

One caveat when you run `/build-next` by hand at tier 2. It works in your current checkout, because the isolated worktree arrives with the tier 3 drivers. Start from a clean tree, or stash first.

**Step 5 is Gate 1.** You have three moves:

- **Approve.** Swap `plan:pending` to `plan:approved`.
- **Request changes.** Comment `/revise <what should change>` **and** swap the label to `plan:revise`. Both halves matter. The driver counts labels to decide whether to wake up, and it cannot see comments. A `/revise` comment on its own never reaches the builder.
- **Take it yourself.** Swap to `ready-for-human` and the fleet leaves it alone.

A "looks good" comment with no label swap waits forever. Label swaps are the entire protocol.

**Step 6.** The builder claims the issue as `agent:building`, branches to `<branchPrefix>/issue-<n>-<slug>`, builds test-first to `coding-standards.md`, and runs every command in `verifyCommands` until they pass. Then it opens a PR carrying the verification steps and the rollback plan from your contract, clears `agent:building`, and comments the PR link.

It does not merge. Nothing in this system merges.

**Step 7 is Gate 2.** Check the PR against the acceptance criteria you wrote in step 1, confirm the rollback path is real, and merge. No rollback path means no approval. The review is a checklist rather than archaeology, because the builder filled the PR body from the contract.

## 5. Turning on the schedule (tier 3)

Tier 3 removes you from everything except the two gates. The installer deliberately stops short of loading a scheduler, so this last mile is yours.

**Set `BS_REPO`.** The installer wrote `~/.build-system/<repo>.env`. Fill in the repo slug:

```bash
BS_REPO="owner/name"
```

That file lives outside the repo because it holds machine-local settings: paths, log directories, and worktree locations. Repo-level configuration stays in `.build-system.json`, which is why the drivers read `branchPrefix` from the manifest rather than from here.

**Open the Night Shift Control issue.** Create an issue titled "Night Shift Control" and pin it. It does two jobs: it receives the self-audit report the night shift posts after every run, and it carries the `triage:paused` kill switch. Without it the night shift has nowhere to report.

**Load the schedulers.** Copy a template out of `scripts/build-system/`, replace `{{REPO_PATH}}` with your repo's absolute path, then:

```bash
cp scripts/build-system/com.build-system.builder.plist.template \
   ~/Library/LaunchAgents/com.build-system.builder.myrepo.plist
# edit {{REPO_PATH}}, then:
launchctl load ~/Library/LaunchAgents/com.build-system.builder.myrepo.plist
```

On Linux, use cron instead. The plist template carries the equivalent line in its comment header. Do the same for the night-shift template.

The builder template wakes at 9:00, 13:00, and 17:00, and the night shift runs once at 20:00. Wake up more often if you want. Idle wake-ups cost nothing, because each driver counts labels with `gh` and exits before invoking Claude when there is no work.

From here the loop runs itself. The builder plans and waits at Gate 1, builds on your approval, and opens PRs. The night shift reproduces failing checks on the fleet's own PRs. It fixes mechanical ones as fresh PRs against the failing branch, escalates judgment calls, and files its report. Both stop at the same two gates you already control.

## 6. Day two

**Pause everything from your phone.** Add `builder:paused` to any open issue to stop the builder, and `triage:paused` to stop the night shift. Remove the label to resume. Neither needs a code change or a shell.

**Read the logs.** Runs land in `docs/ops/agent-logs/`: JSON per builder run, text per night-shift run, and `gh-errors.log` when a pre-check could not reach GitHub. Every builder run ends with `OPENED_PR=<n>` or `OPENED_PR=none`, and the driver pairs that with the run's token usage.

**Upgrade later.** `./install.sh --upgrade --target /path/to/your/repo` re-syncs the files you have not touched and keeps the ones you adapted. Your `config` block survives.

## Where to go next

- [architecture.md](architecture.md) for how the pipeline fits together, including the label state machine.
- [runbook.md](runbook.md) for failure modes, telemetry, and costs.
- [customizing.md](customizing.md) for per-stack verify commands, renaming labels, and changing the schedule.
- [adoption.md](adoption.md) for the tier table and how the manifest decides what to overwrite.
- [rationale.md](rationale.md) for why it works this way, including what was deliberately left out.
