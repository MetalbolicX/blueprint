# Blueprint Production Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the CLI generator production-ready by closing all identified resilience, safety, observability, and type-safety gaps using TDD.

**Architecture:** Keep current hexagonal layering (`domain`/`application`/`infrastructure`/`interfaces`) and harden behaviors at boundaries: filesystem writes, shell/fetch execution, config bootstrap, and CLI lifecycle. Add a small observability slice (structured logger + correlation/run ID + health/readiness commands) without changing core generation flow.

**Tech Stack:** ReScript, Node runtime bindings, `rescript-test`.

---

## File Map

| File | Role |
|------|------|
| `src/application/pipeline/Phase0.res` | Implement real conflict detection |
| `src/application/pipeline/Phase1.res` | Expose/propagate staging cleanup hooks |
| `src/application/pipeline/Phase2.res` | Partial commit tracking + fetch temp file cleanup |
| `src/application/engine/Engine.res` | Orchestrate cleanup on all error paths |
| `src/interfaces/cli/Cli.res` | SIGINT/SIGTERM graceful shutdown + health/ready commands + fail-fast startup validation |
| `src/infrastructure/config/Config.res` | Strict validation helpers |
| `src/infrastructure/bindings/NodeJs.res` | Typed env/regex helpers to reduce `Obj.magic` |
| `src/infrastructure/rendering/Renderer.res` | Remove/centralize `Obj.magic` via typed bridge |
| `src/domain/template/Frontmatter.res` | Remove unsafe regex-capture casts |
| `src/infrastructure/observability/Logger.res` (new) | Structured logs + run ID propagation |
| `test/Phase0_test.res` | Conflict detection tests |
| `test/Engine_test.res` | Cleanup + shutdown orchestration tests |
| `test/Phase2_test.res` | Partial commit + temp cleanup tests |
| `test/Config_test.res` | Fail-fast config validation tests |
| `test/Frontmatter_test.res` | Regex parse safety tests |
| `test/Renderer_test.res` | Typed render bridge tests |
| `test/Integration_test.res` | End-to-end with health/ready and structured logs |

---

## Task 1: Establish Failing Safety Tests (TDD baseline)

**Files:**
- Modify: `test/Phase0_test.res`, `test/Engine_test.res`, `test/Phase2_test.res`, `test/Config_test.res`, `test/Frontmatter_test.res`, `test/Renderer_test.res`, `test/Integration_test.res`

- [ ] **Step 1: Add failing tests for each known gap**

```rescript
// Phase0 — detectConflicts stubbed:
let test_detects_conflict_when_target_exists = () => {
  // scaffold temp target file, run detectConflicts, assert conflictFile returned
}

// Engine — staging dir orphaned on error:
let test_staging_cleaned_on_phase1_error = () => {
  // inject phase1 error, verify staging dir removed
}

// Phase2 — partialCommit never populated:
let test_partial_commit_reported_on_failure = () => {
  // make 3rd write fail, assert error.partialCommit contains first 2 paths
}

// Config — no fail-fast on bad timeout:
let test_invalid_timeout_rejected_at_validation = () => {
  // timeout: -1 -> validateMergedConfig returns Error
}

// Frontmatter — malformed regex throws instead of returns Error:
let test_malformed_directive_returns_error = () => {
  // pass bad inject regex, assert Error response not throw
}

// Renderer — helper bridge crash on bad input:
let test_render_never_crashes_on_missing_var = () => {
  // pass incomplete renderContext, assert Error not throw
}

// CLI — healthz/readyz commands:
let test_healthz_exits_zero = () => { /* assert exit 0 */ }
let test_readyz_checks_config_and_paths = () => { /* assert exit 0 when healthy */ }
```

- [ ] **Step 2: Run tests and confirm they fail**

```bash
pnpm res:test test/Phase0_test.res.mjs
pnpm res:test test/Phase2_test.res.mjs
pnpm res:test test/Config_test.res.mjs
pnpm res:test test/Frontmatter_test.res.mjs
pnpm res:test test/Renderer_test.res.mjs
pnpm res:test test/Integration_test.res.mjs
```

Expected: each new assertion produces FAIL.

- [ ] **Step 3: Commit test baseline**

```bash
git add test/Phase0_test.res test/Engine_test.res test/Phase2_test.res test/Config_test.res test/Frontmatter_test.res test/Renderer_test.res test/Integration_test.res
git commit -m "test: add failing production-hardening specs"
```

---

## Task 2: Implement Real Conflict Detection in Phase0

**Files:**
- Modify: `src/application/pipeline/Phase0.res`
- Test: `test/Phase0_test.res`, `test/Integration_test.res`

