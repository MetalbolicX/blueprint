# Architecture

## Execution pipeline

```mermaid
sequenceDiagram
    participant CLI as cmd/fluxo
    participant Engine as engine
    participant Phase0 as phase0
    participant Phase1 as phase1
    participant Phase2 as phase2
    participant FS as Filesystem

    CLI->>Engine: Execute(ctx, manifestPath, outputRoot, context)
    Engine->>Engine: Read & parse manifest.yaml
    Engine->>Engine: Discover templates (files/*.ejs.t)
    Engine->>Engine: Build Context (cwd, name variants, attributes)

    Engine->>Phase0: Execute(index, promptValues, force)
    Phase0->>Phase0: Resolve prompts (interactive or defaults)
    Phase0-->>Engine: Resolved values

    Engine->>Phase1: Execute(resolvedValues, index, outputRoot)
    Phase1->>Phase1: Create staging dir (os.TempDir)
    Phase1->>Phase1: Render templates via text/template
    Phase1->>Phase1: Apply injections to existing files
    Phase1->>Phase1: Execute shell commands (sh:)
    Phase1-->>Engine: Staged files + injection log

    Engine->>Phase2: Execute(stagedFiles, outputRoot)
    Phase2->>FS: Write files to output root
    Phase2->>FS: Clean up staging dir
    Phase2-->>Engine: Committed files

    Engine->>Engine: Run post_generate hooks
    Engine-->>CLI: Result
```

## Package structure

```
cmd/
└── fluxo/
    └── main.go              CLI entry point

internal/
├── engine/
│   └── engine.go            Pipeline orchestrator, Context struct
├── manifest/
│   └── manifest.go          manifest.yaml parsing & validation
├── discovery/
│   └── discovery.go         FS traversal, template index
├── phases/
│   ├── phase0/
│   │   ├── phase0.go        Prompt routing & conflict detection
│   │   └── prompt_resolver.go  Interactive prompt resolution
│   ├── phase1/
│   │   ├── phase1.go        Staging, rendering, injection dispatch
│   │   └── shell.go         Shell command execution
│   └── phase2/
│       └── phase2.go        Atomic commit & rollback
├── templates/
│   ├── template.go          Template struct & Directives
│   ├── frontmatter.go       Frontmatter parsing, ApplyInjection
│   └── funcmaps.go          Go template FuncMaps
├── hooks/
│   └── hooks.go             Pre/post generate hook execution
└── conflicts/
    └── conflicts.go         Bulk conflict resolution
```

## Three-phase execution

```mermaid
flowchart LR
    subgraph Phase0["Phase 0 — Resolve"]
        P0_Prompts[Resolve prompts]
        P0_Conflicts[Detect file conflicts]
    end

    subgraph Phase1["Phase 1 — Stage"]
        P1_Render[Render templates]
        P1_Inject[Apply injections]
        P1_Shell[Execute shell commands]
    end

    subgraph Phase2["Phase 2 — Commit"]
        P2_Copy[Copy to output root]
        P2_Cleanup[Cleanup staging dir]
    end

    Phase0 --> Phase1 --> Phase2
```

| Phase | Action | Failure handling |
|-------|--------|-----------------|
| 0 | Prompt resolution, conflict detection | Return error immediately |
| 1 | Render to `os.TempDir()`, inject, execute shell | **Rollback**: `os.RemoveAll(stagingDir)` |
| 2 | Atomic copy to output root | No partial writes — commit is all-or-nothing |

## Component state flow

```mermaid
flowchart TD
    Start["fluxo generate <classification>"] --> ParseArgs[Parse CLI flags]
    ParseArgs --> LoadManifest[Load & parse manifest.yaml]
    LoadManifest --> Discover[Discover templates in files/]
    Discover --> BuildContext[Build context map]
    BuildContext --> HasPrompts{manifest has prompts?}

    HasPrompts -- Yes --> Force{--force set?}
    Force -- Yes --> UseDefaults[Use prompt defaults]
    Force -- No --> InteractivePrompts[Prompt user interactively]
    UseDefaults --> Conflicts
    InteractivePrompts --> Conflicts

    HasPrompts -- No --> Conflicts[Detect file conflicts]
    Conflicts --> HasConflicts{conflicts found?}
    HasConflicts -- Yes --> ResolveConflicts[Bulk resolve y/n/s/a]
    HasConflicts -- No --> Stage
    ResolveConflicts --> Stage

    Stage[Create staging dir] --> Render[Render templates]
    Render --> HasInject{frontmatter has inject?}
    HasInject -- Yes --> ApplyInjection[Read existing file, apply injection]
    HasInject -- No --> WriteStaged[Write new file to staging]
    ApplyInjection --> WriteStaged
    WriteStaged --> HasShell{frontmatter has sh?}
    HasShell -- Yes --> RunShell[Execute command in staging dir]
    HasShell -- No --> MoreTemplates{more templates?}
    RunShell --> MoreTemplates
    MoreTemplates -- Yes --> Render
    MoreTemplates -- No --> Commit[Atomic copy to output root]
    Commit --> Cleanup[Remove staging dir]
    Cleanup --> PostHooks[Run post_generate hooks]
    PostHooks --> Finish[Done]
```

## Conflict resolution

```mermaid
flowchart LR
    Conflict[File exists] --> Option{y/n/s/a}
    Option --> Y["y — overwrite all"]
    Option --> N["n — skip all"]
    Option --> S["s — select individually"]
    Option --> A["a — abort"]
    S --> PerFile["y/n per file"]
```

## Rollback safety

Every error path in the pipeline cleans up after itself:

```mermaid
sequenceDiagram
    participant Engine
    participant Phase1
    participant Phase2
    participant Staging
    participant Output

    Engine->>Phase1: Execute
    Phase1->>Staging: Write staged files
    Phase1-->>Engine: Error!
    Engine->>Phase2: Rollback(stagedFiles)
    Phase2->>Staging: os.RemoveAll(stagingDir)
    Note over Staging: No files reach Output

    Engine->>Phase1: Execute
    Phase1->>Staging: Write staged files
    Phase1-->>Engine: OK
    Engine->>Phase2: Execute(stagedFiles, outputRoot)
    Phase2->>Output: Copy files
    Phase2->>Staging: os.RemoveAll
    Note over Output: All files present atomically
```
