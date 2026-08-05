# Plan 030: Generic pre-hook context bridge — feed `pre_generate` hook output to templates

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat dc6cefd..HEAD -- src/infrastructure/hooks/Hooks.res src/application/engine/EngineHooks.res src/application/engine/EngineOrchestrator.res src/application/engine/EngineContext.res src/domain/context/Context.res`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: feature / security
- **Planned at**: commit `dc6cefd`, 2026-08-05

## Why this matters

Blueprint's `pre_generate` hook runs a user script **before** templates are
rendered — the perfect moment to read `package.json`, create a folder, query
git, or fetch info the templates need. The hook's stdout is already captured
internally (`hookResult.output`), but `Hooks.run` throws it away and returns
`result<unit, string>`. Templates therefore cannot consume any data a pre-hook
produces.

This plan adds a **generic** bridge: a `pre_generate` hook may print a JSON
object on stdout; Blueprint parses it and merges those key/value pairs into the
EJS render context, so any template can use them as `<%=key%>`. It is **not** a
hardcoded "read package.json" feature — it is a reusable "run script, return
data" capability. Parsing untrusted hook stdout is new trust surface, so the
plan hardens it: size cap, string-only values, reserved-key protection, and
fail-closed on malformed output.

## Current state

### Data flow today (the gap)

```
EngineOrchestrator.run (src/application/engine/EngineOrchestrator.res)
  ├─ line 47:  EngineContext.buildInitialContext(...)        → Context.context
  ├─ line 55:  EngineHooks.runPreHook(...)                   → result<unit,string>   ← stdout DISCARDED
  ├─ line 97:  EngineContext.buildMergedContext(...)         → Context.context       ← no hook data
  └─ line 107: EnginePhases.runPhase1(... mergedContext ...) → renders templates     ← hook data absent
```

### Verbatim source of the boundaries you will change

**`src/infrastructure/hooks/Hooks.res`** — `hookResult` type and `run`:

```rescript
// lines 6-12
type hookType = PreGenerate | PostGenerate
type hookResult = {
  hookType: hookType,
  output: string,      // ← stdout IS captured here
  exitCode: int,
}

// lines 156-211 — run currently returns result<unit, string>
let run: (
  ~config: Config.config,
  ~projectRoot: string,
  ~hookType: hookType,
  ~shellConfig: option<Config.shellConfig>,
  ~shell: Ports.shell,
  ~process: Ports.process,
  ~path: Ports.path,
  ~fs: Ports.fileSystem,
) => promise<result<unit, string>> = async (...) => {
  // ...
  switch result {
  | Error(e) => Error(e)
  | Ok(r) =>
    if r.exitCode != 0 {
      Error("Hook exited with code " ++ Int.toString(r.exitCode))
    } else {
      Ok(r)            // ← line ~202: the hookResult exists but callers see result<unit,string>
    }
  }
}
```

Wait — note line 202 in the current code already returns `Ok(r)` inside
`executeHook`. The `run` wrapper is what collapses it: find the
`| Ok(_) => Ok()` line inside `run` (the function starting at line 156). That
`Ok(_)` discards the `hookResult` and returns unit. **That single pattern is
the entire gap.**

**`src/application/engine/EngineHooks.res`** — both return unit/generateResult:

```rescript
// runPreHook returns result<unit, string>
let runPreHook: (...) => promise<result<unit, string>> = async (...) => {
  switch config {
  | None => Ok()                              // ← no hookResult to return
  | Some(c) =>
    await Hooks.run(..., ~hookType=Hooks.PreGenerate, ...)   // ← discards hookResult
  }
}

