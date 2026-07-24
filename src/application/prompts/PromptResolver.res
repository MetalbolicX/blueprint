// PromptResolver — re-export shell for backward compatibility
// Implementation moved to sub-modules: EjsSafety, Expression, Validation, Interactive, Resolver

// Module aliases to expose sub-modules as PromptResolver.SubModule
module E = Expression
module V = Validation
module R = Resolver

// Value aliases for the main public API
let evalTemplate = E.evalTemplate
let _validateSelectInput = V._validateSelectInput
let _tokenizeMultiSelect = V._tokenizeMultiSelect
let resolve = R.resolve

// Type alias for resolveError
type resolveError = E.resolveError
