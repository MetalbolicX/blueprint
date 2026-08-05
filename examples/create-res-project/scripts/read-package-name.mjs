#!/usr/bin/env node
// Reads package.json from CWD and emits the package name as JSON.
// Diagnostics go to stderr; exact JSON goes to stdout.
// Reserved keys (name/Name/names/Names/h) are NEVER emitted — we use packageName.
import fs from "node:fs";
import path from "node:path";

const packageJsonPath = path.join(process.cwd(), "package.json");

let raw;
try {
  raw = fs.readFileSync(packageJsonPath, "utf8");
} catch (err) {
  if (err.code === "ENOENT") {
    console.error("read-package-name: package.json not found in CWD", process.cwd());
    process.exit(1);
  }
  console.error("read-package-name: failed to read package.json:", err.message);
  process.exit(1);
}

let pkg;
try {
  pkg = JSON.parse(raw);
} catch (err) {
  console.error("read-package-name: failed to parse package.json:", err.message);
  process.exit(1);
}

const name = pkg.name;
if (name == null || name === "") {
  console.error("read-package-name: package.json has no non-empty 'name' field");
  process.exit(1);
}

// Emit ONLY packageName — never name, Name, names, Names, or h (reserved keys from HookContext bridge)
process.stdout.write(JSON.stringify({ packageName: name }));
