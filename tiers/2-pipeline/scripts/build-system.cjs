#!/usr/bin/env node
const crypto = require("node:crypto");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { invoke, probe } = require("./lib/adapters.cjs");
const { acquireLocalLock, appendEvent, releaseLocalLock, reserveRun, settleRun, writeProvenance } = require("./lib/evidence.cjs");
const { provenanceMatches } = require("./lib/evidence.cjs");
const github = require("./lib/github.cjs");
const { runVerification, validateDeliveryPolicy } = require("./lib/policy.cjs");
const { SCHEMA_VERSION, digest, makeContract, marker, transition, validateWorkOrder } = require("./lib/protocol.cjs");
const { atomicWriteJson, commandExists, ensurePrivateDir, gitRoot, loadConfig, normalizedOrigin, parseArgs, repoId, run, safeSlug } = require("./lib/system.cjs");
const workspace = require("./lib/workspace.cjs");

function usage() {
  console.log(`Usage:
  node scripts/build-system.cjs doctor [--harness claude|codex|all] [--json]
  node scripts/build-system.cjs run [--harness claude|codex] [--issue N] [--dry-run]
  node scripts/build-system.cjs approve --issue N
  node scripts/build-system.cjs status [--json]
  node scripts/build-system.cjs triage [--json]
  node scripts/build-system.cjs reconcile [--apply]

The controller owns queue selection, leases, worktrees, policy, verification,
Git delivery, GitHub transitions, budget, and evidence. Harnesses only plan or
edit inside the isolated worktree.`);
}

function stateRoot(id) {
  const base = process.env.XDG_STATE_HOME || path.join(os.homedir(), ".local", "state");
  return path.join(base, "build-system", id);
}

function newRunId() {
  return `${new Date().toISOString().replace(/[-:.TZ]/g, "").slice(0, 14)}-${crypto.randomBytes(6).toString("hex")}`;
}

function context(args) {
  const source = gitRoot(process.cwd());
  const { manifest, config, manifestFile } = loadConfig(source, args.manifest);
  const repo = github.resolveRepo(source, config.repo);
  const originRepo = normalizedOrigin(source);
  if (originRepo && originRepo.toLowerCase() !== repo.toLowerCase()) throw new Error(`origin '${originRepo}' does not match GitHub repository '${repo}'`);
  const id = repoId(source, repo);
  const root = stateRoot(id);
  ensurePrivateDir(root);
  if (config.leaseMinutes * 60 <= config.runTimeoutSeconds + 300) throw new Error("leaseMinutes must exceed runTimeoutSeconds by at least five minutes");
  return { source, manifest, manifestFile, config, repo, repoId: id, stateDir: root };
}

function doctor(args) {
  const checks = [];
  let ctx;
  try { ctx = context(args); checks.push(check("manifest", true, ctx.manifestFile)); }
  catch (error) {
    checks.push(check("manifest", false, error.message));
    return outputDoctor(checks, args);
  }
  for (const binary of ["git", "gh", "node"]) checks.push(check(`binary:${binary}`, commandExists(binary), commandExists(binary) ? "found" : "missing"));
  checks.push(check("gh-auth", run("gh", ["auth", "status"], { cwd: ctx.source, check: false }).status === 0, "authenticated GitHub CLI required"));
  checks.push(check("origin-identity", !normalizedOrigin(ctx.source) || normalizedOrigin(ctx.source).toLowerCase() === ctx.repo.toLowerCase(), `${normalizedOrigin(ctx.source)} -> ${ctx.repo}`));
  checks.push(check("pause-state", !github.paused(ctx.repo, "builder:paused", ctx.source), "builder:paused must be absent"));
  const protection = github.verifyBranchProtection(ctx.repo, ctx.config.defaultBranch, ctx.config.requiredChecks, ctx.source);
  checks.push(check("gate-2", protection.ready, protection.blockers.join(", ") || "branch rules enforce human release"));
  const harnesses = args.harness === "all" ? ["claude", "codex"] : [args.harness || ctx.config.harness];
  for (const harness of harnesses) {
    const result = probe(harness, ctx.source);
    checks.push(check(`adapter:${harness}`, result.ready, result.blockers.join(", ") || result.cli.version));
  }
  const labelList = github.ghJson(["label", "list", "--repo", ctx.repo, "--limit", "200", "--json", "name"], { cwd: ctx.source });
  const installed = new Set(labelList.map((item) => item.name));
  for (const label of ["agent:claimed", "agent:verifying", "agent:retryable", "pr:open"]) checks.push(check(`label:${label}`, installed.has(label), installed.has(label) ? "installed" : "run the installer label step"));
  return outputDoctor(checks, args);
}

