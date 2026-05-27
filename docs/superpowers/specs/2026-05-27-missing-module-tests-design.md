# Design: Missing Module Test Coverage

## Goal

Add unit/integration tests for the 10 ReScript source files that currently lack test coverage, reaching ~100% coverage for the `src/` directory.

## Scope

### Files to cover

| File | Category | Reason |
|------|----------|--------|
| `src/infrastructure/config/ConfigStore.res` | Integration | I/O operations (file system, path resolution) |
| `src/domain/config/ConfigTypes.res` | Unit | Pure type defaults, no I/O |
| `src/infrastructure/bindings/Bindings.res` | Smoke | Re-export aggregation, compile-time check |
| `src/infrastructure/bindings/WebApis.res` | Contract | External Web API bindings |
| `src/infrastructure/adapters/Runtime.res` | Contract | Runtime detection (`isDeno`), pure boolean |
| `src/domain/ports/Ports.res` | Contract | Type definitions / interface contracts |
| `src/infrastructure/bindings/Ejs.res` | Integration | External template library bindings |
| `src/interfaces/cli/Main.res` | Smoke | CLI entry point, no logic |
| Node/Deno adapters (remaining) | Integration | Per-adapter behavior tests |

## Strategy

### Unit Tests (pure logic, no I/O)
- **ConfigTypes**: Instantiate `defaultGlobalConfig` and assert all field values match expected defaults. Verify type constructors produce well-formed records.
- **Ports**: Verify adapter implementations satisfy port contracts by checking field presence and types at runtime.

### Contract/Integration Tests (has I/O or external deps)
- **ConfigStore**: Create in-memory `fileSystem` and `path` stubs; test `_globalConfigPath` path resolution, `saveGlobal`/`loadGlobal` round-trip, `loadFrom` file discovery.
- **Ejs**: Call `Bindings.Ejs.render` with known dict → assert output string contains expected rendered content. Test `renderFile` happy path.
- **WebApis**: Verify `AbortSignal.timeout` creates a signal of correct type that can be used for cancellation.
- **Runtime**: Call `Runtime.isDeno()` → assert it returns a boolean and behaves deterministically (consistent across multiple calls).
- **Bindings**: Smoke test — access each submodule namespace to confirm re-exports are valid.
- **Main**: Evaluate the IIFE entry point → assert no exception is thrown.

### Adapter Tests
- Follow existing patterns from `NodeJsShell_test.res`, `DenoFileSystem_test.res`, etc.
- Happy path + error cases per adapter.

## Test File Naming

- `ConfigStore_test.res`
- `ConfigTypes_test.res`
- `Bindings_test.res`
- `WebApis_test.res`
- `Runtime_test.res`
- `Ports_test.res`
- `Ejs_test.res`
- `Main_test.res`

## Notes

- All tests follow existing `retest` conventions: `suite()`, `test()`, `testAsync()`.
- Helper assertions from `test/res/TestHelpers.res` (`assert_eq`, `assert_true`, `assert_false`) are reused.
- Integration tests use `NodeJs.Os.makeStagingDir()` for temp directory isolation.
- No existing tests are modified or removed.