// runPostHook returns result<generateResult, string>
let runPostHook: (...) => promise<result<generateResult, string>> = async (...) => {
  // ...
  let hookResult = await Hooks.run(..., ~hookType=Hooks.PostGenerate, ...)
  switch hookResult {
  | Error(e) => Error(e)
  | Ok() => Ok(result)                        // ← Ok() matches unit; will need Ok(_)
  }
}
```

**`src/application/engine/EngineOrchestrator.res:55-67`** — pre-hook call site:

```rescript
// Pre-hook
let preResult = switch await EngineHooks.runPreHook(
  ~config, ~projectRoot=context.cwd, ~shell, ~process=proc, ~path, ~fs,
) {
| Error(e) => io.close(); Error({Commit.message: e})
| Ok() => Ok(io)                              // ← Ok() matches unit; stdout gone
}
```

**`src/application/engine/EngineContext.res:18-37`** — merged context builder:

```rescript
let buildMergedContext: (
  ~initialContext: Context.context,
  ~name: string,
  ~cliAttributes: dict<Context.attrValue>,
  ~promptAnswers: dict<string>,
) => Context.context = (~initialContext, ~name, ~cliAttributes, ~promptAnswers) => {
  // wraps promptAnswers into Scalar, then:
  Context.build(~cwd=initialContext.cwd, ~actionfolder=initialContext.actionfolder,
    ~name, ~cliAttributes, ~promptAnswers=wrappedAnswers, ())
}
```

**`src/domain/context/Context.res`** — `build` and `mergeAttributes`:

```rescript
// lines 37-73 — mergeAttributes precedence TODAY:
let mergeAttributes = (~cliAttributes, ~promptAnswers, ~manifestDefaults, ~nameVariants) => {
  let merged = Dict.make()
  manifestDefaults->Dict.toArray->Array.forEach(...)        // 1. lowest
  Dict.set(merged, "name", Scalar(nameVariants.name))       // 2. name variants
  Dict.set(merged, "Name", ...)
  Dict.set(merged, "names", ...)
  Dict.set(merged, "Names", ...)
  promptAnswers->Dict.toArray->Array.forEach(...)           // 3. prompts
  cliAttributes->Dict.toArray->Array.forEach(...)           // 4. highest (CLI)
  merged
}