function check(name, ready, detail) { return { name, status: ready ? "ready" : "unsafe", detail }; }

function outputDoctor(checks, args) {
  const result = { schemaVersion: 1, status: checks.every((item) => item.status === "ready") ? "READY" : "UNSAFE", checks };
  if (args.json) console.log(JSON.stringify(result));
  else {
    for (const item of checks) console.log(`${item.status === "ready" ? "OK" : "BLOCK"} ${item.name}: ${item.detail}`);
    console.log(result.status);
  }
  if (result.status !== "READY") process.exitCode = 3;
  return result;
}

function latestRecord(issue, kind) {
  const records = github.commentsWithMarker(issue, kind);
  return records.length ? records[records.length - 1].payload : null;
}

function contractFor(ctx, issue) {
  const contract = makeContract(ctx.repoId, issue);
  return { contract, contractDigest: digest(contract) };
}

function approve(args) {
  if (!args.issue || !/^\d+$/.test(args.issue)) throw new Error("approve requires --issue N");
  const ctx = context(args);
  const issue = github.issueDetails(ctx.repo, Number(args.issue), ctx.source);
  if (github.currentLifecycle(issue) !== "plan:pending") throw new Error("Gate 1 can approve only plan:pending");
  const { contractDigest } = contractFor(ctx, issue);
  const plan = latestRecord(issue, "plan");
  if (!plan || plan.contractDigest !== contractDigest) throw new Error("latest plan is not bound to the current issue contract");
  const actor = github.assertMaintainer(ctx.repo, ctx.source);
  const approval = { schemaVersion: 1, issue: issue.number, contractDigest, planDigest: plan.planDigest, actor: actor.login, permission: actor.permission, approvedAt: new Date().toISOString() };
  github.postComment(ctx.repo, issue.number, `Gate 1 approved by @${actor.login}.\n\n${marker("approval", approval)}`, ctx.source, ctx.stateDir);
  transition("plan:pending", "plan:approved");
  github.transitionLabels(ctx.repo, issue.number, "plan:pending", "plan:approved", ctx.source);
  console.log(JSON.stringify({ schemaVersion: 1, status: "approved", issue: issue.number, contractDigest, planDigest: plan.planDigest }));
}

function status(args) {
  const ctx = context(args);
  const states = {};
  for (const label of github.LIFECYCLE_LABELS) {
    const issues = github.listIssues(ctx.repo, label, ctx.source);
    if (issues.length) states[label] = issues.map((issue) => issue.number);
  }
  const result = { schemaVersion: 1, repo: ctx.repo, paused: github.paused(ctx.repo, "builder:paused", ctx.source), states };
  console.log(args.json ? JSON.stringify(result) : JSON.stringify(result, null, 2));
}

function failingCheck(check) {
  const conclusion = String(check && check.conclusion || "").toLowerCase();
  const state = String(check && check.state || "").toLowerCase();
  return ["failure", "timed_out", "cancelled", "action_required", "startup_failure"].includes(conclusion) || ["failure", "error"].includes(state);
}

