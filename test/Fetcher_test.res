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
    globalThis.__BLUEPRINT_BODY_CANCELS__ = 0;
    globalThis.__BLUEPRINT_CANCEL_COUNT_AT_SECOND_FETCH__ = null;
    globalThis.fetch = async function(url, options) {
      globalThis.__BLUEPRINT_SEQUENCE_CALLS__.push({url, redirect: options && options.redirect});
      if (globalThis.__BLUEPRINT_SEQUENCE_CALLS__.length === 2) {
        globalThis.__BLUEPRINT_CANCEL_COUNT_AT_SECOND_FETCH__ = globalThis.__BLUEPRINT_BODY_CANCELS__;
      }
      const descriptor = globalThis.__BLUEPRINT_SEQUENCE__[globalThis.__BLUEPRINT_SEQUENCE_CALLS__.length - 1] || "200|done";
      const [statusText, value, length, bodyMode] = descriptor.split("|");
      const status = Number(statusText);
      return {
        ok: status >= 200 && status < 300,
        status,
        statusText: status === 200 ? "OK" : (status === 500 ? "Internal Server Error" : "Redirect"),
        headers: { get(name) { return name.toLowerCase() === "location" ? value : (name.toLowerCase() === "content-length" ? length : null); } },
        body: value === "stream-over-cap" ? new ReadableStream({
          start(controller) { controller.enqueue(new Uint8Array(10 * 1024 * 1024 + 1)); controller.close(); }
        }) : bodyMode === "cancel" ? {
          cancel: async function() { globalThis.__BLUEPRINT_BODY_CANCELS__++; }
        } : bodyMode === "cancel-throws" ? {
          cancel: function() { throw new Error("cancel failed"); }
        } : undefined,
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

let getBodyCancelCount: unit => int = %raw(`
  function() { return globalThis.__BLUEPRINT_BODY_CANCELS__ || 0; }
`)

let getCancelCountAtSecondFetch: unit => int = %raw(`
  function() { return globalThis.__BLUEPRINT_CANCEL_COUNT_AT_SECOND_FETCH__; }
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

  testAsync("redirect without Location cancels the body and returns HTTP error", resolve => {
    Fetcher.clearCache()
    installResponseSequence(["302|||cancel"])
    Fetcher.fetch("http://8.8.8.8/no-location")
    ->Promise.then(result => {
      switch result {
      | Error(msg) => assert_eq(msg, "HTTP 302: Redirect")
      | Ok(_) => assert_false(true)
      }
      assert_true(getBodyCancelCount() >= 1)
      assert_eq(getBodyCancelCount(), 1)
      restoreFetch()
      resolve()
      Promise.resolve()
    })->ignore
  })

  testAsync("redirect-loop cap cancels the body and returns too-many-redirects error", resolve => {
    Fetcher.clearCache()
    installResponseSequence([
      "302|/1", "302|/2", "302|/3", "302|/4", "302|/5", "302|/6||cancel",
    ])
    Fetcher.fetch("http://8.8.8.8/loop")
    ->Promise.then(result => {
      switch result {
      | Error(msg) => assert_eq(msg, "Too many redirects (maximum 5)")
      | Ok(_) => assert_false(true)
      }
      assert_true(getBodyCancelCount() >= 1)
      assert_eq(getBodyCancelCount(), 1)
      restoreFetch()
      resolve()
      Promise.resolve()
    })->ignore
  })

  testAsync("invalid redirect URL cancels the body and returns the validation error", resolve => {
    Fetcher.clearCache()
    installResponseSequence(["302|file:///etc/passwd||cancel"])
    Fetcher.fetch("http://8.8.8.8/invalid-redirect")
    ->Promise.then(result => {
      switch result {
      | Error(msg) => assert_eq(msg, "Only http/https URLs are supported: file:///etc/passwd")
      | Ok(_) => assert_false(true)
      }
      assert_true(getBodyCancelCount() >= 1)
      assert_eq(getBodyCancelCount(), 1)
      restoreFetch()
      resolve()
      Promise.resolve()
    })->ignore
  })

  testAsync("throwing Location header cancels the body and returns invalid-Location error", resolve => {
    let location = "http://1.1.1.1:99999/path"
    Fetcher.clearCache()
    installResponseSequence(["302|" ++ location ++ "||cancel"])
    Fetcher.fetch("http://8.8.8.8/throwing-location")
    ->Promise.then(result => {
      switch result {
      | Error(msg) => assert_eq(msg, "Invalid redirect Location: " ++ location)
      | Ok(_) => assert_false(true)
      }
      assert_true(getBodyCancelCount() >= 1)
      assert_eq(getBodyCancelCount(), 1)
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

  testAsync("redirect body is cancelled before the next fetch", resolve => {
    Fetcher.clearCache()
    installResponseSequence(["301|http://1.1.1.1/final||cancel", "200|final body"])
    Fetcher.fetch("http://8.8.8.8/start")
    ->Promise.then(result => {
      switch result {
      | Ok(body) => assert_eq(body, "final body")
      | Error(_) => assert_false(true)
      }
      assert_eq(getCancelCountAtSecondFetch(), 1)
      assert_eq(getBodyCancelCount(), 1)
      restoreFetch()
      resolve()
      Promise.resolve()
    })->ignore
  })

  testAsync("non-ok response body is cancelled and returns HTTP error", resolve => {
    Fetcher.clearCache()
    installResponseSequence(["500|failure||cancel", "500|failure||cancel", "500|failure||cancel"])
    Fetcher.fetch("http://8.8.8.8/failure")
    ->Promise.then(result => {
      switch result {
      | Error(msg) => assert_true(String.includes(msg, "HTTP 500"))
      | Ok(_) => assert_false(true)
      }
      assert_eq(getBodyCancelCount(), 3)
      restoreFetch()
      resolve()
      Promise.resolve()
    })->ignore
  })

  testAsync("synchronous body cancel throw does not mask HTTP error", resolve => {
    Fetcher.clearCache()
    installResponseSequence(["500|failure||cancel-throws", "500|failure||cancel-throws", "500|failure||cancel-throws"])
    Fetcher.fetch("http://8.8.8.8/cancel-throws")
    ->Promise.then(result => {
      switch result {
      | Error(msg) => assert_true(String.includes(msg, "HTTP 500"))
      | Ok(_) => assert_false(true)
      }
      restoreFetch()
      resolve()
      Promise.resolve()
    })->ignore
  })

  testAsync("ok response body is consumed without cancelling", resolve => {
    Fetcher.clearCache()
    installResponseSequence(["200|ok body||cancel"])
    Fetcher.fetch("http://8.8.8.8/ok")
    ->Promise.then(result => {
      switch result {
      | Ok(body) => assert_eq(body, "ok body")
      | Error(_) => assert_false(true)
      }
      assert_eq(getBodyCancelCount(), 0)
      restoreFetch()
      resolve()
      Promise.resolve()
    })->ignore
  })

  testAsync("responses without a body retain existing behavior", resolve => {
    Fetcher.clearCache()
    installResponseSequence(["200|bodyless success", "404|bodyless failure"])
    Fetcher.fetch("http://8.8.8.8/bodyless-success")
    ->Promise.then(firstResult => {
      switch firstResult {
      | Ok(body) => assert_eq(body, "bodyless success")
      | Error(_) => assert_false(true)
      }
      Fetcher.clearCache()
      Fetcher.fetch("http://8.8.8.8/bodyless-failure")
      ->Promise.then(secondResult => {
        switch secondResult {
        | Error(msg) => assert_true(String.includes(msg, "HTTP 404"))
        | Ok(_) => assert_false(true)
        }
        restoreFetch()
        resolve()
        Promise.resolve()
      })
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
