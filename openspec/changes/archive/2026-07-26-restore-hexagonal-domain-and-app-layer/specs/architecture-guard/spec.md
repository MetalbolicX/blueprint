# Architecture Guard Specification

## Purpose

A regression test that enforces the hexagonal boundary: the domain and
application layers MUST consume infrastructure only through `Ports`. The
guard scans authored `.res`/`.resi` sources and fails on any direct
infrastructure binding reference, preventing silent boundary regressions.

## Requirements

### Requirement: Domain Layer Isolation

Authored sources under `src/domain/**/*.res` (and `.resi`) MUST NOT contain
direct references to infrastructure bindings. The architecture-guard test
SHALL assert zero matches for each of the patterns `Bindings\.[A-Z]`,
`NodeJs\.[A-Z]`, and `Deno\.[A-Z]`.

#### Scenario: No Bindings references in domain

- GIVEN the architecture-guard test running against `src/domain/**/*.res`
- WHEN it scans for `Bindings\.[A-Z]`
- THEN zero matches are found

#### Scenario: No NodeJs references in domain

- GIVEN the architecture-guard test running against `src/domain/**/*.res`
- WHEN it scans for `NodeJs\.[A-Z]`
- THEN zero matches are found

#### Scenario: No Deno references in domain

- GIVEN the architecture-guard test running against `src/domain/**/*.res`
- WHEN it scans for `Deno\.[A-Z]`
- THEN zero matches are found

### Requirement: Application Layer Isolation

Authored sources under `src/application/**/*.res` (and `.resi`) MUST NOT
contain direct references to infrastructure bindings. The architecture-guard
test SHALL assert zero matches for each of the patterns `Bindings\.[A-Z]`,
`NodeJs\.[A-Z]`, and `Deno\.[A-Z]`.

#### Scenario: No Bindings references in application

- GIVEN the architecture-guard test running against `src/application/**/*.res`
- WHEN it scans for `Bindings\.[A-Z]`
- THEN zero matches are found

#### Scenario: No NodeJs references in application

- GIVEN the architecture-guard test running against `src/application/**/*.res`
- WHEN it scans for `NodeJs\.[A-Z]`
- THEN zero matches are found

#### Scenario: No Deno references in application

- GIVEN the architecture-guard test running against `src/application/**/*.res`
- WHEN it scans for `Deno\.[A-Z]`
- THEN zero matches are found

### Requirement: Infrastructure Layer Exemption

The `src/infrastructure/**/*.res` sources are the designated home for
runtime bindings and adapters. The architecture guard MUST exclude this
tree from its isolation assertions, so legitimate adapter code is not
flagged.

#### Scenario: Infrastructure is not scanned

- GIVEN the architecture-guard test configuration
- WHEN it enumerates scanned directories
- THEN `src/infrastructure/**` is excluded from the domain/application assertions
