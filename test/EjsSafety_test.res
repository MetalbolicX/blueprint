// EjsSafety_test — characterization tests for EjsSafety._hasUnsafeEjsTags

open TestHelpers

suite("EjsSafety", () => {
  // --- Safe: expect false ---

  test("_hasUnsafeEjsTags: plain interpolation is safe", () => {
    assert_false(EjsSafety._hasUnsafeEjsTags("<%= name %>"))
  })

  test("_hasUnsafeEjsTags: interpolation mixed with text is safe", () => {
    assert_false(EjsSafety._hasUnsafeEjsTags("hello <%= a %> world"))
  })

  test("_hasUnsafeEjsTags: plain text with no tags is safe", () => {
    assert_false(EjsSafety._hasUnsafeEjsTags("no tags"))
  })

  test("_hasUnsafeEjsTags: expression with operators is safe", () => {
    assert_false(EjsSafety._hasUnsafeEjsTags("<%= 1 + 2 %>"))
  })

  // --- Unsafe: expect true ---

  test("_hasUnsafeEjsTags: control-flow if is unsafe", () => {
    assert_true(EjsSafety._hasUnsafeEjsTags("<% if (x) %>"))
  })

  test("_hasUnsafeEjsTags: unescaped output is unsafe", () => {
    assert_true(EjsSafety._hasUnsafeEjsTags("<%- rawHtml %>"))
  })

  test("_hasUnsafeEjsTags: slurp tag (leading underscore) is unsafe", () => {
    assert_true(EjsSafety._hasUnsafeEjsTags("<%_ slurp %>"))
  })

  test("_hasUnsafeEjsTags: comment tag is unsafe", () => {
    assert_true(EjsSafety._hasUnsafeEjsTags("<%# comment %>"))
  })

  test("_hasUnsafeEjsTags: arbitrary code is unsafe", () => {
    assert_true(EjsSafety._hasUnsafeEjsTags(" <% console.log() %>"))
  })

  // --- Edge case: escaped percent ---

  test("_hasUnsafeEjsTags: escaped percent <%% is blocked (regex matches <% not followed by =-)", () => {
    // <%% is an escaped percent in EJS (expands to literal <% in output), but the
    // current blocklist regex <%(?![-=]) catches it because % is neither - nor =.
    // This is conservative: any <% not clearly <%- or <%= is treated as unsafe.
    // This is acceptable because user prompt expressions should only use <%= ... %>.
    assert_true(EjsSafety._hasUnsafeEjsTags("<%%"))
  })
})
