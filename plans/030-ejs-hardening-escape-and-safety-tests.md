# Plan 030: Remove the EJS `escape` option from bindings and characterize the EjsSafety guard

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat c29f1c9..HEAD -- src/infrastructure/bindings/Ejs.res src/application/prompts/EjsSafety.res`
> On any mismatch, treat it as a STOP condition.

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: security
- **Planned at**: commit `c29f1c9`, 2026-08-01
- **Method**: Mixed — Step 1 is a binding edit verified by the compiler; Step 2 is TDD (characterization tests first, then tighten if a gap is found).

## Why this matters

Two latent EJS hazards sit in the bindings layer. (1) The `escape` option is
exposed in the ReScript `options` type at `Ejs.res:3` — in EJS, `escape` replaces
the escaping function, and if any future code path passes a user-controlled value
through it, that is arbitrary code execution. No path does today, but the type
makes the footgun one keystroke away. (2) The `EjsSafety._hasUnsafeEjsTags` guard
protects user-supplied prompt expressions (the only place untrusted EJS strings
are evaluated) with a regex blocklist, but it has **no tests** and its coverage of
EJS's less-common tag forms (`<%_`, `<%#`, `<%%`) is unverified. This plan removes
the latent option and locks in the guard's behavior with tests.

## Current state

All line numbers verified against commit `c29f1c9`.

- `src/infrastructure/bindings/Ejs.res`:
  ```
  1: type options = {
  2:   delimiter?: string,
  3:   escape?: string => string,      // <-- latent RCE primitive; remove
  4: }
  6: @module("ejs")
  7: external render: (string, dict<string>, ~options: options=?) => string = "render"
  9: @module("ejs")
  10: external renderFile: (string, dict<string>, ~options: options=?) => promise<string> = "renderFile"
  ```
  - **Confirmed safe today**: `Renderer.res:60` calls `Bindings.Ejs.render(tmpl.body, data->Obj.magic)` with **no** `~options`; `NodeJsEjs.res`/`DenoEjs.res` likewise pass no options. So removing `escape` changes no live call site.
- `src/application/prompts/EjsSafety.res`:
  ```
  6: let _hasUnsafeEjsTags: string => bool = template => {
  7:   let controlFlowPattern = RegExp.fromString("<%(?![-=])")   // <% not followed by - or =
  8:   let unescapedPattern = RegExp.fromString("<%-")             // <%- (unescaped output)
  9:   RegExp.test(controlFlowPattern, template) || RegExp.test(unescapedPattern, template)
  10: }
  ```
  - Used only via `_renderEval` (line 19-22) for prompt `when`/`default`/`label` expressions (callers in `Expression.res`). The main template-body render is intentionally unguarded (templates need full EJS).
  - **No tests exist** for `EjsSafety` (grep `test/**/EjsSafety*` → none).

**Repo conventions**:
- Tests in `test/`, run via `pnpm res:test`. Use `test(` / `testAsync(` + `assert_true`/`assert_false` from `TestHelpers` — see any `test/*_test.res`.
- The EJS bindings are raw FFI (`@module("ejs") external`); options are a ReScript record mapped to a JS object.

## Commands you will need

| Purpose   | Command                          | Expected on success |
|-----------|----------------------------------|---------------------|
| Compile   | `pnpm res:build`                 | exit 0, no errors   |
| Tests     | `pnpm res:test`                  | all pass            |
| Focused   | `npx retest ./test/EjsSafety_test.res.mjs` | all pass |

## Scope

**In scope**:
- `src/infrastructure/bindings/Ejs.res` (Step 1)
- `src/application/prompts/EjsSafety.res` (Step 2 — only if a characterization test reveals a gap)
- New `test/EjsSafety_test.res`

**Out of scope**:
- Eliminating the `Obj.magic` cast at `EjsSafety.res:21` / `Renderer.res:57,60` — previously rejected as QUAL-11 ("safe interop, not worth a plan"). Do NOT touch.
- Any change to the main template-body render path (templates legitimately use `<% %>` and `<%- %>`).
- Changing EJS dependency version (`ejs@3.1.10` is current and patches CVE-2024-33883).

## Steps

### Step 1: Remove the `escape` option from the EJS binding

