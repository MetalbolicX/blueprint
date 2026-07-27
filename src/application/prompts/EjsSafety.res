// EjsSafety — EJS expression safety guard
// Mirrors Go version's phase0/prompt_resolver.go EJS safety checks

// Check that a template contains only interpolation tags (<%= ... %>)
// Rejects control flow (<% ... %>) and unescaped output (<%- ... %>)
let _hasUnsafeEjsTags: string => bool = template => {
  // Match any <% that is NOT followed by =
  let controlFlowPattern = RegExp.fromString("<%(?![-=])")
  // Match <%- (unescaped output)
  let unescapedPattern = RegExp.fromString("<%-")
  RegExp.test(controlFlowPattern, template) || RegExp.test(unescapedPattern, template)
}

// EJS render wrapper: the injected port's renderString is typed as
// `dict<string>`, but our eval context is a structured object
// ({context: dict<string>, answers: dict<string>}).
// This helper localises the Obj.magic cast in one named place so the unsafe
// boundary is explicit and reviewable.
let _renderEval: (~ejs: Ports.ejs, ~template: string, ~ctx: {..}) => result<string, string> =
  (~ejs, ~template, ~ctx) => {
    ejs.renderString(~template, ~context=Obj.magic(ctx))
  }
