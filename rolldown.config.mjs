"use strict";
import { defineConfig } from "rolldown";
import { join } from "node:path";
import { minify } from "rollup-plugin-esbuild";

const dirname = import.meta.dirname ?? ".";

export default defineConfig({
  input: join(dirname, "src", "VanRs.res.mjs"),
  output: {
    format: "es",
    file: join(dirname, "dist", "vanrs.mjs"),
  },
  platform: "browser",
  plugins: [minify()],
  external: [/^@rescript\/runtime$/],
});
