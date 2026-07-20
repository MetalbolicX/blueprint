# Plan 018: Surface real render and injection errors in TemplateRenderer

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 64a81fa..HEAD -- src/application/pipeline/TemplateRenderer.res test/TemplateRenderer_test.res`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: MED
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `64a81fa`, 2026-07-20

## Why this matters

Two catch-all blocks in TemplateRenderer silently swallow real errors. The `resolveTargetPath` catch-all (`| _ => None`) turns an EJS syntax error in a `to:` path into a misleading "No 'to' directive found" message — the user has no idea their template expression is broken. The `applyInjection` catch-all (`| _ => {fileExists := false; ""}`) treats EACCES, ENOSPC, and EIO as "file doesn't exist", so injection operations report "Target file not found" when the real problem is a permission error or disk full. These are the two most common failure modes for template rendering, and both produce confusing diagnostic messages.

## Current state

- `src/application/pipeline/TemplateRenderer.res` — owns target-path resolution, injection, body loading, and the end-to-end render pipeline:
  ```rescript
  // TemplateRenderer.res:42-47 — resolveTargetPath catch-all swallows EJS errors
  try {
    let rendered = Bindings.Ejs.render(path, data)
    Some(rendered)
  } catch {
  | _ => None
  }
  ```
  When `Bindings.Ejs.render` throws (e.g. `undefined_var` in the path expression), the catch-all returns `None`. Downstream at line 191:
  ```rescript
  // TemplateRenderer.res:190-191
  switch targetPathOpt {
  | None => Error("No 'to' directive found in template: " ++ template.sourcePath)
  ```
  The user sees "No 'to' directive found" when the real problem is a broken EJS expression.

  ```rescript
  // TemplateRenderer.res:90-96 — applyInjection catch-all treats ALL errors as "file missing"
  let fileExists = ref(true)
  let existingContent = try {
    await fs.readFile(finalTargetPath, ~options={encoding: "utf8"})
  } catch {
  | _ =>
    fileExists := false
    ""
  }
  ```
  When `readFile` throws EACCES or ENOSPC, `fileExists` is set to `false`. Downstream at lines 100-102:
  ```rescript
  // TemplateRenderer.res:100-102
  if !fileExists.contents {
    switch directive {
    | Inject(_) | Before(_) | After(_) | AtLine(_) | SkipIf(_) =>
      Error("Target file not found: " ++ finalTargetPath)
  ```
  The user sees "Target file not found" when the real problem is a permission error.

  ```rescript
  // TemplateRenderer.res:146-153 — loadTemplateBodyFromDirective catch (OUT OF SCOPE)
  try {
    let externalBody = await fs.readFile(resolvedPath, ~options={encoding: "utf8"})
    Ok({...template, body: externalBody})
  } catch {
  | JsExn(obj) =>
    let msg = switch JsExn.message(obj) {
    | Some(m) => m
    | None => "Read failed"
    }
    Error("Failed to read 'from' template " ++ resolvedPath ++ ": " ++ msg)
  }
  ```
  This third catch site at line 146 **already captures JsExn messages properly** — it matches on `JsExn(obj)` and extracts the message. This is out of scope because it does NOT have the swallowing problem.

- Repo conventions: Conventional commits, PascalCase modules, snake_case values. Error handling uses `result` types. JsExn message extraction pattern: `switch JsExn.message(obj) { | Some(m) => m | None => "fallback" }`.

- Existing test files in `test/` — no `TemplateRenderer_test.res` exists. Tests for rendering live in `test/Phase1_test.res` (which tests `resolveTargetPath` via `Phase1.resolveTargetPath`). There is also `test/Template_test.res` and `test/TemplateIntegration_test.res`.

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Build     | `pnpm build`             | exit 0              |
| Tests     | `pnpm res:test`          | all pass            |

## Scope

**In scope** (the only files you should modify):
- `src/application/pipeline/TemplateRenderer.res` — fix the two catch-all blocks (resolveTargetPath and applyInjection)
- `test/TemplateRenderer_test.res` (create) — new test file covering error propagation

**Out of scope**:
- `src/application/pipeline/TemplateRenderer.res:146-153` — the `loadTemplateBodyFromDirective` catch already extracts JsExn messages correctly
- `test/Phase1_test.res` — existing tests; do not modify
- Any changes to `Bindings.Ejs`, `Injection`, or `Renderer` modules

## Git workflow

- Branch: `advisor/018-surface-render-injection-errors`
- Commit per step or per logical unit; message style: conventional commits, e.g. `fix(renderer): propagate EJS errors from resolveTargetPath`
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Fix resolveTargetPath to propagate EJS errors

In `src/application/pipeline/TemplateRenderer.res`, change `resolveTargetPath` to return `result<string, string>` instead of `option<string>`. Replace the catch-all:

```rescript
// TemplateRenderer.res:42-47 — BEFORE:
try {
  let rendered = Bindings.Ejs.render(path, data)
  Some(rendered)
} catch {
| _ => None
}

// AFTER:
try {
  let rendered = Bindings.Ejs.render(path, data)
  Ok(rendered)
} catch {
| JsExn(obj) =>
  let msg = switch JsExn.message(obj) {
  | Some(m) => m
  | None => "EJS render error"
  }
  Error(msg)
| _ => Error("EJS render error in 'to' path")
}
```

Update the function signature from `option<string>` to `result<string, string>`:
```rescript
// TemplateRenderer.res:12 — BEFORE:
let resolveTargetPath: (Template.directive, Context.context) => option<string> = (

// AFTER:
let resolveTargetPath: (Template.directive, Context.context) => result<string, string> = (
```

Update the `_ => None` case for non-To directives to return `Error`:
```rescript
// TemplateRenderer.res:49 — BEFORE:
| _ => None

// AFTER:
| _ => Error("No 'to' directive")
```

**Verify**: `pnpm build` → exit 0 (this will temporarily break the caller at `render`; fix in Step 2)

### Step 2: Update render() to handle the new result type from resolveTargetPath

In `src/application/pipeline/TemplateRenderer.res`, update the caller of `resolveTargetPath` (around lines 180-191):

```rescript
// BEFORE:
let targetPathOpt =
  template.directives
  ->Array.find(d => {
    switch d {
    | To(_) => true
    | _ => false
    }
  })
  ->Option.flatMap(d => resolveTargetPath(d, context))

switch targetPathOpt {
| None => Error("No 'to' directive found in template: " ++ template.sourcePath)
| Some(targetPath) => {

// AFTER:
let targetPathResult =
  template.directives
  ->Array.find(d => {
    switch d {
    | To(_) => true
    | _ => false
    }
  })
  ->Option.map(d => resolveTargetPath(d, context))

switch targetPathResult {
| None => Error("No 'to' directive found in template: " ++ template.sourcePath)
| Some(Error(e)) => Error("Failed to render 'to' path in template " ++ template.sourcePath ++ ": " ++ e)
| Some(Ok(targetPath)) => {
```

**Verify**: `pnpm build` → exit 0

### Step 3: Fix applyInjection to distinguish ENOENT from other filesystem errors

In `src/application/pipeline/TemplateRenderer.res`, change the `applyInjection` catch block (lines 90-96) to distinguish ENOENT from other errors:

```rescript
// TemplateRenderer.res:90-96 — BEFORE:
let fileExists = ref(true)
let existingContent = try {
  await fs.readFile(finalTargetPath, ~options={encoding: "utf8"})
} catch {
| _ =>
  fileExists := false
  ""
}

// AFTER:
let fileReadResult = try {
  Ok(await fs.readFile(finalTargetPath, ~options={encoding: "utf8"}))
} catch {
| JsExn(obj) =>
  let msg = switch JsExn.message(obj) {
  | Some(m) => m
  | None => "unknown error"
  }
  // Check if this is ENOENT (file not found) vs other errors (EACCES, ENOSPC, etc.)
  let code = switch Obj.magic(obj)["code"] {
  | Some(c) => c
  | None => ""
  }
  if code == "ENOENT" {
    Error("ENOENT")
  } else {
    Error("Read failed for " ++ finalTargetPath ++ ": " ++ msg)
  }
| _ => Error("Read failed for " ++ finalTargetPath)
}

let fileExists = ref(true)
let existingContent = switch fileReadResult {
| Ok(content) => content
| Error("ENOENT") =>
  fileExists := false
  ""
| Error(msg) =>
  // Non-ENOENT error — propagate as a real error, don't pretend file is missing
  failwith(msg)
}
```

Note: The `failwith` at the end is a deliberate choice — it throws the error upward so the caller sees the real message. An alternative is to thread `result` through, but that would change the function signature significantly. The `failwith` approach is simpler and matches the existing pattern where the outer `applyInjection` function already returns `result<string, string>`. However, if you prefer not to use `failwith`, you can wrap the entire function body in a try/catch that catches the failwith and returns `Error(msg)`.

A cleaner alternative: wrap the readFile + injection logic in an inner function that returns `result<string, string>` and return early on error:

```rescript
let existingContentResult = try {
  Ok(await fs.readFile(finalTargetPath, ~options={encoding: "utf8"}))
} catch {
| JsExn(obj) =>
  let msg = switch JsExn.message(obj) {
  | Some(m) => m
  | None => "unknown error"
  }
  let code = switch Obj.magic(obj)["code"] {
  | Some(c) => c
  | None => ""
  }
  if code == "ENOENT" {
    Error("ENOENT")
  } else {
    Error("Read failed for " ++ finalTargetPath ++ ": " ++ msg)
  }
| _ => Error("Read failed for " ++ finalTargetPath)
}

switch existingContentResult {
| Error("ENOENT") =>
  fileExists := false
  // fall through to existing "file not found" logic
| Error(msg) => return Error(msg)  // or: return early with the real error
| Ok(content) =>
  fileExists := true
  // use content as existingContent
}
```

Since ReScript doesn't have early return, the cleanest approach is to restructure as:

```rescript
let readResult = try {
  Ok(await fs.readFile(finalTargetPath, ~options={encoding: "utf8"}))
} catch {
| JsExn(obj) =>
  let msg = switch JsExn.message(obj) {
  | Some(m) => m
  | None => "unknown error"
  }
  let code = switch Obj.magic(obj)["code"] {
  | Some(c) => c
  | None => ""
  }
  if code == "ENOENT" {
    Error("ENOENT")
  } else {
    Error("Read failed for " ++ finalTargetPath ++ ": " ++ msg)
  }
| _ => Error("Read failed for " ++ finalTargetPath)
}

switch readResult {
| Error("ENOENT") =>
  // File truly doesn't exist
  if !fileExists.contents { /* already false */ } else { fileExists := false }
  // Continue with existing "file not found" logic
  switch directive {
  | Inject(_) | Before(_) | After(_) | AtLine(_) | SkipIf(_) =>
    Error("Target file not found: " ++ finalTargetPath)
  | _ => Ok("") // prepend/append can work with empty content
  }
| Error(msg) =>
  // Real filesystem error — propagate
  Error(msg)
| Ok(existingContent) =>
  fileExists := true
  // Apply injection (existing logic from line 107 onward)
  switch Injection.apply(
    ~existingContent,
    ~renderedContent=renderedBody,
    ~directive,
    ~allDirectives=template.directives,
  ) {
  | Error(e) => Error("Injection failed for " ++ finalTargetPath ++ ": " ++ e)
  | Ok({content, applied: _}) => Ok(content)
  }
}
```

This restructuring eliminates the mutable `fileExists` ref and the mutable `existingContent` by using the `readResult` pattern match directly. It's cleaner and more idiomatic ReScript.

**Verify**: `pnpm build` → exit 0

### Step 4: Create TemplateRenderer_test.res

Create `test/TemplateRenderer_test.res` with tests covering:

1. EJS error in `to:` path surfaces the variable error (not "No 'to' directive found")
2. EACCES-class read error surfaces as read failure (not "Target file not found")

Model after `test/Phase1_test.res` (lines 1-50 for the test structure with `open TestHelpers`, `suite`, `test`, `assert_eq`, `assert_true`).

```rescript
// TemplateRenderer_test — unit tests for TemplateRenderer error propagation

open TestHelpers

// Mock filesystem that throws EACCES on readFile
let makeFsWithReadError = (~errorCode: string = "EACCES", ~errorMsg: string = "EACCES: permission denied"): Ports.fileSystem => {
  let base = NodeJsFileSystem.make()
  {
    ...base,
    readFile: (_path, ~options as _=?) => {
      let err = JsExn.make(errorMsg)
      // Set the code property on the error object
      Obj.magic(err)["code"] = Some(errorCode)
      Promise.reject(err)
    },
    fileExists: _ => Promise.resolve(true),
  }
}

suite("TemplateRenderer.resolveTargetPath — error propagation", () => {
  test("EJS syntax error in to: path surfaces the error message", () => {
    let ctx = Context.build(
      ~cwd="/workspace",
      ~actionfolder="/workspace/_templates",
      ~name="Hello",
      (),
    )
    // This template expression references an undefined variable
    let result = TemplateRenderer.resolveTargetPath(Template.To("src/<%= undefined_var %>.tsx"), ctx)
    switch result {
    | Error(msg) =>
      // Should NOT say "No 'to' directive found" — should mention the EJS error
      assert_true(String.includes(msg, "undefined_var") || String.includes(msg, "EJS") || String.includes(msg, "render"))
    | Ok(_) => assert_false(true) // should error
    }
  })

  test("valid to: path resolves successfully", () => {
    let ctx = Context.build(
      ~cwd="/workspace",
      ~actionfolder="/workspace/_templates",
      ~name="Hello",
      (),
    )
    let result = TemplateRenderer.resolveTargetPath(Template.To("src/<%= Name %>.tsx"), ctx)
    switch result {
    | Ok(path) => assert_eq(path, "src/Hello.tsx")
    | Error(_) => assert_false(true) // should not error
    }
  })
})

suite("TemplateRenderer.applyInjection — error propagation", () => {
  testAsync("EACCES read error surfaces as read failure, not 'Target file not found'", resolve => {
    let fs = makeFsWithReadError(~errorCode="EACCES", ~errorMsg="EACCES: permission denied")
    let template: Template.template = {
      sourcePath: "/src/test.ejs.t",
      body: "injected content",
      directives: [Inject({position: Before, marker: "// inject"})],
    }
    TemplateRenderer.applyInjection(
      ~renderedBody="new content",
      ~template,
      ~finalTargetPath="/protected/file.ts",
      ~fs,
    )->Promise.then(result => {
      switch result {
      | Error(msg) =>
        // Should mention "Read failed" or "permission", NOT "Target file not found"
        assert_true(String.includes(msg, "Read failed") || String.includes(msg, "EACCES") || String.includes(msg, "permission"))
        assert_false(String.includes(msg, "Target file not found"))
      | Ok(_) => assert_false(true) // should error on EACCES
      }
      resolve()
      Promise.resolve()
    })->ignore
  })
})
```

**Verify**: `pnpm res:test -- TemplateRenderer` → all tests pass (the EJS error test may need adjustment based on how Bindings.Ejs.render formats its error — run it first, observe the actual message, then adjust the assertion).

### Step 5: Run full test suite

**Verify**: `pnpm res:test` → all tests pass (no regressions)

## Test plan

- New test file: `test/TemplateRenderer_test.res` with 3 tests:
  - EJS error in `to:` path surfaces the variable name (not "No 'to' directive found")
  - Valid `to:` path resolves successfully (happy path regression)
  - EACCES read error surfaces as read failure (not "Target file not found")
- Model after `test/Phase1_test.res` (same test structure: `open TestHelpers`, `suite`, `test`, `testAsync`)
- Verification: `pnpm res:test` → all pass, including 3 new tests

## Done criteria

- [ ] `pnpm build` exits 0
- [ ] `pnpm res:test` exits 0; 3 new tests exist and pass in `test/TemplateRenderer_test.res`
- [ ] `grep -rn "| _ => None" src/application/pipeline/TemplateRenderer.res` returns no matches in the resolveTargetPath catch
- [ ] `grep -rn '| _ =>' src/application/pipeline/TemplateRenderer.res` — the two catch-alls at lines ~46 and ~93 are gone (replaced with structured JsExn matching)
- [ ] No files outside the in-scope list are modified (`git status`)

## STOP conditions

- The code at `TemplateRenderer.res:42-47` or `:90-96` doesn't match the described catch-all patterns
- `Bindings.Ejs.render` throws a non-JsExn exception type (the fix assumes JsExn)
- `Obj.magic(obj)["code"]` doesn't work for checking ENOENT on the JsExn error object in this ReScript/Node environment
- The EJS error test in Step 4 can't be reliably asserted (EJS error message format is unstable) — in that case, downgrade to asserting the error does NOT contain "No 'to' directive found"
- `pnpm build` fails after Step 1 and the fix isn't obvious after one attempt

## Maintenance notes

- The `Obj.magic(obj)["code"]` pattern for checking Node.js error codes is a known ReScript/JS interop idiom. If a safer helper exists in the codebase (check `src/infrastructure/bindings/`), prefer that instead.
- The `loadTemplateBodyFromDirective` catch at line 146 already handles errors correctly — do not touch it.
- Future work: if TemplateRenderer gains more error paths, consider a `templateError` variant type instead of plain `string` errors.
