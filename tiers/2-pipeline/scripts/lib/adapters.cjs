const fs = require("node:fs");
const path = require("node:path");
const { validateAgentResult } = require("./protocol.cjs");
const { atomicWriteJson, commandExists, run } = require("./system.cjs");

const ADAPTER_VERSION = "1.0.0";

function withoutDeliveryCredentials(extra = {}) {
  const source = { ...process.env, ...extra };
  const env = {};
  for (const key of ["PATH", "HOME", "USER", "LOGNAME", "LANG", "LC_ALL", "TERM", "TMPDIR", "XDG_CONFIG_HOME", "CODEX_HOME", "CLAUDE_CONFIG_DIR", "ANTHROPIC_API_KEY", "CLAUDE_CODE_OAUTH_TOKEN", "OPENAI_API_KEY"]) {
    if (typeof source[key] === "string") env[key] = source[key];
  }
  env.GIT_TERMINAL_PROMPT = "0";
  return env;
}

function probe(harness, cwd) {
  const binary = harness === "claude" ? "claude" : harness === "codex" ? "codex" : "";
  const blockers = [];
  if (!binary) blockers.push("unsupported_harness");
  if (binary && !commandExists(binary)) blockers.push("cli_missing");
  let version = null;
  let authenticated = false;
  if (blockers.length === 0) {
    version = run(binary, ["--version"], { check: false }).stdout.trim();
    const auth = harness === "claude"
      ? run("claude", ["auth", "status", "--json"], { check: false })
      : run("codex", ["login", "status"], { check: false });
    authenticated = auth.status === 0;
    if (!authenticated) blockers.push("unauthenticated");
  }
  const instruction = harness === "claude" ? "CLAUDE.md" : "AGENTS.md";
  if (!fs.existsSync(path.join(cwd, instruction))) blockers.push("instructions_missing");
  if (!fs.existsSync(path.join(cwd, ".agents/skills/build-next/SKILL.md")) && harness !== "claude") blockers.push("skill_missing");
  return {
    schemaVersion: 1,
    harness,
    adapterVersion: ADAPTER_VERSION,
    executionMode: "controller-orchestrated",
    ready: blockers.length === 0,
    cli: { path: binary && commandExists(binary) ? run("sh", ["-c", "command -v \"$1\"", "_", binary]).stdout.trim() : null, version, authenticated },
    capabilities: {
      nonInteractive: true,
      structuredFinal: true,
      workspaceWrites: true,
      gitMetadataWrites: false,
      networkTools: false,
      controllerOwnedVcs: true,
      controllerOwnedTransport: true,
    },
    blockers,
  };
}

function buildPrompt(workOrder, contract, planText) {
  const action = workOrder.phase === "build" ? "implement the approved plan" : workOrder.phase === "revise" ? "revise the existing plan" : "produce a plan";
  return [
    "You are a bounded worker inside a deterministic delivery controller.",
    `Your task is to ${action} for issue #${workOrder.issue}.`,
    "Read the repository instructions and standards before acting.",
    "Never run git or gh, change branches, commit, push, create a PR, edit labels, or claim verification passed.",
    "For plan/revise phases, do not edit files. For build, edit only ordinary project source and tests.",
    "The controller independently audits paths, runs verification, commits, pushes, opens the PR, and records evidence.",
    "Return exactly the AgentResult schema supplied by the runner.",
    `WorkOrder: ${JSON.stringify(workOrder)}`,
    `WorkContract: ${JSON.stringify(contract)}`,
    `Approved or prior plan: ${planText || "none"}`,
  ].join("\n\n");
}

