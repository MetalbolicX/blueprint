# Plan 020: Purge dead bindings and helpers

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. When done, update the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 64a81fa..HEAD -- src/infrastructure/bindings/NodeJs.res src/infrastructure/prompts/PromptResolver.res src/domain/manifest/Manifest.res`
> If these files changed, read the current versions before editing.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: tech-debt
- **Planned at**: commit `64a81fa`, 2026-07-20

## Why this matters

`NodeJs.res` contains ~30 externals and types that nothing in the codebase
references. They were written speculatively during initial binding setup. Dead
bindings create noise for contributors reading the file and increase the surface
area for maintenance (e.g. if Node.js changes an API shape, unused bindings
still need attention). `PromptResolver.res` has two unused readline lifecycle
helpers left over from an earlier design. `Manifest.res` has an unused
`parseError` type with a warning suppression annotation. Purging all three
removes ~120 lines of dead code.

## Current state

**File**: `src/infrastructure/bindings/NodeJs.res` (506 lines)

**Os module (lines 97–167)** — externals to REMOVE:
```rescript
// Line 105: external hostname: unit => string = "hostname"
// Line 108: external platform: unit => string = "platform"
// Line 111: external arch: unit => string = "arch"
// Lines 113-121: type cpusTimes, type cpusInfo, external cpus
// Line 124: external totalmem: unit => int = "totalmem"
// Line 127: external freemem: unit => int = "freemem"
// Line 130: external loadavg: unit => array<float> = "loadavg"
// Line 133: external uptime: unit => int = "uptime"
// Lines 135-144: type networkInterfaceInfo, external networkInterfaces
// Lines 146-150: type userInfoOptions, type userInfoResult, external userInfo
```
Os module — KEEP: `tmpdir` (line 99), `homedir` (line 102), `makeStagingDir` (lines 152–166).

**Crypto module (lines 480–497)** — REMOVE entire module:
```rescript
module Crypto = {
  @send external hashUpdate: ({..}, string) => {..} = "update"
  @send external hashDigest: ({..}, string) => string = "digest"
  @module("node:crypto") external createHash: string => {..} = "createHash"
  let sha256Hex: string => string = input => { ... }
}
```

**ChildProcess module (lines 169–370)** — externals and types to REMOVE:
```rescript
// Lines 170-176: type spawnOptions — only used by spawn and execSync (both removed)
// Lines 186-188: external spawn — zero references outside NodeJs.res
// Lines 200-201: external exec — zero references outside NodeJs.res
// Lines 277-278: external execSync — zero references outside NodeJs.res
// Lines 280-288: type execSyncOptions — only used by execFileSync (removed)
// Lines 290-292: external execFileSync — zero references outside NodeJs.res
```
ChildProcess module — KEEP: `childProcess` type (line 178, used by `execWithCallback`/`execFileWithCallback`), `execResult` type (line 190), `execOptions` type (line 192, used by `execWithCallback`/`execAsync`/`execFileWithCallback`/`execFileAsync`/`execShellCommand` and referenced in `NodeJsShell.res:11,18`), `execCallback` type (line 205), `execError` type (line 222), `extractExecError` (line 230), `extractExitCode` (line 237), `execWithCallback` (line 208), `execAsync` (line 243), `execFileWithCallback` (line 295), `execFileAsync` (line 302), `execShellCommand` (line 341).

**Readline module (lines 372–406)** — externals to REMOVE:
```rescript
// Line 399: external moveCursor: (streamReadable, int, int) => unit = "moveCursor"
// Line 402: external clearLine: (streamReadable, int) => unit = "clearLine"
// Lines 404-405: external cursorTo: (streamReadable, int, ~y: int=?, unit) => unit = "cursorTo"
```
Readline module — KEEP: `interface` type (line 373), `completer` type (line 378), `readlineInterface` type (line 380), `streamReadable` type (line 385), `streamWritable` type (line 386), `stdin` (line 388), `stdout` (line 389), `createInterface` (line 392).

**Path module (lines 62–95)** — externals to REMOVE:
```rescript
// Line 67: external join3: (string, string, string) => string = "join"
// Line 88: external normalize: string => string = "normalize"
// Line 73: external relative: (string, string) => string = "relative"
// Line 82: external extname: string => string = "extname"
// Line 91: external sep: string = "sep"
// Line 94: external delimiter: string = "delimiter"
```
Path module — KEEP: `join` (line 64), `resolve` (line 70), `dirname` (line 76), `isAbsolute` (line 85), `basename` (line 79).

**File**: `src/infrastructure/prompts/PromptResolver.res` (535 lines)
```rescript
// Lines 529-531: let _createReadline — defined but never called
let _createReadline: unit => NodeJs.Readline.readlineInterface = () => {
  NodeJs.Readline.createInterface(~input=NodeJs.Readline.stdin, ~output=NodeJs.Readline.stdout, ())
}

