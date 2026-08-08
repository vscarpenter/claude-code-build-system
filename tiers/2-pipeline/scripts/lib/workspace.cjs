const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { canonicalJson } = require("./protocol.cjs");
const { ensurePrivateDir, run } = require("./system.cjs");

function gitEnv(extra = {}) {
  return {
    ...process.env,
    GIT_AUTHOR_NAME: "Build System Controller",
    GIT_AUTHOR_EMAIL: "build-system@localhost",
    GIT_COMMITTER_NAME: "Build System Controller",
    GIT_COMMITTER_EMAIL: "build-system@localhost",
    ...extra,
  };
}

function leaseRef(prefix, issue) {
  return `refs/heads/${prefix}/leases/issue-${issue}`;
}

function createLeaseCommit(cwd, baseSha, record) {
  const tree = run("git", ["rev-parse", `${baseSha}^{tree}`], { cwd }).stdout.trim();
  return run("git", ["commit-tree", tree], { cwd, env: gitEnv(), input: `${canonicalJson(record)}\n` }).stdout.trim();
}

function remoteRefSha(cwd, ref) {
  const output = run("git", ["ls-remote", "--heads", "origin", ref], { cwd, check: false }).stdout.trim();
  return output ? output.split(/\s+/)[0] : null;
}

function readRemoteLease(cwd, ref, sha) {
  run("git", ["fetch", "--quiet", "--no-tags", "origin", ref], { cwd });
  const message = run("git", ["show", "-s", "--format=%B", sha || "FETCH_HEAD"], { cwd }).stdout.trim();
  return JSON.parse(message);
}

function acquireLease({ cwd, prefix, issue, baseSha, record, now = new Date() }) {
  const ref = leaseRef(prefix, issue);
  let fence = 1;
  const observed = remoteRefSha(cwd, ref);
  if (observed) {
    const prior = readRemoteLease(cwd, ref, observed);
    if (!prior.expiresAt || new Date(prior.expiresAt).getTime() > now.getTime()) {
      return { acquired: false, ref, holder: prior, sha: observed };
    }
    fence = Number.isSafeInteger(prior.fence) ? prior.fence + 1 : 1;
  }
  const next = { ...record, schemaVersion: 1, fence };
  const commit = createLeaseCommit(cwd, baseSha, next);
  const args = ["push", "--porcelain"];
  if (observed) args.push(`--force-with-lease=${ref}:${observed}`);
  args.push("origin", `${commit}:${ref}`);
  const pushed = run("git", args, { cwd, check: false });
  if (pushed.status !== 0) return { acquired: false, ref, holder: null, sha: remoteRefSha(cwd, ref) };
  const remoteSha = remoteRefSha(cwd, ref);
  if (remoteSha !== commit) throw new Error("lease push did not resolve to the expected commit");
  return { acquired: true, ref, record: next, sha: commit };
}

function releaseLease(cwd, lease) {
  if (!lease || !lease.acquired) return;
  const result = run("git", ["push", "--porcelain", `--force-with-lease=${lease.ref}:${lease.sha}`, "origin", `:${lease.ref}`], { cwd, check: false });
  if (result.status !== 0) throw new Error("lease release failed; ownership may have changed");
}

function assertLease(cwd, lease, now = new Date()) {
  if (!lease || !lease.acquired) throw new Error("authoritative mutation requires an acquired lease");
  if (!lease.record.expiresAt || new Date(lease.record.expiresAt).getTime() <= now.getTime()) throw new Error("lease expired before authoritative mutation");
  if (remoteRefSha(cwd, lease.ref) !== lease.sha) throw new Error("lease fence changed before authoritative mutation");
  return lease;
}

function createWorktree({ source, stateDir, runId, branch, baseSha }) {
  const worktreesDir = path.join(stateDir, "worktrees");
  ensurePrivateDir(worktreesDir);
  const worktree = path.join(worktreesDir, runId);
  if (fs.existsSync(worktree)) throw new Error(`run worktree already exists: ${worktree}`);
  run("git", ["worktree", "add", "-b", branch, worktree, baseSha], { cwd: source });
  const commonSource = fs.realpathSync(path.resolve(source, run("git", ["rev-parse", "--git-common-dir"], { cwd: source }).stdout.trim()));
  const commonWorktree = fs.realpathSync(path.resolve(worktree, run("git", ["rev-parse", "--git-common-dir"], { cwd: worktree }).stdout.trim()));
  if (commonSource !== commonWorktree) throw new Error("created worktree does not belong to the source repository");
  return worktree;
}

function cleanupWorktree({ source, stateDir, worktree, branch, keep = false }) {
  if (keep || !worktree || !fs.existsSync(worktree)) return;
  const allowedRoot = fs.realpathSync(path.join(stateDir, "worktrees"));
  const actual = fs.realpathSync(worktree);
  if (!actual.startsWith(`${allowedRoot}${path.sep}`)) throw new Error(`refusing to remove worktree outside state root: ${actual}`);
  run("git", ["worktree", "remove", "--force", actual], { cwd: source });
  if (branch) run("git", ["branch", "-D", branch], { cwd: source, check: false });
}

function holder(harness) {
  return `${os.hostname()}:${process.pid}:${harness}`;
}

module.exports = {
  acquireLease,
  assertLease,
  cleanupWorktree,
  createWorktree,
  holder,
  leaseRef,
  readRemoteLease,
  releaseLease,
  remoteRefSha,
};
