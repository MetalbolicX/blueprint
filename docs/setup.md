# Setup

## Requirements

- Go 1.22+

<!-- tabs:start -->

#### **From source**

```bash
git clone https://github.com/fluxo/fluxo.git
cd fluxo
go build -o bin/fluxo ./cmd/fluxo
```

Add `bin/` to your `$PATH`, or move the binary:

```bash
mv bin/fluxo /usr/local/bin/
```

#### **Go install**

```bash
go install github.com/fluxo/fluxo/cmd/fluxo@latest
```

<!-- tabs:end -->

## Initialize a project

```bash
fluxo init
```

Creates `.fluxo.yaml` in the current directory:

```yaml
# Fluxo configuration
generators: []
hooks:
  pre_generate: ""
  post_generate: ""
  timeout: 5s
```

> [!Tip|style:flat|label:Pro tip]
> Commit `.fluxo.yaml` to your repo so all contributors use the same hooks and timeout settings.

## Verify

```bash
fluxo --help
```

Expected output:

```
Usage: fluxo <generator> <action> [--name NAME] [--force] [--output DIR]

Commands:
  init           scaffold a .fluxo.yaml config file
  generate       run template generation

Flags:
  --help         show help
  --name         component name
  --force        force overwrite / skip prompts
  --output       output root directory (default: generated)
```

## Next step

[Create your first template →](tutorials.md)
