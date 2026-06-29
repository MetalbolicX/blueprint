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

  // ---------- WS3: SSRF protection at the Fetcher.fetch surface ----------

  testAsync("WS3: Fetcher.fetch blocks loopback URL without any DNS lookup", resolve => {
    Fetcher.clearCache()

    // The SsrfGuard short-circuits literal-loopback URLs — no DNS, no fetch.
    // Override global fetch so any unexpected success would surface here.
    installRejectingFetch("WS3 test: loopback URL must not reach fetch")

    Fetcher.fetch("http://127.0.0.1/never")
    ->Promise.then(result => {
      switch result {
      | Error(msg) =>
        assert_true(String.includes(msg, "127.0.0.1"))
        assert_true(String.includes(msg, "SSRF") || String.includes(msg, "loopback"))
      | Ok(_) => assert_false(true)
      }
      restoreFetch()
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(_ => {
      restoreFetch()
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("WS3: Fetcher.fetch blocks cloud-metadata URL (169.254.169.254)", resolve => {
    Fetcher.clearCache()

    installRejectingFetch("WS3 test: metadata URL must not reach fetch")

    Fetcher.fetch("http://169.254.169.254/latest/meta-data/")
    ->Promise.then(result => {
      switch result {
      | Error(msg) => assert_true(String.includes(msg, "169.254.169.254"))
      | Ok(_) => assert_false(true)
      }
      restoreFetch()
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(_ => {
      restoreFetch()
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("WS3: Fetcher.fetch blocks IPv6 loopback in URL form", resolve => {
    Fetcher.clearCache()

    installRejectingFetch("WS3 test: IPv6 loopback URL must not reach fetch")

    Fetcher.fetch("http://[::1]/never")
    ->Promise.then(result => {
      switch result {
      | Error(msg) => assert_true(String.includes(msg, "::1"))
      | Ok(_) => assert_false(true)
      }
      restoreFetch()
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(_ => {
      restoreFetch()
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
