# Plan 026: Extract buildFrontmatter and promptForDirectives from runAddFile

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 64a81fa..HEAD -- src/interfaces/cli/CommandsGenerator.res test/CommandsGenerator_test.res`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P3
- **Effort**: M
- **Risk**: LOW
- **Depends on**: plans/021-dedupe-template-predicate-and-getoptstring.md, plans/022-consolidate-prompt-type-parsing.md
- **Category**: tech-debt
- **Planned at**: commit `64a81fa`, 2026-07-20

## Why this matters

`runAddFile` in CommandsGenerator.res is ~167 lines mixing three distinct responsibilities: (1) interactive directive prompting (~12 sequential `io.ask` calls), (2) frontmatter assembly (~15 conditional `Js.Array.push` calls), and (3) file writing. This makes the frontmatter logic untestable without mocking the entire interactive IO stack. Extracting `buildFrontmatter` as a pure function and `promptForDirectives` as an interactive helper makes each piece independently testable. The `runAddFile` function becomes a thin orchestrator that calls these two helpers and writes the result.

**NOTE**: Local `Js.Array.push` accumulation in `buildFrontmatter` is acceptable in this codebase — the goal is extraction for testability, NOT immutability dogma. Do not prescribe a purity refactor.

Plans 021 and 022 must be applied first because they touch CommandsGenerator.res (removing `isTemplateFile` and `parsePromptTypeFromInput`). Applying this plan after them avoids line-number drift.

## Current state

**File**: `src/interfaces/cli/CommandsGenerator.res`

`runAddFile` (lines 267–434) — the function to decompose:

**Part 1: Directive prompting** (lines 287–373) — sequential interactive prompts:
```rescript
let directiveSelection =
  await deps.interactiveIO.ask(
    "Additional directives (comma-separated; e.g. inject,after,before,atLine,skipIf,prepend,append,eofLast,force,unlessExists,tool,fetch,script): ",
  )
let selected = parseDirectiveSelection(directiveSelection)
// ...
let fromValue =
  if hasDirective(~selected, ~key="from") {
    await deps.interactiveIO.ask("from path: ")
  } else { "" }
let injectValue =
  if hasDirective(~selected, ~key="inject") {
    await deps.interactiveIO.ask("inject regex: ")
  } else { "" }
// ... after, before, at_line, skip_if, prepend, append, eof_last,
//     force, unless_exists, tool, fetch, script prompts ...
let body = await deps.interactiveIO.ask("Template body (single-line; optional): ")
```

**Part 2: Frontmatter assembly** (lines 376–422) — pure array building:
```rescript
let frontmatterLines = ["---", "to: " ++ toPath]

if fromValue->String.trim != "" {
  Js.Array.push("from: " ++ fromValue->String.trim, frontmatterLines)->ignore
}
if injectValue->String.trim != "" {
  Js.Array.push("inject: " ++ injectValue->String.trim, frontmatterLines)->ignore
}
if afterValue->String.trim != "" {
  Js.Array.push("after: " ++ afterValue->String.trim, frontmatterLines)->ignore
}
if beforeValue->String.trim != "" {
  Js.Array.push("before: " ++ beforeValue->String.trim, frontmatterLines)->ignore
}
if atLineValue->String.trim != "" {
  Js.Array.push("at_line: " ++ atLineValue->String.trim, frontmatterLines)->ignore
}
if skipIfValue->String.trim != "" {
  Js.Array.push("skip_if: " ++ skipIfValue->String.trim, frontmatterLines)->ignore
}
if prependEnabled {
  Js.Array.push("prepend: true", frontmatterLines)->ignore
}
if appendEnabled {
  Js.Array.push("append: true", frontmatterLines)->ignore
}
if eofLastEnabled {
  Js.Array.push("eof_last: true", frontmatterLines)->ignore
}
if forceEnabled {
  Js.Array.push("force: true", frontmatterLines)->ignore
}
if unlessExistsEnabled {
  Js.Array.push("unless_exists: true", frontmatterLines)->ignore
}
if toolValue->String.trim != "" {
  Js.Array.push("tool: " ++ toolValue->String.trim, frontmatterLines)->ignore
}
if fetchValue->String.trim != "" {
  Js.Array.push("fetch: " ++ fetchValue->String.trim, frontmatterLines)->ignore
}
if scriptValue->String.trim != "" {
  Js.Array.push("script: " ++ scriptValue->String.trim, frontmatterLines)->ignore
}