1. **Record current behavior**: `rg "~options: options" src/` and `rg "escape" src/infrastructure/bindings/Ejs.res` to confirm no caller passes `escape`. (Expected: none.)
2. **Edit** `src/infrastructure/bindings/Ejs.res` — change the `options` type to:
   ```
   type options = {
     delimiter?: string,
   }
   ```
   Add a one-line comment above the type: `// EJS escape/client/outputFunctionName options are intentionally NOT exposed — they are RCE primitives if fed untrusted input.`
3. **Verify**: `pnpm res:build` exits 0 (the compiler confirms no caller referenced `escape`). `pnpm res:test` green.

### Step 2: Characterize the EjsSafety guard with tests; tighten if needed (TDD)

1. **Create `test/EjsSafety_test.res`** and assert, for each input, whether `_hasUnsafeEjsTags` returns `true` (unsafe) or `false` (safe):
   - **Safe (expect `false`)**: `<%= name %>`, `hello <%= a %> world`, plain text `no tags`, `<%= 1 + 2 %>`.
   - **Unsafe (expect `true`)**: `<% if (x) %>`, `<%- rawHtml %>`, `<%_ slurp %>`, `<%# comment %>`, ` <% console.log() %>`, `<% `%>`-style misuse, an expression containing a literal `<%%` (escaped percent) — decide expected behavior and record it.
2. **Run** `npx retest ./test/EjsSafety_test.res.mjs`. If any case does not match the "unsafe" expectation (i.e. a dangerous tag slips through as `false`), **tighten** `_hasUnsafeEjsTags`: the cleanest hardening is an **allowlist** — reject any occurrence of `<%` that is not exactly `<%=` (i.e. the template may contain only `<%= ... %>` and literal text). A candidate implementation:
   ```
   // Allowlist: the only permitted EJS tag is <%= ... %>. Everything else rejects.
   let _hasUnsafeEjsTags = template => {
     let anyTag = RegExp.fromString("<%")
     // find each <% and require the very next non-space char to be '='
     ...reject unless the tag opens with <%= ...
   }
   ```
   If you switch to the allowlist, re-run all characterization tests — they must still match.
3. **If all characterization tests already pass** with the current blocklist, leave the implementation as-is and add a comment documenting that the guard is allowlist-equivalent in practice (only `<%=` passes). Do not change behavior without a failing test justifying it.
4. **Verify**: `npx retest ./test/EjsSafety_test.res.mjs` → all pass; `pnpm res:test` green; `pnpm res:build` exit 0.

## Test plan

- New `test/EjsSafety_test.res`: ~8-10 cases covering safe (`<%=`), unsafe (`<%`, `<%-`, `<%_`, `<%#`), and edge (`<%%`) forms. Model the file structure on any existing `test/*_test.res` (open `test/PathSecurity_test.res` for the `test(`/`testAsync(` + `assert_*` shape).
- Verification: `pnpm res:test` → all pass including the new file.

## Done criteria

- [ ] `pnpm res:build` exits 0
- [ ] `pnpm res:test` exits 0; `test/EjsSafety_test.res` exists and passes
- [ ] `rg "escape" src/infrastructure/bindings/Ejs.res` returns no matches
- [ ] If the guard was changed, every characterization case still matches its expectation
- [ ] No files outside the in-scope list are modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

- Removing `escape` from `options` causes a compile error in a caller — that caller was passing `escape`; report it (it is either a bug or an intentional use that must be audited before proceeding).
- A characterization test reveals the current guard is **already sufficient** and you are tempted to "improve" it anyway — do not change behavior without a failing test. Record the finding and stop.
- Switching to an allowlist breaks a legitimate prompt expression that uses a tag form you assumed unsafe — report; the trust model is "prompt expressions are simple `<%= expr %>` only", so any such case is itself suspicious.

## Maintenance notes

- After Step 1, the EJS binding type enforces "no code-execution options" at compile time. Any future need for a custom delimiter must go through the `options` type explicitly; `escape`/`client`/`outputFunctionName` must never be re-added without a security review.
- The `EjsSafety` guard is the **only** thing standing between user-typed prompt expressions and EJS evaluation. The characterization tests are now the regression net — update them whenever EJS syntax is in question.
- A reviewer should scrutinize: (a) the allowlist regex (if used) does not have a `<%=`-followed-by-malicious escape hole, and (b) the comment in `Ejs.res` accurately names the excluded options.
