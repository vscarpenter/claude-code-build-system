# GitHub setup

Tier 2 can create a plan or edit candidate files only after GitHub identity,
labels, and Gate 2 are unambiguous. This page configures the controls that the
installer cannot safely choose for you.

## 1. Confirm repository identity and access

Run these commands from the target repository:

```bash
gh auth status
gh repo view --json nameWithOwner,defaultBranchRef \
  --jq '{repo: .nameWithOwner, defaultBranch: .defaultBranchRef.name}'
git remote get-url origin
```

Copy `nameWithOwner` and the default branch into `.build-system.json`. The
local controller's authenticated GitHub identity needs enough access to read
issues and branch rules, move labels, write comments, create and delete lease
refs, push a delivery branch, and open a pull request. It never merges.

The installer creates the lifecycle and risk labels when `gh` is authenticated.
If it printed `MANUAL:` lines, run those commands now and rerun the installer
with `--dry-run` to confirm there are no unexpected file operations.

## 2. Make CI check names real

`requiredChecks` contains GitHub check names, not shell commands. First let the
repository's CI workflow complete successfully on a recent pull request. List
the names GitHub reports:

```bash
gh pr checks <pull-request-number>
```

Copy the exact required names into `.build-system.json`:

```json
"requiredChecks": ["test", "lint"]
```

GitHub only offers recently successful checks for selection, and duplicate job
names across workflows can make a required check ambiguous. Keep job names
unique. If the repository has no CI yet, `requiredChecks: []` is valid for a
local trial, but the release gate remains incomplete until real checks exist
and are required.

See GitHub's guidance on
[required checks](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks)
and [status checks](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/collaborating-on-repositories-with-code-quality-features/about-status-checks).

## 3. Configure the classic branch protection rule

The current `doctor` command reads GitHub's classic branch-protection endpoint.
Repository rulesets may add stronger controls, but a ruleset alone is not a
substitute for the classic rule that `doctor` verifies in this release.

On GitHub, open **Settings → Branches → Branch protection rules → Add rule**.
Target the exact `defaultBranch` from `.build-system.json`, then configure:

- Enable **Require a pull request before merging**. For a solo repository, an
  approval count is optional; the human merge remains Gate 2.
- When `requiredChecks` is nonempty, enable **Require status checks to pass
  before merging** and select every configured name. A trial using
  `requiredChecks: []` may omit this setting, but it has not completed the CI
  release gate.
- Enable **Do not allow bypassing the above settings** so administrators and
  bypass-capable roles cannot silently skip Gate 2.
- Leave **Allow force pushes** disabled.
- Leave **Allow deletions** disabled.

Save the rule. GitHub documents the current UI and options in
[Managing a branch protection rule](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/managing-a-branch-protection-rule)
and explains administrator bypass behavior in
[About protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches).

## 4. Configure optional hosted workflows

The risk-label workflow uses the repository `GITHUB_TOKEN` with only the
permissions declared in its YAML. The hosted Claude responder, reviewer, and
Tier 3 builder also need:

```bash
gh secret set CLAUDE_CODE_OAUTH_TOKEN
```

If you enable the Tier 3 hosted builder, open **Settings → Actions → General →
Workflow permissions** and allow GitHub Actions to create pull requests. Keep
the workflow's explicit `permissions` block; do not grant broader default token
access just to make setup easier. GitHub recommends limiting `GITHUB_TOKEN` to
the minimum permissions each workflow needs; see
[Use GITHUB_TOKEN for authentication](https://docs.github.com/en/actions/tutorials/authenticate-with-github_token).

A local Claude or Codex controller does not need the hosted builder. Disable
optional workflows you do not intend to operate.

## 5. Run the deterministic readiness check

Select one installed and authenticated controller harness:

```bash
HARNESS=codex # or claude
node scripts/build-system.cjs doctor --harness "$HARNESS"
```

Resolve every `BLOCK` line and rerun until the final line is `READY`.
`--harness all` intentionally checks both adapters and should be used only when
both are installed; it is not a prerequisite for one working controller.

`READY` proves what the controller can observe: repository identity, CLI and
authentication, pause state, classic branch protection, configured checks,
adapter readiness, and required labels. It cannot prove the effective behavior
of every ruleset, bypass actor, enterprise policy, or credential.

## 6. Prove Gate 2 with the real credential

Use a disposable sandbox repository configured like production. With the exact
credential that will run the local or hosted controller, verify all three
operations are rejected:

1. Directly push a new commit to the protected default branch.
2. Force-push a different commit to the protected default branch.
3. Merge a pull request without satisfying Gate 2.

These are intentionally destructive probes if protection is wrong. Never run
them first against a production repository. Preserve the rejection output and
credential identity as release evidence outside the model-generated run log.

Only after this sandbox proof should the deployment be described as
production-ready.