function triage(args) {
  const ctx = context(args);
  if (github.paused(ctx.repo, "triage:paused", ctx.source)) {
    return console.log(JSON.stringify({ schemaVersion: 1, status: "paused", repo: ctx.repo }));
  }
  const candidates = github.listPullRequests(ctx.repo, ctx.source).filter((pr) =>
    pr.isCrossRepository === false &&
    pr.baseRefName === ctx.config.defaultBranch &&
    Array.isArray(pr.statusCheckRollup) &&
    pr.statusCheckRollup.some(failingCheck)
  );
  const trusted = candidates.filter((pr) => provenanceMatches(ctx.stateDir, { ...pr, repo: ctx.repo }));
  const rejected = candidates.filter((pr) => !trusted.some((item) => item.number === pr.number));
  const result = {
    schemaVersion: 1,
    status: trusted.length ? "attention-required" : "no-work",
    repo: ctx.repo,
    failing: trusted.map((pr) => ({ number: pr.number, branch: pr.headRefName, headSha: pr.headRefOid, url: pr.url })),
    rejected: rejected.map((pr) => ({ number: pr.number, reason: "provenance_mismatch" })),
    action: trusted.length ? "Inspect the failing checks, then move the linked issue to ready-for-human or agent:retryable explicitly." : null,
  };
  console.log(args.json ? JSON.stringify(result) : JSON.stringify(result, null, 2));
}

function runNext(args) {
  const ctx = context(args);
  const harness = args.harness || ctx.config.harness;
  if (!["claude", "codex"].includes(harness)) throw new Error("--harness must be claude or codex");
  if (github.paused(ctx.repo, "builder:paused", ctx.source)) return console.log(JSON.stringify({ schemaVersion: 1, status: "paused" }));
  const selected = args.issue ? selectIssue(ctx, Number(args.issue)) : github.selectNext(ctx.repo, ctx.source);
  if (!selected) return console.log(JSON.stringify({ schemaVersion: 1, status: "no-work" }));
  if (args["dry-run"]) return console.log(JSON.stringify({ schemaVersion: 1, status: "dry-run", issue: selected.issue.number, phase: selected.phase, harness }));
  return execute(ctx, selected, harness, args);
}

function selectIssue(ctx, number) {
  if (!Number.isSafeInteger(number) || number <= 0) throw new Error("--issue must be a positive integer");
  const issue = github.issueDetails(ctx.repo, number, ctx.source);
  const state = github.currentLifecycle(issue);
  const phases = { "plan:approved": "build", "agent:retryable": "build", "plan:revise": "revise", "ready-for-agent": "plan" };
  if (!phases[state]) throw new Error(`issue #${number} is not actionable from ${state}`);
  return { issue, phase: phases[state], sourceLabel: state };
}

