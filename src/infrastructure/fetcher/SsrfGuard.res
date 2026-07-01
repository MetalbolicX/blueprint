/**
 * SsrfGuard — SSRF protection for the fetch: directive.
 *
 * The fetch path is the only escape hatch from a confined generator into the
 * network. To keep it safe-by-default we treat the destination's resolved IP
 * as the trust boundary: we resolve the hostname first and refuse to ship any
 * request whose resolved address falls inside a loopback, private, link-local,
 * or cloud-metadata range. A template or manifest CANNOT widen this allowlist
 * in this slice — the public-IP rule is fixed and built-in.
 */

// Classify a single IP via Node's net module.
// net.isIP returns 0 for invalid, 4 for IPv4, 6 for IPv6. We use Bindings'
// typed wrapper instead of `require("node:net")` since the .mjs output is
// ESM where `require` is not defined.
let _classifyIp: string => string = ip => {
  switch Net.isIP(ip) {
  | 4 => "v4"
  | 6 => "v6"
  | _ => "invalid"
  }
}

// True iff the IPv4 dotted-quad string lies inside [sN..eN] on each of four
// octets. Operates on numeric octets.
let _ipv4InOctetRange: (string, int, int, int, int, int, int, int, int) => bool = (
  ip,
  s0,
  e0,
  s1,
  e1,
  s2,
  e2,
  s3,
  e3,
) => {
  let octets = ip->String.split(".")
  let len = octets->Array.length
  let get = i => {
    if i < len {
      switch octets[i] {
      | Some(s) =>
        switch Int.fromString(s) {
        | Some(n) => n
        | None => -1
        }
      | None => -1
      }
    } else {
      -1
    }
  }
  let o0 = get(0)
  let o1 = get(1)
  let o2 = get(2)
  let o3 = get(3)
  o0 >= s0 && o0 <= e0 && o1 >= s1 && o1 <= e1 && o2 >= s2 && o2 <= e2 && o3 >= s3 && o3 <= e3
}

// True iff `ip` (a normalized IPv6) starts with `hexPrefix`. Used for the
// special-purpose IPv6 ranges that share a short hex prefix.
let _ipv6StartsWith: (string, string) => bool = (ip, hexPrefix) => {
  let normalized = ip->String.toLowerCase
  let _ = normalized->String.length
  String.startsWith(normalized, hexPrefix)
}

// Public IP classifier: true iff the IP is publicly-routable.
// Returns false for: loopback, private, link-local/cloud-metadata, IPv6
// unspecified/multicast, etc. We treat unparseable addresses as NOT allowed
// (defense in depth: an attacker that slips a malformed address through URL
// parsing still gets blocked here).
let isIpAllowed: string => bool = ip => {
  switch _classifyIp(ip) {
  | "invalid" => false
  | "v4" => {
      // Reject IPv4 loopback (127.0.0.0/8), private (10/8, 172.16/12, 192.168/16),
      // link-local (169.254/16) — covers cloud metadata 169.254.169.254.
      // `_ipv4InOctetRange(ip, s0, e0, s1, e1, s2, e2, s3, e3)` requires
      // each octet to fall in [sN..eN]. The trailing octets span [0..255]
      // for the full subnet match.
      let isLoopback = _ipv4InOctetRange(ip, 127, 127, 0, 255, 0, 255, 0, 255)
      let isPrivate10 = _ipv4InOctetRange(ip, 10, 10, 0, 255, 0, 255, 0, 255)
      let isPrivate172 = _ipv4InOctetRange(ip, 172, 172, 16, 31, 0, 255, 0, 255)
      let isPrivate192 = _ipv4InOctetRange(ip, 192, 192, 168, 168, 0, 255, 0, 255)
      let isLinkLocal = _ipv4InOctetRange(ip, 169, 169, 254, 254, 0, 255, 0, 255)
      let isZero = _ipv4InOctetRange(ip, 0, 0, 0, 255, 0, 255, 0, 255)
      if isLoopback || isPrivate10 || isPrivate172 || isPrivate192 || isLinkLocal || isZero {
        false
      } else {
        true
      }
    }
| "v6" => {
      // Loopback ::1, link-local fe80::/10, unique-local fc00::/7,
      // unspecified ::, multicast ff00::/8.
      let normalized = ip->String.toLowerCase
      let isLoopback = normalized == "::1"
      let isUnspecified = normalized == "::"
      // fe80::/10 means first byte = 0xfe AND second byte's top 2 bits = "10"
      // (i.e., second nibble is 8/9/a/b).
      let isLinkLocal =
        _ipv6StartsWith(normalized, "fe8") ||
          _ipv6StartsWith(normalized, "fe9") ||
          _ipv6StartsWith(normalized, "fea") ||
          _ipv6StartsWith(normalized, "feb")
      // fc00::/7 means first byte is 1111 110x = 0xfc or 0xfd.
      let isUniqueLocal =
        _ipv6StartsWith(normalized, "fc") || _ipv6StartsWith(normalized, "fd")
      let isMulticast = _ipv6StartsWith(normalized, "ff")
      // IPv4-mapped IPv6: ::ffff:x.x.x.x — treat the trailing part as IPv4.
      let isIpv4Mapped = String.startsWith(normalized, "::ffff:")
      let ipv4Part = if isIpv4Mapped {
        String.slice(normalized, ~start=7, ~end=String.length(normalized))
      } else {
        ""
      }
      let isMappedLoopback = isIpv4Mapped && _ipv4InOctetRange(ipv4Part, 127, 127, 0, 255, 0, 255, 0, 255)
      let isMappedPrivate10 = isIpv4Mapped && _ipv4InOctetRange(ipv4Part, 10, 10, 0, 255, 0, 255, 0, 255)
      let isMappedPrivate172 = isIpv4Mapped && _ipv4InOctetRange(ipv4Part, 172, 172, 16, 31, 0, 255, 0, 255)
      let isMappedPrivate192 = isIpv4Mapped && _ipv4InOctetRange(ipv4Part, 192, 192, 168, 168, 0, 255, 0, 255)
      let isMappedLinkLocal = isIpv4Mapped && _ipv4InOctetRange(ipv4Part, 169, 169, 254, 254, 0, 255, 0, 255)
      let isMappedZero = isIpv4Mapped && _ipv4InOctetRange(ipv4Part, 0, 0, 0, 255, 0, 255, 0, 255)
      if isLoopback || isUnspecified || isLinkLocal || isUniqueLocal || isMulticast ||
        isMappedLoopback || isMappedPrivate10 || isMappedPrivate172 ||
        isMappedPrivate192 || isMappedLinkLocal || isMappedZero {
        false
      } else {
        true
      }
    }
  | _ => false
  }
}

