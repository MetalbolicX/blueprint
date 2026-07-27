# Design: Restore Hexagonal Domain & Application Layer Boundaries

## Technical Approach

Extend the existing `Ports` dependency bundle rather than introducing another
port family. `Cli` selects Node or Deno adapters once, then passes `Ports.deps`
through application flows. `Manifest.parse` receives a primitive YAML parser;
the manifest projection remains domain logic. The two delta specs are
`ports` (contracts and adapters) and `architecture-guard` (source-boundary
regression).

## Architecture Decisions

| Decision | Choice | Alternatives rejected / rationale |
|---|---|---|
| Staging capability | Add `makeStagingDir: string => promise<string>` to `Ports.fileSystem`. | Existing `mkdir` only creates a caller-selected path; it does not select the runtime temp root or provide unique-prefix semantics. A separate port would duplicate the existing filesystem boundary. Node uses `fs.promises.mkdtemp` under `os.tmpdir()`; Deno uses `Deno.makeTempDir`. Adapters include the timestamp in the generated `blueprint-<timestamp>-...` prefix so orphan cleanup keeps its current contract. |
| EJS contract | Add `renderString` and `renderFile` methods. `renderString` is synchronous and returns `result<string, string>`; `renderFile` preserves native file-rendering as `promise<result<string, string>>`. | One overloaded method obscures whether its input is source text or a path. `To(path)` is proven by current frontmatter/examples to be an inline target-path expression, so `TemplateRenderer` uses `renderString` and keeps its synchronous API. `EjsSafety` also uses `renderString`; its single structured-context `Obj.magic` cast is localized at that port call. |
| Deno package parity | Add `DenoBindings` wrappers over `npm:yaml` and `npm:ejs`. | Deno 2.9 exposes no `Deno.YAML`; using the same npm packages as Node avoids parser/rendering drift and is available in the installed runtime. |
| ReScript type placement | Define `yamlParser`, `ejs`, and the extended `fileSystem`/`deps` records directly in `Ports.res`. No `Ports.resi` exists today; `Manifest.resi` references `Ports.yamlParser`. | A sibling `Types` module or module-qualified type aliases in an interface file reproduces the phase-2 `.resi` failure. |

## Data Flow

```text
Cli (Node/Deno selection) -> Ports.deps
  -> Manifest.parse(~yamlParser) -> domain manifest
  -> Phase0/Resolver(~ejs) -> prompt answers
  -> Phase1(fs.makeStagingDir, ejs.renderString) -> Phase2 commit
```

`EngineLifecycle.cleanupOrphans` retains its injectable `~tmpRoot` test seam.
When omitted, it creates a short-lived staging probe through `makeStagingDir`,
derives the temp root with `path.dirname`, removes the probe, and scans that
root; this removes the last `NodeJs.Os.tmpdir` dependency without adding a
second temp-root port.

## File Changes

| File | Action | Description |
|---|---|---|
| `src/domain/ports/Ports.res` | Modify | Add YAML/EJS contracts, `makeStagingDir`, and `deps` fields. |
| `src/domain/manifest/Manifest.res(.resi)` | Modify | Inject `~yamlParser`; propagate parser errors. |
| `src/infrastructure/adapters/NodeJsYamlParser.res`, `NodeJsEjs.res`, `DenoYamlParser.res`, `DenoEjs.res` | Create | Runtime adapters; normalize thrown/rejected errors to `result`. |
| `src/infrastructure/adapters/{NodeJs,Deno}FileSystem.res`, `src/infrastructure/bindings/NodeJs/Fs.res`, `Deno.res`, `DenoBindings.res` | Modify/Create | Implement prefix-based staging creation and runtime YAML/EJS bindings. |
| `src/interfaces/cli/Cli.res` | Modify | Compose the new ports for the selected runtime. |
| `src/application/engine/{EngineLifecycle,EngineOrchestrator,EnginePhases}.res`, `src/application/pipeline/{Phase0,Phase1,TemplateRenderer}.res`, `src/application/prompts/{EjsSafety,Expression,Resolver}.res` | Modify | Thread `yamlParser`/`ejs`, stage through `fs`, and remove direct infrastructure references. |
| `src/interfaces/cli/commands/Generator/ListCmd.res`, `src/infrastructure/discovery/Discovery.res` | Modify | Pass the injected YAML parser. |
| `test/Manifest_test.res`, `test/GeneratorWizardIntegration_test.res`, `test/Ports_test.res`, `test/Engine_test.res`, `test/Phase1_test.res`, and other `Ports.deps` fixtures | Modify | Use parser/EJS/staging fakes; update all record literals and parse calls. |
| `test/ArchitectureGuard_test.res` | Create | Recursively scan authored `.res`/`.resi` files and assert no `Bindings.`, `NodeJs.`, or `Deno.` in domain/application sources. |

## Interfaces / Contracts

```rescript
type yamlParser = {parse: string => result<JSON.t, string>}
type ejs = {
  renderString: (~template: string, ~context: dict<string>) => result<string, string>,
  renderFile: (~path: string, ~context: dict<string>) => promise<result<string, string>>,
}
// fileSystem gains:
makeStagingDir: string => promise<string>
// deps gains:
yamlParser: yamlParser,
ejs: ejs,
```

## Testing Strategy

| Layer | What to Test | Approach |
|---|---|---|
| Unit | Port contracts, parser/render errors, unique staging paths, injected `Manifest.parse` | Extend `Ports_test`; adapter tests; shared test helpers. |
| Integration | Phase 0/1 use only supplied ports and preserve pipeline behavior | Existing engine/phase tests with fakes; Node and Deno adapter smoke checks. |
| Architecture | Boundary cannot regress | `ArchitectureGuard_test` source scan; RED before removing the five leaks. |
| E2E | Not available in configured OpenSpec test layers | Verify with `pnpm res:test` and `pnpm build`. |

## Threat Matrix

N/A — no routing, shell command composition, subprocess invocation, VCS/PR
automation, executable-file classification, or process-integration boundary is
changed; this is dependency injection for existing YAML, EJS, and temp-dir I/O.

## Migration / Rollout

No migration required. This is internal wiring; rollback is a source revert.

## Open Questions

None.
