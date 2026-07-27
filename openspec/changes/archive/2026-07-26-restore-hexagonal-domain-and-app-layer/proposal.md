# Proposal: Restore Hexagonal Domain & Application Layer Boundaries

## Intent

Phase 3 of the ports-and-adapters refactor. Five sites in the **domain** and **application** layers still call concrete infrastructure directly (`Bindings.Yaml`, `Bindings.Ejs`/`Ejs`, `NodeJs.Os`), violating hexagonal dependency inversion. This change routes every leak through the existing `Ports` interface and adds a regression guard so the boundary cannot silently regress.

**Prior art:** extends the completed `openspec/changes/ports-adapters-refactor` (`Ports.res` + `src/infrastructure/adapters/NodeJs*.res` convention).

## Scope

### In Scope
- New ports: `Ports.yamlParser`, `Ports.ejs.render`; staging-directory capability on `Ports.deps`.
- Node + Deno adapters for the new ports (following `NodeJs*.res` convention).
- Route 1 domain leak: `Manifest.parse` gains `~yamlParser` (Option A) — update `Manifest.resi` + 15 call sites (2 `src/`, 13 `test/`).
- Route 4 app leaks: `EngineLifecycle.res:34`, `Phase1.res:103`, `TemplateRenderer.res:47`, `EjsSafety.res:19`.
- Architecture-guard test: zero `Bindings.|NodeJs.|Deno.` in `src/domain/**`, `src/application/**`.

### Out of Scope
- EJS consolidation (3 render sites → 1 canonical) — deferred per user "Skip".
- Re-attempting the reverted Manifest split (phase 2).
- Touching existing port implementations beyond extension.

## Capabilities

### New Capabilities
- `ports`: Ports DI interface — full port contract set incl. `yamlParser`, `ejs`, staging-dir; invariant that domain/application consume infrastructure **only** via `Ports`.
- `architecture-guard`: regression tests enforcing zero direct infra references in domain/application layers.

### Modified Capabilities
None — `openspec/specs/` is empty (SDD bootstrapped 2026-07-23).

## Approach

Pure dependency inversion. Define port contracts in `Ports.res`; implement adapters in `src/infrastructure/adapters/`; thread `Ports.deps` through the 5 call sites. `Manifest.parse` takes an explicit `~yamlParser` argument (signature change). The guard test locks the boundary with a source scan.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `src/domain/ports/Ports.res(.resi)` | Modified | Add `yamlParser`, `ejs`, staging-dir port |
| `src/domain/manifest/Manifest.res(.resi)` | Modified | `parse` gains `~yamlParser` |
| `src/infrastructure/adapters/NodeJs*.res` (+ Deno) | New/Modified | yaml + ejs + os adapters |
| `src/application/{engine/EngineLifecycle,pipeline/Phase1,pipeline/TemplateRenderer,prompts/EjsSafety}.res` | Modified | Route via `Ports.deps` |
| `src/interfaces/cli/commands/Generator/ListCmd.res`, `src/infrastructure/discovery/Discovery.res` | Modified | Pass `yamlParser` to `Manifest.parse` |
| `test/Manifest_test.res`, `test/GeneratorWizardIntegration_test.res` | Modified | 13 call sites updated |
| `test/ArchitectureGuard_test.res` | New | Boundary regression test |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| `Manifest.parse` signature ripples to 15 sites | Med | Mechanical; compiler catches all |
| ReScript `.resi` cannot reference sibling-module types (phase-2 revert cause) | Med | Confirm `yamlParser` type is exported from `Ports.resi` in design |
| Deno adapters built without an exercised Deno target | Med | Confirm Deno is first-class before building; stub otherwise |
| ~600-800 changed lines, 400-line review budget | High | Reuse parent change's `stacked-to-main` chained-PR strategy |

## Rollback Plan

Revert the merge commit. Leaks are pre-existing and non-fatal; reverting restores prior behavior with no data or config migration. Internal wiring only — no feature flag needed.

## Dependencies

- Phases 1 (`basic-cleanup`) & 2 (`router-and-manifest-tdd`) merged.
- Established `Ports` + adapter convention from `ports-adapters-refactor`.
- Delivery forecast + chain decision deferred to `sdd-tasks` (parent forecast: High risk, `stacked-to-main`).

## Success Criteria

- [ ] `rg -n 'Bindings\.|NodeJs\.|Deno\.' src/domain src/application` → 0 matches; guard test green.
- [ ] `pnpm build` + `pnpm res:test` pass.
- [ ] `Manifest.parse` signature updated; all call sites compile.
