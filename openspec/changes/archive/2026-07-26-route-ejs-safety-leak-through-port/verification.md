# Verification Report: route-ejs-safety-leak-through-port

**Date:** 2026-07-26
**Branch:** `route-ejs-safety-leak-through-port`
**Verifier:** sdd-verify (executor)
**Verdict:** PASS

## Build Status

`pnpm res:build` — **clean**. Compiles 10 modules, 0 errors. Single pre-existing deprecation
warning about `Js.Int.toString` in `test/ArchitectureGuard_test.res:63` (unchanged from main).

```
$ pnpm res:build
Cleaned 0/236
Parsed 1 source files
Compiled 10 modules

  Warning number 3
  /home/metalbolicx/Documents/blueprint/test/ArchitectureGuard_test.res:63
  deprecated: Js.Int.toString
  Use `Int.toString` instead.
```

## Test Summary

`pnpm res:test` — **625/627 passed, 2 failed** (matches expected). The 2 failures are
pre-existing on `main` and are unrelated to the change.

| Metric | Value |
|--------|-------|
| Total tests | 627 |
| Assertions | 1149 |
| Passed | 625 |
| Failed | 2 |
| Failed (pre-existing on main) | 2 — `cleanupOrphans: removes stale blueprint staging dirs` (603/627), `run: cleans orphaned staging dirs and backup leaks before execution` (608/627) |
| Failed (regressed by this change) | 0 |
| Failed (resolved by this change) | 1 (net: 624 → 625 on top of main's 624) |

Sanity check: stashed the change and re-ran `pnpm res:test` — `main`-equivalent shows
**624 passed / 3 failed**. This change shifts the result to **625 passed / 2 failed**,
confirming one previously-failing test is fixed and zero new failures are introduced.

## Critical Behavior Parity Check

The 3 `PromptResolver_test.res` tests that previously regressed with the no-op `stubEjs`
(all now pass with the real-delegating stub):

| # | Test | Result |
|---|------|--------|
| 453/627 | `evalTemplate: renders simple interpolation` | **PASS** |
| 454/627 | `evalTemplate: rejects control flow tags` | **PASS** |
| 455/627 | `evalTemplate: rejects unescaped output tags` | **PASS** |

These are the regression-criticial tests the proposal called out. All three pass.

## Spec Scenario Compliance Matrix

| Spec scenario | Requirement | Covering test/code | Result |
|---|---|---|---|
| "No Ejs references in application" | `src/application/**/*.res` has zero `Ejs\.[A-Z]` matches | `ArchitectureGuard_test.res` test 108/627 | PASS |
| "No Ejs references in domain" | `src/domain/**/*.res` has zero `Ejs\.[A-Z]` matches | `ArchitectureGuard_test.res` test 107/627 | PASS |
| "Guard fails on a bare Ejs.render leak" | Regression-protection | `String.includes(line, "Ejs.")` in `checkLine` (line 35) — would match any `Ejs.[A-Z]` in scanned files | SATISFIED (no leak present; guard logic verified) |
| "Existing isolation assertions remain green" | `Bindings`/`NodeJs`/`Deno` patterns still pass | `checkLine` lines 32-34 + tests 107/108 | PASS |
| "_renderEval renders via the injected port" | `EjsSafety._renderEval` calls `ejs.renderString` | `EjsSafety.res:19-22` — reads `(~ejs, ~template, ~ctx) => { ejs.renderString(...) }` | PASS (and tests 453-455 confirm `Ok(rendered)`) |
| "Structural eval context is preserved" | `_buildEvalContext` returns `{context, answers}`; not flattened | `Expression.res:34-39` — `{"context": baseContext, "answers": answers}` (structural `{..}`); tests 169, 207, 357, 390 all use `answers.X` and `context.X` and pass | PASS |
| "Missing ejs argument is a compile-time error" | `PromptResolver.resi` declares `~ejs: Ports.ejs` as required | `PromptResolver.resi:5,17-19` — labels are required (no default `=?`); build succeeded with all call sites passing `~ejs` | SATISFIED (compile-time enforcement evidenced by clean build with all 28 call sites updated) |
| "Error path is result-based" | `evalTemplate` returns `Error(EvaluationError)` from `ejs.renderString` `Error(msg)` | `Expression.res:57-67` — result-matching on `_renderEval`; test 287 confirms `Error(EvaluationError({prompt: "name", ...}))` | PASS |
| "stubEjs delegates to the real binding" | `TestPorts.stubEjs.renderString` calls `Bindings.Ejs.render` | `TestPorts.res:30-43` — `Ok(Bindings.Ejs.render(template, context->Obj.magic))` wrapped in try/catch | PASS (proved by 453-455 actually interpolating) |
| "Affected tests inject the ejs port" | All call sites pass `~ejs=TestPorts.stubEjs` | 28 occurrences across `test/PromptResolver_test.res` and `test/Phase0Integration_test.res` | PASS |

## Architecture-Guard Test Result

Both architecture-guard tests pass:

| # | Test | Result |
|---|------|--------|
| 107/627 | `domain layer contains no Bindings/NodeJs/Deno/Ejs references` | **PASS** |
| 108/627 | `application layer contains no Bindings/NodeJs/Deno/Ejs references` | **PASS** |

Guard extension at `test/ArchitectureGuard_test.res:31-36`:

```rescript
let checkLine: string => bool = line => {
  String.includes(line, "Bindings.") ||
  String.includes(line, "NodeJs.") ||
  String.includes(line, "Deno.") ||
  String.includes(line, "Ejs.")
}
```

The `Ejs.` clause (line 35) is the new addition. `String.includes` is slightly more
permissive than the spec's `Ejs\.[A-Z]` regex, but it is **stricter in practice** (any
`Ejs.` substring would match). A bare `Ejs.render` leak in any `src/application/**.res`
or `src/domain/**.res` file would now cause the test to fail. The `EjsSafety.res`
header comment was also reworded to drop the `Ejs.` substring so the guard does not
self-trigger.

