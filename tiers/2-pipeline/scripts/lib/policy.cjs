const fs = require("node:fs");
const path = require("node:path");
const { ensurePrivateDir, run } = require("./system.cjs");

const ALWAYS_PROTECTED = Object.freeze([
  ".build-system.json",
  ".github/workflows/**",
  ".claude/**",
  ".agents/**",
  "scripts/build-system/**",
  "scripts/build-system.cjs",
]);

function normalizeRepoPath(value) {
  const result = String(value).replace(/\\/g, "/").replace(/^\.\//, "");
  if (!result || result.startsWith("/") || result === ".." || result.startsWith("../") || result.includes("/../") || result.includes("\0")) {
    throw new Error(`unsafe repository path '${value}'`);
  }
  return result;
}

function globRegex(pattern) {
  const normalized = normalizeRepoPath(pattern);
  let regex = "^";
  for (let i = 0; i < normalized.length; i += 1) {
    const char = normalized[i];
    if (char === "*" && normalized[i + 1] === "*") {
      i += 1;
      if (normalized[i + 1] === "/") { i += 1; regex += "(?:.*/)?"; }
      else regex += ".*";
    } else if (char === "*") regex += "[^/]*";
    else if (char === "?") regex += "[^/]";
    else regex += char.replace(/[|\\{}()[\]^$+?.]/g, "\\$&");
  }
  return new RegExp(`${regex}$`);
}

function matchesAny(file, patterns) {
  const normalized = normalizeRepoPath(file);
  return patterns.some((pattern) => globRegex(pattern).test(normalized));
}

function parseNameStatus(buffer) {
  const parts = buffer.split("\0");
  const files = [];
  for (let i = 0; i < parts.length && parts[i]; i += 1) {
    const status = parts[i];
    if (/^[RC]/.test(status)) {
      files.push({ status, path: normalizeRepoPath(parts[++i]), side: "old" });
      files.push({ status, path: normalizeRepoPath(parts[++i]), side: "new" });
    } else files.push({ status, path: normalizeRepoPath(parts[++i]), side: "current" });
  }
  return files;
}

function changedFiles(cwd, baseSha) {
  const tracked = parseNameStatus(run("git", ["diff", "--name-status", "-z", "--find-renames", baseSha, "--"], { cwd }).stdout);
  const untracked = run("git", ["ls-files", "--others", "--exclude-standard", "-z"], { cwd }).stdout
    .split("\0").filter(Boolean).map((file) => ({ status: "?", path: normalizeRepoPath(file), side: "current" }));
  const seen = new Set();
  return [...tracked, ...untracked].filter((entry) => {
    const key = `${entry.status}\0${entry.path}\0${entry.side}`;
    if (seen.has(key)) return false;
    seen.add(key); return true;
  });
}

function fileMode(cwd, file) {
  const output = run("git", ["ls-files", "-s", "--", file], { cwd, check: false }).stdout.trim();
  return output ? output.split(/\s+/)[0] : null;
}

function validateDeliveryPolicy({ cwd, baseSha, protectedPaths, allowedPaths, maxChangedFiles, maxDiffBytes }) {
  const files = changedFiles(cwd, baseSha);
  const uniquePaths = [...new Set(files.map((entry) => entry.path))];
  if (uniquePaths.length === 0) throw new Error("adapter produced no changes");
  if (uniquePaths.length > maxChangedFiles) throw new Error(`change contains ${uniquePaths.length} files; limit is ${maxChangedFiles}`);
  const denied = [...ALWAYS_PROTECTED, ...protectedPaths];
  for (const entry of files) {
    if (matchesAny(entry.path, denied)) throw new Error(`protected path changed: ${entry.path}`);
    if (!matchesAny(entry.path, allowedPaths)) throw new Error(`path is outside allowedPaths: ${entry.path}`);
    if (entry.status !== "D") {
      const absolute = path.join(cwd, entry.path);
      try {
        const stat = fs.lstatSync(absolute);
        if (stat.isSymbolicLink()) throw new Error(`new or modified symlink is not allowed: ${entry.path}`);
      } catch (error) {
        if (error.code !== "ENOENT") throw error;
      }
      const mode = fileMode(cwd, entry.path);
      if (mode === "120000") throw new Error(`new or modified symlink is not allowed: ${entry.path}`);
      if (mode === "160000") throw new Error(`new or modified gitlink is not allowed: ${entry.path}`);
    }
  }
  const diff = run("git", ["diff", "--binary", baseSha, "--"], { cwd }).stdout;
  const diffBytes = Buffer.byteLength(diff);
  if (diffBytes > maxDiffBytes) throw new Error(`diff is ${diffBytes} bytes; limit is ${maxDiffBytes}`);
  return { files: uniquePaths.sort(), diffBytes, protectedPatterns: denied };
}

function verificationEnvironment(stateDir) {
  const home = path.join(stateDir, "verification-home");
  ensurePrivateDir(home);
  const env = { HOME: home, CI: "true", NODE_ENV: "test" };
  for (const key of ["PATH", "LANG", "LC_ALL", "TERM", "TMPDIR"]) {
    if (typeof process.env[key] === "string") env[key] = process.env[key];
  }
  return env;
}

function runVerification({ cwd, commands, timeoutSeconds, stateDir }) {
  const evidence = [];
  const env = verificationEnvironment(stateDir);
  for (const command of commands) {
    const startedAt = new Date().toISOString();
    const result = run("sh", ["-lc", command], { cwd, env, check: false, timeoutMs: timeoutSeconds * 1000, maxBuffer: 4 * 1024 * 1024 });
    evidence.push({ command, startedAt, exitCode: result.status, signal: result.signal, stdout: result.stdout.slice(-64_000), stderr: result.stderr.slice(-64_000) });
    if (result.error || result.status !== 0) {
      const failure = new Error(`verification failed: ${command}`);
      failure.evidence = evidence;
      throw failure;
    }
  }
  return evidence;
}

module.exports = {
  ALWAYS_PROTECTED,
  changedFiles,
  globRegex,
  matchesAny,
  normalizeRepoPath,
  parseNameStatus,
  runVerification,
  validateDeliveryPolicy,
};