- [ ] **Step 1: Review existing Phase0 test cases for conflict scenarios**

Cases to cover:
- no templates → no conflicts
- template with `to` to non-existing path → no conflicts
- template with `to` to existing file → conflictFile recorded with source+target
- force=true still records conflicts (resolver handles override)

- [ ] **Step 2: Implement detectConflicts**

```rescript
let detectConflicts: (
  ~templates: array<Template.template>,
  ~outputDir: string,
  ~force: bool,
) => promise<array<conflictFile>> = async (~templates, ~outputDir, ~force) => {
  let conflicts = []
  templates->Array.forEach(tmpl => {
    tmpl.directives->Array.forEach(d => {
      switch d {
      | To(targetPath) => {
          let fullTarget = Path.join(outputDir, targetPath)
          let exists = await Fs.fileExists(fullTarget)
          if exists {
            let conflict: conflictFile = {sourcePath: tmpl.sourcePath, targetPath: fullTarget}
            conflicts := [conflict, ...conflicts.contents]
          }
        }
      | _ => ()
      }
    })
  })
  conflicts.contents
}
```

- [ ] **Step 3: Run tests**

```bash
pnpm res:test test/Phase0_test.res.mjs
pnpm res:test test/Integration_test.res.mjs
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add src/application/pipeline/Phase0.res test/Phase0_test.res test/Integration_test.res
git commit -m "fix: implement phase0 conflict detection"
```

---

## Task 3: Graceful Shutdown (SIGINT/SIGTERM) + Engine Abort Safety

**Files:**
- Modify: `src/interfaces/cli/Cli.res`, `src/application/engine/Engine.res`, `src/infrastructure/bindings/NodeJs.res`
- Test: `test/Engine_test.res`, `test/Integration_test.res`

- [ ] **Step 1: Add failing tests for signal handling**

```rescript
let test_sigint_closes_readline_and_exits = () => {
  // send SIGINT, assert readline closed, partial artifacts cleaned
}
let test_sigterm_triggers_graceful_stop = () => {
  // send SIGTERM, assert clean exit with code 143
}
```

- [ ] **Step 2: Implement signal handler registration in Cli.res**

```rescript
let installShutdownHandlers: unit => unit = () => {
  let handle = (sig) => {
    Console.error("Received " ++ sig ++ ", shutting down gracefully...")
    rl->Option.forEach(r => r.close())
    NodeJs.NodeProcess.exit(128 + 2)  // 130 for SIGINT, 143 for SIGTERM
  }
  NodeJs.NodeProcess.on("SIGINT", () => handle("SIGINT"))
  NodeJs.NodeProcess.on("SIGTERM", () => handle("SIGTERM"))
}
```

- [ ] **Step 3: Wire engine cancellation checks around phase boundaries**

In `Engine.res`, wrap each phase call so cancellations propagate:
```rescript
let run = (...) => async (...) => {
  let cancelled = ref(false)
  let checkCancel = () => {
    if cancelled.contents {
      rl.close()
      Error("Generation cancelled")
    }
  }
  // register cancellation flag setter from signal handler
  // check before each phase
}
```

- [ ] **Step 4: Run tests**

```bash
pnpm res:test test/Engine_test.res.mjs
pnpm res:test test/Integration_test.res.mjs
```

- [ ] **Step 5: Commit**

```bash
git add src/interfaces/cli/Cli.res src/application/engine/Engine.res src/infrastructure/bindings/NodeJs.res test/Engine_test.res test/Integration_test.res
git commit -m "feat: add graceful shutdown for cli generation"
```

---

## Task 4: Guaranteed Staging Cleanup on All Error Paths

**Files:**
- Modify: `src/application/engine/Engine.res`, `src/application/pipeline/Phase1.res`
- Test: `test/Engine_test.res`, `test/Phase1_test.res`

- [ ] **Step 1: Add failing cleanup tests**

```rescript
let test_staging_removed_after_phase1_error = () => {
  // inject render error, assert staging dir does not exist post-run
}
let test_staging_removed_after_phase2_error = () => {
  // inject write error, assert staging dir does not exist post-run
}
let test_success_keeps_no_staging = () => {
  // normal run, assert staging dir cleaned
}
```

- [ ] **Step 2: Implement cleanup helper in Engine.res**

```rescript
let cleanupStaging: string => promise<unit> = async stagingDir => {
  let exists = await Bindings.Fs.fileExists(stagingDir)
  if exists {
    await Bindings.Fs.rm(stagingDir, ~options={recursive: true})
  }
}
```

