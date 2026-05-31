// Fetcher_test — unit tests for HTTP fetch functionality

open TestHelpers

let installDeterministicFetchMock: unit => unit = %raw(`
  function() {
    globalThis.__BLUEPRINT_ORIGINAL_FETCH__ = globalThis.fetch;
    globalThis.__BLUEPRINT_FETCH_CALLS__ = {};
    globalThis.fetch = async function(url) {
      const calls = globalThis.__BLUEPRINT_FETCH_CALLS__;
      calls[url] = (calls[url] || 0) + 1;

      if (url === "https://httpbin.org/retry-once") {
        if (calls[url] === 1) {
          throw new Error("temporary network error");
        }

        return {
          ok: true,
          status: 200,
          statusText: "OK",
          text: async function() { return "{\"message\":\"retried\"}"; }
        };
      }

      if (url === "https://httpbin.org/transient-fail") {
        throw new Error("temporary network error");
      }

      if (url === "https://httpbin.org/get") {
        return {
          ok: true,
          status: 200,
          statusText: "OK",
          text: async function() { return "{\"origin\":\"127.0.0.1\"}"; }
        };
      }

      if (url === "https://httpbin.org/status/404") {
        return {
          ok: false,
          status: 404,
          statusText: "Not Found",
          text: async function() { return ""; }
        };
      }

      if (url === "https://httpbin.org/status/500") {
        return {
          ok: false,
          status: 500,
          statusText: "Internal Server Error",
          text: async function() { return ""; }
        };
      }

      if (url === "https://httpbin.org/delay/5") {
        throw new Error("timed out while fetching");
      }

      return {
        ok: false,
        status: 400,
        statusText: "Bad Request",
        text: async function() { return ""; }
      };
    };
  }
`)

let getFetchCallCount: string => int = %raw(`
  function(url) {
    const calls = globalThis.__BLUEPRINT_FETCH_CALLS__ || {};
    return calls[url] || 0;
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

suite("Fetcher", () => {
  testAsync("fetch: successful GET returns Ok with content", resolve => {
    Fetcher.clearCache()
    installDeterministicFetchMock()

    Fetcher.fetch("https://httpbin.org/get", ~timeout=10)
    ->Promise.then(result => {
      switch result {
      | Ok(content) => assert_true(String.includes(content, "origin"))
      | Error(_) => assert_false(true)
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

  testAsync("fetch: 404 returns Error with message", resolve => {
    Fetcher.clearCache()
    installDeterministicFetchMock()

    Fetcher.fetch("https://httpbin.org/status/404", ~timeout=10)
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(msg) => assert_true(String.includes(msg, "HTTP 404"))
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

  testAsync("fetch: transient failure retries and succeeds", resolve => {
    Fetcher.clearCache()
    installDeterministicFetchMock()

    let url = "https://httpbin.org/retry-once"
    Fetcher.fetch(url, ~timeout=10)
    ->Promise.then(result => {
      switch result {
      | Ok(content) =>
        if String.includes(content, "retried") {
          assert_eq(getFetchCallCount(url), 2)
          Fetcher.fetch(url, ~timeout=10)
          ->Promise.then(secondResult => {
            switch secondResult {
            | Ok(secondContent) => {
                assert_true(String.includes(secondContent, "retried"))
                assert_eq(getFetchCallCount(url), 2)
              }
            | Error(_) => assert_false(true)
            }
            restoreFetch()
            resolve()
            Promise.resolve()
          })
        } else {
          assert_false(true)
          restoreFetch()
          resolve()
          Promise.resolve()
        }
      | Error(_) => {
          assert_false(true)
          restoreFetch()
          resolve()
          Promise.resolve()
        }
      }
    })
    ->Promise.catch(_ => {
      restoreFetch()
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("fetch: timeout returns Error", resolve => {
    Fetcher.clearCache()
    installDeterministicFetchMock()

    Fetcher.fetch("https://httpbin.org/delay/5", ~timeout=2)
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

  testAsync("fetch: transient failure exhausts retries and surfaces final error", resolve => {
    Fetcher.clearCache()
    installDeterministicFetchMock()

    let url = "https://httpbin.org/transient-fail"
    Fetcher.fetch(url, ~timeout=10)
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(msg) => {
          assert_true(String.includes(msg, "temporary network error"))
          assert_eq(getFetchCallCount(url), 3)
        }
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

  testAsync("fetch: 404 is non-retryable and only attempts once", resolve => {
    Fetcher.clearCache()
    installDeterministicFetchMock()

    let url = "https://httpbin.org/status/404"
    Fetcher.fetch(url, ~timeout=10)
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(msg) => {
          assert_true(String.includes(msg, "HTTP 404"))
          assert_eq(getFetchCallCount(url), 1)
        }
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

  testAsync("fetch: invalid URL returns Error", resolve => {
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
})
