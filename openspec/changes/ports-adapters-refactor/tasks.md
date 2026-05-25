# Tasks: Ports + Adapters Refactor

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~600-800 lines (many files, but mostly mechanical signature updates) |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | PR 1 (Domain/Infra) → PR 2 (App) → PR 3 (Interfaces/Tests) |
| Delivery strategy | stacked-to-main |
| Chain strategy | stacked-to-main |

Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: stacked-to-main
400-line budget risk: High

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 | Domain ports + Infra adapters | PR 1 | Base: main. Creates types and node adapters, additive. |
| 2 | Application + Infra injection | PR 2 | Base: main. Updates Engine, Phases, Config to accept ports. |
| 3 | Composition Root + Tests | PR 3 | Base: main. Wires Cli.res and updates test injections. |

## Phase 1: Domain & Infrastructure (Foundation)

- [x] 1.1 Create `src/domain/ports/Ports.res` defining `fileSystem`, `process`, `shell`, `path`, and `deps` record types.
- [x] 1.2 Create `src/infrastructure/adapters/NodeJsFileSystem.res` implementing `fileSystem` using `NodeJs.Fs` and `NodeJs.Os`.
- [x] 1.3 Create `src/infrastructure/adapters/NodeJsProcess.res` implementing `process` using `NodeJs.NodeProcess`.
- [x] 1.4 Create `src/infrastructure/adapters/NodeJsShell.res` implementing `shell` using `NodeJs.ChildProcess`.
- [x] 1.5 Create `src/infrastructure/adapters/NodeJsPath.res` implementing `path` using `NodeJs.Path`.

## Phase 2: Application Layer (Injection)

- [x] 2.1 Modify `src/application/pipeline/Phase0.res` to accept `~fs: Ports.fileSystem` and `~path: Ports.path` in `run`. Replace `Bindings` calls.
- [x] 2.2 Modify `src/application/pipeline/Phase1.res` to accept `~fs`, `~path`, `~process` in `run` and helper functions. Replace direct `NodeProcess.cwd` calls.
- [x] 2.3 Modify `src/application/pipeline/Phase2.res` to accept `~fs`, `~path`, `~process`, `~shell` in `run` and `executeShellCommands`. Replace `NodeProcess.env` direct access.
- [x] 2.4 Modify `src/application/engine/Engine.res` to accept `~deps: Ports.deps`. Destructure and pass to Phase 0/1/2.

## Phase 3: Infrastructure Layer (Injection)

- [ ] 3.1 Modify `src/infrastructure/config/Config.res` to accept `~fs`, `~path` in `loadFrom` and `saveGlobalAtPath`.
- [ ] 3.2 Modify `src/infrastructure/discovery/Discovery.res` to accept `~fs`, `~path` in `discover` and `discoverIn`.
- [x] 3.3 Modify `src/infrastructure/hooks/Hooks.res` to accept `~shell`, `~process` in `run` and `executeHook`. Also updated `Hooks.resi`.
- [ ] 3.4 Modify `src/infrastructure/path/PathSecurity.res` to accept `~path: Ports.path` instead of importing `Bindings.NodeJs.Path`.

## Phase 4: Composition Root (Interfaces)

- [ ] 4.1 Modify `src/interfaces/cli/Cli.res` to instantiate adapters (`NodeJsFileSystem.make()`, etc.).
- [ ] 4.2 Modify `src/interfaces/cli/Cli.res` to bundle adapters into a `Ports.deps` record.
- [ ] 4.3 Update `Cli.res` commands (`runGenerate`, `runInit`, etc.) to pass ports to `Engine`, `Config`, and `Discovery`. Replace direct `NodeJs.NodeProcess` calls.

## Phase 5: Test Updates

- [ ] 5.1 Update `test/Phase0_test.res` to construct and pass Node.js adapters.
- [ ] 5.2 Update `test/Phase1_test.res` to construct and pass Node.js adapters.
- [ ] 5.3 Update `test/Phase2_test.res` to construct and pass Node.js adapters.
- [ ] 5.4 Update `test/Config_test.res` to construct and pass Node.js adapters.
- [ ] 5.5 Update `test/Discovery_test.res` to construct and pass Node.js adapters.
- [ ] 5.6 Update `test/TemplateRegistry_test.res` to construct and pass Node.js adapters.
- [ ] 5.7 Update `test/Integration_test.res` to construct and pass Node.js adapters.