function execute(ctx, selected, harness, args) {
  const lock = acquireLocalLock(ctx.stateDir);
  const runId = newRunId();
  const runDir = path.join(ctx.stateDir, "runs", runId);
  ensurePrivateDir(runDir);
  let lease = null;
  let worktree = null;
  let branch = null;
  let usage = null;
  let transitioned = null;
  try {
    run("git", ["fetch", "origin", ctx.config.defaultBranch, "--quiet"], { cwd: ctx.source });
    const baseSha = run("git", ["rev-parse", `origin/${ctx.config.defaultBranch}`], { cwd: ctx.source }).stdout.trim();
    const fresh = github.issueDetails(ctx.repo, selected.issue.number, ctx.source);
    const state = github.currentLifecycle(fresh);
    if (state !== selected.sourceLabel) throw new Error(`issue state changed from ${selected.sourceLabel} to ${state}`);
    const { contract, contractDigest } = contractFor(ctx, fresh);
    const planRecord = latestRecord(fresh, "plan");
    const approval = latestRecord(fresh, "approval");
    validateGate(selected.phase, contractDigest, planRecord, approval);
    branch = `${ctx.config.branchPrefix}/issue-${fresh.number}-${contractDigest.slice(0, 8)}-${safeSlug(fresh.title)}`;
    const now = new Date();
    const expiresAt = new Date(now.getTime() + ctx.config.leaseMinutes * 60_000).toISOString();
    lease = workspace.acquireLease({ cwd: ctx.source, prefix: ctx.config.branchPrefix, issue: fresh.number, baseSha, now, record: { runId, repo: ctx.repo, issue: fresh.number, phase: selected.phase, holder: workspace.holder(harness), contractDigest, planDigest: planRecord ? planRecord.planDigest : null, baseSha, branch, acquiredAt: now.toISOString(), expiresAt } });
    if (!lease.acquired) return console.log(JSON.stringify({ schemaVersion: 1, status: "claimed-elsewhere", issue: fresh.number, holder: lease.holder || null }));
    reserveRun(ctx.stateDir, ctx.config);
    appendEvent(runDir, "lease-acquired", { issue: fresh.number, ref: lease.ref, sha: lease.sha, fence: lease.record.fence });
    worktree = workspace.createWorktree({ source: ctx.source, stateDir: ctx.stateDir, runId, branch, baseSha });
    const order = validateWorkOrder({ schemaVersion: SCHEMA_VERSION, runId, repoId: ctx.repoId, issue: fresh.number, phase: selected.phase, contractDigest, planDigest: planRecord ? planRecord.planDigest : null, baseSha, worktree, allowedPaths: ctx.config.allowedPaths, protectedPaths: ctx.config.protectedPaths, verifyCommands: ctx.config.verifyCommands, fence: lease.record.fence });
    atomicWriteJson(path.join(runDir, "work-order.json"), order);
    if (selected.phase === "build") {
      workspace.assertLease(ctx.source, lease);
      transition(state, "agent:claimed");
      github.transitionLabels(ctx.repo, fresh.number, state, "agent:claimed", ctx.source);
      transitioned = "agent:claimed";
      transition("agent:claimed", "agent:building");
      github.transitionLabels(ctx.repo, fresh.number, "agent:claimed", "agent:building", ctx.source);
      transitioned = "agent:building";
    }
    const schemaFile = path.join(__dirname, "schemas", "agent-result.schema.json");
    const adapter = invoke({ harness, worktree, runDir, workOrder: order, contract, planText: planRecord ? planRecord.planText : null, timeoutSeconds: ctx.config.runTimeoutSeconds, maxBudgetUsd: ctx.config.maxBudgetUsd, schemaFile });
    usage = adapter.result.usage;
    appendEvent(runDir, "adapter-finished", { harness, status: adapter.result.status, usage });
    let outcome;
    if (selected.phase === "build") outcome = finalizeBuild(ctx, fresh, state, order, adapter.result, runDir, branch, baseSha, contractDigest, planRecord, lease);
    else outcome = finalizePlan(ctx, fresh, state, selected.phase, adapter.result, runDir, contractDigest, planRecord, lease);
    settleRun(ctx.stateDir, true, usage);
    appendEvent(runDir, "run-completed", outcome);
    console.log(JSON.stringify({ schemaVersion: 1, runId, ...outcome }));
  } catch (error) {
    settleRun(ctx.stateDir, false, usage);
    appendEvent(runDir, "run-failed", { message: error.message, evidence: error.evidence || null });
    if (transitioned) recoverIssue(ctx, selected.issue.number, transitioned, error);
    console.error(`ERROR: ${error.message}`);
    process.exitCode = classifyExit(error);
  } finally {
    try { if (lease && lease.acquired) workspace.releaseLease(ctx.source, lease); } catch (error) { console.error(`ERROR: ${error.message}`); process.exitCode ||= 4; }
    try { workspace.cleanupWorktree({ source: ctx.source, stateDir: ctx.stateDir, worktree, branch, keep: args["keep-worktree"] || process.exitCode }); } catch (error) { console.error(`WARN: ${error.message}`); }
    releaseLocalLock(lock);
  }
}

function validateGate(phase, contractDigest, plan, approval) {
  if (phase === "plan") return;
  if (!plan || plan.contractDigest !== contractDigest || plan.planDigest !== digest({ contractDigest, planText: plan.planText })) throw new Error("plan digest does not match the current contract");
  if (phase === "build" && (!approval || approval.contractDigest !== contractDigest || approval.planDigest !== plan.planDigest)) throw new Error("Gate 1 approval is absent or stale");
}