// Pure multi-IP classifier. Returns Ok only when ALL ips are allowed.
let checkIps: (string, array<string>) => result<unit, string> = (hostname, ips) => {
  switch ips[0] {
  | None => Error("DNS resolution returned no addresses for: " ++ hostname)
  | Some(_) => {
      let bad = ips->Array.find(ip => !isIpAllowed(ip))
      switch bad {
      | Some(badIp) =>
        Error(
          "SSRF blocked: " ++ hostname ++ " resolves to " ++ badIp ++ " which is in a loopback/private/link-local/metadata range",
        )
      | None => Ok()
      }
    }
  }
}

// Parse URL hostname. We bind directly to keep SsrfGuard self-contained.
type jsUrl
@new external _makeUrl: string => jsUrl = "URL"
@get external _hostname: jsUrl => string = "hostname"

let _hostnameOf: string => option<string> = url => {
  try {
    let parsed = _makeUrl(url)
    let h = _hostname(parsed)
    if h == "" {
      None
    } else {
      // JS URL returns IPv6 hostnames wrapped in [..] (e.g. "[::1]").
      // Strip the brackets so IP classification works directly.
      let stripped = if String.startsWith(h, "[") && String.endsWith(h, "]") {
        String.slice(h, ~start=1, ~end=String.length(h) - 1)
      } else {
        h
      }
      Some(stripped)
    }
  } catch {
  | _ => None
  }
}

// Typed binding for Node's dns.lookup. The `@module("node:dns")` external
// compiles to a static ESM import at the top of the .mjs output, which is the
// ESM-safe equivalent of the previous dynamic `await import('node:dns')`.
// We use Node's net-aware dns.lookup with verbatim: true so the resolver
// returns the actual A/AAAA record (defeats DNS-rebinding middleware that
// would otherwise return an internal IP for the second connection).
type lookupAddress = {address: string}
type lookupOptions = {all: bool, verbatim: bool}

@module("node:dns")
external lookupImpl: (
  string,
  lookupOptions,
  (Nullable.t<JsExn.t>, array<lookupAddress>) => unit,
) => unit = "lookup"

let _defaultLookup: string => promise<array<string>> = host =>
  Promise.make((resolve, reject) => {
    lookupImpl(host, {all: true, verbatim: true}, (err, addresses) =>
      switch Nullable.toOption(err) {
      | Some(e) => reject(e)
      | None => resolve(addresses->Array.map(a => a.address))
      }
    )
  })

// Compose: parse URL → extract hostname → DNS-resolve → checkIps.
// Accepts an optional ~lookup function for tests; default uses Node dns.
let isUrlAllowed: (
  string,
  ~lookup: (string => promise<array<string>>)=?,
) => promise<result<unit, string>> = (url, ~lookup=?) => {
  let lk = switch lookup {
  | Some(f) => f
  | None => _defaultLookup
  }
  switch _hostnameOf(url) {
  | None => Promise.resolve(Error("Invalid URL: " ++ url))
  | Some(hostname) =>
    // If hostname is already a literal IP, skip DNS and check directly.
    if _classifyIp(hostname) !== "invalid" {
      Promise.resolve(checkIps(hostname, [hostname]))
    } else {
      lk(hostname)
      ->Promise.then(ips => Promise.resolve(checkIps(hostname, ips)))
      // Promise.catch handler receives `exn` (not JsExn.t); Obj.magic is
      // required to bridge the untyped exception payload into JsExn.t.
      ->Promise.catch(e => {
        let msg = switch JsExn.message(e->Obj.magic) {
        | Some(m) => m
        | None => "DNS lookup failed"
        }
        Promise.resolve(Error("DNS lookup failed for " ++ hostname ++ ": " ++ msg))
      })
    }
  }
}
