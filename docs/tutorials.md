# Tutorials

> [!Note|style:flat|label=Language-agnostic]
> These tutorials show Go, TypeScript, and Python — but Blueprint outputs plain text. The same mechanism works for Rust, SQL, YAML, Terraform, or any text format.

## Generate Go model files

### 1. Directory structure

```
templates/
└── model/
    ├── manifest.yaml
    └── files/
        ├── model.go.ejs.t
        └── repo.go.ejs.t
```

### 2. Write the manifest

```yaml
# templates/model/manifest.yaml
name: model
classification: model
prompts:
  - name: package
    type: input
    description: "Go package name"
    default: models
  - name: withRepo
    type: confirm
    description: "Generate repository layer?"
    default: false
```

> [!Note]
> Prompts are resolved interactively at generation time. Use `--force` to skip prompts and use defaults.

### 3. Write templates

**`templates/model/files/model.go.ejs.t`**

```yaml
---
to: models/<%= h.snakeCase(Name) %>.go
---
package <%= package %>

// <%= Name %> represents a <%= name %> entity.
type <%= Name %> struct {
    ID string `json:"id"`
}
```

**`templates/model/files/repo.go.ejs.t`**

```yaml
---
to: repos/<%= h.snakeCase(Name) %>_repo.go
---
package repos

import "models"

// <%= Name %>Repository handles <%= name %> persistence.
type <%= Name %>Repository struct{}

func New<%= Name %>Repository() *<%= Name %>Repository {
    return &<%= Name %>Repository{}
}
```

### 4. Generate

```bash
blueprint generate model --name User
```

Output:

```
Fluxo: generated 2 file(s)
Files:
  - generated/models/user.go
  - generated/repos/user_repo.go
```

## Generate a React component (TypeScript)

### 1. Directory structure

```
templates/
└── react-component/
    ├── manifest.yaml
    └── files/
        ├── Component.tsx.ejs.t
        └── index.ts.ejs.t
```

### 2. Write the manifest

```yaml
name: react-component
classification: react-component
prompts:
  - name: withStyles
    type: confirm
    description: "Include CSS module import?"
    default: true
```

### 3. Write templates

**`templates/react-component/files/Component.tsx.ejs.t`**

```yaml
---
to: src/components/<%= h.pascalCase(Name) %>/<%= h.pascalCase(Name) %>.tsx
---
import React from 'react';
<% if (withStyles) { %>import styles from './<%= h.pascalCase(Name) %>.module.css';<% } %>

interface <%= h.pascalCase(Name) %>Props {
  name: string;
}

export const <%= h.pascalCase(Name) %>: React.FC<<%= h.pascalCase(Name) %>Props> = ({ name }) => {
  return (
    <div<% if (withStyles) { %> className={styles.container}<% } %>>
      <h1>Hello, {name}!</h1>
    </div>
  );
};
```

**`templates/react-component/files/index.ts.ejs.t`**

```yaml
---
to: src/components/<%= h.pascalCase(Name) %>/index.ts
---
export { <%= h.pascalCase(Name) %> } from './<%= h.pascalCase(Name) %>';
```

### 4. Generate

```bash
blueprint generate react-component --name UserCard
```

Output:

```
Fluxo: generated 2 file(s)
Files:
  - generated/src/components/UserCard/UserCard.tsx
  - generated/src/components/UserCard/index.ts
```

## Generate a FastAPI route (Python)

### 1. Directory structure

```
templates/
└── fastapi-route/
    ├── manifest.yaml
    └── files/
        ├── route.py.ejs.t
        └── schema.py.ejs.t
```

### 2. Write the manifest

```yaml
name: fastapi-route
classification: fastapi-route
prompts:
  - name: method
    type: select
    description: "HTTP method"
    options:
      - GET
      - POST
      - PUT
      - DELETE
    default: GET
  - name: auth
    type: confirm
    description: "Requires authentication?"
    default: true
```

### 3. Write templates

**`templates/fastapi-route/files/route.py.ejs.t`**

```yaml
---
to: routes/<%= h.snakeCase(name) %>.py
---
from fastapi import APIRouter, Depends<% if (auth) { %>, HTTPException, Security<% } %>

router = APIRouter(prefix="/<%= name %>", tags=["<%= name %>"])

<% if (auth) { %>from core.auth import get_current_user<% } %>

@router.<% if (method === "GET") { %>get<% } else if (method === "POST") { %>post<% } else if (method === "PUT") { %>put<% } else { %>delete<% } %>("/")
async def handle_<%= h.snakeCase(name) %>(<% if (auth) { %>current_user: dict = Depends(get_current_user)<% } %>):
    return {"message": "<%= h.pascalCase(name) %> endpoint"}
```

**`templates/fastapi-route/files/schema.py.ejs.t`**

```yaml
---
to: schemas/<%= h.snakeCase(name) %>.py
---
from pydantic import BaseModel

class <%= h.pascalCase(Name) %>Request(BaseModel):
    pass

class <%= h.pascalCase(Name) %>Response(BaseModel):
    id: str
    message: str
```

### 4. Generate

```bash
blueprint generate fastapi-route --name user
```

Output:

```
Fluxo: generated 2 file(s)
Files:
  - generated/routes/user.py
  - generated/schemas/user.py
```

## Inject into existing files

Modify an existing file by matching a regex pattern.

**`templates/model/files/registry.go.ejs.t`**

```yaml
---
inject: pkg/registry/registry.go
after: func RegisterRoutes\(
---
    router.Handle("<%= h.kebabCase(name) %>", handler)
```

Running `blueprint generate model --name Product` finds the line `func RegisterRoutes(` in the existing file and inserts the route registration after it.

> [!Warning|style:flat|label:Regex caution]
> The `after` and `before` patterns are compiled as JavaScript regex. Always escape special characters (`\.`, `\(`, `\)`, etc.).

## Use configured tools and scripts

Run a configured tool or script after rendering a template.

```yaml
---
tool: gofmt
to: <%= h.snakeCase(Name) %>.go
---
package <%= package %>

type <%= Name %> struct{}
```

The command runs in the staging directory. If it fails, the staged files are rolled back.

<!-- tabs:start -->

#### **Bash**

```yaml
script: format
```

#### **Node.js**

```yaml
script: postprocess
```

#### **Python**

```yaml
script: validate
```

<!-- tabs:end -->

## Handling conflicts

When generated files overlap with existing files, Blueprint asks what to do:

```
[blueprint] File conflicts detected:
  - src/models/user.go (source: user.go)

Options: [y]es to all, [n]o to all, [s]elect individually, [a]bort
```

- `y` — overwrite all conflicts
- `n` — skip all conflicts
- `s` — decide per file
- `a` — abort