## Files Changed

14 files, +105/-81 (matches the apply agent's prediction exactly):

| Tier | File | Change |
|------|------|--------|
| Boundary | `src/application/prompts/EjsSafety.res` | `_renderEval` accepts `~ejs`, calls `ejs.renderString`; reworded comment |
| Application | `src/application/prompts/Expression.res` | `evalTemplate` + 3 helpers accept/forward `~ejs`; result-based error path |
| Application | `src/application/prompts/PromptResolver.resi` | `~ejs: Ports.ejs` declared on `evalTemplate` and `resolve` |
| Application | `src/application/prompts/Resolver.res` | `resolve`/`processPrompt`/`processPromptBody` thread `~ejs` (5 call sites updated) |
| Pipeline | `src/application/pipeline/Phase0.res` / `.resi` | `run(~ejs)` forwards port to `Resolver.resolve` |
| Engine | `src/application/engine/EnginePhases.res` / `.resi` | `runPhase0(~ejs)` forwards to `Phase0.run` |
| Engine | `src/application/engine/EngineOrchestrator.res` | Destructures `deps.ejs`, passes to `runPhase0` |
| Test | `test/res/utils/TestPorts.res` | `stubEjs.renderString` delegates to `Bindings.Ejs.render` (real interpolation) |
| Test | `test/PromptResolver_test.res` | All `evalTemplate`/`resolve` calls inject `~ejs=TestPorts.stubEjs` (23 sites) |
| Test | `test/Phase0Integration_test.res` | All `Phase0.run` calls inject `~ejs=TestPorts.stubEjs` (5 sites) |
| Test | `test/ArchitectureGuard_test.res` | `checkLine` adds `Ejs.`; test names updated to include "Ejs" |
| Repo | `.atl/skill-registry.md` | Registry refresh (incidental) |

## No New Leaked Bindings

```
$ grep -nE "Ejs\.render|Bindings\.Ejs" src/application/prompts/EjsSafety.res
(no matches — exit 1)

$ grep -rnE "Ejs\.[A-Z]" src/application/ src/domain/
(no matches)
```

The bare binding leak in `EjsSafety.res` is gone. Domain and application layers have
zero `Ejs.[A-Z]` references. The `src/infrastructure/**` exemption is unchanged.

## Stub Delegation Verification

`test/res/utils/TestPorts.res:30-43`:

```rescript
let stubEjs: ejs = {
  renderString: (~template, ~context) => {
    try {
      Ok(Bindings.Ejs.render(template, context->Obj.magic))
    } catch {
    | JsExn(obj) => {
        let msg = switch JsExn.message(obj) {
        | Some(m) => m
        | None => "EJS render error"
        }
        Error(msg)
      }
    }
  },
  renderFile: ...
}
```

Confirmed: `stubEjs.renderString` calls `Bindings.Ejs.render` (the real binding) and is
**not** the prohibited `Ok(template)` no-op. This mirrors `stubYamlParser` and is why
the 3 `evalTemplate` tests now pass — they exercise real interpolation against
`context.foo`/`answers.bar`.

## Thread-Through Audit

Dependency path (per design doc):

```
deps.ejs (EngineOrchestrator.res:32)
  → EnginePhases.runPhase0(~ejs)   (EnginePhases.res:13)
    → Phase0.run(~ejs)              (Phase0.res:89)
      → Resolver.resolve(~ejs)      (Resolver.res:115)
        → Resolver.processPrompt(~ejs)    (Resolver.res:139)
          → Expression._evaluateWhen(~ejs) / _evaluateDefault(~ejs) / _evaluateOptions(~ejs)
            → Expression.evalTemplate(~ejs)
              → EjsSafety._renderEval(~ejs)
                → ejs.renderString(~template, ~context=Obj.magic(ctx))
```

All eight labeled-argument thread-through points are in place. Verified by
`git diff main -- src/application/prompts/Resolver.res` and downstream files.

## Issues

**CRITICAL:** None.

**WARNING:** None — the only build-time warning is the pre-existing `Js.Int.toString`
deprecation, untouched by this change.

**SUGGESTION:** The `EjsSafety.res` header comment could drop the "(..." trailing
context now that the `Ejs.render` call is gone, but this is cosmetic and out of scope.

## Final Verdict

**PASS** — implementation matches the proposal, design, spec, and tasks. The 3
previously-regressed tests now pass. The 2 pre-existing failures on `main`
(`cleanupOrphans`) are unrelated to this change and should be tracked separately.

**Recommendation:** ready-for-archive.
