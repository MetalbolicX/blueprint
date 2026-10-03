# Plan 049: Cancel abandoned fetch response bodies

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 100b121..HEAD -- src/infrastructure/fetcher/Fetcher.res src/infrastructure/fetcher/Fetcher.resi src/infrastructure/bindings/WebApis.res test/Fetcher_test.res test/FetchSecurity_test.res`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW (only unused responses are affected)
- **Depends on**: none
- **Category**: perf
- **Planned at**: commit `100b121`, 2026-10-01

## Why this matters

`httpGetHop` abandons response bodies it does not consume: on a redirect it
recurses without touching `response.body`, and on a non-ok status it returns
an error without consuming. Each abandoned body keeps its pooled
connection/timer alive until garbage collection or timeout. This is a
hygiene/resource-release fix — per-attempt `AbortSignal.timeout` already
bounds the retention window (default ~10s × ≤3 attempts), so do NOT claim or
test for a "socket leak"; the win is deterministic, prompt release of
resources the code will never read.

## Current state

At `100b121` (`src/infrastructure/fetcher/Fetcher.res`):

- `:100-133` — `httpGetHop` (recursive, manual redirects, max 5 hops):
  - redirect arm (`:117-126`): reads `location`, validates the next URL,
    recurses — `response.body` never touched.
  - ok arm (`:131`): `Ok(await readBoundedBody(response))` — consumed.
  - non-ok arm (`:132-133`): returns `Error("HTTP ...")` — body never
    touched, never cancelled.
- `:63-99` — `readBoundedBody` (raw-JS `%raw` helper): content-length
  pre-check, streaming reader with a 10 MiB cap that DOES cancel
  (`await reader.cancel().catch(() => {})` at `:88-89`), and a non-stream
  fallback via `response.text()`. This is the established `%raw` style for
  response-shape helpers — match it.
- `:161-167` — `httpGetOnce` wraps the whole attempt in
  `AbortSignal.timeout(timeout * 1000)` (per attempt, all hops) — the
  existing bound that makes this hygiene rather than a leak fix.
- `test/Fetcher_test.res:100-107,310-421` — the mock harness
  (`installResponseSequence` style): mocked responses currently lack
  cancellable bodies on the redirect/error paths (that is exactly why this
  gap was invisible); `:393-424` covers the 10 MiB cap.
- `test/FetchSecurity_test.res:24-36,168-175` — `@skip`-marked network
  tests; do NOT unskip them here (they need real network; separate concern).

## Commands you will need

| Purpose | Command | Expected on success |
|-----------|---------|---------------------|
| Compile (typecheck) | `pnpm res:build` | exit 0 |
| All tests | `pnpm res:test` | all pass |
| Focused tests | `npx retest ./test/Fetcher_test.res.mjs` | all pass |

`.res.mjs` artifacts are gitignored (in-source compilation) — build locally,
never commit them.

## Scope

**In scope** (the only files you should modify):
- `src/infrastructure/fetcher/Fetcher.res`
- `test/Fetcher_test.res`

**Out of scope** (do NOT touch):
- SSRF/per-hop validation (`SsrfGuard`, `validateUrl`) — unchanged.
- Redirect cap, retry/backoff, timeout values — unchanged.
- https→http redirect downgrade policy — a KNOWN OPEN item from the audit
  (scheme-only per-hop check); deliberately NOT this plan.
- `test/FetchSecurity_test.res` skips — separate concern.

## Git workflow

- Branch: `perf/049-cancel-abandoned-fetch-bodies`
- Conventional commits, e.g. `perf(fetcher): cancel abandoned redirect and error bodies`
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Add a guarded `cancelBody` helper

Inside `Fetcher.res` (same `%raw` style and placement as
`readBoundedBody`):

```javascript
let cancelBody: 'response => promise<unit> = %raw(`
  async function(response) {
    if (response && response.body && typeof response.body.cancel === "function") {
      await response.body.cancel().catch(() => {});
    }
  }
`)
```

The guard matters: the test mocks (and any minimal Response shape) may lack
`body` — the helper must be a no-op then, never a rejection.

**Verify**: `pnpm res:build` → exit 0.

### Step 2: Call it in both abandoning arms

In `httpGetHop`:

1. Redirect arm: `await cancelBody(response)` BEFORE recursing into
   `httpGetHop(nextUrl, ...)` (order matters: release this hop's body
   before starting the next).
2. Non-ok arm: `await cancelBody(response)` BEFORE returning the `Error`.

The ok arm is unchanged (consumed by `readBoundedBody`).

**Verify**: `pnpm res:build` → exit 0; `npx retest ./test/Fetcher_test.res.mjs` → all pass (mocks without bodies are no-ops).

### Step 3: RED→GREEN tests

In `test/Fetcher_test.res`, extend the response-sequence mocks for two new
cases (give the mocked responses a `body: { cancel: <recorder> }`):

1. Redirect sequence (301 → Location → 200 ok): assert the FIRST response's
   `body.cancel` was called exactly once before the second fetch happened
   (the recorder can note ordering vs the second fetch count). (RED today:
   cancel never called.)
2. Non-ok sequence (e.g. 500): assert `body.cancel` called once, result is
   the `Error("HTTP 500 ...")`. (RED today.)
3. Regression: ok path with a cancellable body → `cancel` NOT called by the
   harness (the reader consumes; the cap-cancel path is already covered at
   `:393-424`) and the body content is returned.
4. Regression: mocked responses WITHOUT a `body` property → no rejection,
   same results as today.

**Verify**: `npx retest ./test/Fetcher_test.res.mjs` → all pass; `pnpm res:test` → all pass.

## Test plan

- The 4 cases above in `test/Fetcher_test.res`; model the mock extension on
  the existing `installResponseSequence` harness.
- Full-suite gate.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `pnpm res:build` exits 0
- [ ] `pnpm res:test` exits 0 including the new cancel assertions
- [ ] Both the redirect and non-ok tests assert `cancel` was called (RED→GREEN recorded in your report)
- [ ] Existing fetch tests (SSRF, redirect cap, 10 MiB cap, retries) pass unchanged
- [ ] No files outside the in-scope list are modified (`git status --short`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report (do not improvise) if:

- The mock harness cannot represent `body.cancel` (extend it; if the
  harness's shape is load-bearing for other suites, report before
  extending).
- `await cancelBody(...)` changes observable retry/redirect semantics in
  any existing test (e.g. a mock that rejects on cancel — the guard's
  `.catch(() => {})` should make this impossible; if not, STOP).

## Maintenance notes

- Reviewer focus: the redirect arm must cancel the CURRENT response before
  recursing (not the next one).
- Known open item deliberately out of scope: https→http redirect downgrade
  is allowed today (scheme-only per-hop re-check at `:117-126` +
  `validateUrl`); if that policy is ever tightened, it needs its own
  decision (legitimate http-only targets exist).
- If the mocks ever gain signal echo/cancellation fidelity, the
  `FetchSecurity_test.res` skips can be revisited separately.
