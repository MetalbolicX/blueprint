# Setup

## Requirements

- Node.js 18+
- pnpm

## Install

```bash
git clone https://github.com/blueprint/blueprint.git
cd blueprint
pnpm install
pnpm bundle
```

The bundled CLI is at `dist/main.mjs`. Run it directly or link it:

```bash
node dist/main.mjs --help
```

## Initialize a project

```bash
blueprint init
```

Creates `.blueprint.yaml` in the current directory:

```yaml
# Blueprint configuration
generators: []
hooks:
  pre_generate: ""
  post_generate: ""
  timeout: 5s
```

> [!Tip|style:flat|label:Pro tip]
> Commit `.blueprint.yaml` to your repo so all contributors use the same hooks and timeout settings.

## Verify

```bash
blueprint --help
```

Expected output:

```
Usage: blueprint <generator> <action> [--name NAME] [--force] [--output DIR]

Commands:
  init           scaffold a .blueprint.yaml config file
  generate       run template generation

Flags:
  --help         show help
  --name         component name
  --force        force overwrite / skip prompts
  --output       output root directory (default: generated)
```

## Next step

[Create your first template →](tutorials.md)