// Lines 533-535: let _closeReadline — defined but never called
let _closeReadline: NodeJs.Readline.readlineInterface => unit = rl => {
  rl.close()
}
```

**File**: `src/domain/manifest/Manifest.res` (348 lines)
```rescript
// Line 27: @@warning("-34") — suppresses unused-variable warning for parseError
@@warning("-34")

// Lines 28-31: type parseError — defined but never used
type parseError = {
  message: string,
  line?: int,
}
```

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Build     | `pnpm build`             | exit 0              |
| Tests     | `pnpm res:test`          | all pass            |

## Scope

**In scope** (the only files you should modify):
- `src/infrastructure/bindings/NodeJs.res` — remove dead externals/types
- `src/infrastructure/prompts/PromptResolver.res` — remove `_createReadline`, `_closeReadline`
- `src/domain/manifest/Manifest.res` — remove `parseError` type and `@@warning("-34")`

**Out of scope**:
- Any test files
- `src/infrastructure/adapters/NodeJsShell.res` — uses `execOptions` type (kept)
- Any other source files

## Git workflow

- Branch: `advisor/020-purge-dead-bindings`
- Commit per step with conventional commit messages
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Remove dead Os externals from NodeJs.res

In `src/infrastructure/bindings/NodeJs.res`, remove from the Os module:
- `hostname` external (line 105)
- `platform` external (line 108)
- `arch` external (line 111)
- `cpusTimes` type, `cpusInfo` type, `cpus` external (lines 113–121)
- `totalmem` external (line 124)
- `freemem` external (line 127)
- `loadavg` external (line 130)
- `uptime` external (line 133)
- `networkInterfaceInfo` type, `networkInterfaces` external (lines 135–144)
- `userInfoOptions` type, `userInfoResult` type, `userInfo` external (lines 146–150)

Keep: `tmpdir` (line 99), `homedir` (line 102), `makeStagingDir` (lines 152–166).

After removal, the Os module should contain only:
```rescript
module Os = {
  @module("node:os")
  external tmpdir: unit => string = "tmpdir"

  @module("node:os")
  external homedir: unit => string = "homedir"

  let makeStagingDir: unit => string = () => {
    let ts = Date.now()->Float.toInt->Int.toString
    let r = Math.random()->Float.toString
    let r2 = String.split(r, ".")->Array.get(1)->Option.getOr("x")
    let dir = "blueprint-" ++ ts ++ "-" ++ r2
    let tmp = tmpdir()
    let fullPath = Path.join(tmp, dir)
    try {
      let _ = Fs.mkdirSync(fullPath, ~options={recursive: true})
      fullPath
    } catch {
    | _ => fullPath
    }
  }
}
```

**Verify**: `pnpm build` → exit 0

### Step 2: Remove Crypto module from NodeJs.res

In `src/infrastructure/bindings/NodeJs.res`, delete the entire Crypto module (lines 480–497):
```rescript
module Crypto = {
  @send
  external hashUpdate: ({..}, string) => {..} = "update"
  @send
  external hashDigest: ({..}, string) => string = "digest"
  @module("node:crypto") external createHash: string => {..} = "createHash"
  let sha256Hex: string => string = input => {
    let hash = createHash("sha256")
    let _ = hash->hashUpdate(input)
    hashDigest(hash, "hex")
  }
}
```

**Verify**: `pnpm build` → exit 0

### Step 3: Remove dead ChildProcess externals from NodeJs.res

In `src/infrastructure/bindings/NodeJs.res`, remove from the ChildProcess module:
- `spawnOptions` type (lines 170–176) — only used by `spawn` and `execSync` (both removed)
- `spawn` external (lines 186–188)
- `exec` external (lines 200–201)
- `execSync` external (lines 277–278)
- `execSyncOptions` type (lines 280–288) — only used by `execFileSync` (removed)
- `execFileSync` external (lines 290–292)

Keep: `childProcess` type (line 178), `execResult` type (line 190), `execOptions` type (line 192), `execCallback` type (line 205), `execError` type (line 222), `extractExecError` (line 230), `extractExitCode` (line 237), `execWithCallback` (line 208), `execAsync` (line 243), `execFileWithCallback` (line 295), `execFileAsync` (line 302), `execShellCommand` (line 341).

**Verify**: `pnpm build` → exit 0

### Step 4: Remove dead Readline externals from NodeJs.res

In `src/infrastructure/bindings/NodeJs.res`, remove from the Readline module:
- `moveCursor` external (line 399)
- `clearLine` external (line 402)
- `cursorTo` external (lines 404–405)

Keep: `interface` type, `completer` type, `readlineInterface` type, `streamReadable` type, `streamWritable` type, `stdin`, `stdout`, `createInterface`.

**Verify**: `pnpm build` → exit 0

### Step 5: Remove dead Path externals from NodeJs.res

In `src/infrastructure/bindings/NodeJs.res`, remove from the Path module:
- `join3` external (line 67)
- `normalize` external (line 88)
- `relative` external (line 73)
- `extname` external (line 82)
- `sep` external (line 91)
- `delimiter` external (line 94)

Keep: `join` (line 64), `resolve` (line 70), `dirname` (line 76), `isAbsolute` (line 85), `basename` (line 79).

**Verify**: `pnpm build` → exit 0

### Step 6: Remove dead readline helpers from PromptResolver.res

In `src/infrastructure/prompts/PromptResolver.res`, delete lines 528–535:
```rescript
// Readline interface lifecycle
let _createReadline: unit => NodeJs.Readline.readlineInterface = () => {
  NodeJs.Readline.createInterface(~input=NodeJs.Readline.stdin, ~output=NodeJs.Readline.stdout, ())
}