function finalizePlan(ctx, issue, state, phase, result, runDir, contractDigest, _planRecord, lease) {
  workspace.assertLease(ctx.source, lease);
  if (result.needsHuman || result.status === "escalated" || !result.plan) {
    const next = "ready-for-human";
    transition(state, next);
    github.postComment(ctx.repo, issue.number, `Controller escalation: ${result.summary}`, ctx.source, ctx.stateDir);
    github.transitionLabels(ctx.repo, issue.number, state, next, ctx.source);
    return { status: "escalated", issue: issue.number };
  }
  const dirty = run("git", ["status", "--porcelain"], { cwd: path.join(ctx.stateDir, "worktrees", path.basename(runDir)) }).stdout;
  if (dirty) throw new Error("planning adapter modified the worktree");
  const planText = result.plan;
  const planDigest = digest({ contractDigest, planText });
  const record = { schemaVersion: 1, issue: issue.number, contractDigest, planDigest, planText, runId: path.basename(runDir), createdAt: new Date().toISOString() };
  github.postComment(ctx.repo, issue.number, `${phase === "revise" ? "**Revised plan**" : "**Plan**"}\n\n${planText}\n\n${marker("plan", record)}`, ctx.source, ctx.stateDir);
  workspace.assertLease(ctx.source, lease);
  if (["docs", "chore"].includes(makeContract(ctx.repoId, issue).risk)) {
    const approval = { schemaVersion: 1, issue: issue.number, contractDigest, planDigest, actor: "policy:auto", permission: "repository-policy", approvedAt: new Date().toISOString() };
    github.postComment(ctx.repo, issue.number, `Gate 1 auto-approved by repository risk policy.\n\n${marker("approval", approval)}`, ctx.source, ctx.stateDir);
    transition(state, "plan:approved");
    github.transitionLabels(ctx.repo, issue.number, state, "plan:approved", ctx.source);
    return { status: "planned-auto-approved", issue: issue.number, contractDigest, planDigest };
  }
  transition(state, "plan:pending");
  github.transitionLabels(ctx.repo, issue.number, state, "plan:pending", ctx.source);
  return { status: phase === "revise" ? "revised" : "planned", issue: issue.number, contractDigest, planDigest };
}

