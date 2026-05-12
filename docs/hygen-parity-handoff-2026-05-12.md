# Session Handoff

## Next Session Focus

Use Hygen's README + source code as the functional baseline to decide Fluxo's parity target and implementation order:
- Lock a parity policy (`core parity`, `selective parity`, or `full parity`).
- Convert high-priority parity gaps into a new SDD change proposal.
- Keep Fluxo's Go-native architecture (`manifest.yaml`, transactional phases) while defining migration behavior for Hygen users.

## Context & Summary

The SDD cycle for `go-template-generator` is complete and archived (proposal/spec/design/tasks/apply/verify/archive all done).

After completion, we ran a Hygen reverse-engineering pass because Hygen lacks current docs beyond README + source. Findings were captured from:
- Hygen README (raw GitHub URL).
- Hygen source (`src/`, `__tests__/`, `package.json`) for operational behavior and edge cases.

Current state:
- Fluxo has 7 implemented capabilities and passing verification in its current scope.
- Hygen parity is partial: core frontmatter + discovery + injection + shell/hook concepts are present, but several directives and workflow features are still missing.
- EJS/JS ecosystem differences are acknowledged; compatibility is possible but should be explicitly scoped (do not assume drop-in parity by default).

## Detailed Findings (Condensed)

### Already Covered in Fluxo

- Manifest parsing and validation.
- Template discovery + classification index.
- 3-phase transactional execution (prompt/collision -> stage/render/inject -> atomic commit/rollback).
- Core frontmatter directives (`to`, `inject`, `after`, `before`, `prepend`, `append`, `force`, `sh`).
- Hook lifecycle execution (`pre_generate`, `post_generate`) and bulk conflict resolution.

### High-Priority Hygen Gaps

1. Missing frontmatter controls: `skip_if`, `unless_exists`, `from`, `at_line`, `eof_last`.
2. Missing context/ergonomics: auto name variants (`name`, `Name`, `names`, `Names`), inflection helpers, config-defined helpers.
3. Missing discovery/runtime controls: `.hygenignore`, `HYGEN_TMPLS`, `HYGEN_OVERWRITE`.
4. Missing defaults pipeline: `localsDefaults`/config-driven context defaults.

### Medium-Priority Hygen Gaps

- `--dry` mode, conditional `to: null` rendering, shell stdin piping, `sh_ignore_exit`, spinner UX.
- Repo setup and messaging directives (`setup`, `echo`, `message`).

### Compatibility Positioning

- Hygen templates are `.ejs.t` + JS prompt/config hooks.
- Fluxo is Go `text/template` + manifest-driven architecture.
- Recommended stance: compatibility adapter is optional and should be a separate scoped change, not implicit behavior.

## External Artifacts

- Hygen README raw: https://raw.githubusercontent.com/jondot/hygen/refs/heads/master/README.md
- Hygen repo: https://github.com/jondot/hygen
- Previous project handoff: `docs/fluxo-handoff-2026-05-11.md`
- SDD proposal artifact: Engram `#199` (`sdd/go-template-generator/proposal`)
- SDD spec artifact: Engram `#200` (`sdd/go-template-generator/spec`)
- SDD design artifact: Engram `#201` (`sdd/go-template-generator/design`)
- SDD tasks artifact: Engram `#202` (`sdd/go-template-generator/tasks`)
- SDD verify report: Engram `#204` (`sdd/go-template-generator/verify-report`)
- SDD archive report: Engram `#205` (`sdd/go-template-generator/archive-report`)
- Hygen parity discovery: Engram `#206` (`sdd/go-template-generator/hygen-parity`)

## Suggested Skills

- `sdd-propose` (open parity follow-up change)
- `sdd-spec` (formalize missing Hygen-equivalent requirements)
- `sdd-design` (adapter strategy: EJS migration vs Go-native conversion)
- `sdd-tasks` (slice by parity priority)
- `go-testing` (cover directive behavior and edge-case parity)
- `test-driven-development` (when implementing each parity slice)
