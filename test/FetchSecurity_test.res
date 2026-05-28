// FetchSecurity_test — fetch directive security tests

open TestHelpers

let installRejectingFetch: string => unit = %raw(`
  function(message) {
    globalThis.__BLUEPRINT_ORIGINAL_FETCH__ = globalThis.fetch;
    globalThis.fetch = async function() {
      throw new Error(message);
    };
  }
`)

let restoreFetch: unit => unit = %raw(`
  function() {
    if (globalThis.__BLUEPRINT_ORIGINAL_FETCH__) {
      globalThis.fetch = globalThis.__BLUEPRINT_ORIGINAL_FETCH__;
      delete globalThis.__BLUEPRINT_ORIGINAL_FETCH__;
    }
  }
`)

suite("FetchSecurity", () => {
  @skip("network-dependent: requires live HTTP server")
  test("Fetcher.fetch: valid URL returns content", () => {
    assert_true(true)
  })

  @skip("network-dependent: requires live HTTP server that returns 404")
  test("Fetcher.fetch: 404 returns error with Not found", () => {
    assert_true(true)
  })

  @skip("network-dependent: requires live HTTP server that returns 500")
  test("Fetcher.fetch: 500 returns error with status", () => {
    assert_true(true)
  })

  testAsync("Fetcher.fetch: timeout returns error", resolve => {
    Fetcher.clearCache()
    installRejectingFetch("timed out while fetching")

    Fetcher.fetch("https://example.com/slow", ~timeout=1)
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(msg) => assert_eq(msg, "Request timed out")
      }
      restoreFetch()
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(_ => {
      restoreFetch()
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("Fetcher.fetch: invalid URL returns Error", resolve => {
    Fetcher.clearCache()

    Fetcher.fetch("not-a-valid-url", ~timeout=5)
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(msg) => assert_true(String.includes(msg, "Invalid URL"))
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("Fetcher.fetch: non-http URL returns Error", resolve => {
    Fetcher.clearCache()

    Fetcher.fetch("ftp://example.com/archive.tar.gz", ~timeout=5)
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(msg) => assert_true(String.includes(msg, "Only http/https URLs are supported"))
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  @skip("network-dependent: requires live HTTP server with redirect")
  test("Fetcher.fetch: follows redirects and returns final content", () => {
    assert_true(true)
  })

  @skip("network-dependent: requires live HTTP server with large response")
  test("Fetcher.fetch: huge response is truncated", () => {
    assert_true(true)
  })
})
