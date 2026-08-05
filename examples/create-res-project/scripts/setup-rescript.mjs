#!/usr/bin/env node
// Post-hook: mutates package.json to add ReScript toolchain deps/scripts/bin.
// Read from CWD (= outputDir set by EngineOrchestrator).
// Diagnostics go to stderr; success is silent.
// NO child_process, NO package manager.
import fs from "node:fs";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------
const TOOLCHAIN_DEPS = {rescript: "^12.3.0", "@rescript/runtime": "^12.3.0"}
const TOOLCHAIN_DEV_DEPS = {rolldown: "^1.2.3", "rollup-plugin-esbuild": "^6.2.1"}
const SCRIPTS = {
  "res:build": "rescript",
  "res:dev": "rescript watch",
  "res:clean": "rescript clean",
  "bundle": "rolldown -c",
  "start": "node dist/main.mjs",
}
const NODE_FLOOR = ">=22.0.0"
const MAIN_FIELD = "dist/main.mjs"

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
/**
 * Shallow-merge `value` into `target[key]` only when the key is absent.
 * For dependencies / devDependencies objects.
 */
function mergeAddIfAbsent(target, key, value) {
  const existing = target[key]
  if (existing == null) {
    target[key] = value
  } else if (typeof existing === "object" && !Array.isArray(existing)) {
    for (const [k, v] of Object.entries(value)) {
      if (!(k in existing)) {
        existing[k] = v
      }
    }
  }
}

/**
 * Set `target[key] = candidate` only when the current value is absent or
 * lower than `candidate`. Used for engines.node floor-raise.
 */
function mergeFloorRaise(target, key, candidate) {
  const current = target[key]
  if (current == null) {
    target[key] = candidate
  } else {
    // Simple string comparison — ">=" check is enough for the node floor
    // e.g. ">=20.0.0" is lower than ">=22.0.0"
    if (typeof current === "string" && current < candidate) {
      target[key] = candidate
    }
  }
}

/**
 * Merge { [packageName]: MAIN_FIELD } into target.bin, preserving existing entries.
 */
function mergeBin(target, packageName) {
  if (target.bin == null) {
    target.bin = {}
  }
  if (!(packageName in target.bin)) {
    target.bin[packageName] = MAIN_FIELD
  }
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------
function main() {
  const packageJsonPath = "package.json"

  // Read original bytes for rollback
  let originalContent
  try {
    originalContent = fs.readFileSync(packageJsonPath)
  } catch (err) {
    if (err.code === "ENOENT") {
      console.error("setup-rescript: package.json not found in CWD", process.cwd())
    } else if (err.code === "EACCES") {
      console.error("setup-rescript: permission denied reading package.json:", err.message)
    } else {
      console.error("setup-rescript: failed to read package.json:", err.message)
    }
    process.exit(1)
  }

  // Parse
  let pkg
  try {
    pkg = JSON.parse(originalContent.toString("utf8"))
  } catch (err) {
    console.error("setup-rescript: failed to parse package.json:", err.message)
    process.exit(1)
  }

  // Initialize top-level keys
  if (pkg.dependencies == null) pkg.dependencies = {}
  if (pkg.devDependencies == null) pkg.devDependencies = {}
  if (pkg.scripts == null) pkg.scripts = {}
  if (pkg.engines == null) pkg.engines = {}

  // Merge deps / devDeps / scripts (add-if-absent)
  mergeAddIfAbsent(pkg, "dependencies", TOOLCHAIN_DEPS)
  mergeAddIfAbsent(pkg, "devDependencies", TOOLCHAIN_DEV_DEPS)
  mergeAddIfAbsent(pkg, "scripts", SCRIPTS)

  // engines.node floor-raise
  mergeFloorRaise(pkg.engines, "node", NODE_FLOOR)

  // main: skip-if-present (only set when absent)
  if (pkg.main == null) {
    pkg.main = MAIN_FIELD
  }

  // bin: merge
  if (pkg.name != null) {
    mergeBin(pkg, pkg.name)
  }

  // Serialize with 2-space indent + trailing newline
  const json = JSON.stringify(pkg, null, 2) + "\n"

  // Atomic write: tmp -> rename
  const tmpPath = "package.json.tmp"
  let restoreOnError = false
  try {
    fs.writeFileSync(tmpPath, json, {encoding: "utf8"})
    restoreOnError = true
    fs.renameSync(tmpPath, packageJsonPath)
  } catch (err) {
    if (restoreOnError) {
      // Attempt to restore original content
      try {
        fs.writeFileSync(packageJsonPath, originalContent)
      } catch (_) {
        // best-effort — already in an error state
      }
    }
    if (err.code === "EACCES" || err.code === "EROFS") {
      console.error("setup-rescript: permission denied writing package.json:", err.message)
    } else {
      console.error("setup-rescript: failed to write package.json:", err.message)
    }
    process.exit(1)
  }
}

main()
