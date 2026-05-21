---
to: opencode.json
---
{
  "$schema": "https://opencode.ai/config.json",
  "lsp": {
    "typescript": {
      "command": ["typescript-language-server", "--stdio"],
      "extensions": [".ts", ".tsx", ".mts", ".cts"]
    },
    "javascript": {
      "command": ["typescript-language-server", "--stdio"],
      "extensions": [".js", ".jsx", ".mjs", ".cjs"]
    }
  }
}