// lines 76-121 — build signature TODAY (no hook param):
let build = (~cwd, ~actionfolder, ~name, ~cliAttributes=?, ~promptAnswers=?, ~manifestDefaults=?, ()) => { ... }
```

**`src/infrastructure/rendering/Renderer.res:40-76`** — how attributes reach EJS:

```rescript
let data = Dict.make()
Dict.set(data, "name", ctx.name)                            // name variants first
Dict.set(data, "Name", ctx.pascalName)
Dict.set(data, "names", ctx.names)
Dict.set(data, "Names", ctx.pluralPascalName)
Dict.toArray(ctx.attributes)->Array.forEach(((k, v) => {    // attributes AFTER — CAN override name!
  Dict.set(data, k, v)
})
Dict.set(data, "h", FuncMap.makeHelpersDict()->Obj.magic)   // helpers last — safe from override
```

> **Security note embedded here**: because `Renderer.render` applies attributes
> AFTER the name variants, a hook key named `"name"` in attributes WOULD
> override `<%=name%>` in every template. Reserved-key protection in
> `mergeAttributes` is therefore **mandatory**, not optional.

### Security coverage that ALREADY exists (reuse, do not rebuild)

| Control | File | What it does | Applies to pre_generate? |
|---|---|---|---|
| Path containment | `src/infrastructure/path/PathSecurity.res` | Symlink-aware `isWithinTree`; denies `../evil.sh` and absolute paths outside cwd | YES — path-based hook commands (`./scripts/x.sh`) |
| Env whitelist | `src/infrastructure/env/EnvFilter.res` | Only `PATH`+`HOME`+explicit vars; blocks `&&;\|;\`;$();${;<>;\n` in values | YES — all hook exec |
| Timeout | `src/domain/exec/ExecPolicy.res:13` + `Hooks.res` | `defaultTimeout=30000ms`; configurable `hooks.timeout` | YES |
| Non-zero exit → abort | `Hooks.res:142-146` | Hook failure stops the pipeline | YES |

### What is NEW trust surface (this plan must harden)

Parsing hook stdout into the render context. The hook is user-authored code
that already runs with the user's own privileges, so stdout parsing is not a
privilege-escalation vector — but it IS a data-integrity surface:

1. **Reserved-key override** — a hook could emit `{"name":"x"}` and corrupt
   every template's name variants. → Guard reserved keys.
2. **Helper clobbering** — `{"h":...}` targets the EJS helper dict. → Guard.
   (Renderer re-sets `h` last, so defense-in-depth only.)
3. **Type confusion** — non-string JSON values. The render context is
   `dict<string>`. → Reject non-strings, hard error.
4. **Resource exhaustion** — a runaway hook prints megabytes. → Cap stdout
   size before parsing.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Build ReScript | `pnpm res:build` | exit 0, no errors |
| Run tests | `pnpm res:test` | all pass |
| Run one test file | `pnpm res:test -- test/Hooks_test.res.mjs` | that suite passes |
| Full build (rescript + bundle) | `pnpm build` | exit 0 |

> Tests compile to `.res.mjs` then run via `retest ./test/*.res.mjs`. After
> editing a `.res` file you MUST run `pnpm res:build` before `pnpm res:test`
> picks up the change. Pattern: `pnpm res:build && pnpm res:test`.

## Scope

**In scope** (the only files you should modify):
- `src/infrastructure/hooks/Hooks.res` — `run` return type
- `src/application/engine/EngineHooks.res` — `runPreHook` return type; `runPostHook` pattern adapt
- `src/application/engine/EngineOrchestrator.res` — parse stdout, thread into context
- `src/application/engine/EngineContext.res` — `buildMergedContext` param
- `src/domain/context/Context.res` — `build` + `mergeAttributes` param + reserved-key guard
- `test/Hooks_test.res` — adapt `Ok()` → `Ok(_)` patterns
- `test/Context_test.res` — new hook-attribute tests
- `test/EngineOrchestrator_test.res` (if it exists) or equivalent integration test — hook→context propagation

**Out of scope** (do NOT touch):
- `src/infrastructure/rendering/Renderer.res` — no change needed; attributes already flow to EJS.
- `src/infrastructure/path/PathSecurity.res`, `src/infrastructure/env/EnvFilter.res`, `src/domain/exec/ExecPolicy.res` — reused as-is.
- The `post_generate` hook — its stdout stays discarded; only `pre_generate` feeds context.
- Any `.blueprint.yaml` schema change — the hook config format is unchanged; only its stdout gains meaning.
- The `create-res-project` generator itself — that is a separate consumer plan (031).

## The JSON contract (hook ↔ template protocol)

A `pre_generate` hook MAY print a JSON object on **stdout**. Contract:

| Stdout content | Behavior |
|---|---|
| Empty or whitespace-only | No-op — no attributes merged (backward compatible) |
| Valid JSON object, all string values | Merged into render context |
| Valid JSON, any non-string value (number/array/object/bool/null) | **Hard error** — generation aborts before any file is written |
| Not valid JSON | **Hard error** — generation aborts before any file is written |
| Object containing a reserved key | **Hard error** — reserved keys are `name`, `Name`, `names`, `Names`, `h` |
| stdout exceeds 64 KiB | **Hard error** — reject before parsing |

**Diagnostics go to stderr, not stdout.** Only data goes to stdout. Document
this in the hook's script (the executor writing plan 031 must follow it).

Precedence (lowest → highest, explicit user input always wins):

```
manifestDefaults  <  nameVariants  <  hookAttributes  <  promptAnswers  <  cliAttributes
```

## Git workflow

- Branch: `plan/030-pre-hook-context-bridge`
- Commit per step; conventional commits. Example from this repo's history:
  `feat(hooks): propagate pre_generate hook stdout into render context`
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Change `Hooks.run` to return `result<hookResult, string>`

File: `src/infrastructure/hooks/Hooks.res`, the `run` function (starts ~line 156).

Change the return type from `promise<result<unit, string>>` to
`promise<result<hookResult, string>>`. In the body, find the success branch
that currently collapses to `Ok()` and return the `hookResult` instead:

```rescript
// BEFORE (inside run):
switch result {
| Ok(_) => Ok()        // ← discards hookResult
| Error(e) => ...
}

// AFTER:
switch result {
| Ok(r) => Ok(r)       // ← preserve hookResult (r already validated exitCode==0 by executeHook)
| Error(e) => ...
}
```

`executeHook` already returns `Ok(hookResult)` only when `exitCode == 0`
(lines 142-146), so `run` just forwards it. No exit-code re-check needed.

**Verify**: `pnpm res:build` → exit 0. (Callers will break — fixed in steps 2-3.)

### Step 2: Adapt `EngineHooks.runPreHook` to return `result<hookResult, string>`

File: `src/application/engine/EngineHooks.res`.

```rescript
// BEFORE:
let runPreHook: (...) => promise<result<unit, string>> = async (...) => {
  switch config {
  | None => Ok()
  | Some(c) => await Hooks.run(..., ~hookType=Hooks.PreGenerate, ...)
  }
}

// AFTER:
let runPreHook: (...) => promise<result<hookResult, string>> = async (...) => {
  switch config {
  | None => Ok({hookType: PreGenerate, output: "", exitCode: 0})  // synthetic empty result
  | Some(c) => await Hooks.run(..., ~hookType=Hooks.PreGenerate, ...)
  }
}
```

The `None` branch returns a synthetic empty `hookResult` so downstream parsing
sees empty stdout (no-op). Import `hookResult` type if not already in scope
(it is defined in `Hooks.res`; you may need `Hooks.hookResult`).

### Step 3: Adapt `EngineHooks.runPostHook` (ignore output, keep behavior)

Same file. `runPostHook` calls `Hooks.run` for `PostGenerate`. Update the
pattern from `Ok()` to `Ok(_)` since the inner type is now `hookResult`:

```rescript
// BEFORE:
switch hookResult {
| Error(e) => Error(e)
| Ok() => Ok(result)
}

// AFTER:
switch hookResult {
| Error(e) => Error(e)
| Ok(_) => Ok(result)   // post-hook stdout stays discarded by design
}
```

**Verify**: `pnpm res:build` → exit 0. (Orchestrator still breaks — fixed step 4.)

### Step 4: Parse pre-hook stdout and thread into the orchestrator

File: `src/application/engine/EngineOrchestrator.res`, lines 54-67.

Replace the pre-hook block so it captures the `hookResult`, parses stdout, and
stores the parsed attributes for `buildMergedContext`:

```rescript
// Pre-hook — capture stdout for context injection
let preHookResult = switch await EngineHooks.runPreHook(
  ~config, ~projectRoot=context.cwd, ~shell, ~process=proc, ~path, ~fs,
) {
| Error(e) => io.close(); Error({Commit.message: e})
| Ok(hookRes) => Ok(hookRes)
}

// Parse hook stdout into attributes (fail-closed on malformed output)
let hookAttributes = switch preHookResult {
| Error(_) => None
| Ok(hookRes) =>
  switch HookContext.parse(~stdout=hookRes.output) {
  | Ok(attrs) => Some(attrs)
  | Error(e) => io.close(); Error({Commit.message: e})   // aborts before any file written
  }
}
```

> The `preResult`/`bindPhase` wiring below must still carry `io`. Restructure
> minimally: thread `hookAttributes` (a `result<option<dict<attrValue>>, phase2Error>`)
> into the phase-0 `bindPhase` closure so it reaches `buildMergedContext` in
> the phase-1 closure (line 97). The cleanest shape: bind `hookAttributes`
> alongside `preResult` and pass `~hookAttributes` into `buildMergedContext`.

Create a new pure module `src/application/engine/HookContext.res` for the
parsing logic (keeps it unit-testable and isolated from IO):

```rescript
// HookContext.res — pure stdout→attributes parser (no IO, no side effects)
open Context

let maxStdoutBytes = 65536   // 64 KiB cap

let reservedKeys = ["name", "Name", "names", "Names", "h"]

let parse: (~stdout: string) => result<dict<attrValue>, string> = (~stdout) => {
  let trimmed = Js.String.trim(stdout)
  if trimmed == "" {
    Ok(Dict.make())                                    // empty = no-op
  } else if String.length(trimmed) > maxStdoutBytes {
    Error("pre_generate hook stdout exceeds " ++ Int.toString(maxStdoutBytes) ++ " bytes")
  } else {
    switch Js.Json.parseExn(trimmed) {
    | _ => Error("pre_generate hook stdout is not valid JSON")
    | json =>
      switch Js.Json.decodeObject(json) {
      | None => Error("pre_generate hook stdout must be a JSON object")
      | Some(entries) =>
        let result = Dict.make()
        let acc = ref(Ok(()))
        entries->Belt.Array.forEach(((k, v)) => {
          switch acc.contents {
          | Error(_) => ()                             // short-circuit on first error
          | Ok(_) =>
            if reservedKeys->Array.some(r => r == k) {
              acc := Error("pre_generate hook output uses reserved key: " ++ k)
            } else {
              switch Js.Json.decodeString(v) {
              | None => acc := Error("pre_generate hook value for '" ++ k ++ "' must be a string")
              | Some(s) => Dict.set(result, k, Scalar(s))
              }
            }
          }
        })
        switch acc.contents {
        | Error(e) => Error(e)
        | Ok(_) => Ok(result)
        }
      }
    }
  }
}
```

> ReScript `Js.Json.parseExn` throws on bad JSON, so the `_ =>` catch arm
> comes FIRST in the switch (ReScript evaluates variant arms in order; the
> throw is caught). Confirm against the live compiler behavior in step 1 of
> testing — if `parseExn` returns `JS.Exn` variant instead, adapt.

**Verify**: `pnpm res:build` → exit 0.

### Step 5: Add `~hookAttributes` to `EngineContext.buildMergedContext`

File: `src/application/engine/EngineContext.res`.

```rescript
// BEFORE:
let buildMergedContext = (~initialContext, ~name, ~cliAttributes, ~promptAnswers) => { ... }

// AFTER:
let buildMergedContext = (
  ~initialContext,
  ~name,
  ~cliAttributes,
  ~promptAnswers,
  ~hookAttributes: dict<Context.attrValue>=?,
) => Context.build(
  ~cwd=initialContext.cwd,
  ~actionfolder=initialContext.actionfolder,
  ~name, ~cliAttributes, ~promptAnswers=wrappedAnswers,
  ~hookAttributes=?,   // forwarded
  (),
)
```

Update the call site in `EngineOrchestrator.res:97` to pass
`~hookAttributes=?` from the parsed result of step 4.

**Verify**: `pnpm res:build` → exit 0.

### Step 6: Add `~hookAttributes` to `Context.build` + `mergeAttributes` with reserved-key guard

File: `src/domain/context/Context.res`.

Extend `build` signature with `~hookAttributes: dict<attrValue>=?` and forward
to `mergeAttributes`. In `mergeAttributes`, insert hook attributes between
nameVariants and promptAnswers, AND re-assert reserved keys (defense-in-depth,
since `HookContext.parse` already rejects them):

```rescript
let mergeAttributes = (
  ~cliAttributes, ~promptAnswers, ~manifestDefaults, ~nameVariants,
  ~hookAttributes: dict<attrValue>=?,
) => {
  let merged = Dict.make()
  manifestDefaults->Dict.toArray->Array.forEach(...)
  Dict.set(merged, "name", Scalar(nameVariants.name))
  Dict.set(merged, "Name", ...)
  Dict.set(merged, "names", ...)
  Dict.set(merged, "Names", ...)
  // hook attributes — skip reserved keys as a second line of defense
  switch hookAttributes { | Some(h) => h->Dict.toArray->Array.forEach(((k, v)) => {
      if !reservedKeys->Array.some(r => r == k) { Dict.set(merged, k, v) }
    }) | None => () }
  promptAnswers->Dict.toArray->Array.forEach(...)
  cliAttributes->Dict.toArray->Array.forEach(...)
  merged
}
```

Define `reservedKeys` at module top (same list as `HookContext.res`: `name`,
`Name`, `names`, `Names`, `h`).

**Verify**: `pnpm res:build && pnpm res:test` → existing tests pass (new param is optional, no caller forced yet except orchestrator).

### Step 7: Fix `Hooks_test.res` patterns

File: `test/Hooks_test.res`. The `run` tests (lines 45-102) pattern-match
`Ok()` against `result<unit,string>`. Since `run` now returns
`result<hookResult,string>`, change those to `Ok(_)`:

```rescript
// BEFORE (lines 56, 66, 93):
| Ok() => ...
// AFTER:
| Ok(_) => ...
```

Add one new test asserting `run` now returns the hookResult with output:

```rescript
testAsync("run: returns hookResult with stdout for pre_generate", resolve => {
  let cfg: Config.config = { hooks: { preGenerate: {command: "echo {\"k\":\"v\"}"}, timeout: 5 } }
  Hooks.run(~config=cfg, ~projectRoot=".", ~hookType=Hooks.PreGenerate, ~shellConfig=None,
    ~shell=shellAdapter, ~process=processAdapter, ~path=pathAdapter, ~fs=fsAdapter)
  ->Promise.then(r => {
    switch r {
    | Ok(hookResult) =>
      assert_eq(hookResult.hookType, Hooks.PreGenerate)
      assert_true(String.includes(hookResult.output, "k"))   // stdout survived
    | Error(_) => assert_false(true)
    }
    resolve(); Promise.resolve()
  })->ignore
})
```

**Verify**: `pnpm res:build && pnpm res:test -- test/Hooks_test.res.mjs` → all pass.

## Test plan

New tests to write:

**`test/HookContext_test.res`** (new file) — pure parser, the security core:
- empty stdout → `Ok(emptyDict)`
- valid JSON `{"a":"1","b":"2"}` → `Ok` with both scalars
- non-object JSON (`"x"`, `[1]`, `5`) → `Error("must be a JSON object")`
- non-string value `{"a":1}` → `Error("must be a string")`
- reserved key `{"name":"x"}` → `Error("reserved key")`
- reserved key `{"h":"x"}` → `Error("reserved key")`
- invalid JSON `{bad` → `Error("not valid JSON")`
- oversized stdout (>64KiB) → `Error("exceeds ... bytes")`

**`test/Context_test.res`** — precedence and guard:
- `build` with `~hookAttributes={"packageName":"x"}` → `toRenderContext().attributes` contains `packageName=x`
- hook key `name` is dropped even if it slips through → name variants unchanged
- prompt answer overrides hook attribute with same key
- CLI attribute overrides hook attribute with same key

**`test/Hooks_test.res`** — adapt patterns + one new (step 7).

**Integration** — if `test/EngineOrchestrator_test.res` or a phase test exists,
add: a generator whose `.blueprint.yaml` defines `pre_generate: "echo {\"pkgName\":\"demo\"}"`
and a template `<%=pkgName%>` renders to `demo`. If no such integration harness
exists, note it as a follow-up rather than inventing one.

Model the pure-parser tests after `test/Context_test.res` style (suite + sync
asserts). Model the hook test after the existing `testAsync` pattern in
`Hooks_test.res`.

**Verification**: `pnpm res:build && pnpm res:test` → all pass, including the
new files.

## Done criteria

ALL must hold:

- [ ] `pnpm res:build` exits 0
- [ ] `pnpm res:test` exits 0; new tests in `HookContext_test.res` and `Context_test.res` pass
- [ ] A `pre_generate` hook printing `{"x":"y"}` makes `<%=x%>` render as `y` in a template
- [ ] A `pre_generate` hook printing invalid JSON aborts generation with a clear error BEFORE any file is written (no staging dir left behind)
- [ ] A hook output key `name` does NOT override the name variants in rendered output
- [ ] `grep -rn "Ok()" test/Hooks_test.res` against `Hooks.run` returns no unit-match results (all adapted to `Ok(_)`)
- [ ] No files outside the in-scope list are modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report (do not improvise) if:

- The code at `Hooks.res` `run`, `EngineHooks.res`, `EngineOrchestrator.res:55-67`, `Context.res mergeAttributes`, or `EngineContext.res buildMergedContext` does not match the excerpts above (codebase has drifted).
- `Js.Json.parseExn` in this ReScript version does not behave as assumed (it may return a `JSONError` variant or use ` Belt.Result` instead of throwing) — confirm the actual API and adapt `HookContext.parse` before continuing.
- Adapting the `bindPhase` threading in `EngineOrchestrator.res` to carry `hookAttributes` alongside `io` requires restructuring more than the pre-hook + phase-0 + phase-1 closures shown (report the actual control flow).
- `hookResult` type is not exported from `Hooks.res` (needs a `.resi` change you weren't expecting).
- A step's verification fails twice after a reasonable fix attempt.

## Maintenance notes

- **Future hooks wanting arbitrary (non-string) data**: today the render context is `dict<string>`. If a future hook needs to emit arrays/objects, extend `Context.attrValue` (`Values` exists for comma-joined) rather than weakening the string-only contract — measure the template-side impact first.
- **Reviewers**: scrutinize (1) the reserved-key list staying in sync between `HookContext.res` and `Context.res`, (2) the 64 KiB cap not being silently bypassed, (3) that `post_generate` stdout remains discarded (only `pre_generate` feeds context — by design, since post runs after commit and cannot affect rendering).
- **Follow-up plan 031**: the `create-res-project` generator will consume this capability — its `pre_generate` script reads `package.json` and prints `{"packageName":"<name>"}` on stdout (logs to stderr). That plan depends on this one landing first.
