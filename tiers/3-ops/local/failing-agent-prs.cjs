"use strict";

const FAIL_CONCLUSIONS = new Set(["failure", "timed_out", "cancelled", "action_required", "startup_failure"]);
const FAIL_STATES = new Set(["failure", "error"]);
// GitHub authorAssociation values that mark a trusted maintainer rather than an
// arbitrary external contributor. Only honored when a caller supplies the field
// (`gh pr list` does not expose it; `gh pr view` does).
const TRUSTED_ASSOCIATIONS = new Set(["OWNER", "MEMBER", "COLLABORATOR"]);
const DEFAULT_BRANCH_PREFIX = "claude";

// The prefix arrives from config.branchPrefix in .build-system.json, which is
// hand-edited, so treat it as boundary input. A blank or non-string value must
// fall back to the default rather than reach startsWith(""), which is true for
// every branch name and would hand the night shift the entire PR queue —
// including hand-written human branches.
function normalizeBranchPrefix(branchPrefix) {
  if (typeof branchPrefix !== "string") return DEFAULT_BRANCH_PREFIX;
  const trimmed = branchPrefix.trim().replace(/\/+$/, "");
  return trimmed === "" ? DEFAULT_BRANCH_PREFIX : trimmed;
}

function isAgentBranch(headRefName, branchPrefix) {
  if (typeof headRefName !== "string") return false;
  return headRefName.startsWith(`${normalizeBranchPrefix(branchPrefix)}/`);
}

// A fleet-prefixed head branch name is attacker-controlled on a fork PR, so
// the prefix alone must NOT confer the "fleet's own output" trust that lets the
// night shift check out the branch and run its build/test/lint locally. Require
// provenance: the head branch must live in the base repo itself (not a fork), or
// the PR author must be a trusted maintainer. Missing/ambiguous data is treated
// as untrusted (fail safe — exclude).
function isTrustedProvenance(pr, repoOwner) {
  if (!pr || typeof pr !== "object") return false;
  // GitHub reports head repo == base repo — a same-repo branch, not a fork.
  if (pr.isCrossRepository === false) return true;
  // Head repo is owned by the base repo's owner (same-repo branch, not a fork).
  const headOwner = pr.headRepositoryOwner && pr.headRepositoryOwner.login;
  if (typeof repoOwner === "string" && repoOwner !== "" && headOwner === repoOwner) return true;
  // Trusted maintainer as author (only present if the caller fetched it).
  return TRUSTED_ASSOCIATIONS.has(String(pr.authorAssociation || "").toUpperCase());
}

// A statusCheckRollup entry is failing if its CheckRun conclusion or its
// StatusContext state indicates failure. Pending/success/neutral/skipped are not.
function isFailingCheck(check) {
  if (!check || typeof check !== "object") return false;
  const conclusion = String(check.conclusion || "").toLowerCase();
  const state = String(check.state || "").toLowerCase();
  return FAIL_CONCLUSIONS.has(conclusion) || FAIL_STATES.has(state);
}

function failingAgentPRs(prs, repoOwner, branchPrefix) {
  if (!Array.isArray(prs)) return [];
  return prs.filter(
    (pr) =>
      pr &&
      isAgentBranch(pr.headRefName, branchPrefix) &&
      isTrustedProvenance(pr, repoOwner) &&
      Array.isArray(pr.statusCheckRollup) &&
      pr.statusCheckRollup.some(isFailingCheck)
  );
}

module.exports = {
  normalizeBranchPrefix,
  isAgentBranch,
  isTrustedProvenance,
  isFailingCheck,
  failingAgentPRs,
};

// CLI: read `gh pr list --json number,headRefName,headRepositoryOwner,isCrossRepository,statusCheckRollup`
// from stdin, print the count of failing agent PRs. The base-repo owner is supplied
// via BS_TRIAGE_REPO_OWNER so same-repo branches can be told apart from forks, and
// the fleet's branch prefix via BS_TRIAGE_BRANCH_PREFIX (the driver reads it from
// config.branchPrefix). Fail-safe to 0 on bad input.
if (require.main === module) {
  let input = "";
  process.stdin.on("data", (c) => (input += c));
  process.stdin.on("end", () => {
    let prs = [];
    try {
      prs = JSON.parse(input);
    } catch {
      prs = [];
    }
    process.stdout.write(
      String(
        failingAgentPRs(prs, process.env.BS_TRIAGE_REPO_OWNER, process.env.BS_TRIAGE_BRANCH_PREFIX).length
      )
    );
  });
}
