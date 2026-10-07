# Plan 064: Cancel abandoned fetch bodies in every failure arm of the redirect chain

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to
> the next step. If anything in the "STOP conditions" section occurs, stop
> and report — do not improvise. When done, update the status row for this
> plan in `plans/README.md` — unless a reviewer dispatched you and told
> they maintain the index.
>
> **Drift check (run first)**: `git diff --stat b2f2670..HEAD -- src/infrastructure/fetcher/Fetcher.res test/Fetcher_test.res`
> Semantic mismatch with the excerpts below is a STOP condition;
> line-number-only drift is benign.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `b2f2670`, 2026-10-05

## Why this matters

Plan 049 taught the fetcher to cancel abandoned response bodies
(`perf/049-cancel-abandoned-fetch-bodies`, commit `3b1972f`): every
response we do not consume must have its body cancelled, or the
underlying socket stays pinned until keep-alive timeout — a slow
resource leak under retries and redirects. Two arms were fixed (the
successful-redirect recursion and the non-ok terminal), but the plan's
reviewer advisory recorded four failure arms that STILL return `Error`
without cancelling (`plans/README.md` row 049: "invalid-redirect/Location
failure arms remain uncancelled (candidate-scoped; follow-up)"). Every
one of them is reachable after a real `fetch` allocated a body: redirect
without `Location`, redirect-loop cap, invalid next URL, and a
`Location` that throws during processing. This plan closes all four with
the exact pattern already in the file.

## Current state

`src/infrastructure/fetcher/Fetcher.res` — `httpGetHop`:

- `:99-105` — the guarded helper (pattern to reuse):
  ```rescript
  let cancelBody: 'response => promise<unit> = %raw(...)
  ```
  (try/catch inside; never rejects).
- `:128` — `if redirectStatus(status) {`
- `:130` — redirect WITHOUT Location — **no cancel**:
  ```rescript
  | None => Error("HTTP " ++ Int.toString(status) ++ ": " ++ response["statusText"])
  ```
- `:132-133` — redirect-loop cap — **no cancel**:
  ```rescript
  if redirects >= 5 { Error("Too many redirects (maximum 5)") }
  ```
- `:137-138` — invalid next URL — **no cancel**:
  ```rescript
  switch validateUrl(nextUrl)
  | Error(message) => Error(message)
  ```
- `:140` — the CORRECT pattern (ok-redirect): `await cancelBody(response)`
  immediately before recursing.
- `:145` — `Location` processing throws — **no cancel**:
  ```rescript
  | JsExn(_) => Error("Invalid redirect Location: " ++ location)
  ```
- `:149-150` — ok arm: `Ok(await readBoundedBody(response))` (bounded
  reader cancels itself on oversize at `:87`).
- `:152-153` — non-ok terminal — the other CORRECT pattern:
  `await cancelBody(response)` then `Error("HTTP " ++ …)`.

Test infrastructure in `test/Fetcher_test.res`: cancel-counting fake at
`:84,101-104,129`; passing exemplars to mirror — `:364` "redirect body is
cancelled before the next fetch", `:381` "non-ok response body is
cancelled and returns HTTP error", `:397` "synchronous body cancel throw
does not mask HTTP error". Redirect-failure tests exist at `:331,451,467,483`
but assert NO cancel behavior (audit: "tests asserting cancel on
invalid-redirect/Location-failure arms: not found").

Conventions: stringly `result<'a, string>` errors in this module;
`%raw` JS escape hatches are established here; test names state the
behavior in English imperative style as seen above.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Compile | `pnpm res:build` | exit 0 |
| Focused | `npx retest ./test/Fetcher_test.res.mjs` | all pass |
| Full suite | `pnpm res:test` | all pass, exit 0 |

Test-first: observe RED, then GREEN.

## Scope

**In scope**:
- `src/infrastructure/fetcher/Fetcher.res` (the four arms)
- `test/Fetcher_test.res`

**Out of scope**:
- `cancelBody` itself; `readBoundedBody`; `validateUrl` / SsrfGuard
  semantics; retry policy; the pre-fetch guard arm (`:117-119` — no
  response exists yet, nothing to cancel).

## Git workflow

- Branch: `fix/064-cancel-fetch-body-failure-arms`
- Commit style: `fix(fetcher): cancel abandoned bodies in redirect failure arms`
- Never commit on `main`; no push/PR unless instructed.

## Steps

### Step 1: RED — four cancel assertions

Add four tests in `test/Fetcher_test.res`, each modeled on `:381` (error
arm + cancel count) using the existing cancel-counting fake:

1. "redirect without Location cancels the body and returns HTTP error"
2. "redirect-loop cap cancels the body and returns too-many-redirects error"
3. "invalid redirect URL cancels the body and returns the validation error"
4. "throwing Location header cancels the body and returns invalid-Location error"

Each asserts: result is the expected `Error(...)` AND the cancel counter
is ≥1 for that response.

**Verify**: `npx retest ./test/Fetcher_test.res.mjs` → the four new
assertions FAIL on cancel count (0 today); error strings pass. Record RED.

### Step 2: GREEN — cancel before each failing return

In `Fetcher.res`, at each of `:130`, `:133`, `:138`, `:145`: insert
`await cancelBody(response)` immediately before constructing the
`Error` return — byte-for-byte the pattern of `:140`/`:152`. Do not
change any error message.

**Verify**: `npx retest ./test/Fetcher_test.res.mjs` → all pass
including the four new tests (GREEN).

### Step 3: Regression gate

**Verify**: `pnpm res:test` → all pass, exit 0 (plan 049's own tests at
`:364,381,397,412` must remain green — per-attempt cancellation
semantics unchanged).

## Test plan

- New: the four Step-1 tests (error + cancel-count assertions, mirroring
  the `:381` structure).
- Existing: plan 049 suite pins the already-correct arms.

## Done criteria

- [ ] RED evidence recorded for all four arms
- [ ] `pnpm res:test` exits 0
- [ ] Every `Error` return reachable after a successful `fetch` in
      `httpGetHop` is preceded by `await cancelBody(response)` (read the
      function end-to-end and confirm)
- [ ] No files outside the in-scope list modified
- [ ] `plans/README.md` status row updated

## STOP conditions

- Any arm turns out to be reachable WITHOUT a live response object
  (cancel would be a no-op lie — adjust the test instead of forcing it).
- Inserting `await` changes error-dominance ordering in an existing test
  (e.g. a cancel rejection masking an HTTP error — `cancelBody` is
  guarded, but verify `:397`'s throw case still holds).

## Maintenance notes

- This closes plan 049's recorded follow-up advisory; the ledger row can
  reference this plan.
- Reviewer focus: no error-message drift — tests at `:331,451,467,483`
  assert the exact strings.
