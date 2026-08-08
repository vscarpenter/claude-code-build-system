#!/usr/bin/env node
const assert = require("node:assert/strict");
const childProcess = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "..");
const LIB = path.join(ROOT, "tiers/2-pipeline/scripts/lib");
const protocol = require(path.join(LIB, "protocol.cjs"));
const policy = require(path.join(LIB, "policy.cjs"));
const workspace = require(path.join(LIB, "workspace.cjs"));
const adapters = require(path.join(LIB, "adapters.cjs"));
const evidence = require(path.join(LIB, "evidence.cjs"));

let passed = 0;
function test(name, fn) {
  try { fn(); passed += 1; console.log(`ok controller ${name}`); }
  catch (error) { console.error(`not ok controller ${name}: ${error.stack || error.message}`); process.exitCode = 1; }
}

function exec(command, args, cwd, env = process.env) {
  const result = childProcess.spawnSync(command, args, { cwd, env, encoding: "utf8" });
  if (result.status !== 0) throw new Error(`${command} ${args.join(" ")} failed: ${result.stderr}`);
  return result.stdout.trim();
}

function repoFixture() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "build-system-controller-"));
  exec("git", ["init", "-q", "-b", "main"], dir);
  fs.writeFileSync(path.join(dir, "README.md"), "base\n");
  exec("git", ["add", "README.md"], dir);
  exec("git", ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "base"], dir);
  return dir;
}

test("canonical digests ignore key order and normalize contract text", () => {
  assert.equal(protocol.digest({ b: 2, a: 1 }), protocol.digest({ a: 1, b: 2 }));
  const first = protocol.makeContract("r", { number: 1, title: "Café\r\n", body: "a\r\nb", updatedAt: "t", labels: [{ name: "risk:feature" }] });
  const second = protocol.makeContract("r", { number: 1, title: "Cafe\u0301\n", body: "a\nb", updatedAt: "t", labels: ["risk:feature"] });
  assert.equal(protocol.digest(first), protocol.digest(second));
});

test("state reducer accepts legal transitions and rejects regressions", () => {
  assert.equal(protocol.transition("plan:approved", "agent:claimed").to, "agent:claimed");
  assert.throws(() => protocol.transition("pr:open", "agent:building"), /illegal/);
  assert.throws(() => protocol.transition("done", "ready-for-agent"), /illegal/);
});

test("agent result rejects unknown fields and unsafe usage", () => {
  const base = { schemaVersion: 1, status: "completed", summary: "ok", plan: null, changedPaths: [], needsHuman: false, usage: null };
  assert.equal(protocol.validateAgentResult(base).status, "completed");
  assert.throws(() => protocol.validateAgentResult({ ...base, openedPr: 999 }), /unknown/);
  assert.throws(() => protocol.validateAgentResult({ ...base, usage: { inputTokens: -1, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0, totalTokens: 0, costUsd: null } }), /nonnegative/);
});

test("portable glob policy handles exact, star, question, and globstar", () => {
  assert.equal(policy.matchesAny("deploy/prod/app.yml", ["deploy/**"]), true);
  assert.equal(policy.matchesAny("src/a.ts", ["src/*.ts"]), true);
  assert.equal(policy.matchesAny("src/nested/a.ts", ["src/*.ts"]), false);
  assert.equal(policy.matchesAny("src/a.ts", ["src/?.ts"]), true);
  assert.throws(() => policy.globRegex("../secret"), /unsafe/);
});

test("delivery policy rejects protected edits, symlinks, and oversized diffs", () => {
  const repo = repoFixture();
  const base = exec("git", ["rev-parse", "HEAD"], repo);
  fs.mkdirSync(path.join(repo, "src"));
  fs.writeFileSync(path.join(repo, "src", "ok.js"), "ok\n");
  let result = policy.validateDeliveryPolicy({ cwd: repo, baseSha: base, protectedPaths: ["deploy/**"], allowedPaths: ["src/**"], maxChangedFiles: 2, maxDiffBytes: 1000 });
  assert.deepEqual(result.files, ["src/ok.js"]);
  fs.mkdirSync(path.join(repo, "deploy"));
  fs.writeFileSync(path.join(repo, "deploy", "prod.yml"), "bad\n");
  assert.throws(() => policy.validateDeliveryPolicy({ cwd: repo, baseSha: base, protectedPaths: ["deploy/**"], allowedPaths: ["**"], maxChangedFiles: 10, maxDiffBytes: 1000 }), /protected/);
  fs.rmSync(path.join(repo, "deploy"), { recursive: true });
  fs.symlinkSync("ok.js", path.join(repo, "src", "link.js"));
  assert.throws(() => policy.validateDeliveryPolicy({ cwd: repo, baseSha: base, protectedPaths: [], allowedPaths: ["**"], maxChangedFiles: 10, maxDiffBytes: 1000 }), /symlink/);
});

