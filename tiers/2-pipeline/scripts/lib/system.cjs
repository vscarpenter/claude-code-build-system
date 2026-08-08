const childProcess = require("node:child_process");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

function run(command, args = [], options = {}) {
  const result = childProcess.spawnSync(command, args, {
    cwd: options.cwd,
    env: options.env || process.env,
    encoding: "utf8",
    input: options.input,
    maxBuffer: options.maxBuffer || 8 * 1024 * 1024,
    timeout: options.timeoutMs,
    shell: false,
  });
  const output = { status: result.status, signal: result.signal, stdout: result.stdout || "", stderr: result.stderr || "", error: result.error };
  if (options.check !== false && (result.error || result.status !== 0)) {
    const detail = result.error ? result.error.message : (output.stderr || output.stdout).trim();
    throw new Error(`${command} failed${detail ? `: ${detail}` : ""}`);
  }
  return output;
}

function commandExists(command) {
  const result = run("sh", ["-c", "command -v \"$1\" >/dev/null 2>&1", "_", command], { check: false });
  return result.status === 0;
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

function ensurePrivateDir(dir) {
  const parent = path.dirname(dir);
  if (parent !== dir && !fs.existsSync(parent)) ensurePrivateDir(parent);
  if (fs.existsSync(dir)) {
    const stat = fs.lstatSync(dir);
    if (stat.isSymbolicLink() || !stat.isDirectory()) throw new Error(`unsafe state directory: ${dir}`);
  } else {
    fs.mkdirSync(dir, { mode: 0o700 });
  }
  fs.chmodSync(dir, 0o700);
}

function atomicWriteJson(file, value) {
  ensurePrivateDir(path.dirname(file));
  const temp = `${file}.tmp-${process.pid}-${crypto.randomBytes(6).toString("hex")}`;
  const fd = fs.openSync(temp, "wx", 0o600);
  try {
    fs.writeFileSync(fd, `${JSON.stringify(value, null, 2)}\n`);
    fs.fsyncSync(fd);
  } finally {
    fs.closeSync(fd);
  }
  fs.renameSync(temp, file);
  fs.chmodSync(file, 0o600);
}

function parseArgs(argv) {
  const args = { _: [] };
  for (let i = 0; i < argv.length; i += 1) {
    const value = argv[i];
    if (!value.startsWith("--")) { args._.push(value); continue; }
    const key = value.slice(2);
    if (["json", "dry-run", "keep-worktree"].includes(key)) args[key] = true;
    else {
      if (i + 1 >= argv.length) throw new Error(`${value} requires a value`);
      args[key] = argv[++i];
    }
  }
  return args;
}

function repoId(cwd, repoSlug) {
  const canonical = fs.realpathSync(cwd);
  const suffix = crypto.createHash("sha256").update(canonical).digest("hex").slice(0, 12);
  return `${repoSlug || path.basename(canonical)}-${suffix}`.replace(/[^A-Za-z0-9._-]/g, "-");
}

function sanitizeBranchPrefix(value) {
  if (typeof value !== "string" || !/^[A-Za-z0-9._-]+$/.test(value) || value === "." || value === "..") {
    throw new Error("config.branchPrefix must match ^[A-Za-z0-9._-]+$");
  }
  return value;
}

function safeSlug(value) {
  return String(value).normalize("NFKD").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 48) || "change";
}

function loadConfig(cwd, explicitFile) {
  const manifestFile = path.resolve(cwd, explicitFile || ".build-system.json");
  const manifest = readJson(manifestFile);
  const raw = manifest.config || {};
  const requiredArrays = ["verifyCommands", "protectedPaths"];
  for (const key of requiredArrays) {
    if (!Array.isArray(raw[key]) || raw[key].some((item) => typeof item !== "string" || item.startsWith("REPLACE:"))) {
      throw new Error(`config.${key} must be configured with string values`);
    }
  }
  const config = {
    repo: typeof raw.repo === "string" ? raw.repo : "",
    defaultBranch: typeof raw.defaultBranch === "string" ? raw.defaultBranch : "main",
    branchPrefix: sanitizeBranchPrefix(raw.branchPrefix || "agent"),
    harness: typeof raw.harness === "string" ? raw.harness : "claude",
    verifyCommands: raw.verifyCommands,
    protectedPaths: raw.protectedPaths,
    allowedPaths: Array.isArray(raw.allowedPaths) ? raw.allowedPaths : ["**"],
    requiredChecks: Array.isArray(raw.requiredChecks) ? raw.requiredChecks : [],
    leaseMinutes: integerInRange(raw.leaseMinutes, 90, 5, 1440, "leaseMinutes"),
    runTimeoutSeconds: integerInRange(raw.runTimeoutSeconds, 3600, 60, 14_400, "runTimeoutSeconds"),
    verifyTimeoutSeconds: integerInRange(raw.verifyTimeoutSeconds, 900, 10, 3600, "verifyTimeoutSeconds"),
    maxChangedFiles: integerInRange(raw.maxChangedFiles, 100, 1, 10_000, "maxChangedFiles"),
    maxDiffBytes: integerInRange(raw.maxDiffBytes, 1_048_576, 1_024, 100_000_000, "maxDiffBytes"),
    dailyRunLimit: integerInRange(raw.dailyRunLimit, 20, 1, 10_000, "dailyRunLimit"),
    maxConsecutiveFailures: integerInRange(raw.maxConsecutiveFailures, 3, 1, 100, "maxConsecutiveFailures"),
    maxBudgetUsd: finiteInRange(raw.maxBudgetUsd, 10, 0.01, 10_000, "maxBudgetUsd"),
  };
  return { manifest, manifestFile, config };
}

function integerInRange(value, fallback, min, max, name) {
  const number = value === undefined ? fallback : value;
  if (!Number.isSafeInteger(number) || number < min || number > max) throw new Error(`config.${name} must be an integer from ${min} to ${max}`);
  return number;
}

function finiteInRange(value, fallback, min, max, name) {
  const number = value === undefined ? fallback : value;
  if (!Number.isFinite(number) || number < min || number > max) throw new Error(`config.${name} must be from ${min} to ${max}`);
  return number;
}

function gitRoot(cwd) {
  return fs.realpathSync(run("git", ["rev-parse", "--show-toplevel"], { cwd }).stdout.trim());
}

function normalizedOrigin(cwd) {
  const url = run("git", ["remote", "get-url", "origin"], { cwd }).stdout.trim();
  const match = url.match(/(?:github\.com[:/])([^/]+)\/([^/]+?)(?:\.git)?$/i);
  return match ? `${match[1]}/${match[2]}` : "";
}

module.exports = {
  atomicWriteJson,
  commandExists,
  ensurePrivateDir,
  gitRoot,
  loadConfig,
  normalizedOrigin,
  parseArgs,
  readJson,
  repoId,
  run,
  safeSlug,
  sanitizeBranchPrefix,
};
