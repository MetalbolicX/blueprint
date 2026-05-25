# Session Handoff: Update API Reference with New Directives

## Next Session Focus

Update `docs/api-reference.md` to document all 5 new Hygen-compatible template directives and the new `Injection.apply` signature.

## Context

Commit `340a357` on `main` implemented `from`, `unless_exists`, `at_line`, `skip_if`, `eof_last` across:
- `src/domain/template/Template.res` / `.resi` — directive variant types
- `src/domain/template/Frontmatter.res` — parsing
- `src/domain/template/Injection.res` / `.resi` — injection utilities + `~allDirectives`
- `src/application/pipeline/Phase0.res` — unless_exists exclusion
- `src/application/pipeline/Phase1.res` — from/unless_exists rendering

`docs/quick-reference.md` was already updated. `docs/api-reference.md` was only updated with the global config section — the directive table and injection modes sections are missing the new directives.

## Changes Required

### 1. Directive table (api-reference.md ~line 70)

Insert after line 71 (`inject:` row):

```
| `from` | string | inject | External file path used as template body |
| `unless_exists` | bool | all | Skip render when target file already exists |
| `at_line` | int | inject | Insert rendered content at specific line (1-based) |
| `skip_if` | regex | inject | Skip injection when regex matches existing content |
| `eof_last` | bool | all | Trim trailing newline from injected payload |
```

### 2. Injection modes table (api-reference.md ~line 83)

After the `append: true` row, add:

```
| `at_line:` | Insert rendered content at a specific line number | No |
| `skip_if:` | Skip injection if existing content matches regex | Requires another injection directive |
| `eof_last: true` | Trim trailing newline from rendered content | Modifier (paired with other directives) |
```

### 3. Add "Combined directives" subsection

After the injection modes table, add a note:

```
Directives like `skip_if`, `eof_last`, and `unless_exists` combine with other injection directives
via the `~allDirectives` parameter on `Injection.apply`.
```

### 4. Update `Injection.apply` signature

Replace:
```
Injection.apply(~existingContent, ~renderedContent, ~directive)
```
with:
```
Injection.apply(~existingContent, ~renderedContent, ~directive, ~allDirectives=?)
```

### 5. Update injection modes intro sentence (line 81)

Change to include new modes:

```
When `inject`, `after`, `before`, `prepend`, `append`, or `at_line` is set...
```

## Reference

- `docs/quick-reference.md` — already updated, mirror descriptions and phrasing
- `src/domain/template/Injection.res` — `apply` function with `~allDirectives`
- `src/domain/template/Template.res` — directive type definitions (canonical descriptions)

## Suggested Skills

- cognitive-doc-design
- Docsify Documentation Editor
