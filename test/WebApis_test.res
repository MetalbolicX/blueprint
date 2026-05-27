// test/WebApis_test.res
open TestHelpers

suite("WebApis", () => {
  test("AbortSignal.timeout: creates signal of correct type", () => {
    let _signal: WebApis.AbortSignal.t = WebApis.AbortSignal.timeout(5000)
    assert_true(true)
  })

  test("AbortSignal.timeout: accepts zero timeout", () => {
    let _signal: WebApis.AbortSignal.t = WebApis.AbortSignal.timeout(0)
    assert_true(true)
  })
})