function finalizeBuild(ctx, issue, originalState, order, result, runDir, branch, baseSha, contractDigest, plan, lease) {
  if (result.needsHuman || result.status === "escalated") throw new Error(`adapter escalated: ${result.summary}`);
  const worktree = order.worktree;
  const branchNow = run("git", ["branch", "--show-current"], { cwd: worktree }).stdout.trim();
  const headBefore = run("git", ["rev-parse", "HEAD"], { cwd: worktree }).stdout.trim();
  if (branchNow !== branch || headBefore !== baseSha) throw new Error("adapter changed Git branch or commit metadata");
  const policy = validateDeliveryPolicy({ cwd: worktree, baseSha, protectedPaths: order.protectedPaths, allowedPaths: order.allowedPaths, maxChangedFiles: ctx.config.maxChangedFiles, maxDiffBytes: ctx.config.maxDiffBytes });
  workspace.assertLease(ctx.source, lease);
  transition("agent:building", "agent:verifying");
  github.transitionLabels(ctx.repo, issue.number, "agent:building", "agent:verifying", ctx.source);
  const verification = runVerification({ cwd: worktree, commands: order.verifyCommands, timeoutSeconds: ctx.config.verifyTimeoutSeconds, stateDir: runDir });
  const finalPolicy = validateDeliveryPolicy({ cwd: worktree, baseSha, protectedPaths: order.protectedPaths, allowedPaths: order.allowedPaths, maxChangedFiles: ctx.config.maxChangedFiles, maxDiffBytes: ctx.config.maxDiffBytes });
  if (github.paused(ctx.repo, "builder:paused", ctx.source)) throw new Error("builder paused before delivery");
  workspace.assertLease(ctx.source, lease);
  const branchRules = github.verifyBranchProtection(ctx.repo, ctx.config.defaultBranch, ctx.config.requiredChecks, ctx.source);
  if (!branchRules.ready) throw new Error(`Gate 2 is not enforceable: ${branchRules.blockers.join(", ")}`);
  run("git", ["add", "-A"], { cwd: worktree });
  run("git", ["commit", "-m", `Build issue #${issue.number}: ${issue.title}`, "-m", `Build-System-Run: ${order.runId}\nContract-Digest: ${contractDigest}\nPlan-Digest: ${plan.planDigest}`], { cwd: worktree });
  const headSha = run("git", ["rev-parse", "HEAD"], { cwd: worktree }).stdout.trim();
  run("git", ["merge-base", "--is-ancestor", baseSha, headSha], { cwd: worktree });
  const remoteExisting = run("git", ["ls-remote", "--heads", "origin", `refs/heads/${branch}`], { cwd: worktree }).stdout.trim();
  if (remoteExisting) throw new Error(`remote delivery branch already exists: ${branch}`);
  workspace.assertLease(ctx.source, lease);
  run("git", ["push", "--porcelain", "origin", `${headSha}:refs/heads/${branch}`], { cwd: worktree });
  const remoteSha = run("git", ["ls-remote", "--heads", "origin", `refs/heads/${branch}`], { cwd: worktree }).stdout.trim().split(/\s+/)[0];
  if (remoteSha !== headSha) throw new Error("remote branch SHA does not match the verified commit");
  const prBody = [`Closes #${issue.number}`, "", result.summary, "", "## Controller verification", ...verification.map((item) => `- \`${item.command}\`: exit ${item.exitCode}`), "", `Contract digest: \`${contractDigest}\``, `Plan digest: \`${plan.planDigest}\``, `Run: \`${order.runId}\``].join("\n");
  workspace.assertLease(ctx.source, lease);
  const pr = github.createPullRequest({ repo: ctx.repo, branch, base: ctx.config.defaultBranch, title: issue.title, body: prBody, cwd: worktree, stateDir: runDir });
  if (pr.headRefName !== branch || pr.headRefOid !== headSha || pr.baseRefName !== ctx.config.defaultBranch) throw new Error("GitHub PR postcondition does not match verified delivery");
  const delivery = { schemaVersion: 1, runId: order.runId, issue: issue.number, repo: ctx.repo, baseSha, headSha, branch, pr: pr.number, contractDigest, planDigest: plan.planDigest, policy, finalPolicy, verification: verification.map((item) => ({ command: item.command, exitCode: item.exitCode, startedAt: item.startedAt })), deliveredAt: new Date().toISOString() };
  writeProvenance(ctx.stateDir, delivery);
  workspace.assertLease(ctx.source, lease);
  github.postComment(ctx.repo, issue.number, `Pull request opened: ${pr.url}\n\n${github.deliveryMarker(delivery)}`, ctx.source, ctx.stateDir);
  transition("agent:verifying", "pr:open");
  github.transitionLabels(ctx.repo, issue.number, "agent:verifying", "pr:open", ctx.source);
  return { status: "delivered", issue: issue.number, pr: pr.number, url: pr.url, branch, headSha };
}

function recoverIssue(ctx, issueNumber, state, error) {
  try {
    const fresh = github.issueDetails(ctx.repo, issueNumber, ctx.source);
    const current = github.currentLifecycle(fresh);
    if (!["agent:claimed", "agent:building", "agent:verifying"].includes(current)) return;
    const next = /protected path|Gate 2|Git branch|GitHub PR postcondition/.test(error.message) ? "ready-for-human" : "agent:retryable";
    transition(current, next);
    github.postComment(ctx.repo, issueNumber, `Controller stopped safely before release: ${error.message}`, ctx.source, ctx.stateDir);
    github.transitionLabels(ctx.repo, issueNumber, current, next, ctx.source);
  } catch (recoveryError) { console.error(`ERROR: recovery failed: ${recoveryError.message}`); }
}