- [ ] **Step 3: Wire finally-style cleanup in Engine.run**

All code paths that error must call `cleanupStaging` before returning:
- preHook error → cleanup + return
- Phase0 error → cleanup + return
- ConflictResolver abort → cleanup + return
- Phase1 error → cleanup + return
- Phase2 error → cleanup + return
- success → cleanup (always)

- [ ] **Step 4: Run tests**

```bash
pnpm res:test test/Phase1_test.res.mjs
pnpm res:test test/Engine_test.res.mjs
```

- [ ] **Step 5: Commit**

```bash
git add src/application/engine/Engine.res src/application/pipeline/Phase1.res test/Phase1_test.res test/Engine_test.res
git commit -m "fix: guarantee staging cleanup on generation failures"
```

---

## Task 5: Phase2 Partial Commit Tracking + Fetch Temp Cleanup

**Files:**
- Modify: `src/application/pipeline/Phase2.res`
- Test: `test/Phase2_test.res`

- [ ] **Step 1: Add failing tests**

```rescript
let test_partial_commit_includes_successful_files_before_failure = () => {
  // queue 3 writes; make 3rd fail; assert error.partialCommit = [path1, path2]
}
let test_fetch_temp_files_removed_on_success = () => {
  // run Fetch directive, assert no fetch-*.tmp files remain
}
let test_fetch_temp_files_removed_on_failure = () => {
  // Fetch + subsequent error, assert no fetch-*.tmp files remain
}
```

- [ ] **Step 2: Implement committed-path tracking**

```rescript
let executeShellCommands = (...) => {
  let committed = ref(list<string>())
  // after each successful file write:
  committed := list{path, ...committed.contents}
  // on error return Error({message, partialCommit: list.reverse(committed.contents)})
}
```

- [ ] **Step 3: Track and clean fetch temp artifacts**

```rescript
let tempFiles = ref(list<string>())
// on fetch write: tempFiles := list{fetchPath, ...tempFiles.contents}
// on finally/catch: tempFiles->List.iter(Fs.rm(~options={recursive:true}))
```

- [ ] **Step 4: Run tests**

```bash
pnpm res:test test/Phase2_test.res.mjs
```

- [ ] **Step 5: Commit**

```bash
git add src/application/pipeline/Phase2.res test/Phase2_test.res
git commit -m "fix: track partial commits and cleanup fetch temp files"
```

---

## Task 6: Fail-Fast Startup Configuration Validation

**Files:**
- Modify: `src/infrastructure/config/Config.res`, `src/interfaces/cli/Cli.res`
- Test: `test/Config_test.res`, `test/Integration_test.res`

- [ ] **Step 1: Add failing validation tests**

```rescript
let test_negative_timeout_rejected = () => {
  // cfg.timeout = -5 -> validateMergedConfig returns Error
}
let test_zero_timeout_rejected = () => {
  // cfg.timeout = 0 -> validateMergedConfig returns Error
}
let test_shell_enabled_without_tools_rejected = () => {
  // shell.enabled = true, tools = None -> Error
}
let test_malformed_hook_command_rejected = () => {
  // hook command missing 'command' field -> Error
}
```

- [ ] **Step 2: Implement validateMergedConfig in Config.res**

```rescript
let validateMergedConfig: mergedConfig => result<unit, string> = cfg => {
  if cfg.timeout < 1 {
    Error("timeout must be >= 1, got " ++ Int.toString(cfg.timeout))
  } else {
    switch cfg.shell {
    | Some(s) if s.enabled && !s.tools->Option.isSome =>
      Error("shell.enabled=true requires tools to be defined")
    | _ => Ok()
    }
  }
}
```

- [ ] **Step 3: Wire validate into Cli bootstrap**

```rescript
let runGenerate = (...) => async (...) => {
  let globalCfg = await Config.loadGlobal()
  let merged = Config.mergeConfig(...)
  switch Config.validateMergedConfig(merged) {
  | Error(e) => {
      Console.error("Configuration error: " ++ e)
      NodeJs.NodeProcess.exit(1)
    }
  | Ok => proceed with generation
  }
}
```

- [ ] **Step 4: Run tests**

```bash
pnpm res:test test/Config_test.res.mjs
pnpm res:test test/Integration_test.res.mjs
```

- [ ] **Step 5: Commit**

```bash
git add src/infrastructure/config/Config.res src/interfaces/cli/Cli.res test/Config_test.res test/Integration_test.res
git commit -m "feat: enforce fail-fast configuration validation"
```

---

## Task 7: Remove `Obj.magic` via Typed Bridges

