---
to: .oxlintrc.json
---
{
  "$schema": "./node_modules/oxlint/configuration_schema.json",
  "plugins": ["typescript", "unicorn", "import", "vitest"],
  "env": { "node": true, "browser": true },
  "categories": { "correctness": "error" },
  "rules": {
    "import/no-commonjs": "error",
    "no-else-return": "error",
    "prefer-const": "error",
    "unicorn/prefer-node-protocol": "error",
    "prefer-template": "error",
    "prefer-arrow-callback": "error",
    "@typescript-eslint/prefer-optional-chain": "error",
    "no-empty": "error",
    "@typescript-eslint/no-explicit-any": "warn",
    "vitest/no-focused-tests": "warn",
    "vitest/no-disabled-tests": "warn",
    "no-var": "error"
  }
}
