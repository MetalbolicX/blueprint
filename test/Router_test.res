// Router_test — unit tests for Router.extractAttributes

open TestHelpers

suite("Router extractAttributes", () => {
  test("extracts --key=value", () => {
    let result = Router.extractAttributes(~args=["--myVar=hello"])
    switch Dict.get(result, "myVar") {
    | Some(Scalar(v)) => assert_eq(v, "hello")
    | _ => assert_false(true)
    }
  })

  test("extracts --key value", () => {
    let result = Router.extractAttributes(~args=["--myVar", "hello"])
    switch Dict.get(result, "myVar") {
    | Some(Scalar(v)) => assert_eq(v, "hello")
    | _ => assert_false(true)
    }
  })

  test("extracts --key as boolean true", () => {
    let result = Router.extractAttributes(~args=["--flag"])
    switch Dict.get(result, "flag") {
    | Some(Scalar(v)) => assert_eq(v, "true")
    | _ => assert_false(true)
    }
  })

  test("skips known flags (name, force, output, help)", () => {
    let result = Router.extractAttributes(~args=["--name=foo", "--force", "--output=./dist", "--help", "--myVar=bar"])
    // name, force, output, help should NOT be in the result
    switch Dict.get(result, "name") {
    | None => assert_true(true)
    | Some(_) => assert_false(true)
    }
    switch Dict.get(result, "force") {
    | None => assert_true(true)
    | Some(_) => assert_false(true)
    }
    switch Dict.get(result, "output") {
    | None => assert_true(true)
    | Some(_) => assert_false(true)
    }
    switch Dict.get(result, "help") {
    | None => assert_true(true)
    | Some(_) => assert_false(true)
    }
    // myVar SHOULD be in the result
    switch Dict.get(result, "myVar") {
    | Some(Scalar(v)) => assert_eq(v, "bar")
    | _ => assert_false(true)
    }
  })

  test("stops parsing at -- terminator", () => {
    let result = Router.extractAttributes(~args=["--myVar=hello", "--", "--other=ignored"])
    switch Dict.get(result, "myVar") {
    | Some(Scalar(v)) => assert_eq(v, "hello")
    | _ => assert_false(true)
    }
    switch Dict.get(result, "other") {
    | None => assert_true(true)
    | Some(_) => assert_false(true)
    }
  })

  test("accumulates multiple values for the same key", () => {
    let result = Router.extractAttributes(~args=["--items=a", "--items=b", "--items=c"])
    switch Dict.get(result, "items") {
    | Some(Values(arr)) => {
        assert_eq(Array.length(arr), 3)
        switch arr[0] { | Some(v) => assert_eq(v, "a") | None => assert_false(true) }
        switch arr[1] { | Some(v) => assert_eq(v, "b") | None => assert_false(true) }
        switch arr[2] { | Some(v) => assert_eq(v, "c") | None => assert_false(true) }
      }
    | _ => assert_false(true)
    }
  })

  test("handles empty args", () => {
    let result = Router.extractAttributes(~args=[])
    assert_eq(Dict.toArray(result)->Array.length, 0)
  })

  test("handles --key= (empty string value)", () => {
    let result = Router.extractAttributes(~args=["--myVar="])
    switch Dict.get(result, "myVar") {
    | Some(Scalar(v)) => assert_eq(v, "")
    | _ => assert_false(true)
    }
  })
})
