/**
 * Fetcher — HTTP fetch wrapper with timeout support
 */

let fetch: (string, ~timeout: int=?) => promise<result<string, string>>