function parseClaudeOutput(stdout) {
  const outer = JSON.parse(stdout);
  if (outer.is_error || (outer.subtype && outer.subtype !== "success")) throw new Error("Claude reported an execution error");
  const candidate = outer.structured_output || outer.result;
  const result = typeof candidate === "string" ? JSON.parse(candidate) : candidate;
  const validated = validateAgentResult(result);
  if (!validated.usage && outer.usage) {
    const values = [outer.usage.input_tokens, outer.usage.output_tokens, outer.usage.cache_read_input_tokens, outer.usage.cache_creation_input_tokens];
    if (values.every((value) => Number.isSafeInteger(value) && value >= 0)) {
      const usage = {
        inputTokens: values[0], outputTokens: values[1], cacheReadTokens: values[2], cacheWriteTokens: values[3],
        totalTokens: values.reduce((sum, value) => sum + value, 0),
        costUsd: Number.isFinite(outer.total_cost_usd) ? outer.total_cost_usd : null,
      };
      validated.usage = usage;
    }
  }
  return validated;
}

function invoke({ harness, worktree, runDir, workOrder, contract, planText, timeoutSeconds, maxBudgetUsd, schemaFile }) {
  const capability = probe(harness, worktree);
  if (!capability.ready) throw new Error(`adapter is not ready: ${capability.blockers.join(", ")}`);
  fs.mkdirSync(runDir, { recursive: true, mode: 0o700 });
  const prompt = buildPrompt(workOrder, contract, planText);
  fs.writeFileSync(path.join(runDir, "prompt.txt"), prompt, { mode: 0o600 });
  const rawFile = path.join(runDir, harness === "claude" ? "events.json" : "events.jsonl");
  const stderrFile = path.join(runDir, "stderr.log");
  const finalFile = path.join(runDir, "provider-final.json");
  const env = withoutDeliveryCredentials();
  let result;
  if (harness === "claude") {
    result = run("claude", ["-p", "--output-format", "json", "--json-schema", fs.readFileSync(schemaFile, "utf8"), "--permission-mode", "dontAsk", "--tools", "Read,Edit,Write,Glob,Grep", "--allowedTools", "Read,Edit,Write,Glob,Grep", "--disallowedTools", "Read(.git)", "Read(.git/**)", "Read(../**/.git/**)", "--setting-sources", "project", "--no-session-persistence", "--max-budget-usd", String(maxBudgetUsd)], { cwd: worktree, env, input: prompt, check: false, timeoutMs: timeoutSeconds * 1000 });
    fs.writeFileSync(rawFile, result.stdout, { mode: 0o600 });
    fs.writeFileSync(stderrFile, result.stderr, { mode: 0o600 });
    if (result.error || result.status !== 0) throw new Error(`Claude adapter failed with exit ${result.status}${result.error ? `: ${result.error.message}` : ""}`);
    const normalized = parseClaudeOutput(result.stdout);
    atomicWriteJson(path.join(runDir, "agent-result.json"), normalized);
    return { result: normalized, capability, artifacts: { rawFile, stderrFile } };
  }
  if (harness === "codex") {
    result = run("codex", ["exec", "--ignore-user-config", "--strict-config", "--sandbox", "workspace-write", "--ephemeral", "--json", "--output-schema", schemaFile, "--output-last-message", finalFile, "-C", worktree, "-c", 'approval_policy="never"', "-c", 'web_search="disabled"', "-c", "sandbox_workspace_write.network_access=false", "-"], { cwd: worktree, env, input: prompt, check: false, timeoutMs: timeoutSeconds * 1000 });
    fs.writeFileSync(rawFile, result.stdout, { mode: 0o600 });
    fs.writeFileSync(stderrFile, result.stderr, { mode: 0o600 });
    if (result.error || result.status !== 0) throw new Error(`Codex adapter failed with exit ${result.status}${result.error ? `: ${result.error.message}` : ""}`);
    for (const line of result.stdout.split("\n").filter(Boolean)) JSON.parse(line);
    const normalized = validateAgentResult(JSON.parse(fs.readFileSync(finalFile, "utf8")));
    atomicWriteJson(path.join(runDir, "agent-result.json"), normalized);
    return { result: normalized, capability, artifacts: { rawFile, stderrFile, finalFile } };
  }
  throw new Error(`unsupported harness '${harness}'`);
}

module.exports = { ADAPTER_VERSION, buildPrompt, invoke, parseClaudeOutput, probe, withoutDeliveryCredentials };
