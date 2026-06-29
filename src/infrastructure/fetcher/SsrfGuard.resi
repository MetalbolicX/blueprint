/**
 * SsrfGuard — SSRF protection for the fetch: directive.
 *
 * Public-IP-only allowlist after DNS resolution. Blocklist covers loopback,
 * private, link-local, and cloud-metadata (169.254/16 includes 169.254.169.254).
 * The IPv6 fc00::/7 unique-local range is also rejected.
 *
 * Template or manifest input cannot widen the built-in allowlist in this slice.
 */

/**
 * Pure IP classifier: true iff the IP is publicly routable.
 */
let isIpAllowed: string => bool

/**
 * Multi-IP classifier: returns Ok only when ALL ips are allowed.
 */
let checkIps: (string, array<string>) => result<unit, string>

/**
 * URL-level check: parse URL → extract hostname → DNS-resolve (uses Node's
 * dns.lookup with verbatim: true) → verify the resolved IP set is public.
 *
 * Tests can inject a custom lookup function via the `~lookup` argument to
 * cover rebinding-style scenarios deterministically.
 */
let isUrlAllowed: (
  string,
  ~lookup: (string => promise<array<string>>)=?,
) => promise<result<unit, string>>
