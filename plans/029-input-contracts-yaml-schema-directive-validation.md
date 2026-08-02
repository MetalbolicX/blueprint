# Plan 029: Pin YAML schema to JSON, reject unknown manifest keys, validate directive values

> **Design revision (2026-08-01)**: Steps 1 & 2 (YAML schema pin to `schema: "json"`) were abandoned.
> Orchestrator verification with `node -e` confirmed that `yaml@2.9.0`'s `schema: "json"` does NOT accept
> YAML block syntax — it requires JSON syntax and errors with "Unresolved plain scalar" on simple
> `key: value` input. The schema pin would break EVERY existing manifest/template, not just anchor-heavy ones.
> The default `core` schema is already safe from arbitrary JS-type instantiation; the pin guarded a
> near-zero risk at the cost of breaking everything. Steps 3 & 4 (unknown-key rejection + directive validation)
> proceed on their own merits and do not modify YAML parsing behavior.

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat c29f1c9..HEAD -- src/infrastructure/bindings/Yaml.res src/domain/manifest/Manifest.res src/domain/template/Frontmatter.res src/infrastructure/config/ConfigYamlBindings.res src/infrastructure/adapters/NodeJsYamlParser.res src/infrastructure/adapters/DenoYamlParser.res`
> On any mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: security
- **Planned at**: commit `c29f1c9`, 2026-08-01
- **Method**: TDD — each validator gets a failing test proving the accepted-bad input, then the fix makes it reject. The schema-pin *decision* is embedded as a spec paragraph below.

## Why this matters

All YAML/manifest/frontmatter input is currently parsed permissively and trusted
as-is: `yaml.parse` runs with no explicit schema (it relies on `yaml@2.x`'s
JSON-safe *default*, which a library upgrade or an options change could silently
widen); the manifest parser silently ignores unknown top-level keys and accepts
arbitrary structure into `metadata: dict<JSON.t>`; and directive values (`to:`,
`from:`, `fetch:`) reach path/URL builders with no early validation — containment
is enforced only downstream and indirectly. This plan makes those contracts
explicit so the safety does not depend on library defaults or caller discipline.

## Spec decision (the contract this plan establishes)

- **YAML schema is pinned to JSON** (`schema: "json"`) at every parse site. JSON
  schema allows scalars, arrays, objects — and **nothing else** (no `!!js/`,
  no anchors/aliases that expand to arbitrary types). This survives `yaml`
  major-version bumps.
- **Manifests must declare only known top-level keys.** Unknown keys are a hard
  `Error`, not a silent ignore. `metadata` stays `dict<JSON.t>` for now (it is
  pass-through data), but unknown *top-level* keys are rejected.
- **Directive values are validated at parse time.** `to:` / `from:` reject
  absolute paths and `..` segments. `fetch:` must be http/https (defense-in-depth
  with the existing SSRF guard). This duplicates the downstream containment check
  *intentionally* — early, clear errors instead of an indirect "escapes output tree".

## Current state

All line numbers verified against commit `c29f1c9`.

- `src/infrastructure/bindings/Yaml.res`:
  - Line 2 — `external parse: string => JSON.t = "parse"` (zero-arg, no schema).
  - Lines 27-31 — `documentOptions = {indent?, lineWidth?, singleQuote?}` — **no `schema` field**.
  - Line 34 — `external parseWithOptions: (string, ~options: documentOptions=?) => JSON.t` — exists but is unused and cannot pass a schema yet.
- Four parse entry points all call the zero-arg `parse`:
  - `src/infrastructure/config/ConfigYamlBindings.res:4` — `let parse = Bindings.Yaml.parse`
  - `src/infrastructure/adapters/NodeJsYamlParser.res:10` — `Ok(Bindings.Yaml.parse(yamlString))`
  - `src/infrastructure/adapters/DenoYamlParser.res:10` — `Ok(Bindings.Yaml.parse(yamlString))`
  - `src/infrastructure/manifest/ManifestYamlEditor.res:60` — `Bindings.Yaml.parse(yamlContent)` (and `parseDocument` at :52)
- `src/domain/manifest/Manifest.res`:
  - Lines 200-213 — `parse` extracts `name`/`classification`/`metadata`/`prompts` and ignores everything else.
  - Line 46 — `metadata?: dict<JSON.t>` (untyped hole — left as-is per scope).
- `src/domain/template/Frontmatter.res`:
  - Lines 22-61 — `checkDirective` accepts raw string values for `To` (line 23-24), `From` (25-26), `Fetch` (52-53), `Script` (54-55), `Tool` (50-51) with no validation.

**Repo conventions**:
- `result<'a, string>` throughout — see `Manifest.res:200` and `Frontmatter.res:22`.
- ReScript record options map field names directly to JS object keys when passed through FFI (see how `documentOptions` is already consumed by `parseWithOptions`).
- Tests in `test/`, run via `pnpm res:test`. Look for an existing `Manifest_test.res` / `Frontmatter_test.res` to model on (if absent, create).