**Files:**
- Modify: `src/domain/template/Frontmatter.res`, `src/infrastructure/rendering/Renderer.res`, `src/infrastructure/bindings/NodeJs.res`
- Test: `test/Frontmatter_test.res`, `test/Renderer_test.res`

- [ ] **Step 1: Add failing tests**

```rescript
let test_malformed_directive_never_throws = () => {
  // pass corrupt frontmatter -> Error, never exception
}
let test_render_returns_error_on_missing_required_var = () => {
  // pass incomplete context missing 'name' -> Error not throw
}
let test_render_handles_all_helper_types_safely = () => {
  // all h.* helpers callable without Obj.magic coercion
}
```

- [ ] **Step 2: Frontmatter — safe regex capture helper**

```rescript
// Replace Obj.magic on regex match array reads with typed extractor:
let extractCapture: (array<Js.String.t>, int) => option<string> = (arr, idx) => {
  if idx < 0 || idx >= Array.length(arr) {
    None
  } else {
    let s = arr[idx]
    Some(Obj.magic(s))  // Obj.magic here is unavoidable — Js.String.t → string
  }
}
```

- [ ] **Step 3: Renderer — typed EJS payload adapter**

```rescript
// Single binding-level unsafe cast, all Renderer logic uses typed bridge:
type ejsPayload = {
  name: string,
  Name: string,
  names: string,
  Names: string,
  cwd: string,
  actionfolder: string,
  attributes: dict<string>,
  h: {
    pascalCase: string => string,
    camelCase: string => string,
    kebabCase: string => string,
    snakeCase: string => string,
    upper: string => string,
    lower: string => string,
    trim: string => string,
    title: string => string,
  },
}

let toEjsPayload: renderContext => ejsPayload = ctx => {
  // build typed payload — no Obj.magic in business logic
}

let render: (template, renderContext) => result<string, string> = (tmpl, ctx) => {
  let payload = toEjsPayload(ctx)
  try {
    Ok(Bindings.Ejs.render(tmpl.body, payload->Obj.magic))
  } catch {
  | JsExn(obj) => Error(...)
  }
}
```

- [ ] **Step 4: NodeJs — typed process env access**

```rescript
module NodeProcess = {
  @module("node:process") external env: dict<string> = "env"
  // Remove Obj.magic at call sites; typed accessor above is sufficient
}
```

- [ ] **Step 5: Run tests**

```bash
pnpm res:test test/Frontmatter_test.res.mjs
pnpm res:test test/Renderer_test.res.mjs
```

- [ ] **Step 6: Commit**

```bash
git add src/domain/template/Frontmatter.res src/infrastructure/rendering/Renderer.res src/infrastructure/bindings/NodeJs.res test/Frontmatter_test.res test/Renderer_test.res
git commit -m "refactor: replace Obj.magic usage with typed bridges"
```

---

## Task 8: Structured Logging + Correlation (Run ID)

**Files:**
- Create: `src/infrastructure/observability/Logger.res`
- Modify: `src/interfaces/cli/Cli.res`, `src/application/engine/Engine.res`
- Test: `test/Integration_test.res`, `test/Engine_test.res`

- [ ] **Step 1: Add failing logging-shape tests**

```rescript
let test_log_line_is_valid_json = () => {
  // Logger.info(~event, ~message) -> stdout line parses as JSON
}
let test_log_contains_runid = () => {
  // assert parsed JSON has "runId" field matching process runId
}
let test_log_contains_timestamp = () => {
  // assert parsed JSON has "timestamp" ISO string
}
```

- [ ] **Step 2: Implement Logger.res**

```rescript
type logLevel = Info | Warn | Error

type logEntry = {
  timestamp: string,
  level: string,
  runId: string,
  event: string,
  message: string,
  meta?: dict<string>,
}

let runId: string = {
  // generate stable runId from timestamp + random suffix
  let ts = Js.Date.now() |> Int.toString
  let rand = Js.Math.random() |> Js.Math.floor |> Int.toString
  ts ++ "-" ++ rand
}

let log: (
  ~level: logLevel,
  ~event: string,
  ~message: string,
  ~meta: dict<string>=?,
  unit,
) => unit = (~level, ~event, ~message, ~meta=?) => {
  let entry: logEntry = {
    timestamp: Js.Date.now() |> Js.Date.toISOString,
    level: switch level {
    | Info => "INFO"
    | Warn => "WARN"
    | Error => "ERROR"
    },
    runId,
    event,
    message,
    meta: ?meta,
  }
  Console.log(Js.Json.stringify(Obj.magic(entry)))
}
```

