# Architecture

## Execution pipeline

```mermaid
sequenceDiagram
    participant CLI as dist/main.mjs
    participant Engine as engine
    participant Phase0 as phase0
    participant Phase1 as phase1
    participant Phase2 as phase2
    participant FS as Filesystem

    CLI->>Engine: run(generator, name, cliAttributes, outputDir, force)
    Engine->>Engine: Read & parse manifest.yaml (via generator.manifest)
    Engine->>Engine: Discover templates (_templates/<gen>/<action>/*.ejs.t)
    Engine->>Engine: Build Context (cwd, name variants, attributes, cliAttributes)

    Engine->>Phase0: run(rl, generator, context, outputDir, force)
    Phase0->>Phase0: Resolve prompts (interactive or force defaults)
    Phase0-->>Engine: resolvedAttributes + conflicts

    Engine->>Phase1: run(templates, mergedContext, outputDir, conflictDecisions)
    Phase1->>Phase1: Create staging dir (Os.makeStagingDir)
    Phase1->>Phase1: Render templates via EJS
    Phase1-->>Engine: Staged files + shell commands

    Engine->>Phase2: run(stagingDir, outputDir, renderedFiles)
    Phase2->>FS: Copy files from staging to output
    Phase2->>FS: Clean up staging dir
    Phase2-->>Engine: Committed files

    Engine-->>CLI: Result(filesCreated, commandsExecuted)
```

## Package structure

```
src/
├── interfaces/cli/          CLI entry point (Cli.res, Main.res)
├── application/
│   ├── engine/              Pipeline orchestrator (Engine.res)
│   └── pipeline/            Phase0/1/2 (Phase0.res, Phase1.res, Phase2.res)
├── infrastructure/
│   ├── discovery/           FS traversal, template index (Discovery.res)
│   ├── rendering/           EJS template rendering (Renderer.res)
│   ├── prompts/             Interactive prompt resolution (PromptResolver.res)
│   └── bindings/            Node.js/third-party FFI (NodeJs.res, Bindings.res)
├── domain/
│   └── context/             Context building, name variants, merge (Context.res)
└── main/                    Main module wrapper
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
        P1_Shell[Queue shell commands]
    end

    subgraph Phase2["Phase 2 — Commit"]
        P2_Copy[Copy to output root]
        P2_Shell[Execute shell commands]
        P2_Rollback[Rollback output on command failure]
        P2_Cleanup[Cleanup staging dir]
    end

    Phase0 --> Phase1 --> Phase2
```

| Phase | Action | Failure handling |
|-------|--------|-----------------|
| 0 | Prompt resolution, conflict detection | Return error immediately |
| 1 | Render to `os.TempDir()`, inject, collect shell commands | **Rollback**: `os.RemoveAll(stagingDir)` |
| 2 | Commit files, execute queued commands, cleanup | On command failure, restore overwritten files and delete newly created files |

## Component state flow

```mermaid
flowchart TD
    Start["blueprint generate <classification>"] --> ParseArgs[Parse CLI flags]
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
    HasShell -- Yes --> QueueShell[Queue command for Phase2]
    HasShell -- No --> MoreTemplates{more templates?}
    QueueShell --> MoreTemplates
    MoreTemplates -- Yes --> Render
    MoreTemplates -- No --> Commit[Copy staged files to output root]
    Commit --> RunQueuedShell[Execute queued shell/fetch/script commands]
    RunQueuedShell --> ShellFail{command failed?}
    ShellFail -- Yes --> RollbackOutput[Restore backups + delete newly created files]
    ShellFail -- No --> Cleanup[Remove staging dir]
    RollbackOutput --> Cleanup
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
    Engine->>Phase2: Execute(stagedFiles, outputRoot, shellCommands)
    Phase2->>Output: Copy files (backup overwritten targets)
    Phase2->>Phase2: Execute queued shell/fetch/script commands
    alt command fails
      Phase2->>Output: Restore overwritten files from backup
      Phase2->>Output: Remove newly created files
      Note over Output: Output state restored
    else all commands succeed
      Note over Output: All files committed
    end
    Phase2->>Staging: os.RemoveAll

Fetch commands write transient `fetch-*.tmp` files in output during execution; Phase2 removes those files on both success and failure paths.
```