## Commands you will need

| Purpose   | Command                          | Expected on success |
|-----------|----------------------------------|---------------------|
| Compile   | `pnpm res:build`                 | exit 0, no errors   |
| Tests     | `pnpm res:test`                  | all pass            |
| Focused   | `npx retest ./test/Manifest_test.res.mjs` (and Frontmatter) | all pass |
| Audit templates for YAML features | `rg "[&*]" _templates/ examples/` | only safe matches |

## Scope

**In scope**:
- `src/infrastructure/bindings/Yaml.res` (Step 1)
- All four parse entry points above (Step 2)
- `src/domain/manifest/Manifest.res` (Step 3)
- `src/domain/template/Frontmatter.res` (Step 4)
- New/extended tests under `test/`

**Out of scope**:
- Input **length/size limits** — previously rejected (plans/README.md:103, "negligible risk for local-CLI"). Do NOT add them.
- Changing `metadata: dict<JSON.t>` to a typed schema — deferred (could be a follow-up; touches downstream consumers).
- Any change to the SSRF guard itself (`SsrfGuard.res`) — `fetch:` scheme check here is defense-in-depth only.
- Frontmatter parsing *mechanism* (the regex parser stays; only `checkDirective` validation changes).

## Steps

### Step 1: Expose `schema` in the YAML binding (TDD)

1. **Write the failing test** (new `test/YamlBindings_test.res`): assert that parsing a YAML string containing a YAML-only feature that JSON schema forbids — e.g. an anchor/alias `a: &x 1\nb: *x` or a `!!` tag — returns a value that is *not* silently expanded. (Under `schema: "json"`, `*x` is an error or a plain string; under default it expands.) Pin the expectation to "alias does not resolve to the anchored value". Today the zero-arg `parse` resolves it.
2. **Add `schema?: string`** to `documentOptions` in `Yaml.res:27-31`.
3. **Verify**: `pnpm res:build` exit 0 (no behavior change yet — just the field exists).

### Step 2: Route every parse site through the JSON schema (TDD)