Js.Array.push("---", frontmatterLines)->ignore
let templateContent = frontmatterLines->Array.concat([body])->Array.join("\n") ++ "\n"
```

**Part 3: File writing** (lines 424–428) — creates dir and writes:
```rescript
let actionDir = deps.path.join(generatorDir, actionFolder)
let targetPath = deps.path.join(actionDir, filename)
let _ = await deps.fs.mkdir(actionDir, ~options={recursive: true})
await deps.fs.writeFile(targetPath, templateContent)
Console.log("Created template: " ++ targetPath)
```

**File**: `test/CommandsGenerator_test.res` (165 lines)
- Uses `TestHelpers` (assert_eq, assert_true, assert_false)
- Test structure: `suite("CommandsGenerator", () => { test(...); testAsync(...) })`
- Existing tests cover: `normalizeTemplateFilename`, `isTemplateFile`, `resolveGeneratorDir`, `runList`
- No existing tests for `runAddFile` or frontmatter assembly

## Commands you will need

| Purpose   | Command                  | Expected on success       |
|-----------|--------------------------|---------------------------|
| Build     | `pnpm build`             | exit 0                    |
| Tests     | `pnpm res:test`          | all pass                  |
| Single    | `npx retest ./test/CommandsGenerator_test.res.mjs` | all pass |

## Scope

**In scope**:
- `src/interfaces/cli/CommandsGenerator.res` — extract `buildFrontmatter` and `promptForDirectives`; thin down `runAddFile`
- `test/CommandsGenerator_test.res` — add unit tests for `buildFrontmatter`

**Out of scope**:
- Refactoring the file-writing part of `runAddFile`
- Changing the interactive prompt flow
- Plans 021 and 022 (they are dependencies, applied before this plan)

## Steps

### Step 1: Ensure plans 021 and 022 are applied

Verify that `isTemplateFile` has been moved to Template.res and `parsePromptTypeFromInput` has been removed from CommandsGenerator.res.

**Verify**: `grep -n "isTemplateFile" src/interfaces/cli/CommandsGenerator.res` → 0 matches (plan 021 moved it)
**Verify**: `grep -n "parsePromptTypeFromInput" src/interfaces/cli/CommandsGenerator.res` → 0 matches (plan 022 removed it)

If matches are found, STOP and report — plans 021 and 022 must be applied first.

### Step 2: Extract `buildFrontmatter` pure function

In `src/interfaces/cli/CommandsGenerator.res`, add a new function before `runAddFile`. This function takes all the directive values and returns the assembled template content string:

```rescript
type directiveValues = {
  toPath: string,
  from: string,
  inject: string,
  after: string,
  before: string,
  atLine: string,
  skipIf: string,
  prepend: bool,
  append: bool,
  eofLast: bool,
  force: bool,
  unlessExists: bool,
  tool: string,
  fetch: string,
  script: string,
  body: string,
}

