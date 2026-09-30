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

let installResponseSequence: array<string> => unit = %raw(`
  function(descriptors) {
    globalThis.__BLUEPRINT_ORIGINAL_FETCH__ = globalThis.fetch;
    globalThis.__BLUEPRINT_SEQUENCE__ = descriptors;
    globalThis.__BLUEPRINT_SEQUENCE_CALLS__ = [];
    globalThis.__BLUEPRINT_BODY_READS__ = 0;
    globalThis.fetch = async function(url, options) {
      globalThis.__BLUEPRINT_SEQUENCE_CALLS__.push({url, redirect: options && options.redirect});
      const descriptor = globalThis.__BLUEPRINT_SEQUENCE__[globalThis.__BLUEPRINT_SEQUENCE_CALLS__.length - 1] || "200|done";
      const [statusText, value, length] = descriptor.split("|");
      const status = Number(statusText);
      return {
        ok: status >= 200 && status < 300,
        status,
        statusText: status === 200 ? "OK" : "Redirect",
        headers: { get(name) { return name.toLowerCase() === "location" ? value : (name.toLowerCase() === "content-length" ? length : null); } },
        body: value === "stream-over-cap" ? new ReadableStream({
          start(controller) { controller.enqueue(new Uint8Array(10 * 1024 * 1024 + 1)); controller.close(); }
        }) : undefined,
        text: async function() { globalThis.__BLUEPRINT_BODY_READS__++; return value || ""; }
      };
    };
  }
`)

let getSequenceCallCount: unit => int = %raw(`
  function() { return globalThis.__BLUEPRINT_SEQUENCE_CALLS__ ? globalThis.__BLUEPRINT_SEQUENCE_CALLS__.length : 0; }
`)

let getRedirectModeForFirstCall: unit => string = %raw(`
  function() { return globalThis.__BLUEPRINT_SEQUENCE_CALLS__[0].redirect || ""; }
`)

let getBodyReadCount: unit => int = %raw(`
  function() { return globalThis.__BLUEPRINT_BODY_READS__ || 0; }
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

  testAsync("redirect to metadata IP is rejected before its fetch", resolve => {
    Fetcher.clearCache()
    installResponseSequence(["302|http://169.254.169.254/latest/meta-data"])
    Fetcher.fetch("http://8.8.8.8/start")
    ->Promise.then(result => {
      switch result {
      | Error(msg) => assert_true(String.includes(msg, "169.254.169.254"))
      | Ok(_) => assert_false(true)
      }
      assert_eq(getSequenceCallCount(), 1)
      restoreFetch()
      resolve()
      Promise.resolve()
    })->ignore
  })

  testAsync("public redirect is followed manually and returns final body", resolve => {
    Fetcher.clearCache()
    installResponseSequence(["302|http://1.1.1.1/final", "200|final body"])
    Fetcher.fetch("http://8.8.8.8/start")
    ->Promise.then(result => {
      switch result {
      | Ok(body) => assert_eq(body, "final body")
      | Error(_) => assert_false(true)
      }
      assert_eq(getSequenceCallCount(), 2)
      assert_eq(getRedirectModeForFirstCall(), "manual")
      restoreFetch()
      resolve()
      Promise.resolve()
    })->ignore
  })

  testAsync("relative redirect is resolved and guarded", resolve => {
    Fetcher.clearCache()
    installResponseSequence(["302|/final", "200|relative body"])
    Fetcher.fetch("http://8.8.8.8/start")
    ->Promise.then(result => {
      switch result {
      | Ok(body) => assert_eq(body, "relative body")
      | Error(_) => assert_false(true)
      }
      assert_eq(getSequenceCallCount(), 2)
      restoreFetch()
      resolve()
      Promise.resolve()
    })->ignore
  })

  testAsync("redirect to non-http scheme is rejected", resolve => {
    Fetcher.clearCache()
    installResponseSequence(["302|file:///etc/passwd"])
    Fetcher.fetch("http://8.8.8.8/start")
    ->Promise.then(result => {
      switch result {
      | Error(msg) => assert_true(String.includes(msg, "Only http/https"))
      | Ok(_) => assert_false(true)
      }
      assert_eq(getSequenceCallCount(), 1)
      restoreFetch()
      resolve()
      Promise.resolve()
    })->ignore
  })

  testAsync("more than five redirects are rejected", resolve => {
    Fetcher.clearCache()
    installResponseSequence([
      "302|/1", "302|/2", "302|/3", "302|/4", "302|/5", "302|/6",
    ])
    Fetcher.fetch("http://8.8.8.8/start")
    ->Promise.then(result => {
      switch result {
      | Error(msg) => assert_true(String.includes(msg, "redirect"))
      | Ok(_) => assert_false(true)
      }
      assert_eq(getSequenceCallCount(), 6)
      restoreFetch()
      resolve()
      Promise.resolve()
    })->ignore
  })

  testAsync("oversized content-length rejects without reading body", resolve => {
    Fetcher.clearCache()
    installResponseSequence(["200|large|10485761"])
    Fetcher.fetch("http://8.8.8.8/large")
    ->Promise.then(result => {
      switch result {
      | Error(msg) => assert_true(String.includes(msg, "10 MiB"))
      | Ok(_) => assert_false(true)
      }
      assert_eq(getBodyReadCount(), 0)
      restoreFetch()
      resolve()
      Promise.resolve()
    })->ignore
  })

  testAsync("unknown-length streaming body over cap is aborted", resolve => {
    Fetcher.clearCache()
    installResponseSequence(["200|stream-over-cap"])
    Fetcher.fetch("http://8.8.8.8/stream")
    ->Promise.then(result => {
      switch result {
      | Error(msg) => assert_true(String.includes(msg, "10 MiB"))
      | Ok(_) => assert_false(true)
      }
      restoreFetch()
      resolve()
      Promise.resolve()
    })->ignore
  })
})
