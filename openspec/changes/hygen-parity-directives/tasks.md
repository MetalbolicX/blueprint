# Tasks: Hygen Parity Directives

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | 180-260 |
| 400-line budget risk | Low |
| Chained PRs recommended | No |
| Suggested split | Single implementation batch |
| Delivery strategy | single-pr |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: N/A
400-line budget risk: Low

## Phase 1: Directive Model & Parsing

- [x] 1.1 Add `from`, `unless_exists`, `at_line`, `skip_if`, `eof_last` variants in `Template.res` and `Template.resi`
- [x] 1.2 Parse new directives in `Frontmatter.res`

## Phase 2: Injection Behavior

- [x] 2.1 Add `insertAtLine` utility for line-index insertion
- [x] 2.2 Add `shouldSkip` regex guard utility
- [x] 2.3 Add `trimTrailingNewline` utility for `eof_last`
- [x] 2.4 Extend `Injection.apply` to support combined behavior via `~allDirectives`

## Phase 3: Pipeline Integration

- [x] 3.1 Add `unless_exists` exclusion in Phase0 conflict detection
- [x] 3.2 Add `from` external body loading in Phase1 rendering
- [x] 3.3 Add `unless_exists` skip behavior in Phase1 render pass

## Phase 4: Test Coverage

- [x] 4.1 Add variant tests in `Template_test.res`
- [x] 4.2 Add parser tests in `Frontmatter_test.res`
- [x] 4.3 Add injection utility + combined-behavior tests in `Injection_test.res`
- [x] 4.4 Add Phase0/Phase1 behavior tests for `unless_exists` and `from`

## Phase 5: Documentation

- [x] 5.1 Update directive table and API note in `docs/quick-reference.md`