let buildFrontmatter: directiveValues => string = (vals) => {
  let frontmatterLines = ["---", "to: " ++ vals.toPath]

  if vals.from->String.trim != "" {
    Js.Array.push("from: " ++ vals.from->String.trim, frontmatterLines)->ignore
  }
  if vals.inject->String.trim != "" {
    Js.Array.push("inject: " ++ vals.inject->String.trim, frontmatterLines)->ignore
  }
  if vals.after->String.trim != "" {
    Js.Array.push("after: " ++ vals.after->String.trim, frontmatterLines)->ignore
  }
  if vals.before->String.trim != "" {
    Js.Array.push("before: " ++ vals.before->String.trim, frontmatterLines)->ignore
  }
  if vals.atLine->String.trim != "" {
    Js.Array.push("at_line: " ++ vals.atLine->String.trim, frontmatterLines)->ignore
  }
  if vals.skipIf->String.trim != "" {
    Js.Array.push("skip_if: " ++ vals.skipIf->String.trim, frontmatterLines)->ignore
  }
  if vals.prepend {
    Js.Array.push("prepend: true", frontmatterLines)->ignore
  }
  if vals.append {
    Js.Array.push("append: true", frontmatterLines)->ignore
  }
  if vals.eofLast {
    Js.Array.push("eof_last: true", frontmatterLines)->ignore
  }
  if vals.force {
    Js.Array.push("force: true", frontmatterLines)->ignore
  }
  if vals.unlessExists {
    Js.Array.push("unless_exists: true", frontmatterLines)->ignore
  }
  if vals.tool->String.trim != "" {
    Js.Array.push("tool: " ++ vals.tool->String.trim, frontmatterLines)->ignore
  }
  if vals.fetch->String.trim != "" {
    Js.Array.push("fetch: " ++ vals.fetch->String.trim, frontmatterLines)->ignore
  }
  if vals.script->String.trim != "" {
    Js.Array.push("script: " ++ vals.script->String.trim, frontmatterLines)->ignore
  }

  Js.Array.push("---", frontmatterLines)->ignore
  frontmatterLines->Array.concat([vals.body])->Array.join("\n") ++ "\n"
}
```

**Verify**: `pnpm build` → exits 0 (new function added, old code still exists — no conflict)

### Step 3: Extract `promptForDirectives` interactive helper

Add a new function that handles the interactive prompting and returns a `directiveValues` record:

```rescript
let promptForDirectives: (
  ~io: Ports.interactiveIO,
  ~toPath: string,
) => promise<directiveValues> = async (~io, ~toPath) => {
  let directiveSelection =
    await io.ask(
      "Additional directives (comma-separated; e.g. inject,after,before,atLine,skipIf,prepend,append,eofLast,force,unlessExists,tool,fetch,script): ",
    )
  let selected = parseDirectiveSelection(directiveSelection)

  let fromValue =
    if hasDirective(~selected, ~key="from") {
      await io.ask("from path: ")
    } else { "" }
  let injectValue =
    if hasDirective(~selected, ~key="inject") {
      await io.ask("inject regex: ")
    } else { "" }
  let afterValue =
    if hasDirective(~selected, ~key="after") {
      await io.ask("after regex: ")
    } else { "" }
  let beforeValue =
    if hasDirective(~selected, ~key="before") {
      await io.ask("before regex: ")
    } else { "" }
  let atLineValue =
    if hasDirective(~selected, ~key="at_line") {
      await io.ask("at_line number: ")
    } else { "" }
  let skipIfValue =
    if hasDirective(~selected, ~key="skip_if") {
      await io.ask("skip_if regex: ")
    } else { "" }

  let prependEnabled =
    hasDirective(~selected, ~key="prepend")
      ? await io.askConfirm(~question="Enable prepend: true?", ~defaultYes=true)
      : false
  let appendEnabled =
    hasDirective(~selected, ~key="append")
      ? await io.askConfirm(~question="Enable append: true?", ~defaultYes=true)
      : false
  let eofLastEnabled =
    hasDirective(~selected, ~key="eof_last")
      ? await io.askConfirm(~question="Enable eof_last: true?", ~defaultYes=true)
      : false
  let forceEnabled =
    hasDirective(~selected, ~key="force")
      ? await io.askConfirm(~question="Enable force: true?", ~defaultYes=true)
      : false
  let unlessExistsEnabled =
    hasDirective(~selected, ~key="unless_exists")
      ? await io.askConfirm(~question="Enable unless_exists: true?", ~defaultYes=true)
      : false

  let toolValue =
    if hasDirective(~selected, ~key="tool") {
      await io.ask("tool name: ")
    } else { "" }
  let fetchValue =
    if hasDirective(~selected, ~key="fetch") {
      await io.ask("fetch URL: ")
    } else { "" }
  let scriptValue =
    if hasDirective(~selected, ~key="script") {
      await io.ask("script name (resolved from shell.scripts): ")
    } else { "" }

  let body = await io.ask("Template body (single-line; optional): ")

  {
    toPath,
    from: fromValue,
    inject: injectValue,
    after: afterValue,
    before: beforeValue,
    atLine: atLineValue,
    skipIf: skipIfValue,
    prepend: prependEnabled,
    append: appendEnabled,
    eofLast: eofLastEnabled,
    force: forceEnabled,
    unlessExists: unlessExistsEnabled,
    tool: toolValue,
    fetch: fetchValue,
    script: scriptValue,
    body,
  }
}
```

**Verify**: `pnpm build` → exits 0

### Step 4: Rewrite `runAddFile` to use the extracted helpers

Replace the body of `runAddFile` (lines 267–434) with a thin orchestrator:

```rescript
let runAddFile: (~deps: Ports.deps, ~name: option<string>) => promise<unit> = async (~deps, ~name) => {
  switch requireGeneratorName(~deps, ~name) {
  | None => ()
  | Some(generatorName) => {
      switch await resolveGeneratorDir(~deps, ~name=generatorName) {
      | None => {
          Console.error("Error: generator not found: " ++ generatorName)
          deps.process.exit(1)
        }
      | Some(generatorDir) => {
          let actionFolderRaw = await deps.interactiveIO.ask("Action folder (default: new): ")
          let actionFolder = switch maybeString(actionFolderRaw) {
          | Some(v) => v
          | None => "new"
          }

          let filenameRaw = await deps.interactiveIO.ask("Template file name (e.g. index.ejs.t): ")
          let filename = normalizeTemplateFilename(filenameRaw->String.trim)
          let toPath = (await deps.interactiveIO.ask("to path (required): "))->String.trim

          if filename == ".ejs.t" || toPath == "" {
            Console.error("Error: template file name and 'to' are required")
            deps.process.exit(1)
          } else {
            let directives = await promptForDirectives(~io=deps.interactiveIO, ~toPath)
            let templateContent = buildFrontmatter(directives)

            let actionDir = deps.path.join(generatorDir, actionFolder)
            let targetPath = deps.path.join(actionDir, filename)
            let _ = await deps.fs.mkdir(actionDir, ~options={recursive: true})
            await deps.fs.writeFile(targetPath, templateContent)
            Console.log("Created template: " ++ targetPath)
          }
        }
      }
    }
  }
}
```

**Verify**: `pnpm build` → exits 0

### Step 5: Add unit tests for `buildFrontmatter`

In `test/CommandsGenerator_test.res`, add tests inside the existing `suite("CommandsGenerator", ...)` block:

```rescript
test("buildFrontmatter: to only", () => {
  let vals: CommandsGenerator.directiveValues = {
    toPath: "src/App.tsx",
    from: "",
    inject: "",
    after: "",
    before: "",
    atLine: "",
    skipIf: "",
    prepend: false,
    append: false,
    eofLast: false,
    force: false,
    unlessExists: false,
    tool: "",
    fetch: "",
    script: "",
    body: "",
  }
  let result = CommandsGenerator.buildFrontmatter(vals)
  assert_true(String.includes(result, "---"))
  assert_true(String.includes(result, "to: src/App.tsx"))
  assert_false(String.includes(result, "inject:"))
})

