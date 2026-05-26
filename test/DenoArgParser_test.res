open TestHelpers

suite("DenoArgParser adapter", () => {
  let parser = DenoArgParser.make()

  test("parse returns positionals correctly", () => {
    let args = ["foo", "bar"]
    let result = parser.parse(~args, ~strict=false, ~allowPositionals=true)
    
    switch result {
    | Ok(parsed) => {
        assert_eq(parsed.positionals, args)
      }
    | Error(_) => assert_true(false)
    }
  })

  test("parse extracts boolean flags", () => {
    let args = ["--force", "--message", "hello"]
    // util.parseArgs with strict=false and no predefined options treats flags as booleans
    // and subsequent words as positionals.
    let result = parser.parse(~args, ~strict=false, ~allowPositionals=true)
    
    switch result {
    | Ok(parsed) => {
        assert_eq(Dict.get(parsed.values, "force"), Some("true"))
        assert_eq(Dict.get(parsed.values, "message"), Some("true"))
        assert_eq(parsed.positionals, ["hello"])
      }
    | Error(_) => assert_true(false)
    }
  })

  test("parse handles known string options with space-separated values", () => {
    let args = ["--name", "Item", "--output", "src", "--force"]
    let result = parser.parse(~args, ~strict=false, ~allowPositionals=true)

    switch result {
    | Ok(parsed) => {
        assert_eq(Dict.get(parsed.values, "name"), Some("Item"))
        assert_eq(Dict.get(parsed.values, "output"), Some("src"))
        assert_eq(Dict.get(parsed.values, "force"), Some("true"))
        assert_eq(parsed.positionals, [])
      }
    | Error(_) => assert_true(false)
    }
  })
})
