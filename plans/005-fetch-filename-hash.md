# Plan 005: Fix fetch temp filename collision from weak hash

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. When done, update the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 3a6df55..HEAD -- src/application/pipeline/ShellExecutor.res src/infrastructure/bindings/NodeJs.res`
> If these files changed since this plan was written, read the current versions
> and adjust line references before editing.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug / perf
- **Planned at**: commit `3a6df55`, 2026-06-29

## Why this matters

The fetch file name is derived from `String.split("")->Array.reduce(0, (acc, c) => acc + charCode)`. This sums character codes — "ab" and "ba" produce identical hashes. Two different URLs with the same checksum produce the same temp filename, and the second fetch silently overwrites the first's data. Collisions are likely for short URLs.

## Current state

**File**: `src/application/pipeline/ShellExecutor.res`, lines 64-72

```rescript
let hash = url->String.split("")->Array.reduce(0, (acc, c) => {
  let code = switch String.charCodeAt(c, 0) {
  | Some(n) => n
  | None => 0
  }
  acc + code
})
"fetch-" ++ Int.toString(hash) ++ ".tmp"
```

**File**: `src/infrastructure/bindings/NodeJs.res` — no Crypto module exists yet.

**Convention**: ReScript FFI uses `@module("node:*") external` bindings.
Modules under `NodeJs.res` group related bindings. The ShellExecutor already
receives `path` and `fs` ports — no port changes needed.

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Build     | `pnpm res:build`         | exit 0              |
| Tests     | `pnpm res:test`          | all pass            |

## Scope

**In scope**:
- `src/infrastructure/bindings/NodeJs.res` — add Crypto binding
- `src/application/pipeline/ShellExecutor.res` — use proper hash

**Out of scope**:
- Deno binding (not needed — Deno has `crypto.subtle` available natively)
- Any changes to the Fetcher module
- Any port interface changes

## Steps

### Step 1: Add Crypto module to NodeJs bindings

Add a `Crypto` module to `src/infrastructure/bindings/NodeJs.res`:

```rescript
module Crypto = {
  @module("node:crypto")
  external createHash: string => {..} = "createHash"

  @module("node:crypto")
  external update: ({..}, string, string) => {..} = "update"

  @module("node:crypto")
  external digest: ({..}, string) => string = "digest"

  let sha256Hex: string => string = input => {
    let hash = createHash("sha256")
    let _ = update(hash, input, "utf8")
    digest(hash, "hex")
  }
}
```

**Verify**: `pnpm res:build` — compiles without errors.

### Step 2: Replace hash in ShellExecutor

In `src/application/pipeline/ShellExecutor.res`, replace lines 64-72 with:

```rescript
let fetchFileName = {
  let hash = NodeJs.Crypto.sha256Hex(url)
  "fetch-" ++ hash->String.slice(~start=0, ~end=16) ++ ".tmp"
}
```

This uses the first 16 hex chars of SHA-256 — collision probability is
effectively zero, and the filename stays readable.

**Verify**: `pnpm res:build` — compiles without errors.

### Step 3: Run tests

`pnpm res:test` — all tests pass. The Fetch-related tests in ShellExecutor
and Phase2 integration tests should still pass (the fetch file name is
only used for temp storage within a single executeShellCommands call, so
no test asserts the exact filename).

## Done criteria

- [ ] `pnpm res:build` exits 0
- [ ] `pnpm res:test` exits 0
- [ ] No files outside the in-scope list are modified
- [ ] `plans/README.md` status row updated

## STOP conditions

- The code doesn't match the excerpts above (read the current file first).
- A step's verification fails twice after a reasonable fix attempt.

## Maintenance notes

The SHA-256 binding uses structural typing (`{..}`) for the hash object,
which is the standard ReScript pattern for objects with many methods.
If Deno fetch support is extended, a similar `Crypto.sha256Hex` should be
added to the Deno bindings.