function reconcile(args) {
  const ctx = context(args);
  const prefix = `refs/heads/${ctx.config.branchPrefix}/leases/`;
  const refs = run("git", ["ls-remote", "--heads", "origin", `${prefix}*`], { cwd: ctx.source }).stdout.trim().split("\n").filter(Boolean);
  const report = [];
  for (const line of refs) {
    const [sha, ref] = line.split(/\s+/);
    let record;
    try { record = workspace.readRemoteLease(ctx.source, ref, sha); }
    catch (error) { report.push({ ref, sha, status: "malformed", error: error.message }); continue; }
    const expired = new Date(record.expiresAt).getTime() <= Date.now();
    const item = { ref, sha, status: expired ? "expired" : "active", record };
    if (expired && args.apply) {
      const result = run("git", ["push", "--porcelain", `--force-with-lease=${ref}:${sha}`, "origin", `:${ref}`], { cwd: ctx.source, check: false });
      item.action = result.status === 0 ? "released" : "release-failed";
      if (item.action === "released" && Number.isSafeInteger(record.issue)) {
        try {
          const issue = github.issueDetails(ctx.repo, record.issue, ctx.source);
          const current = github.currentLifecycle(issue);
          if (["agent:claimed", "agent:building", "agent:verifying"].includes(current)) {
            github.postComment(ctx.repo, record.issue, `Reconciler released expired lease from run \`${record.runId}\`; work was not delivered.`, ctx.source, ctx.stateDir);
            github.transitionLabels(ctx.repo, record.issue, current, "agent:retryable", ctx.source);
            item.issueAction = "agent:retryable";
          }
        } catch (error) { item.issueAction = `failed:${error.message}`; }
      }
    }
    report.push(item);
  }
  const deliveries = [];
  for (const issue of github.listIssues(ctx.repo, "pr:open", ctx.source)) {
    const fresh = github.issueDetails(ctx.repo, issue.number, ctx.source);
    const records = github.commentsWithMarker(fresh, "delivery");
    if (!records.length) { deliveries.push({ issue: issue.number, status: "missing-delivery-evidence" }); continue; }
    const delivery = records[records.length - 1].payload;
    try {
      const pr = github.pullRequest(ctx.repo, delivery.pr, ctx.source);
      const exact = pr.headRefName === delivery.branch && pr.headRefOid === delivery.headSha && pr.baseRefName === ctx.config.defaultBranch && provenanceMatches(ctx.stateDir, { ...pr, repo: ctx.repo });
      const item = { issue: issue.number, pr: pr.number, status: exact ? (pr.mergedAt ? "merged" : pr.state.toLowerCase()) : "provenance-mismatch" };
      if (args.apply && exact && pr.mergedAt) {
        github.transitionLabels(ctx.repo, issue.number, "pr:open", "done", ctx.source);
        item.action = "done";
      } else if (args.apply && !exact) {
        github.postComment(ctx.repo, issue.number, "Reconciler detected delivery provenance drift; human review is required.", ctx.source, ctx.stateDir);
        github.transitionLabels(ctx.repo, issue.number, "pr:open", "ready-for-human", ctx.source);
        item.action = "ready-for-human";
      }
      deliveries.push(item);
    } catch (error) { deliveries.push({ issue: issue.number, pr: delivery.pr, status: "unavailable", error: error.message }); }
  }
  console.log(JSON.stringify({ schemaVersion: 1, repo: ctx.repo, mode: args.apply ? "apply" : "read-only", leases: report, deliveries }, null, args.json ? 0 : 2));
}

function classifyExit(error) {
  if (/lease/.test(error.message)) return 4;
  if (/protected path|outside allowedPaths|symlink|gitlink|diff is/.test(error.message)) return 5;
  if (/verification/.test(error.message)) return 6;
  if (/adapter|Claude|Codex|AgentResult/.test(error.message)) return 7;
  if (/push|PR|delivery|Gate 2/.test(error.message)) return 8;
  return 2;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const command = args._[0];
  if (!command || ["help", "-h", "--help"].includes(command)) return usage();
  if (command === "doctor") return doctor(args);
  if (command === "run" || command === "next") return runNext(args);
  if (command === "approve") return approve(args);
  if (command === "status") return status(args);
  if (command === "triage") return triage(args);
  if (command === "reconcile") return reconcile(args);
  throw new Error(`unknown command '${command}'`);
}

try { main(); }
catch (error) { console.error(`ERROR: ${error.message}`); process.exitCode = 2; }
