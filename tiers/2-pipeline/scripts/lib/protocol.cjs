const crypto = require("node:crypto");

const SCHEMA_VERSION = 1;
const STATES = Object.freeze([
  "needs-triage",
  "needs-info",
  "ready-for-agent",
  "plan:pending",
  "plan:revise",
  "plan:approved",
  "agent:claimed",
  "agent:building",
  "agent:verifying",
  "agent:retryable",
  "pr:open",
  "ready-for-human",
  "done",
  "wontfix",
]);

const TRANSITIONS = Object.freeze({
  "needs-triage": new Set(["needs-info", "ready-for-agent", "ready-for-human", "wontfix"]),
  "needs-info": new Set(["needs-triage", "wontfix"]),
  "ready-for-agent": new Set(["plan:pending", "plan:approved", "agent:claimed", "ready-for-human"]),
  "plan:pending": new Set(["plan:approved", "plan:revise", "needs-triage", "ready-for-human"]),
  "plan:revise": new Set(["plan:pending", "ready-for-human"]),
  "plan:approved": new Set(["agent:claimed", "needs-triage", "ready-for-human"]),
  "agent:claimed": new Set(["agent:building", "agent:retryable", "ready-for-human"]),
  "agent:building": new Set(["agent:verifying", "agent:retryable", "ready-for-human"]),
  "agent:verifying": new Set(["pr:open", "agent:retryable", "ready-for-human"]),
  "agent:retryable": new Set(["ready-for-agent", "plan:approved", "agent:claimed", "ready-for-human"]),
  "pr:open": new Set(["done", "agent:retryable", "ready-for-human"]),
  "ready-for-human": new Set(["ready-for-agent", "plan:approved", "done", "wontfix"]),
  done: new Set(),
  wontfix: new Set(),
});

function normalizeText(value) {
  return String(value ?? "").normalize("NFC").replace(/\r\n?/g, "\n");
}

function canonicalize(value) {
  if (value === null || typeof value === "boolean" || typeof value === "string") return value;
  if (typeof value === "number") {
    if (!Number.isSafeInteger(value)) throw new Error("canonical JSON accepts safe integers only");
    return value;
  }
  if (Array.isArray(value)) return value.map(canonicalize);
  if (typeof value === "object") {
    const out = {};
    for (const key of Object.keys(value).sort()) out[key] = canonicalize(value[key]);
    return out;
  }
  throw new Error(`unsupported canonical JSON value: ${typeof value}`);
}

function canonicalJson(value) {
  return JSON.stringify(canonicalize(value));
}

function digest(value) {
  return crypto.createHash("sha256").update(canonicalJson(value)).digest("hex");
}

function assertObject(value, name) {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error(`${name} must be an object`);
}

function assertExactKeys(value, allowed, name) {
  for (const key of Object.keys(value)) {
    if (!allowed.includes(key)) throw new Error(`${name} contains unknown field '${key}'`);
  }
}

function assertString(value, name, max = 100_000) {
  if (typeof value !== "string" || value.length > max) throw new Error(`${name} must be a string <= ${max} characters`);
}

function assertStringArray(value, name, maxItems = 100) {
  if (!Array.isArray(value) || value.length > maxItems) throw new Error(`${name} must be an array <= ${maxItems} items`);
  value.forEach((item, index) => assertString(item, `${name}[${index}]`, 10_000));
}

function validateWorkContract(value) {
  assertObject(value, "WorkContract");
  assertExactKeys(value, ["schemaVersion", "repoId", "issue", "title", "body", "risk", "sourceUpdatedAt"], "WorkContract");
  if (value.schemaVersion !== SCHEMA_VERSION) throw new Error("unsupported WorkContract schemaVersion");
  assertString(value.repoId, "WorkContract.repoId", 500);
  if (!Number.isSafeInteger(value.issue) || value.issue <= 0) throw new Error("WorkContract.issue must be a positive integer");
  assertString(value.title, "WorkContract.title", 500);
  assertString(value.body, "WorkContract.body");
  if (!["docs", "chore", "feature", "risky"].includes(value.risk)) throw new Error("WorkContract.risk is invalid");
  assertString(value.sourceUpdatedAt, "WorkContract.sourceUpdatedAt", 100);
  return canonicalize(value);
}

