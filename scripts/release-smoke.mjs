#!/usr/bin/env node
/**
 * release-smoke.mjs — single-command publish-readiness check
 *
 * Runs: pnpm build → npm pack → install in temp dir → invoke blueprint --version → cleanup
 * Exits 0 on success, non-zero on failure.
 */

import { execSync, execFileSync } from "child_process";
import { mkdtempSync, rmSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";
import { fileURLToPath } from "url";

const __dirname = fileURLToPath(new URL(".", import.meta.url));
// project root is the parent of scripts/
const projectRoot = join(__dirname, "..");

function run(cmd, opts = {}) {
  console.log(`> ${cmd}`);
  try {
    execSync(cmd, {
      stdio: "inherit",
      cwd: opts.cwd || projectRoot,
      ...opts,
    });
    return true;
  } catch (err) {
    console.error(`FAILED: ${cmd}`);
    return false;
  }
}

function runCapture(cmd, opts = {}) {
  console.log(`> ${cmd}`);
  try {
    const result = execSync(cmd, {
      cwd: opts.cwd || projectRoot,
      encoding: "utf8",
      timeout: opts.timeout || 60000,
      ...opts,
    });
    return { exitCode: 0, stdout: result, stderr: "" };
  } catch (err) {
    return {
      exitCode: err.status || 1,
      stdout: err.stdout || "",
      stderr: err.stderr || "",
    };
  }
}

let tempDir = null;
let success = false;

try {
  // Step 1: build
  if (!run("pnpm build")) {
    console.error("release-smoke FAILED at pnpm build");
    process.exit(1);
  }

  // Step 2: npm pack
  console.log("(pack output shown above)");
  const packResult = runCapture("npm pack --dry-run", { timeout: 60000 });
  if (packResult.exitCode !== 0) {
    // Try a real pack to get the filename
    const realPack = runCapture("npm pack", { timeout: 60000 });
    if (realPack.exitCode !== 0) {
      console.error("release-smoke FAILED at npm pack");
      process.exit(1);
    }
    var tgzFile = realPack.stdout.trim().split("\n").pop();
  } else {
    // Dry-run succeeded — use a real pack to get the filename for install test
    const realPack = runCapture("npm pack", { timeout: 60000 });
    if (realPack.exitCode !== 0) {
      console.error("release-smoke FAILED at npm pack");
      process.exit(1);
    }
    var tgzFile = realPack.stdout.trim().split("\n").pop();
  }
  console.log(`Packaged: ${tgzFile}`);

  // Step 3: install in temp dir
  tempDir = mkdtempSync(join(tmpdir(), "blueprint-smoke-"));
  console.log(`Install dir: ${tempDir}`);
  if (!run(`npm install "${join(projectRoot, tgzFile)}"`, { cwd: tempDir })) {
    console.error("release-smoke FAILED at npm install");
    process.exit(1);
  }

  // Step 4: invoke blueprint --version
  const binPath = join(tempDir, "node_modules", ".bin", "blueprint");
  const versionResult = runCapture(`"${binPath}" --version`, { timeout: 30000 });
  if (versionResult.exitCode !== 0) {
    console.error(`release-smoke FAILED: blueprint --version exited ${versionResult.exitCode}`);
    console.error(`stdout: ${versionResult.stdout}`);
    console.error(`stderr: ${versionResult.stderr}`);
    process.exit(1);
  }
  console.log(` blueprint version check passed`);

  success = true;
  console.log("\nrelease-smoke PASSED — package is publish-ready");
} finally {
  // Step 5: cleanup
  if (tempDir) {
    try {
      rmSync(tempDir, { recursive: true, force: true });
      console.log(`Cleaned up: ${tempDir}`);
    } catch (_) {
      // best-effort
    }
  }
}

process.exit(success ? 0 : 1);