test("buildFrontmatter: to + inject + after", () => {
  let vals: CommandsGenerator.directiveValues = {
    toPath: "src/App.tsx",
    from: "",
    inject: "export default",
    after: "import React",
    before: "",
    atLine: "",
    skipIf: "",
    prepend: false,
    append: false,
    eofLast: false,
    force: false,
    unlessExists: false,
    tool: "",
    fetch: "",
    script: "",
    body: "const x = 1",
  }
  let result = CommandsGenerator.buildFrontmatter(vals)
  assert_true(String.includes(result, "inject: export default"))
  assert_true(String.includes(result, "after: import React"))
  assert_true(String.includes(result, "const x = 1"))
})

test("buildFrontmatter: prepend + append", () => {
  let vals: CommandsGenerator.directiveValues = {
    toPath: "config.json",
    from: "",
    inject: "",
    after: "",
    before: "",
    atLine: "",
    skipIf: "",
    prepend: true,
    append: true,
    eofLast: false,
    force: false,
    unlessExists: false,
    tool: "",
    fetch: "",
    script: "",
    body: "{}",
  }
  let result = CommandsGenerator.buildFrontmatter(vals)
  assert_true(String.includes(result, "prepend: true"))
  assert_true(String.includes(result, "append: true"))
})

test("buildFrontmatter: force flag", () => {
  let vals: CommandsGenerator.directiveValues = {
    toPath: "output.txt",
    from: "",
    inject: "",
    after: "",
    before: "",
    atLine: "",
    skipIf: "",
    prepend: false,
    append: false,
    eofLast: false,
    force: true,
    unlessExists: false,
    tool: "",
    fetch: "",
    script: "",
    body: "hello",
  }
  let result = CommandsGenerator.buildFrontmatter(vals)
  assert_true(String.includes(result, "force: true"))
})

