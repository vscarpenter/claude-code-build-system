const fs = require("node:fs");
const path = require("node:path");
const { marker, parseMarkers } = require("./protocol.cjs");
const { run } = require("./system.cjs");

const LIFECYCLE_LABELS = Object.freeze([
  "needs-triage", "needs-info", "ready-for-agent", "plan:pending", "plan:approved",
  "plan:revise", "agent:claimed", "agent:building", "agent:verifying",
  "agent:retryable", "pr:open", "ready-for-human", "done", "wontfix",
]);

function ghJson(args, options = {}) {
  const output = run("gh", args, { cwd: options.cwd, check: options.check !== false, env: options.env });
  return output.stdout.trim() ? JSON.parse(output.stdout) : null;
}

function resolveRepo(cwd, configured) {
  const actual = ghJson(["repo", "view", "--json", "nameWithOwner"], { cwd }).nameWithOwner;
  if (configured && configured !== actual) throw new Error(`config.repo '${configured}' does not match authenticated repository '${actual}'`);
  return actual;
}

function paused(repo, label, cwd) {
  const issues = ghJson(["issue", "list", "--repo", repo, "--label", label, "--state", "open", "--limit", "1", "--json", "number"], { cwd });
  return issues.length > 0;
}

function listIssues(repo, label, cwd) {
  return ghJson(["issue", "list", "--repo", repo, "--label", label, "--state", "open", "--limit", "100", "--json", "number,title,body,labels,createdAt,updatedAt"], { cwd })
    .sort((a, b) => a.createdAt.localeCompare(b.createdAt) || a.number - b.number);
}

function selectNext(repo, cwd) {
  for (const [label, phase] of [["plan:approved", "build"], ["plan:revise", "revise"], ["agent:retryable", "build"], ["ready-for-agent", "plan"]]) {
    const issues = listIssues(repo, label, cwd);
    if (issues.length) return { issue: issues[0], phase, sourceLabel: label };
  }
  return null;
}

function issueDetails(repo, issue, cwd) {
  return ghJson(["issue", "view", String(issue), "--repo", repo, "--json", "number,title,body,labels,createdAt,updatedAt,comments"], { cwd });
}

function labelNames(issue) {
  return (issue.labels || []).map((item) => typeof item === "string" ? item : item.name);
}

function currentLifecycle(issue) {
  const labels = labelNames(issue).filter((label) => LIFECYCLE_LABELS.includes(label));
  if (labels.length !== 1) throw new Error(`issue #${issue.number} must have exactly one lifecycle label; found ${labels.join(", ") || "none"}`);
  return labels[0];
}

function transitionLabels(repo, issueNumber, expected, next, cwd) {
  const before = issueDetails(repo, issueNumber, cwd);
  if (currentLifecycle(before) !== expected) throw new Error(`issue #${issueNumber} state changed before transition`);
  const args = ["issue", "edit", String(issueNumber), "--repo", repo, "--remove-label", expected, "--add-label", next];
  run("gh", args, { cwd });
  const after = issueDetails(repo, issueNumber, cwd);
  if (currentLifecycle(after) !== next) throw new Error(`issue #${issueNumber} transition did not settle at ${next}`);
  return after;
}

function postComment(repo, issue, body, cwd, stateDir) {
  const file = path.join(stateDir, `comment-${issue}-${process.pid}.md`);
  fs.writeFileSync(file, body, { mode: 0o600 });
  try { run("gh", ["issue", "comment", String(issue), "--repo", repo, "--body-file", file], { cwd }); }
  finally { fs.rmSync(file, { force: true }); }
}

function commentsWithMarker(issue, kind) {
  return (issue.comments || []).flatMap((comment) => parseMarkers(comment.body || "", kind).map((payload) => ({ payload, comment })));
}

function currentActor(cwd) {
  return ghJson(["api", "user", "--jq", "{login:.login,id:.id}"], { cwd });
}

function actorPermission(repo, login, cwd) {
  return ghJson(["api", `repos/${repo}/collaborators/${login}/permission`], { cwd }).permission;
}

function assertMaintainer(repo, cwd) {
  const actor = currentActor(cwd);
  const permission = actorPermission(repo, actor.login, cwd);
  if (!["admin", "maintain", "write"].includes(permission)) throw new Error(`${actor.login} lacks write permission required for Gate 1`);
  return { ...actor, permission };
}

function verifyBranchProtection(repo, branch, requiredChecks, cwd) {
  const result = run("gh", ["api", `repos/${repo}/branches/${encodeURIComponent(branch)}/protection`], { cwd, check: false });
  if (result.status !== 0) return { ready: false, status: "unknown", blockers: ["branch_protection_unavailable"] };
  const protection = JSON.parse(result.stdout);
  const blockers = [];
  if (!protection.required_pull_request_reviews) blockers.push("pull_request_reviews_not_required");
  if (!protection.enforce_admins || protection.enforce_admins.enabled !== true) blockers.push("admins_can_bypass");
  if (protection.allow_force_pushes && protection.allow_force_pushes.enabled) blockers.push("force_push_allowed");
  if (protection.allow_deletions && protection.allow_deletions.enabled) blockers.push("branch_deletion_allowed");
  const contexts = protection.required_status_checks ? (protection.required_status_checks.contexts || []) : [];
  for (const check of requiredChecks) if (!contexts.includes(check)) blockers.push(`required_check_missing:${check}`);
  return { ready: blockers.length === 0, status: blockers.length ? "unsafe" : "ready", blockers, protection };
}

function createPullRequest({ repo, branch, base, title, body, cwd, stateDir }) {
  const existing = ghJson(["pr", "list", "--repo", repo, "--head", branch, "--state", "all", "--json", "number,headRefName,headRefOid,baseRefName,url,state"], { cwd });
  if (existing.length > 1) throw new Error(`multiple PRs exist for ${branch}`);
  if (!existing.length) {
    const bodyFile = path.join(stateDir, `pr-${process.pid}.md`);
    fs.writeFileSync(bodyFile, body, { mode: 0o600 });
    try { run("gh", ["pr", "create", "--repo", repo, "--head", branch, "--base", base, "--title", title, "--body-file", bodyFile], { cwd }); }
    finally { fs.rmSync(bodyFile, { force: true }); }
  }
  const prs = ghJson(["pr", "list", "--repo", repo, "--head", branch, "--state", "all", "--json", "number,headRefName,headRefOid,baseRefName,url,state"], { cwd });
  if (prs.length !== 1) throw new Error(`could not resolve exactly one PR for ${branch}`);
  return prs[0];
}

function listPullRequests(repo, cwd) {
  return ghJson(["pr", "list", "--repo", repo, "--state", "open", "--limit", "100", "--json", "number,headRefName,headRefOid,baseRefName,isCrossRepository,statusCheckRollup,url"], { cwd });
}

function pullRequest(repo, number, cwd) {
  return ghJson(["pr", "view", String(number), "--repo", repo, "--json", "number,headRefName,headRefOid,baseRefName,state,mergedAt,url"], { cwd });
}

function deliveryMarker(record) { return marker("delivery", record); }

module.exports = {
  LIFECYCLE_LABELS,
  actorPermission,
  assertMaintainer,
  commentsWithMarker,
  createPullRequest,
  currentActor,
  currentLifecycle,
  deliveryMarker,
  ghJson,
  issueDetails,
  labelNames,
  listIssues,
  listPullRequests,
  paused,
  postComment,
  pullRequest,
  resolveRepo,
  selectNext,
  transitionLabels,
  verifyBranchProtection,
};
