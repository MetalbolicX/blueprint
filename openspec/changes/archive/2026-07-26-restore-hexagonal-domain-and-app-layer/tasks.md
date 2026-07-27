# Tasks: Restore Hexagonal Domain & Application Layer Boundaries

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimate | 600-800 changed lines |
| Risk / chain | High / Yes |
| Split | PR 1 ports/adapters → PR 2 injection → PR 3 wiring/guard |
| Delivery / chain strategy | ask-on-risk / stacked-to-main |

Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: stacked-to-main
400-line budget risk: High

### Suggested Work Units

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|---|---|---|---|---|---|
| 1 | Ports/adapters | PR 1 | `pnpm res:build && npx retest ./test/*Adapter_test.res.mjs` | N/A: retest is the adapter smoke | Ports and adapters |
| 2 | Manifest/app injection | PR 2 | `pnpm res:build && pnpm res:test` | N/A: no configured e2e layer | Manifest/app only |
| 3 | Wiring/guard | PR 3 | `pnpm res:build && npx retest ./test/ArchitectureGuard_test.res.mjs` | `pnpm build && node dist/main.mjs --help` | Cli, fixtures, guard |

## Phase 1: Ports & Runtime Adapters

- [ ] 1.1 F: `src/domain/ports/Ports.res` (verify no `Ports.resi`). A: YAML/EJS/staging/deps contracts. R: high; P: no; D: —.
- [ ] 1.2 F: new `src/infrastructure/adapters/{NodeJsYamlParser,NodeJsEjs}.res`; extend `src/infrastructure/bindings/{Yaml,Ejs}.res`, `NodeJs/Fs.res`, `src/infrastructure/adapters/NodeJsFileSystem.res`. A: Node validity, parity, errors, EJS sync/async, unique staging. R: high; P: yes with 1.3; D: 1.1.
- [ ] 1.3 F: new `src/infrastructure/adapters/{DenoYamlParser,DenoEjs}.res`, `src/infrastructure/bindings/DenoBindings.res`; extend `Deno.res`, `src/infrastructure/adapters/DenoFileSystem.res`. A: Deno parity, errors, EJS, temp-dir scenarios. R: high; P: yes with 1.2; D: 1.1.

## Phase 2: Dependency-Inversion Migration

- [ ] 2.1 F: `src/domain/manifest/Manifest.res`, `.resi`. A: inject parser, preserve helpers, propagate errors; valid round-trip/malformed-YAML scenarios. R: medium; P: no; D: 1.1.
- [ ] 2.2 F: `src/interfaces/cli/commands/Generator/ListCmd.res`, `src/infrastructure/discovery/Discovery.res`, `src/interfaces/cli/commands/{Generate,TemplateCopy}.res`, `test/{Discovery,TemplateRegistry}_test.res`. A: parser is threaded and valid/error manifests behave identically. R: medium; P: yes with 2.3-2.4; D: 2.1.
- [ ] 2.3 F: `test/Manifest_test.res`, `GeneratorWizardIntegration_test.res`, `test/res/TestHelpers.res`, deps fixtures. A: all 13 calls use centralized parser helper; manifest scenarios stay green. R: medium; P: yes with 2.2; D: 1.1.
- [ ] 2.4 F: `src/application/engine/EngineLifecycle.res`, `test/Engine_test.res`. A: replace `NodeJs.Os.tmpdir()` with `fs.makeStagingDir`, derive/remove probe root, retain `~tmpRoot` cleanup. R: high; P: yes with 2.5-2.7; D: 1.2.
- [ ] 2.5 F: `src/application/pipeline/Phase1.res`, `src/application/engine/{EnginePhases,EngineOrchestrator}.res`, phase tests. A: use `fs.makeStagingDir(prefix)` and preserve unique staging. R: high; P: yes with 2.4/2.6/2.7; D: 1.2.
- [ ] 2.6 F: `src/application/pipeline/{Phase1,TemplateRenderer}.res`. A: thread `Ports.ejs`; use `renderString` for inline `To(path)` (design contract), preserving context/errors. R: high; P: yes with 2.4/2.5/2.7; D: 1.2.
- [ ] 2.7 F: `src/application/{engine/EnginePhases,pipeline/Phase0,prompts/{Resolver,Expression,EjsSafety}}.res`. A: thread `deps.ejs`, remove direct EJS, preserve unsafe-tag/prompt-expression failures. R: high; P: yes with 2.4-2.6; D: 1.2.
- [ ] 2.8 F: `src/interfaces/cli/Cli.res` and all `Ports.deps` test literals. A: Node/Deno bundles expose callable YAML/EJS ports. R: medium; P: no; D: 2.2-2.7.

## Phase 3: Regression Guard & Verification

- [ ] 3.1 F: new `test/ArchitectureGuard_test.res`. A: recursively scan domain/application `.res`/`.resi`; zero `Bindings\.[A-Z]`, `NodeJs\.[A-Z]`, `Deno\.[A-Z]`; exclude infrastructure. R: medium; P: no; D: 2.1-2.8.
- [ ] 3.2 F: none (verification only). A: clean `pnpm res:build`, `pnpm build`, `pnpm res:test`; 623+ tests, adapters, and guard pass. R: medium; P: no; D: 3.1.
