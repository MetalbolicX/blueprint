# Plan 013: Fix IPv4-mapped IPv6 SSRF guard bypass

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat bfd0397..HEAD -- src/infrastructure/fetcher/SsrfGuard.res test/SsrfGuard_test.res`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: security
- **Planned at**: commit `bfd0397`, 2026-06-29

## Why this matters

The SSRF guard blocks IPv4 private/link-local/loopback addresses but does not handle IPv4-mapped IPv6 addresses like `::ffff:127.0.0.1` or `::ffff:169.254.169.254`. An attacker crafting a URL targeting `http://[::ffff:169.254.169.254]/latest/meta-data/` would bypass the guard and exfiltrate cloud instance metadata (AWS/GCP/Azure IAM credentials, user-data scripts). The fix is a small addition to the IPv6 classification branch.

## Current state

- `src/infrastructure/fetcher/SsrfGuard.res:94-117` — The IPv6 branch blocks `::1`, `::`, `fe80::/10`, `fc00::/7`, `ff00::/8`. Addresses like `::ffff:127.0.0.1` start with `::ffff` which matches none of these prefixes, so `isIpAllowed` returns `true`.
- `src/infrastructure/fetcher/SsrfGuard.res:16-22` — `_classifyIp` calls `Net.isIP(ip)` which returns `6` for `::ffff:127.0.0.1` (valid IPv6), sending it to the `"v6"` branch.
- `test/SsrfGuard_test.res` — existing tests cover IPv4 ranges and standard IPv6 blocks; no test for `::ffff:` prefix.

## Commands you will need

| Purpose   | Command                              | Expected on success       |
|-----------|--------------------------------------|---------------------------|
| Tests     | `pnpm res:test -- SsrfGuard`        | all pass                  |
| Full test | `pnpm res:test`                      | all pass                  |

## Scope

**In scope**:
- `src/infrastructure/fetcher/SsrfGuard.res` — add `::ffff:` prefix detection
- `test/SsrfGuard_test.res` — add tests for IPv4-mapped IPv6 addresses

**Out of scope**:
- DNS rebinding TOCTOU (previously evaluated and rejected — see plans/README.md)
- Any changes to `Fetcher.res` or `Fetcher` fetch logic

## Steps

### Step 1: Add IPv4-mapped IPv6 detection to `isIpAllowed`

In `src/infrastructure/fetcher/SsrfGuard.res`, inside the `"v6"` branch of `isIpAllowed` (after line 97), add:

```rescript
// IPv4-mapped IPv6: ::ffff:x.x.x.x — treat the trailing part as IPv4.
let isIpv4Mapped =
  _ipv6StartsWith(normalized, "ffff:")
    && String.startsWith(normalized, "::")
let ipv4Part = if isIpv4Mapped {
  // Extract everything after "::ffff:" and classify as IPv4
  let afterPrefix = String.slice(normalized, ~start=6, ~end=String.length(normalized))
  afterPrefix
} else {
  ""
}
let isMappedLoopback = isIpv4Mapped && _ipv4InOctetRange(ipv4Part, 127, 127, 0, 255, 0, 255, 0, 255)
let isMappedPrivate10 = isIpv4Mapped && _ipv4InOctetRange(ipv4Part, 10, 10, 0, 255, 0, 255, 0, 255)
let isMappedPrivate172 = isIpv4Mapped && _ipv4InOctetRange(ipv4Part, 172, 172, 16, 31, 0, 255, 0, 255)
let isMappedPrivate192 = isIpv4Mapped && _ipv4InOctetRange(ipv4Part, 192, 192, 168, 168, 0, 255, 0, 255)
let isMappedLinkLocal = isIpv4Mapped && _ipv4InOctetRange(ipv4Part, 169, 169, 254, 254, 0, 255, 0, 255)
let isMappedZero = isIpv4Mapped && _ipv4InOctetRange(ipv4Part, 0, 0, 0, 255, 0, 255, 0, 255)
```

Then update the final `if` to include the mapped checks:

```rescript
if isLoopback || isUnspecified || isLinkLocal || isUniqueLocal || isMulticast
   || isMappedLoopback || isMappedPrivate10 || isMappedPrivate172
   || isMappedPrivate192 || isMappedLinkLocal || isMappedZero {
  false
} else {
  true
}
```

**Verify**: `pnpm res:test -- SsrfGuard` → all existing tests pass (no regressions)

### Step 2: Add tests for IPv4-mapped IPv6 addresses

In `test/SsrfGuard_test.res`, add a new test section after the existing IPv6 tests:

```rescript
// IPv4-mapped IPv6 bypass — these should be BLOCKED
TestHelpers.test("isIpAllowed: IPv4-mapped IPv6 loopback is blocked", () => {
  TestHelpers.assert_false(SsrfGuard.isIpAllowed("::ffff:127.0.0.1"))
})

TestHelpers.test("isIpAllowed: IPv4-mapped IPv6 cloud metadata is blocked", () => {
  TestHelpers.assert_false(SsrfGuard.isIpAllowed("::ffff:169.254.169.254"))
})

TestHelpers.test("isIpAllowed: IPv4-mapped IPv6 private 10.x is blocked", () => {
  TestHelpers.assert_false(SsrfGuard.isIpAllowed("::ffff:10.0.0.1"))
})

TestHelpers.test("isIpAllowed: IPv4-mapped IPv6 private 172.16.x is blocked", () => {
  TestHelpers.assert_false(SsrfGuard.isIpAllowed("::ffff:172.16.0.1"))
})

TestHelpers.test("isIpAllowed: IPv4-mapped IPv6 private 192.168.x is blocked", () => {
  TestHelpers.assert_false(SsrfGuard.isIpAllowed("::ffff:192.168.1.1"))
})

TestHelpers.test("isIpAllowed: IPv4-mapped IPv6 public IP is allowed", () => {
  TestHelpers.assert_true(SsrfGuard.isIpAllowed("::ffff:8.8.8.8"))
})
```

**Verify**: `pnpm res:test -- SsrfGuard` → all tests pass including 6 new ones

### Step 3: Run full test suite

**Verify**: `pnpm res:test` → all tests pass (no regressions elsewhere)

## Test plan

- 6 new tests in `test/SsrfGuard_test.res` covering:
  - `::ffff:127.0.0.1` (loopback) → blocked
  - `::ffff:169.254.169.254` (cloud metadata) → blocked
  - `::ffff:10.0.0.1` (private 10.x) → blocked
  - `::ffff:172.16.0.1` (private 172.16.x) → blocked
  - `::ffff:192.168.1.1` (private 192.168.x) → blocked
  - `::ffff:8.8.8.8` (public) → allowed
- Model after existing `SsrfGuard_test.res` test structure

## Done criteria

- [ ] `pnpm res:test -- SsrfGuard` exits 0 with all tests passing
- [ ] `pnpm res:test` exits 0 (no regressions)
- [ ] 6 new tests exist in `test/SsrfGuard_test.res`
- [ ] `grep -rn "ffff" src/infrastructure/fetcher/SsrfGuard.res` returns matches
- [ ] No files outside in-scope list are modified

## STOP conditions

- The code at `SsrfGuard.res:94-117` doesn't match the described IPv6 branch
- `pnpm res:test` fails after Step 1
- The fix requires touching files outside the in-scope list

## Maintenance notes

- If new IPv6 special-purpose ranges are added to the SSRF policy, this code must be extended
- The `_ipv4InOctetRange` helper is reused here — any bugs in it affect both IPv4 and mapped-IPv6 checks
- Future work: DNS rebinding TOCTOU was evaluated and rejected as disproportionate for a CLI tool (see plans/README.md)
