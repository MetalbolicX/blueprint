// HookContext_test — pure stdout→attributes parser (security core)

open TestHelpers

let yamlParser = TestPorts.stubYamlParser

suite("HookContext", () => {
  // empty stdout → no-op (backward compat)
  test("parse: empty string returns empty dict", () => {
    let result = HookContext.parse(~stdout="", ~yamlParser)
    switch result {
    | Ok(dict) => assert_eq(Dict.size(dict), 0)
    | Error(_) => assert_false(true)
    }
  })

  test("parse: whitespace-only returns empty dict", () => {
    let result = HookContext.parse(~stdout="   \n\t  ", ~yamlParser)
    switch result {
    | Ok(dict) => assert_eq(Dict.size(dict), 0)
    | Error(_) => assert_false(true)
    }
  })

  // valid JSON object with all string values → merged
  test("parse: valid object with string values", () => {
    let result = HookContext.parse(~stdout="{\"a\":\"1\",\"b\":\"2\"}", ~yamlParser)
    switch result {
    | Ok(dict) => {
        assert_eq(Dict.size(dict), 2)
        switch Dict.get(dict, "a") {
        | Some(Context.Scalar(s)) => assert_eq(s, "1")
        | _ => assert_false(true)
        }
      }
    | Error(_) => assert_false(true)
    }
  })

  // non-object JSON → hard error
  test("parse: non-object JSON (array) aborts", () => {
    let result = HookContext.parse(~stdout="[1,2,3]", ~yamlParser)
    switch result {
    | Ok(_) => assert_false(true)
    | Error(msg) => assert_true(String.includes(msg, "JSON object"))
    }
  })

  test("parse: non-object JSON (string) aborts", () => {
    let result = HookContext.parse(~stdout="\"hello\"", ~yamlParser)
    switch result {
    | Ok(_) => assert_false(true)
    | Error(msg) => assert_true(String.includes(msg, "JSON object"))
    }
  })

  test("parse: non-object JSON (number) aborts", () => {
    let result = HookContext.parse(~stdout="42", ~yamlParser)
    switch result {
    | Ok(_) => assert_false(true)
    | Error(msg) => assert_true(String.includes(msg, "JSON object"))
    }
  })

  // non-string value → hard error naming the offending key
  test("parse: non-string value (number) aborts", () => {
    let result = HookContext.parse(~stdout="{\"a\":1}", ~yamlParser)
    switch result {
    | Ok(_) => assert_false(true)
    | Error(msg) => assert_true(String.includes(msg, "must be a string"))
    }
  })

  test("parse: non-string value (object) aborts", () => {
    let result = HookContext.parse(~stdout="{\"a\":{\"b\":\"c\"}}", ~yamlParser)
    switch result {
    | Ok(_) => assert_false(true)
    | Error(msg) => assert_true(String.includes(msg, "must be a string"))
    }
  })

  // reserved key → hard error naming the reserved key
  test("parse: reserved key 'name' aborts", () => {
    let result = HookContext.parse(~stdout="{\"name\":\"x\"}", ~yamlParser)
    switch result {
    | Ok(_) => assert_false(true)
    | Error(msg) => assert_true(String.includes(msg, "reserved key"))
    }
  })

  test("parse: reserved key 'Name' aborts", () => {
    let result = HookContext.parse(~stdout="{\"Name\":\"x\"}", ~yamlParser)
    switch result {
    | Ok(_) => assert_false(true)
    | Error(msg) => assert_true(String.includes(msg, "reserved key"))
    }
  })

  test("parse: reserved key 'names' aborts", () => {
    let result = HookContext.parse(~stdout="{\"names\":\"x\"}", ~yamlParser)
    switch result {
    | Ok(_) => assert_false(true)
    | Error(msg) => assert_true(String.includes(msg, "reserved key"))
    }
  })

  test("parse: reserved key 'Names' aborts", () => {
    let result = HookContext.parse(~stdout="{\"Names\":\"x\"}", ~yamlParser)
    switch result {
    | Ok(_) => assert_false(true)
    | Error(msg) => assert_true(String.includes(msg, "reserved key"))
    }
  })

  test("parse: reserved key 'h' aborts", () => {
    let result = HookContext.parse(~stdout="{\"h\":\"x\"}", ~yamlParser)
    switch result {
    | Ok(_) => assert_false(true)
    | Error(msg) => assert_true(String.includes(msg, "reserved key"))
    }
  })

  // invalid JSON → hard error
  test("parse: invalid JSON aborts", () => {
    let result = HookContext.parse(~stdout="{not json", ~yamlParser)
    switch result {
    | Ok(_) => assert_false(true)
    | Error(msg) => assert_true(String.includes(msg, "not valid JSON") || String.includes(msg, "unknown error"))
    }
  })

  // stdout > 64 KiB → hard error
  test("parse: oversized stdout (>64KiB) aborts", () => {
    let oversized = Array.make(~length=65537, "x")->Array.join("")
    let result = HookContext.parse(~stdout=oversized, ~yamlParser)
    switch result {
    | Ok(_) => assert_false(true)
    | Error(msg) => assert_true(String.includes(msg, "exceeds") && String.includes(msg, "bytes"))
    }
  })
})
