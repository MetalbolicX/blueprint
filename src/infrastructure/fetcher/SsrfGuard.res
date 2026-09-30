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

type ipClass = Private | Loopback | LinkLocal | Multicast | Public | Unspecified

/// Parse dotted-quad IPv4 into an array of numeric octets.
let parseIpv4 = (ip: string): array<int> => {
  ip->String.split(".")->Array.map(s =>
    switch Int.fromString(s) {
    | Some(n) => n
    | None => -1
    }
  )
}

/// Expand only an explicit :: gap; embedded IPv4 tails occupy two groups.
let parseIpv6 = (ip: string): array<string> => {
  let normalized = ip->String.toLowerCase
  let dottedParts = normalized->String.split(":")
  let last = dottedParts->Array.get(dottedParts->Array.length - 1)->Option.getOr("")
  let parts = if String.includes(last, ".") {
    let octets = parseIpv4(last)
    let high = (octets[0]->Option.getOr(0) * 256) + octets[1]->Option.getOr(0)
    let low = (octets[2]->Option.getOr(0) * 256) + octets[3]->Option.getOr(0)
    let hexGroups: array<int> => array<string> = %raw(`
      values => values.map(value => value.toString(16))
    `)
    let prefix = dottedParts->Array.slice(~start=0, ~end=dottedParts->Array.length - 1)
    Array.concat(prefix, hexGroups([high, low]))
  } else {
    dottedParts
  }
  let hasGap = String.includes(normalized, "::")
  let groups = parts->Array.filter(s => s != "")
  if hasGap {
    let zerosToAdd = 8 - groups->Array.length
    let before = ref([])
    let after = ref([])
    let gapFound = ref(false)
    parts->Array.forEach(part => {
      if part == "" {
        if !gapFound.contents { gapFound := true }
      } else if gapFound.contents {
        after := Array.concat(after.contents, [part])
      } else {
        before := Array.concat(before.contents, [part])
      }
    })
    Array.concat(Array.concat(before.contents, Array.make(~length=zerosToAdd, "0")), after.contents)
  } else {
    groups
  }
}

/// Classify an IPv4 address (as parsed octets).
let classifyIpv4 = (octets: array<int>): ipClass => {
  let get = i =>
    if i < octets->Array.length {
      switch octets[i] {
      | Some(n) => n
      | None => -1
      }
    } else {
      -1
    }
  let o0 = get(0)
  let o1 = get(1)
  let o2 = get(2)
  let o3 = get(3)

  if o0 >= 127 && o0 <= 127 && o1 >= 0 && o1 <= 255 && o2 >= 0 && o2 <= 255 && o3 >= 0 && o3 <= 255 {
    Loopback
  } else if o0 >= 10 && o0 <= 10 && o1 >= 0 && o1 <= 255 && o2 >= 0 && o2 <= 255 && o3 >= 0 && o3 <= 255 {
    Private
  } else if o0 >= 172 && o0 <= 172 && o1 >= 16 && o1 <= 31 && o2 >= 0 && o2 <= 255 && o3 >= 0 && o3 <= 255 {
    Private
  } else if o0 >= 192 && o0 <= 192 && o1 >= 168 && o1 <= 168 && o2 >= 0 && o2 <= 255 && o3 >= 0 && o3 <= 255 {
    Private
  } else if o0 >= 169 && o0 <= 169 && o1 >= 254 && o1 <= 254 && o2 >= 0 && o2 <= 255 && o3 >= 0 && o3 <= 255 {
    LinkLocal
  } else if o0 == 100 && o1 >= 64 && o1 <= 127 {
    Private
  } else if o0 >= 224 && o0 <= 239 {
    Multicast
  } else if o0 >= 240 && o0 <= 255 || (o0 == 255 && o1 == 255 && o2 == 255 && o3 == 255) {
    Multicast
  } else if o0 >= 0 && o0 <= 0 && o1 >= 0 && o1 <= 255 && o2 >= 0 && o2 <= 255 && o3 >= 0 && o3 <= 255 {
    Unspecified
  } else {
    Public
  }
}

let mappedIpv4: array<string> => option<string> = %raw(`
  function(parts) {
    if (parts.length !== 8 || parts.slice(0, 5).some(part => parseInt(part, 16) !== 0) || parseInt(parts[5], 16) !== 65535) return undefined;
    const upper = parseInt(parts[6], 16), lower = parseInt(parts[7], 16);
    return [upper >> 8, upper & 255, lower >> 8, lower & 255].join(".");
  }
`)

let isSiteLocalPrefix: string => bool = %raw(`
  function(firstGroup) {
    const value = parseInt(firstGroup, 16);
    return value >= 0xfec0 && value <= 0xfeff;
  }
`)

/// Classify an IPv6 address (as expanded 8-group parts).
let classifyIpv6 = (parts: array<string>): ipClass => {
  let len = parts->Array.length
  let get = i =>
    if i < len {
      switch parts[i] {
      | Some(s) => s
      | None => ""
      }
    } else {
      ""
    }

  // Unspecified (::)
  if len > 0 && parts->Array.every(s => s == "0") {
    Unspecified
  } 
  // Loopback (::1)
  else if len >= 2 {
    let lastPart = get(len - 1)
    let allButLast = parts->Array.slice(~start=0, ~end=len - 1)
    if allButLast->Array.every(s => s == "0") && lastPart == "1" {
      Loopback
    } else {
      // Prefix-based checks on first group
      let first = get(0)
      if String.startsWith(first, "fe8") || String.startsWith(first, "fe9") ||
         String.startsWith(first, "fea") || String.startsWith(first, "feb") {
        LinkLocal
      } else if String.startsWith(first, "fc") || String.startsWith(first, "fd") {
        Private
      } else if isSiteLocalPrefix(first) {
        Private
      } else if String.startsWith(first, "ff") {
        Multicast
      } else {
        Public
      }
    }
  } else {
    Public
  }
}

/// Normalize an IPv6 address. For IPv4-mapped IPv6 (::ffff:x.x.x.x) we extract
/// the embedded IPv4 so that Net.isIP returns 4 and classifyIpv4 handles it.
let normalizeIpv6 = (addr: string): string => {
  let normalized = addr->String.toLowerCase
  if String.startsWith(normalized, "::ffff:") {
    let len = String.length(normalized)
    String.slice(normalized, ~start=7, ~end=len)
  } else {
    normalized
  }
}

/// Policy: which IP classes are allowed for outbound fetch.
let isClassAllowed = (cls: ipClass): bool => {
  switch cls {
  | Public => true
  | _ => false
  }
}

// Public IP classifier: true iff the IP is publicly-routable.
// Returns false for: loopback, private, link-local/cloud-metadata, IPv6
// unspecified/multicast, etc. We treat unparseable addresses as NOT allowed
// (defense in depth: an attacker that slips a malformed address through URL
// parsing still gets blocked here).
let isIpAllowed: string => bool = ip => {
  let normalized = normalizeIpv6(ip)
  switch Net.isIP(normalized) {
  | 4 => parseIpv4(normalized)->classifyIpv4->isClassAllowed
  | 6 => {
      let groups = parseIpv6(normalized)
      switch mappedIpv4(groups) {
      | Some(mapped) => parseIpv4(mapped)->classifyIpv4->isClassAllowed
      | None => groups->classifyIpv6->isClassAllowed
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
        let msg = Errors.extractErrorMessage(e)
        Promise.resolve(Error("DNS lookup failed for " ++ hostname ++ ": " ++ msg))
      })
    }
  }
}