test("buildFrontmatter: sh (script) directive", () => {
  let vals: CommandsGenerator.directiveValues = {
    toPath: "script.sh",
    from: "",
    inject: "",
    after: "",
    before: "",
    atLine: "",
    skipIf: "",
    prepend: false,
    append: false,
    eofLast: false,
    force: false,
    unlessExists: false,
    tool: "",
    fetch: "",
    script: "build",
    body: "#!/bin/bash",
  }
  let result = CommandsGenerator.buildFrontmatter(vals)
  assert_true(String.includes(result, "script: build"))
  assert_true(String.includes(result, "#!/bin/bash"))
})
```

**Verify**: `npx retest ./test/CommandsGenerator_test.res.mjs` → all pass, including new tests

### Step 6: Run full test suite

**Verify**: `pnpm res:test` → all tests pass

## Test plan

- **New tests** (in `test/CommandsGenerator_test.res`):
  - `buildFrontmatter`: to only
  - `buildFrontmatter`: to + inject + after
  - `buildFrontmatter`: prepend + append
  - `buildFrontmatter`: force flag
  - `buildFrontmatter`: sh (script) directive
- **Existing tests** that validate the change:
  - All existing CommandsGenerator_test tests pass (behavior preserved)
  - The `runAddFile` function is not directly tested today, but the extraction is behavior-preserving

## Done criteria

- [ ] `pnpm build` exits 0
- [ ] `pnpm res:test` exits 0
- [ ] `npx retest ./test/CommandsGenerator_test.res.mjs` exits 0 with all new buildFrontmatter tests passing
- [ ] `grep -n "buildFrontmatter" src/interfaces/cli/CommandsGenerator.res` returns at least 2 matches (definition + call site)
- [ ] `grep -n "promptForDirectives" src/interfaces/cli/CommandsGenerator.res` returns at least 2 matches (definition + call site)
- [ ] `runAddFile` is ≤40 lines (thin orchestrator)
- [ ] No files outside the in-scope list are modified

## STOP conditions

- The code at the locations in "Current state" doesn't match the excerpts (the codebase has drifted since this plan was written).
- Plans 021 and 022 have not been applied (`isTemplateFile` still local in CommandsGenerator.res or `parsePromptTypeFromInput` still exists).
- `pnpm build` fails after Step 4 with an error not described above.
- The `directiveValues` type conflicts with an existing type in the codebase (grep first).
- `runAddFile` cannot be thin enough because the prompt sequence has conditional branching that doesn't decompose cleanly.

## Maintenance notes

- The `directiveValues` type is public and lives in CommandsGenerator — if other modules need it, promote it to a shared types module.
- The `buildFrontmatter` function uses `Js.Array.push` for accumulation — this is consistent with the rest of the codebase and is not a code smell here.
- If new directives are added in the future, both the `directiveValues` type and `buildFrontmatter` must be updated together.
- `promptForDirectives` is still interactive (takes `~io`) — it is NOT pure. Only `buildFrontmatter` is pure and unit-testable.
