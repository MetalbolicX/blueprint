/**
 * Fetcher — HTTP fetch wrapper with timeout and in-memory caching
 */

/**
 * Clears the in-memory fetch cache.
 */
let clearCache: unit => unit

let _getClearCacheCount: unit => int

let _resetClearCacheCount: unit => unit

/**
 * Fetches content from a URL via GET request, with caching.
 * Subsequent fetches of the same URL return the cached result.
 */
let fetch: (string, ~timeout: int=?) => promise<result<string, string>>