1. **Extend the failing test**: call the adapter parse (e.g. `NodeJsYamlParser.parse`) on the anchor YAML and assert the alias is **not** expanded (or parsing errors). Today it expands.
2. **Add a helper** in `Yaml.res`: `let parseJsonSafe: string => JSON.t = s => parseWithOptions(s, ~options={schema: "json"})`. (Keep `parse` for the editor's `parseDocument` path if needed, but prefer `parseJsonSafe` everywhere a manifest/config/frontmatter is read.)
3. **Switch all four entry points** to `parseJsonSafe`:
   - `ConfigYamlBindings.res:4` → `let parse = Bindings.Yaml.parseJsonSafe`
   - `NodeJsYamlParser.res:10` and `DenoYamlParser.res:10` → `Ok(Bindings.Yaml.parseJsonSafe(yamlString))`
   - `ManifestYamlEditor.res:60` → `Bindings.Yaml.parseJsonSafe(yamlContent)` (for `parseDocument` at :52, pass `{schema: "json"}` to the document options if the API supports it; if `parseDocument` does not accept schema, leave a TODO + STOP note — document mutation is a narrower path).
4. **Audit before merging**: `rg "[&*]" _templates/ examples/` and scan any test fixtures. If any real manifest uses anchors/aliases (rare), it will now fail — that is expected; convert it to explicit values. If a *published* generator depends on YAML aliases, **STOP** (see STOP conditions).
5. **Verify**: new test passes; `pnpm res:test` green; existing manifest/config fixtures still parse.

### Step 3: Reject unknown top-level manifest keys (TDD)

1. **Write the failing test** in the Manifest test file: parse `name: x\nclassification: y\nbogusField: 123` and assert the result is `Error(_)` (or carries a validation error mentioning `bogusField`). Today `parse` silently drops it.
2. **Implement** in `Manifest.parse` (`Manifest.res:200-213`): after `yamlParser.parse` succeeds, switch on `JSON.Object(dict)` and check that every key is in `{name, classification, metadata, prompts}`; collect unknown keys and return `Error("Unknown manifest fields: " ++ String.concat(", ", unknowns))` if any. Keep the existing field extraction otherwise unchanged.
3. **Verify**: new test passes; run `pnpm res:test` — if any existing manifest fixture has an extra key, update the fixture (this is the intended tightening).

### Step 4: Validate directive values at parse time (TDD)

1. **Write the failing tests** in the Frontmatter test file:
   - `to: /etc/abs` (absolute) → `checkDirective("to", "/etc/abs")` returns `Error`.
   - `to: ../escape` (parent segment) → `Error`.
   - `from: /abs/path` → `Error`.
   - `fetch: file:///etc` (non-http scheme) → `Error`.
   - `fetch: https://ok` → `Ok` (happy path still passes).
   - `to: src/x.ts` (normal relative) → `Ok`.
2. **Implement** in `Frontmatter.checkDirective` (`Frontmatter.res:22-61`):
   - Add a helper `rejectUnsafePath: string => result<string, string>` that returns `Error` if `path.isAbsolute(value)` OR the value contains a `..` path segment (split on `/`/`\` and check). Wire it into the `To` and `From` branches.
   - Add `requireHttpUrl: string => result<string, string>` that parses the URL (reuse the `new URL(...)` + `protocol` pattern from `Fetcher.res:20-30`) and returns `Error` unless `http:`/`https:`. Wire into the `Fetch` branch.
   - Leave `Tool`/`Script` as literal lookup keys (confirmed safe — they index into `.blueprint.yaml`).
3. **Verify**: new tests pass; `pnpm res:test` green.

## Test plan

- New `test/YamlBindings_test.res`: schema-pinning behavior (alias not expanded).
- Manifest test file (create or extend): unknown-key rejection, happy-path still parses.
- Frontmatter test file (create or extend): absolute/`..` path rejection for `to`/`from`; non-http `fetch` rejection; happy paths still `Ok`.
- Verification: `pnpm res:test` → all pass.

## Done criteria

- [ ] `pnpm res:build` exits 0
- [ ] `pnpm res:test` exits 0; new tests for schema-pin, unknown-key rejection, and directive validation exist and pass
- [ ] `rg "Bindings.Yaml.parse\b" src/` returns only `parseJsonSafe`/`parseWithOptions` usages (no zero-arg `parse` on manifest/config/frontmatter paths)
- [ ] `rg "documentOptions"` in `Yaml.res` shows `schema?: string`
- [ ] `rg "[&*]" _templates/ examples/` shows no manifests relying on YAML anchors/aliases
- [ ] No files outside the in-scope list are modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

- A **published** generator manifest or a fixture in `_templates/`/`examples/` legitimately relies on YAML anchors, aliases, or non-JSON-schema types — the JSON pin breaks it. Report; do not silently rewrite published artifacts (decide: convert, or keep default schema and accept the residual risk).
- `ManifestYamlEditor.res`'s `parseDocument` path cannot accept `{schema: "json"}` — report; the document-mutation path is narrower but should still be pinned or explicitly excluded with a comment.
- Rejecting unknown manifest keys breaks a fixture that intentionally tests forward-compat — confirm intent before changing the fixture.

## Maintenance notes

- The JSON schema pin makes the YAML parser **stricter than the library default**. Anyone adding a manifest field that uses YAML-native features (anchors, typed tags) will get a parse error — that is the intended guardrail.
- Directive validation duplicates the downstream `isWithinTree` containment check. This is intentional: early, clear errors at the source instead of an indirect failure deep in the pipeline. If you change one boundary, keep the other in sync.
- A reviewer should scrutinize: (a) the `..` detection handles both `/` and `\` separators, (b) the unknown-key list in `Manifest.parse` stays in sync with the `manifest` record fields (add new fields to both).