function validateWorkOrder(value) {
  assertObject(value, "WorkOrder");
  assertExactKeys(value, ["schemaVersion", "runId", "repoId", "issue", "phase", "contractDigest", "planDigest", "baseSha", "worktree", "allowedPaths", "protectedPaths", "verifyCommands", "fence"], "WorkOrder");
  if (value.schemaVersion !== SCHEMA_VERSION) throw new Error("unsupported WorkOrder schemaVersion");
  for (const key of ["runId", "repoId", "phase", "contractDigest", "baseSha", "worktree"]) assertString(value[key], `WorkOrder.${key}`, 2_000);
  if (!Number.isSafeInteger(value.issue) || value.issue <= 0) throw new Error("WorkOrder.issue must be positive");
  if (!Number.isSafeInteger(value.fence) || value.fence <= 0) throw new Error("WorkOrder.fence must be positive");
  if (!['plan', 'revise', 'build'].includes(value.phase)) throw new Error("WorkOrder.phase is invalid");
  if (value.planDigest !== null) assertString(value.planDigest, "WorkOrder.planDigest", 128);
  assertStringArray(value.allowedPaths, "WorkOrder.allowedPaths");
  assertStringArray(value.protectedPaths, "WorkOrder.protectedPaths");
  assertStringArray(value.verifyCommands, "WorkOrder.verifyCommands", 50);
  return canonicalize(value);
}

function validateAgentResult(value) {
  assertObject(value, "AgentResult");
  assertExactKeys(value, ["schemaVersion", "status", "summary", "plan", "changedPaths", "needsHuman", "usage"], "AgentResult");
  if (value.schemaVersion !== SCHEMA_VERSION) throw new Error("unsupported AgentResult schemaVersion");
  if (!["planned", "completed", "escalated", "failed", "no-work"].includes(value.status)) throw new Error("AgentResult.status is invalid");
  assertString(value.summary, "AgentResult.summary", 20_000);
  if (value.plan !== null) assertString(value.plan, "AgentResult.plan", 100_000);
  assertStringArray(value.changedPaths, "AgentResult.changedPaths", 1_000);
  if (typeof value.needsHuman !== "boolean") throw new Error("AgentResult.needsHuman must be boolean");
  if (value.usage !== null) {
    assertObject(value.usage, "AgentResult.usage");
    assertExactKeys(value.usage, ["inputTokens", "outputTokens", "cacheReadTokens", "cacheWriteTokens", "totalTokens", "costUsd"], "AgentResult.usage");
    for (const key of ["inputTokens", "outputTokens", "cacheReadTokens", "cacheWriteTokens", "totalTokens"]) {
      if (!Number.isSafeInteger(value.usage[key]) || value.usage[key] < 0) throw new Error(`AgentResult.usage.${key} must be a nonnegative safe integer`);
    }
    if (value.usage.costUsd !== null && (!Number.isFinite(value.usage.costUsd) || value.usage.costUsd < 0)) throw new Error("AgentResult.usage.costUsd is invalid");
  }
  return canonicalize(value);
}

function transition(from, to) {
  if (!STATES.includes(from) || !STATES.includes(to)) throw new Error(`unknown state transition ${from} -> ${to}`);
  if (!TRANSITIONS[from].has(to)) throw new Error(`illegal state transition ${from} -> ${to}`);
  return { schemaVersion: SCHEMA_VERSION, from, to };
}

function marker(kind, payload) {
  return `<!-- build-system-${kind} ${canonicalJson(payload)} -->`;
}

function parseMarkers(text, kind) {
  const prefix = `<!-- build-system-${kind} `;
  return normalizeText(text).split("\n").flatMap((line) => {
    const start = line.indexOf(prefix);
    if (start < 0 || !line.endsWith(" -->")) return [];
    try { return [JSON.parse(line.slice(start + prefix.length, -4))]; } catch { return []; }
  });
}

function makeContract(repoId, issue) {
  const riskLabel = (issue.labels || []).map((item) => typeof item === "string" ? item : item.name).find((name) => /^risk:/.test(name));
  return validateWorkContract({
    schemaVersion: SCHEMA_VERSION,
    repoId,
    issue: issue.number,
    title: normalizeText(issue.title),
    body: normalizeText(issue.body),
    risk: riskLabel ? riskLabel.slice(5) : "feature",
    sourceUpdatedAt: normalizeText(issue.updatedAt),
  });
}

module.exports = {
  SCHEMA_VERSION,
  STATES,
  canonicalJson,
  digest,
  makeContract,
  marker,
  normalizeText,
  parseMarkers,
  transition,
  validateAgentResult,
  validateWorkContract,
  validateWorkOrder,
};
