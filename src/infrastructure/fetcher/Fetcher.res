/**
 * Fetcher — HTTP fetch wrapper with timeout support
 * Provides simple GET requests with error handling
 */

module Impl = {
  @val
  external _nativeFetch: (string, 'options) => promise<'response> = "fetch"

  let httpGet: (string, int) => promise<result<string, string>> = async (url, timeout) => {
    try {
      let signal = Bindings.WebApis.AbortSignal.timeout(timeout * 1000)
      let response = await _nativeFetch(url, {"method": "GET", "signal": signal})
      if (response["ok"]) {
        let content = await response["text"]()
        Ok(content)
      } else {
        Error("HTTP " ++ Int.toString(response["status"]) ++ ": " ++ response["statusText"])
      }
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
}

/**
 * Fetches content from a URL via GET request.
 *
 * @param url - The URL to fetch from
 * @param timeout - Optional timeout in seconds (default: 10)
 * @returns Ok(content) on success, Error(message) on failure
 */
let fetch: (string, ~timeout: int=?) => promise<result<string, string>> = (url, ~timeout=10) => {
  Impl.httpGet(url, timeout)
}
