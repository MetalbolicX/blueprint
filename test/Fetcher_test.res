// Fetcher_test — unit tests for HTTP fetch functionality

open TestHelpers

suite("Fetcher", () => {
  testAsync("fetch: successful GET returns Ok with content", resolve => {
    Fetcher.fetch("https://httpbin.org/get", ~timeout=10)
    ->Promise.then(result => {
      switch result {
      | Ok(content) =>
        // Should contain something from httpbin
        assert_true(String.length(content) > 0)
      | Error(_) => assert_false(true)
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("fetch: 404 returns Error with message", resolve => {
    Fetcher.fetch("https://httpbin.org/status/404", ~timeout=10)
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(msg) => assert_true(String.length(msg) > 0)
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("fetch: 500 returns Error with message", resolve => {
    Fetcher.fetch("https://httpbin.org/status/500", ~timeout=10)
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(msg) => assert_true(String.length(msg) > 0)
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("fetch: timeout returns Error", resolve => {
    // httpbin's delay endpoint can simulate slow responses
    Fetcher.fetch("https://httpbin.org/delay/5", ~timeout=2)
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(msg) => assert_true(String.includes(msg, "timed out") || String.includes(msg, "timeout"))
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("fetch: invalid URL returns Error", resolve => {
    Fetcher.fetch("not-a-valid-url", ~timeout=5)
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(_) => assert_true(true)
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })
})