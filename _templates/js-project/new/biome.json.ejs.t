---
to: biome.json
---
{
  "$schema": "https://biomejs.dev/schemas/2.2.3/schema.json",
  "vcs": {
    "enabled": false
  },
  "files": {
    "ignoreUnknown": false
  },
  "formatter": {
    "enabled": true,
    "indentStyle": "space",
    "indentWidth": 2,
    "lineWidth": 120
  },
  "linter": {
    "enabled": true,
    "rules": {
      "recommended": true,
      "style": {
        "noCommonJs": "error",
        "noUselessElse": "error",
        "useConst": "error",
        "useForOf": "error",
        "useNodejsImportProtocol": "error",
        "useTemplate": "error"
      },
      "complexity": {
        "useArrowFunction": "error",
        "useOptionalChain": "error"
      },
      "suspicious": {
        "noEmptyBlock": "error",
        "noExplicitAny": "warn",
        "noFocusedTests": "warn",
        "noSkippedTests": "warn",
        "noVar": "error"
      }
    }
  },
  "assist": {
    "actions": {
      "source": {
        "organizeImports": "on"
      }
    }
  },
  "javascript": {
    "formatter": {
      "quoteStyle": "double",
      "semicolons": "always"
    }
  }
}
