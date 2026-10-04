# Feature: code-health-batch-2

Source: code-health audit (batch-2) + ~30 non-blocking advisories from the slice-review campaign.
Branch: `refactor/code-health-batch-2` (from `main` @ a5bfc0b). Scope guard: **zero behavior change** except where explicitly noted with tests; structural refactors (error-type unification, SSRF single-pass, hook-policy centralization, Discovery decomposition) are OUT — separate features.
Verification: focused `pnpm res:build && npx retest ./test/<X>_test.res.mjs` per task; full `pnpm res:test` at close; native review of the branch range at close.

## Tasks

### T1 — Dead code purge (zero-caller, grep-verified only)
- **Files:** `src/infrastructure/config/ConfigJsonParser.res` (`_getObjectField` :11, `_getIntField` :18), `src/infrastructure/config/Config.res` (facade exports :27-29 `parseHookCommand`/`parseShellConfig` if zero callers incl. `.resi`), `src/domain/template/Frontmatter.res` (`parseError` :12), `src/infrastructure/rendering/Renderer.res` (`_helpers` :41; remove `makeHelpers` itself only if zero callers — FuncMap dual-surface drift), `src/infrastructure/discovery/Discovery.res` (`_hasActionDirectory` :344 block 331-343).
- **Rule:** grep callers first; remove ONLY zero-caller items. `Discovery.discover`/`findByClassification` are test-only — KEEP (separate follow-up).
- **Status:** done — **Evidence:** 5/5 candidates removed (zero-caller verified; makeHelpers retained — has callers). Build 0 warnings; Config/Frontmatter/Discovery/TemplateRenderer suites 92/156 baseline exact. Commit `76756f1` (48 deletions).

### T2 — Unify JsExn extraction via `Errors.extractErrorMessage`
- **Files:** `src/application/pipeline/TemplateRenderer.res` (:95,:159), `src/application/pipeline/Commit.res` (:55,:124,:197,:211,:255), `src/infrastructure/config/ConfigStore.res` (:31-37,:74-79,:118-123), `src/infrastructure/config/ConfigYamlParser.res` (:41-47,:84-91).
- **Rule:** behavior-identical — preserve each site's exact fallback string ("Unknown error" vs "unknown error" stay as-is). Verify `Errors.extractErrorMessage` covers message/code unwrap; extend it if a site needs the `code` field.
- **Status:** done — **Evidence:** 12/12 sitios refactorizados, fallbacks byte-idénticos, extractErrorCode añadido para ENOENT. Neto −29 líneas; build 0 warnings; suites enfocadas 53/53. Commit `526601f`.

### T3 — Single defaults source for config
- **Files:** `src/domain/config/ConfigTypes.res` (canonical default), `src/infrastructure/config/ConfigYamlParser.res` (:19), `src/infrastructure/config/ConfigYaml.res` (:20).
- **Rule:** `timeout = 5` defined once; parsers reference it. Behavior identical.
- **Status:** done — **Evidence:** `ConfigTypes.defaultTimeout` canónica; parser y facade la referencian. 51/51 suites de config. Commit `5e62ae9`.

### T4 — Test coverage for reviewer-flagged gaps
- **Files:** `test/ShellExecutor_test.res` (default-enabled allowlist path, ~:283), `test/TemplateRegistry_test.res` (depth cap :19-20; marker-present cleanup :100-104), `test/Router_test.res` (strengthen weak template `-v` assertion :228), `test/Staging_test.res` (assert mode on every created dir, not only first, :159-164).
- **Rule:** new tests must pass against current behavior (these are coverage gaps, not bugs). If a new test FAILS, that's a found bug → stop, report, do not paper over.
- **Status:** done — **Evidence:** 4 tests añadidos/fortalecidos; 73 tests/167 aserciones en las 4 suites, todo verde contra comportamiento actual (sin bugs encontrados).

### T5 — Two bounded WARNING fixes
- **Files:** `src/infrastructure/fetcher/Fetcher.res` (:103 `cancelBody` sync-throw → guard), `src/infrastructure/discovery/Discovery.res` (:353-365 silent search-path catch → warn, matching sibling catch at :271-283).
- **Rule:** test-first where a test can observe it (Fetcher: swallowed-throw scenario; Discovery: warn output via existing harness patterns). Minimal diffs.
- **Status:** done — **Evidence:** ambos test-first (RED real: regresiones fallaban pre-fix). Fetcher 39/72 verde. Commit en git log.

## Commit plan
1. `chore(config): remove dead helpers and facade exports` (T1)
2. `refactor(errors): route JsExn extraction through Errors.extractErrorMessage` (T2)
3. `refactor(config): single source for default timeout` (T3)
4. `test: cover reviewer-flagged gaps (allowlist, depth cap, marker cleanup, staging mode)` (T4)
5. `fix(fetcher): guard cancelBody against sync throw; chore(discovery): warn on search-path failure` (T5)

## Close
- Full `pnpm res:test` + `pnpm build` green; native review of branch range vs `main`; report.
