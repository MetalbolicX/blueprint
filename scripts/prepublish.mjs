#!/usr/bin/env node
// Runs the same build pipeline as `pnpm build` (rescript + rolldown -c)
// Detects available package manager; falls back to npx when pnpm is absent.

import { execSync } from "child_process";

function run(cmd) {
  console.log(`> ${cmd}`);
  execSync(cmd, { stdio: "inherit" });
}

const usePnpm = process.env.npm_config_user_agent?.startsWith("pnpm/");

if (usePnpm) {
  run("pnpm res:build");
  run("pnpm bundle");
} else {
  run("npx rescript");
  run("npx rolldown -c");
}
