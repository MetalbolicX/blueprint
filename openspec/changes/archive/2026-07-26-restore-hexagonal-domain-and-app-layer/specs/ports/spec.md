# Ports Specification

## Purpose

Defines the dependency-inversion contracts (`Ports`) that the ReScript
domain and application layers consume instead of touching infrastructure
bindings directly. Each port is a runtime-neutral interface satisfied by
both Node.js and Deno adapters.

## Requirements

### Requirement: YAML Parser Port

The system SHALL expose `Ports.yamlParser` with
`parse: string => result<JSON.t, string>`. Node.js and Deno adapters
SHALL exist and SHALL normalize thrown/rejected errors into `Error(msg)`.

#### Scenario: Valid YAML parses to JSON

- GIVEN a `yamlParser` port constructed from the Node or Deno adapter
- WHEN `parse` is called with a valid YAML string
- THEN it returns `Ok(json)` where `json` satisfies `JSON.t`

#### Scenario: Malformed YAML returns an error

- GIVEN a `yamlParser` port
- WHEN `parse` is called with malformed YAML
- THEN it returns `Error(msg)` with a non-empty message string

### Requirement: Node YAML Parser Parity

The `NodeYamlParser.parse(s)` adapter SHALL return the same JSON shape as
the pre-change `Bindings.Yaml.parse(s)` call, preserving manifest output
exactly.

#### Scenario: Adapter output matches legacy binding

- GIVEN the pre-change `Bindings.Yaml.parse` output for an input `s`
- WHEN `NodeYamlParser.parse(s)` runs on the same input
- THEN the returned `JSON.t` is structurally identical

### Requirement: EJS Port

The system SHALL expose `Ports.ejs` with two methods:
`renderString(~template, ~context) => result<string, string>` (synchronous)
and `renderFile(~path, ~context) => promise<result<string, string>>`
(asynchronous). Node.js and Deno adapters SHALL exist.

#### Scenario: renderString renders synchronously

- GIVEN an `ejs` port and a template body plus context
- WHEN `renderString` is called
- THEN it returns `Ok(rendered)` synchronously

#### Scenario: renderFile resolves asynchronously

- GIVEN an `ejs` port and a file path plus context
- WHEN `renderFile` is called
- THEN it returns a `promise` that resolves with `Ok(rendered)`

### Requirement: Filesystem Staging Port

The system SHALL expose
`Ports.fileSystem.makeStagingDir(prefix) => promise<string>`. The Node
adapter SHALL combine `os.tmpdir()` + `path.join` + `mkdir({recursive: true})`;
the Deno adapter SHALL use `Deno.makeTempDir` (or equivalent).

#### Scenario: Unique staging directory under tmpdir

- GIVEN the `makeStagingDir` port and a prefix string
- WHEN `makeStagingDir(prefix)` is called
- THEN it returns a unique directory path located under the runtime temp root

### Requirement: Deps Bundle Composition

`Ports.deps` SHALL be extended with both `yamlParser: yamlParser` and
`ejs: ejs`. When constructed for a runtime, both fields SHALL be non-null
and callable.

#### Scenario: Bundled ports are wired and callable

- GIVEN a `Ports.deps` record constructed by the CLI for the selected runtime
- WHEN the record is inspected
- THEN both `deps.yamlParser` and `deps.ejs` are non-null and callable

### Requirement: Manifest.parse Dependency Injection

`Manifest.parse` SHALL change signature from
`string => result<manifest, string>` to
`(~yamlParser: Ports.yamlParser, ~yaml: string) => result<manifest, string>`.
The body SHALL replace the `Bindings.Yaml.parse` call with `yamlParser.parse`.

#### Scenario: Valid manifest round-trips

- GIVEN a `Manifest.parse` called with a valid YAML and a configured `yamlParser`
- WHEN parse completes
- THEN it returns `Ok(manifest)` matching the pre-change output exactly

#### Scenario: Malformed YAML surfaces an error

- GIVEN a `Manifest.parse` called with malformed YAML
- WHEN parse runs
- THEN it returns an `Error`