test("remote ref lease gives one winner and CAS release", () => {
  const source = repoFixture();
  const parent = fs.mkdtempSync(path.join(os.tmpdir(), "build-system-lease-"));
  const bare = path.join(parent, "remote.git");
  exec("git", ["clone", "--bare", source, bare], parent);
  const one = path.join(parent, "one");
  const two = path.join(parent, "two");
  exec("git", ["clone", "-q", bare, one], parent);
  exec("git", ["clone", "-q", bare, two], parent);
  const base = exec("git", ["rev-parse", "HEAD"], one);
  const expiresAt = new Date(Date.now() + 60_000).toISOString();
  const first = workspace.acquireLease({ cwd: one, prefix: "agent", issue: 7, baseSha: base, record: { runId: "one", expiresAt } });
  const second = workspace.acquireLease({ cwd: two, prefix: "agent", issue: 7, baseSha: base, record: { runId: "two", expiresAt } });
  assert.equal(first.acquired, true);
  assert.equal(second.acquired, false);
  assert.equal(workspace.assertLease(one, first), first);
  workspace.releaseLease(one, first);
  assert.throws(() => workspace.assertLease(one, first), /fence changed/);
  const after = workspace.acquireLease({ cwd: two, prefix: "agent", issue: 7, baseSha: base, record: { runId: "two", expiresAt } });
  assert.equal(after.acquired, true);
  workspace.releaseLease(two, after);
});

test("per-run worktree preserves a dirty active checkout", () => {
  const source = repoFixture();
  fs.writeFileSync(path.join(source, "DIRTY"), "sentinel\n");
  const before = exec("git", ["status", "--porcelain"], source);
  const state = fs.mkdtempSync(path.join(os.tmpdir(), "build-system-state-"));
  const base = exec("git", ["rev-parse", "HEAD"], source);
  const worktree = workspace.createWorktree({ source, stateDir: state, runId: "run-1", branch: "agent/issue-1-test", baseSha: base });
  assert.equal(fs.existsSync(path.join(worktree, "README.md")), true);
  workspace.cleanupWorktree({ source, stateDir: state, worktree, branch: "agent/issue-1-test" });
  assert.equal(exec("git", ["status", "--porcelain"], source), before);
  assert.equal(fs.readFileSync(path.join(source, "DIRTY"), "utf8"), "sentinel\n");
});

test("adapter environment strips delivery credentials", () => {
  const env = adapters.withoutDeliveryCredentials({ GH_TOKEN: "secret", GITHUB_TOKEN: "secret2", KEEP_ME: "yes" });
  assert.equal(env.GH_TOKEN, undefined);
  assert.equal(env.GITHUB_TOKEN, undefined);
  assert.equal(env.KEEP_ME, undefined);
  assert.equal(env.GIT_TERMINAL_PROMPT, "0");
});

test("Claude normalization ignores model-authored PR markers", () => {
  const agent = { schemaVersion: 1, status: "completed", summary: "OPENED_PR=999", plan: null, changedPaths: ["src/a.js"], needsHuman: false, usage: null };
  const normalized = adapters.parseClaudeOutput(JSON.stringify({ type: "result", subtype: "success", is_error: false, result: JSON.stringify(agent) }));
  assert.equal(normalized.summary, "OPENED_PR=999");
  assert.equal(Object.hasOwn(normalized, "openedPr"), false);
});

test("budget circuit breaker and evidence hash chain are durable", () => {
  const state = fs.mkdtempSync(path.join(os.tmpdir(), "build-system-evidence-"));
  const config = { dailyRunLimit: 2, maxConsecutiveFailures: 1 };
  evidence.reserveRun(state, config, new Date("2026-08-08T10:00:00Z"));
  evidence.settleRun(state, false, null);
  assert.throws(() => evidence.reserveRun(state, config, new Date("2026-08-08T11:00:00Z")), /circuit breaker/);
  const runDir = path.join(state, "runs", "one");
  const a = evidence.appendEvent(runDir, "start", { ok: true });
  const b = evidence.appendEvent(runDir, "finish", { ok: true });
  assert.equal(b.prevHash, a.hash);
  assert.equal(fs.statSync(path.join(runDir, "evidence.jsonl")).mode & 0o777, 0o600);
});

test("night-shift provenance requires exact repo, PR, branch, and head", () => {
  const state = fs.mkdtempSync(path.join(os.tmpdir(), "build-system-provenance-"));
  evidence.writeProvenance(state, { repo: "acme/widget", pr: 41, branch: "agent/issue-41", headSha: "abc123" });
  assert.equal(evidence.provenanceMatches(state, { repo: "acme/widget", number: 41, headRefName: "agent/issue-41", headRefOid: "abc123" }), true);
  assert.equal(evidence.provenanceMatches(state, { repo: "acme/widget", number: 41, headRefName: "agent/issue-41", headRefOid: "tampered" }), false);
  assert.equal(evidence.provenanceMatches(state, { repo: "evil/fork", number: 41, headRefName: "agent/issue-41", headRefOid: "abc123" }), false);
});

test("Claude prompt is supplied over stdin and adapters expose no Bash", () => {
  const source = fs.readFileSync(path.join(LIB, "adapters.cjs"), "utf8");
  assert.match(source, /\["-p", "--output-format"/);
  assert.match(source, /env, input: prompt/);
  assert.doesNotMatch(source, /Read,Edit,Write,Glob,Grep,Bash/);
});

test("controller CLI exposes deterministic operator commands", () => {
  const result = childProcess.spawnSync("node", [path.join(ROOT, "tiers/2-pipeline/scripts/build-system.cjs"), "help"], { encoding: "utf8" });
  assert.equal(result.status, 0);
  assert.match(result.stdout, /doctor/);
  assert.match(result.stdout, /reconcile/);
});

if (!process.exitCode) console.log(`controller_passed=${passed}`);
