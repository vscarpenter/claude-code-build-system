const fs = require("node:fs");
const path = require("node:path");
const { canonicalJson, digest } = require("./protocol.cjs");
const { atomicWriteJson, ensurePrivateDir, readJson } = require("./system.cjs");

function acquireLocalLock(stateDir) {
  ensurePrivateDir(stateDir);
  const lock = path.join(stateDir, "controller.lock");
  try { fs.mkdirSync(lock, { mode: 0o700 }); }
  catch (error) {
    if (error.code === "EEXIST") throw new Error(`another local controller holds ${lock}`);
    throw error;
  }
  fs.writeFileSync(path.join(lock, "owner.json"), `${JSON.stringify({ pid: process.pid, startedAt: new Date().toISOString() })}\n`, { mode: 0o600 });
  return lock;
}

function releaseLocalLock(lock) {
  if (lock) fs.rmSync(lock, { recursive: true, force: true });
}

function budgetFile(stateDir) { return path.join(stateDir, "budget.json"); }

function reserveRun(stateDir, config, now = new Date()) {
  const file = budgetFile(stateDir);
  const day = now.toISOString().slice(0, 10);
  let ledger = { schemaVersion: 1, day, runs: 0, consecutiveFailures: 0, costUsd: 0 };
  if (fs.existsSync(file)) ledger = readJson(file);
  if (ledger.day !== day) ledger = { schemaVersion: 1, day, runs: 0, consecutiveFailures: 0, costUsd: 0 };
  if (ledger.runs >= config.dailyRunLimit) throw new Error(`daily run limit reached (${config.dailyRunLimit})`);
  if (ledger.consecutiveFailures >= config.maxConsecutiveFailures) throw new Error(`circuit breaker open after ${ledger.consecutiveFailures} consecutive failures`);
  ledger.runs += 1;
  ledger.lastReservedAt = now.toISOString();
  atomicWriteJson(file, ledger);
  return ledger;
}

function settleRun(stateDir, succeeded, usage) {
  const file = budgetFile(stateDir);
  const ledger = fs.existsSync(file) ? readJson(file) : { schemaVersion: 1, day: new Date().toISOString().slice(0, 10), runs: 1, consecutiveFailures: 0, costUsd: 0 };
  ledger.consecutiveFailures = succeeded ? 0 : ledger.consecutiveFailures + 1;
  if (usage && Number.isFinite(usage.costUsd)) ledger.costUsd = Number((ledger.costUsd + usage.costUsd).toFixed(6));
  ledger.lastSettledAt = new Date().toISOString();
  atomicWriteJson(file, ledger);
  return ledger;
}

function appendEvent(runDir, type, data) {
  ensurePrivateDir(runDir);
  const file = path.join(runDir, "evidence.jsonl");
  let seq = 1;
  let prevHash = null;
  if (fs.existsSync(file)) {
    const lines = fs.readFileSync(file, "utf8").trim().split("\n").filter(Boolean);
    if (lines.length) {
      const prior = JSON.parse(lines[lines.length - 1]);
      seq = prior.seq + 1;
      prevHash = prior.hash;
    }
  }
  const base = { schemaVersion: 1, seq, type, at: new Date().toISOString(), prevHash, data };
  const event = { ...base, hash: digest(base) };
  fs.appendFileSync(file, `${canonicalJson(event)}\n`, { mode: 0o600 });
  fs.chmodSync(file, 0o600);
  return event;
}

function writeProvenance(stateDir, record) {
  const dir = path.join(stateDir, "provenance");
  ensurePrivateDir(dir);
  atomicWriteJson(path.join(dir, `pr-${record.pr}.json`), { schemaVersion: 1, ...record });
}

function provenanceMatches(stateDir, candidate) {
  const file = path.join(stateDir, "provenance", `pr-${candidate.number}.json`);
  if (!fs.existsSync(file)) return false;
  try {
    const record = readJson(file);
    return record.repo === candidate.repo && record.pr === candidate.number && record.branch === candidate.headRefName && record.headSha === candidate.headRefOid;
  } catch { return false; }
}

module.exports = {
  acquireLocalLock,
  appendEvent,
  provenanceMatches,
  releaseLocalLock,
  reserveRun,
  settleRun,
  writeProvenance,
};