let _closeReadline: NodeJs.Readline.readlineInterface => unit = rl => {
  rl.close()
}
```

**Verify**: `pnpm build` → exit 0

### Step 7: Remove dead parseError type from Manifest.res

In `src/domain/manifest/Manifest.res`, remove:
- Line 27: `@@warning("-34")`
- Lines 28–31: the `parseError` type

After removal, lines 27 onward should be:
```rescript
type validationError = {
  field: string,
  message: string,
}
```

**Verify**: `pnpm build` → exit 0

### Step 8: Run tests and confirm no stale references

Run the full test suite, then grep for removed identifiers.

**Verify**: `pnpm res:test` → all pass

**Verify**: `grep -rn "hostname\|platform\|arch\|cpus\|totalmem\|freemem\|loadavg\|uptime\|networkInterfaces\|userInfo\|cpusTimes\|cpusInfo\|networkInterfaceInfo\|userInfoOptions\|userInfoResult" src/infrastructure/bindings/NodeJs.res` → 0 matches

**Verify**: `grep -rn "Crypto\|sha256Hex\|createHash\|hashUpdate\|hashDigest" src/infrastructure/bindings/NodeJs.res` → 0 matches

**Verify**: `grep -rn "spawnOptions\|execSyncOptions\|external spawn\|external exec\b\|external execSync\|external execFileSync" src/infrastructure/bindings/NodeJs.res` → 0 matches

**Verify**: `grep -rn "moveCursor\|clearLine\|cursorTo" src/infrastructure/bindings/NodeJs.res` → 0 matches

**Verify**: `grep -rn "join3\|normalize\|relative\|extname\|external sep\|external delimiter" src/infrastructure/bindings/NodeJs.res` → 0 matches

**Verify**: `grep -rn "_createReadline\|_closeReadline" src/infrastructure/prompts/PromptResolver.res` → 0 matches

**Verify**: `grep -rn "parseError" src/domain/manifest/Manifest.res` → 0 matches

## Test plan

No new tests required — this is a pure deletion of unused code. The existing
test suite (`pnpm res:test`) verifies nothing breaks.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `pnpm build` exits 0
- [ ] `pnpm res:test` exits 0
- [ ] `grep -rn "hostname\|platform\|arch\|cpus\|totalmem\|freemem\|loadavg\|uptime\|networkInterfaces\|userInfo" src/infrastructure/bindings/NodeJs.res` returns 0 matches
- [ ] `grep -rn "Crypto" src/infrastructure/bindings/NodeJs.res` returns 0 matches
- [ ] `grep -rn "spawnOptions\|execSyncOptions\|external spawn\|external execSync\|external execFileSync" src/infrastructure/bindings/NodeJs.res` returns 0 matches
- [ ] `grep -rn "moveCursor\|clearLine\|cursorTo" src/infrastructure/bindings/NodeJs.res` returns 0 matches
- [ ] `grep -rn "join3\|normalize\|relative\|extname\|external sep\|external delimiter" src/infrastructure/bindings/NodeJs.res` returns 0 matches
- [ ] `grep -rn "_createReadline\|_closeReadline" src/infrastructure/prompts/PromptResolver.res` returns 0 matches
- [ ] `grep -rn "parseError" src/domain/manifest/Manifest.res` returns 0 matches
- [ ] No files outside the in-scope list are modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

- A step's verification fails twice after a reasonable fix attempt.
- You discover that an identifier listed as dead is actually referenced (grep shows matches in src/ or test/). In that case, do NOT remove it — report the discrepancy.
- The code at the locations in "Current state" doesn't match the excerpts (the codebase has drifted since this plan was written).

## Maintenance notes

- If new Node.js bindings are needed in the future, add them to the appropriate module in `NodeJs.res` only when a call site exists.
- The `execOptions` type in ChildProcess is shared with `NodeJsShell.res` — do not remove it.
- The `childProcess` type is the return type of `execWithCallback` and `execFileWithCallback` — do not remove it.
