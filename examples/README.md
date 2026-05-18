# Blueprint Examples

This directory contains example templates you can copy and customize for your own projects.

## Quick start

1. Copy an example template to your project:
   ```bash
   cp -r examples/react-component _templates/
   ```

2. Generate from the template:
   ```bash
   blueprint generate react-component --name Button --path src/components
   ```

3. Or use the example config (optional):
   ```bash
   cp examples/.blueprint.yaml .blueprint.yaml
   ```

## Available examples

### react-component

React component generator with TypeScript. Creates a component file and an accompanying test file.

**Prompts:**
- `name` — Component name (PascalCase, default: MyComponent)
- `path` — Output directory (default: src/components)

**Files:**
- `Component.tsx.ejs.ts` — React component with props interface
- `Component.test.tsx.ejs.ts` — Vitest test file with basic rendering test

**Run:**
```bash
blueprint generate react-component --name Button --path src/components
```

### go-handler

Go HTTP handler generator. Creates a handler struct with ServeHTTP method.

**Prompts:**
- `name` — Handler name (PascalCase, default: Handler)
- `package` — Go package name (default: handlers)

**Files:**
- `handler.go.ejs.t` — Go file with struct, constructor, and HTTP method

**Run:**
```bash
blueprint generate go-handler --name User --package handlers
```

### python-fastapi

Python FastAPI route generator. Creates a route file and an accompanying test file.

**Prompts:**
- `name` — Route name (PascalCase, default: Route)
- `description` — Route description (default: API endpoint)

**Files:**
- `route.py.ejs.t` — FastAPI route with GET and POST handlers
- `test_route.py.ejs.t` — pytest test file

**Run:**
```bash
blueprint generate python-fastapi --name User --description "User management"
```

### yaml-config

YAML configuration file generator. Creates environment-specific config files.

**Prompts:**
- `name` — Config name (default: config)
- `environment` — Environment name (default: development)
- `port` — Port number (default: 3000)

**Files:**
- `config.yaml.ejs.t` — YAML config with environment, port, and database settings

**Run:**
```bash
blueprint generate yaml-config --name myapp --environment production --port 8080
```

## Customizing templates

### Change the classification

Edit `manifest.yaml` and change the `classification` field. Then run:
```bash
blueprint generate <your-classification>
```

### Add more prompts

Add entries to the `prompts` array in `manifest.yaml`:

```yaml
prompts:
  - name: name
    type: input
    description: "Component name"
    default: MyComponent
  - name: framework
    type: select
    description: "Choose framework"
    options:
      - react
      - vue
      - svelte
```

### Use helpers in templates

Access name variants and helpers via the `h` object:

```ejs
<%= name %>           # lowercase: mycomponent
<%= Name %>           # PascalCase: MyComponent
<%= names %>          # plural lowercase: mycomponents
<%= Names %>          # plural PascalCase: MyComponents
<%= h.kebabCase(name) %>  # kebab-case: my-component
<%= h.snakeCase(name) %>  # snake_case: my_component
```

### Add directives

Use frontmatter to control how files are generated:

```yaml
---
to: src/<%= name %>.tsx      # Output path
inject: class \w+            # Inject into existing file
force: true                  # Overwrite without prompting
---
```

## More resources

- [Full documentation](/docs)
- [Template format reference](/docs/templates.md)
- [Frontmatter directives](/docs/directives.md)