- [ ] **Step 3: Replace high-value CLI/engine logs**

```rescript
// In Cli.res:
// - generation start
// - config load success/failure
// - command completion
// In Engine.res:
// - phase0/phase1/phase2 transitions
// - error with context
// - final summary (files created, injected, commands)
```

- [ ] **Step 4: Run tests**

```bash
pnpm res:test test/Engine_test.res.mjs
pnpm res:test test/Integration_test.res.mjs
```

- [ ] **Step 5: Commit**

```bash
git add src/infrastructure/observability/Logger.res src/interfaces/cli/Cli.res src/application/engine/Engine.res test/Engine_test.res test/Integration_test.res
git commit -m "feat: add structured logging with run correlation id"
```

---

## Task 9: Health/Readiness Commands for Operational Probes

**Files:**
- Modify: `src/interfaces/cli/Cli.res`, `src/infrastructure/config/Config.res`
- Test: `test/Integration_test.res`

- [ ] **Step 1: Add failing CLI probe tests**

```rescript
let test_healthz_exits_zero = () => {
  // assert run("blueprint healthz").exitCode == 0
}
let test_readyz_exits_zero_when_healthy = () => {
  // config valid + template paths exist + write access -> exit 0
}
let test_readyz_exits_nonzero_when_unhealthy = () => {
  // corrupt config -> exit 1
}
```

- [ ] **Step 2: Implement command routing**

```rescript
let main: unit => promise<unit> = async () => {
  let args = NodeJs.Process.argv
  switch args[2] {
  | Some("healthz") => {
      Console.log("OK")
      NodeJs.NodeProcess.exit(0)
    }
  | Some("readyz") => {
      let globalResult = await Config.loadGlobal()
      switch globalResult {
      | Error(_) => NodeJs.NodeProcess.exit(1)
      | Ok(_) => NodeJs.NodeProcess.exit(0)
      }
    }
  | _ => runCommand(args)
  }
}
```

- [ ] **Step 3: Implement readyz checks**

```rescript
let readyz: unit => promise<int> = async () => {
  // 1. Config parse check
  // 2. Template discovery check (~/.config/blueprint or cwd _templates)
  // 3. Write permission check (temp file in cwd)
  // All pass -> 0, any fail -> 1
}
```

- [ ] **Step 4: Run tests**

```bash
pnpm res:test test/Integration_test.res.mjs
```

- [ ] **Step 5: Commit**

```bash
git add src/interfaces/cli/Cli.res src/infrastructure/config/Config.res test/Integration_test.res
git commit -m "feat: add healthz and readyz cli probes"
```

---

## Task 10: Final Verification + Docs Sync

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Run full test suite**

```bash
pnpm res:test ./test/*.res.mjs
```

Expected: PASS (all tests green).

- [ ] **Step 2: Audit for remaining `Obj.magic`**

```bash
rg 'Obj\.magic' src/
```

Expected: only bindings-layer `Obj.magic` (unavoidable Node interop); zero in business logic call sites.

- [ ] **Step 3: Update docs**

```md
## Operational Behavior

### Health Probes

`blueprint healthz` — basic liveness probe (process is running)
`blueprint readyz` — readiness probe (config valid, templates accessible, write access OK)

### Structured Logging

All CLI output during generation is JSON Lines format:

```json
{"timestamp":"2026-05-19T10:30:00.000Z","level":"INFO","runId":"1747655400123-4821","event":"phase0/start","message":"Starting prompt resolution","meta":{}}
```

### Graceful Shutdown

Receiving SIGINT or SIGTERM triggers clean shutdown:
- Open readline interfaces are closed
- Staging directories are removed
- In-flight generation returns an error (no partial files left behind)

### Fail-Fast Configuration

The CLI validates configuration on startup and exits immediately with an error if:
- `timeout` is not a positive integer
- `shell.enabled: true` without a `tools` allowlist

### Conflict Detection

When a target file already exists, the CLI prompts for resolution strategy. Use `--force` to overwrite all without prompting.

### Fetch Directives

Fetched URLs are downloaded to temporary files that are cleaned up on success and on error.
```

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: document production hardening behavior and probes"
```

---

## Execution Order

1 → 10 exactly (TDD foundation before dependent work; low-risk integration last).

## Definition of Done

- All new/updated tests pass
- No `Obj.magic` remaining at business-logic call sites (only bindings layer)
- Conflict detection no longer stubbed
- Graceful shutdown + staging cleanup verified
- Health/readiness probes working
- Structured logging with runId active
- Fail-fast config validation enforced