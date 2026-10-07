/**
 * Fetcher — HTTP fetch wrapper with timeout and in-memory caching
 * Provides simple GET requests with error handling.
 * Caches results by URL to avoid duplicate fetches within a single session.
 */

// In-memory cache: keyed by URL, stores the pending promise so duplicate
// fetches (within the same Phase2.run invocation) share a single request.
let cache: Dict.t<promise<result<string, string>>> = Dict.make()
let clearCacheCount = ref(0)

type jsUrl

@new
external makeUrl: string => jsUrl = "URL"

@new
external resolveUrl: (string, string) => jsUrl = "URL"

@get
external protocol: jsUrl => string = "protocol"

@get
external href: jsUrl => string = "href"

let validateUrl: string => result<unit, string> = url => {
  try {
    let parsed = makeUrl(url)
    switch protocol(parsed) {
    | "http:" | "https:" => Ok()
    | _ => Error("Only http/https URLs are supported: " ++ url)
    }
  } catch {
  | JsExn(_) => Error("Invalid URL: " ++ url)
  }
}

module Impl = {
  @val
  external _nativeFetch: (string, 'options) => promise<'response> = "fetch"

  @val external setTimeout: (unit => unit, int) => int = "setTimeout"
  let sleepMs: int => promise<unit> = ms => Promise.make((resolve, _reject) => {
    let _ = setTimeout(() => resolve(. ()), ms)
  })

  let isRetryableError: string => bool = message => {
    let normalized = String.toLowerCase(message)
    String.startsWith(message, "HTTP 5")
    || String.includes(normalized, "timeout")
    || String.includes(normalized, "timed out")
    || String.includes(normalized, "network error")
    || String.includes(normalized, "fetch failed")
  }

  let backoffMs: int => int = attempt =>
    switch attempt {
    | 0 => 100
    | 1 => 200
    | _ => 400
    }

  let getHeader: ('response, string) => option<string> = %raw(`
    (response, name) => response.headers && response.headers.get(name) || undefined
  `)

  let readBoundedBody: 'response => promise<string> = %raw(`
    async function(response) {
      const limit = 10 * 1024 * 1024;
      const declared = response.headers && response.headers.get("content-length");
      if (declared !== null && declared !== undefined && Number(declared) > limit) {
        throw new Error("Response body exceeds 10 MiB limit");
      }
      if (!response.body || typeof response.body.getReader !== "function") {
        const text = await response.text();
        if (new TextEncoder().encode(text).length > limit) throw new Error("Response body exceeds 10 MiB limit");
        return text;
      }
      const reader = response.body.getReader();
      const chunks = [];
      let size = 0;
      while (true) {
        const item = await reader.read();
        if (item.done) break;
        size += item.value.byteLength;
        if (size > limit) {
          await reader.cancel().catch(() => {});
          throw new Error("Response body exceeds 10 MiB limit");
        }
        chunks.push(item.value);
      }
      const bytes = new Uint8Array(size);
      let offset = 0;
      for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
      return new TextDecoder().decode(bytes);
    }
  `)

  let cancelBody: 'response => promise<unit> = %raw(`
    async function(response) {
      if (response && response.body && typeof response.body.cancel === "function") {
        try { await response.body.cancel(); } catch (_) {}
      }
    }
  `)

  let redirectStatus: int => bool = status => status >= 300 && status <= 399

  let rec httpGetHop: (string, int, 'signal) => promise<result<string, string>> = async (
    url,
    redirects,
    signal,
  ) => {
    let guarded = await SsrfGuard.isUrlAllowed(url)
    switch guarded {
    | Error(message) => Error(message)
    | Ok() => {
        let response = await _nativeFetch(url, {"method": "GET", "signal": signal, "redirect": "manual"})
        let status: int = response["status"]
        if redirectStatus(status) {
          switch getHeader(response, "location") {
          | None => {
              await cancelBody(response)
              Error("HTTP " ++ Int.toString(status) ++ ": " ++ response["statusText"])
            }
          | Some(location) =>
              if redirects >= 5 {
                await cancelBody(response)
                Error("Too many redirects (maximum 5)")
              } else {
                try {
                  let nextUrl = href(resolveUrl(location, url))
                  switch validateUrl(nextUrl) {
                  | Error(message) => {
                      await cancelBody(response)
                      Error(message)
                    }
                  | Ok() => {
                      await cancelBody(response)
                      await httpGetHop(nextUrl, redirects + 1, signal)
                    }
                  }
                } catch {
                | JsExn(_) => {
                    await cancelBody(response)
                    Error("Invalid redirect Location: " ++ location)
                  }
                }
              }
          }
        } else if response["ok"] {
          Ok(await readBoundedBody(response))
        } else {
          await cancelBody(response)
          Error("HTTP " ++ Int.toString(status) ++ ": " ++ response["statusText"])
        }
      }
    }
  }

  let httpGetOnce: (string, int) => promise<result<string, string>> = async (url, timeout) => {
    try {
      let signal = Bindings.WebApis.AbortSignal.timeout(timeout * 1000)
      await httpGetHop(url, 0, signal)
    } catch {
    | JsExn(obj) =>
      let msg = switch JsExn.message(obj) {
      | Some(m) => m
      | None => "Unknown error"
      }
      if String.includes(msg, "timeout") || String.includes(msg, "timed out") {
        Error("Request timed out")
      } else {
        Error(msg)
      }
    }
  }

  let rec httpGetWithRetry: (string, int, int) => promise<result<string, string>> = async (
    url,
    timeout,
    attempt,
  ) => {
    let result = await httpGetOnce(url, timeout)
    switch result {
    | Ok(content) => Ok(content)
    | Error(message) => {
        if attempt >= 2 || !isRetryableError(message) {
          Error(message)
        } else {
          await sleepMs(backoffMs(attempt))
          await httpGetWithRetry(url, timeout, attempt + 1)
        }
      }
    }
  }

  let httpGet: (string, int) => promise<result<string, string>> = (url, timeout) =>
    httpGetWithRetry(url, timeout, 0)
}

/**
 * Clears the in-memory fetch cache. Useful between independent runs
 * to prevent stale URLs from being served across different templates.
 */
let clearCache: unit => unit = () => {
  clearCacheCount.contents = clearCacheCount.contents + 1
  let keys: array<string> = []
  cache->Dict.forEachWithKey((_v, k) => keys->Array.push(k))
  keys->Array.forEach(key => cache->Dict.delete(key))
}

let _getClearCacheCount: unit => int = () => clearCacheCount.contents

let _resetClearCacheCount: unit => unit = () => {
  clearCacheCount.contents = 0
}

/**
 * Fetches content from a URL via GET request, with caching.
 *
 * If the same URL was already fetched in this session, returns the cached result.
 * This prevents duplicate network requests when multiple templates reference
 * the same URL in a single generate run.
 *
 * @param url - The URL to fetch from
 * @param timeout - Optional timeout in seconds (default: 10)
 * @returns Ok(content) on success, Error(message) on failure
 */
let fetch: (string, ~timeout: int=?) => promise<result<string, string>> = (url, ~timeout=10) => {
  switch validateUrl(url) {
  | Error(message) => Promise.resolve(Error(message))
  | Ok() =>
    // WS3: SSRF guard — only allow public-IP destinations before network IO.
    // DNS is checked once per hop, leaving a rebinding TOCTOU before connect;
    // connect-time pinning via a custom undici dispatcher is a follow-up.
    // Cache the rejected promise too
    // so a flood of identical rejected requests still costs only one lookup.
    SsrfGuard.isUrlAllowed(url)
    ->Promise.then(guard => switch guard {
      | Error(message) => Promise.resolve(Error(message))
      | Ok() =>
        switch Dict.get(cache, url) {
        | Some(cachedPromise) => cachedPromise
        | None => {
            let promise = Impl.httpGet(url, timeout)
            Dict.set(cache, url, promise)
            promise
          }
        }
      })
  }
}
