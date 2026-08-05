---
to: rolldown.config.mjs
---
"use strict";
import { defineConfig } from "rolldown";
import { join } from "node:path";

const dirname = import.meta.dirname ?? ".";

export default defineConfig({
  input: join(dirname, "src", "Main.res.mjs"),
  output: {
    format: "es",
    file: join(dirname, "dist", "main.mjs"),
    banner: "#!/usr/bin/env node",
  },
  platform: "node",
  external: [
    /^node:/,
    "ejs",
    "yaml",
    /^@rescript\/runtime/,
  ],
});
