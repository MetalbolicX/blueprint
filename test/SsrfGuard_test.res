// SsrfGuard_test — WS3 SSRF protection coverage.
// Exercises the pure IP classifier and the checkIps multi-IP aggregator, plus
// a rebinding-style scenario where isUrlAllowed is fed a hostname whose mocked
// DNS returns an array mixing public and loopback/private addresses.

open TestHelpers

suite("SsrfGuard.isIpAllowed", () => {
  // Public IPv4 hosts — cloud DNS and major CDNs. Must NOT be in the SSRF list.
  test("8.8.8.8 (Google public DNS) → true", () => {
    assert_true(SsrfGuard.isIpAllowed("8.8.8.8"))
  })

  test("1.1.1.1 (Cloudflare public DNS) → true", () => {
    assert_true(SsrfGuard.isIpAllowed("1.1.1.1"))
  })

  test("93.184.216.34 (example.com) → true", () => {
    assert_true(SsrfGuard.isIpAllowed("93.184.216.34"))
  })

  // IPv4 loopback.
  test("127.0.0.1 (IPv4 loopback) → false", () => {
    assert_false(SsrfGuard.isIpAllowed("127.0.0.1"))
  })

  test("127.255.255.254 (high-end of 127.0.0.0/8) → false", () => {
    assert_false(SsrfGuard.isIpAllowed("127.255.255.254"))
  })

  // IPv4 private ranges.
  test("10.0.0.1 (RFC1918 10/8) → false", () => {
    assert_false(SsrfGuard.isIpAllowed("10.0.0.1"))
  })

  test("172.16.0.1 (RFC1918 172.16/12 lower bound) → false", () => {
    assert_false(SsrfGuard.isIpAllowed("172.16.0.1"))
  })

  test("172.31.255.254 (RFC1918 172.16/12 upper bound) → false", () => {
    assert_false(SsrfGuard.isIpAllowed("172.31.255.254"))
  })

  test("192.168.0.1 (RFC1918 192.168/16) → false", () => {
    assert_false(SsrfGuard.isIpAllowed("192.168.0.1"))
  })

  // IPv4 link-local — covers cloud metadata 169.254.169.254.
  test("169.254.169.254 (AWS/GCP cloud metadata) → false", () => {
    assert_false(SsrfGuard.isIpAllowed("169.254.169.254"))
  })

  test("169.254.0.1 (lower bound of 169.254/16) → false", () => {
    assert_false(SsrfGuard.isIpAllowed("169.254.0.1"))
  })

  // IPv4 zero.
  test("0.0.0.0 → false (unspecified)", () => {
    assert_false(SsrfGuard.isIpAllowed("0.0.0.0"))
  })

  // IPv6 loopback + unspecified.
  test("::1 (IPv6 loopback) → false", () => {
    assert_false(SsrfGuard.isIpAllowed("::1"))
  })

  test(":: (IPv6 unspecified) → false", () => {
    assert_false(SsrfGuard.isIpAllowed("::"))
  })

  // IPv6 unique-local fc00::/7 covers fc00:: and fd00:: ranges.
  test("fc00::1 (IPv6 unique-local lower) → false", () => {
    assert_false(SsrfGuard.isIpAllowed("fc00::1"))
  })

  test("fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff (IPv6 unique-local upper) → false", () => {
    assert_false(SsrfGuard.isIpAllowed("fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff"))
  })

  // IPv6 link-local fe80::/10.
  test("fe80::1 (IPv6 link-local) → false", () => {
    assert_false(SsrfGuard.isIpAllowed("fe80::1"))
  })

  test("febf:ffff:: (link-local upper) → false", () => {
    assert_false(SsrfGuard.isIpAllowed("febf:ffff::"))
  })

  // IPv6 multicast ff00::/8.
  test("ff02::1 (IPv6 multicast all-nodes) → false", () => {
    assert_false(SsrfGuard.isIpAllowed("ff02::1"))
  })

  // Public IPv6 — Google.
  test("2001:4860:4860::8888 (Google IPv6 DNS) → true", () => {
    assert_true(SsrfGuard.isIpAllowed("2001:4860:4860::8888"))
  })

  // Unparseable addresses are treated as not-allowed.
  test("not-an-ip → false", () => {
    assert_false(SsrfGuard.isIpAllowed("not-an-ip"))
  })

  test("999.999.999.999 → false", () => {
    assert_false(SsrfGuard.isIpAllowed("999.999.999.999"))
  })

  // Boundary edge: 172.32.0.1 is OUTSIDE 172.16/12 — public.
  test("172.32.0.1 (just past RFC1918 172.16/12) → true", () => {
    assert_true(SsrfGuard.isIpAllowed("172.32.0.1"))
  })

  // Boundary edge: 172.15.255.255 is OUTSIDE 172.16/12 — public.
  test("172.15.255.255 (just before RFC1918 172.16/12) → true", () => {
    assert_true(SsrfGuard.isIpAllowed("172.15.255.255"))
  })

  // IPv4-mapped IPv6 bypass — these should be BLOCKED.
  test("::ffff:127.0.0.1 (IPv4-mapped IPv6 loopback) → false", () => {
    assert_false(SsrfGuard.isIpAllowed("::ffff:127.0.0.1"))
  })

  test("::ffff:169.254.169.254 (IPv4-mapped IPv6 cloud metadata) → false", () => {
    assert_false(SsrfGuard.isIpAllowed("::ffff:169.254.169.254"))
  })

  test("::ffff:10.0.0.1 (IPv4-mapped IPv6 private 10/8) → false", () => {
    assert_false(SsrfGuard.isIpAllowed("::ffff:10.0.0.1"))
  })

  test("::ffff:172.16.0.1 (IPv4-mapped IPv6 private 172.16/12) → false", () => {
    assert_false(SsrfGuard.isIpAllowed("::ffff:172.16.0.1"))
  })

  test("::ffff:192.168.1.1 (IPv4-mapped IPv6 private 192.168/16) → false", () => {
    assert_false(SsrfGuard.isIpAllowed("::ffff:192.168.1.1"))
  })

  test("::ffff:8.8.8.8 (IPv4-mapped IPv6 public IP) → true", () => {
    assert_true(SsrfGuard.isIpAllowed("::ffff:8.8.8.8"))
  })
})

suite("SsrfGuard.checkIps", () => {
  test("empty list → Error", () => {
    switch SsrfGuard.checkIps("example.com", []) {
    | Error(msg) => assert_true(String.includes(msg, "no addresses"))
    | Ok() => assert_false(true)
    }
  })

  test("all-public IPs → Ok", () => {
    switch SsrfGuard.checkIps("dns.google", ["8.8.8.8", "1.1.1.1"]) {
    | Ok() => ()
    | Error(_) => assert_false(true)
    }
  })

  test("mix of public + 127.0.0.1 → Error referencing the bad IP", () => {
    switch SsrfGuard.checkIps("attacker.example", ["8.8.8.8", "127.0.0.1"]) {
    | Error(msg) => assert_true(String.includes(msg, "127.0.0.1"))
    | Ok() => assert_false(true)
    }
  })

  test("mix including 169.254.169.254 → Error mentioning it", () => {
    switch SsrfGuard.checkIps("cloud.example", ["1.1.1.1", "169.254.169.254"]) {
    | Error(msg) => assert_true(String.includes(msg, "169.254.169.254"))
    | Ok() => assert_false(true)
    }
  })

  test("rebinding-style: hostname returns public + IPv6 loopback → reject", () => {
    switch SsrfGuard.checkIps("rebinder.example", ["8.8.8.8", "::1"]) {
    | Error(msg) => assert_true(String.includes(msg, "::1"))
    | Ok() => assert_false(true)
    }
  })

  test("rebinding-style: hostname returns public + IPv6 unique-local → reject", () => {
    switch SsrfGuard.checkIps("rebinder.example", ["2001:4860:4860::8888", "fc00::1"]) {
    | Error(msg) => assert_true(String.includes(msg, "fc00::1"))
    | Ok() => assert_false(true)
    }
  })
})

suite("SsrfGuard.isUrlAllowed", () => {
  testAsync("public hostname + mocked public DNS lookup → Ok", resolve => {
    SsrfGuard.isUrlAllowed("https://example.com/data", ~lookup=_ => Promise.resolve(["8.8.8.8"]))
    ->Promise.then(result => {
      switch result {
      | Ok() => ()
      | Error(_msg) => assert_true(false)
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("hostname that resolves to 169.254.169.254 → Error (metadata blocked)", resolve => {
    // Simulates an attacker controlling a public hostname whose DNS returns the
    // AWS metadata IP — this is the classic DNS-rebinding attack.
    SsrfGuard.isUrlAllowed(
      "https://attacker.example/payload",
      ~lookup=_ => Promise.resolve(["169.254.169.254"]),
    )
    ->Promise.then(result => {
      switch result {
      | Error(msg) => assert_true(String.includes(msg, "169.254.169.254"))
      | Ok() => assert_false(true)
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("rebinding-style resolution with mixed public + loopback → Error", resolve => {
    // First IP is public, second is loopback — even one bad IP rejects the
    // request. This is the rebinding case where the resolver first returns
    // a public IP but the connection-time lookup returns internal.
    SsrfGuard.isUrlAllowed(
      "https://rebinder.example/api",
      ~lookup=_ => Promise.resolve(["1.1.1.1", "127.0.0.1"]),
    )
    ->Promise.then(result => {
      switch result {
      | Error(msg) => assert_true(String.includes(msg, "127.0.0.1"))
      | Ok() => assert_false(true)
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("DNS failure surfaces as Error with hostname context", resolve => {
    let failingLookup = _ => Promise.reject(Obj.magic({"message": "ENOTFOUND example.invalid"}))
    SsrfGuard.isUrlAllowed("https://example.invalid/", ~lookup=failingLookup)
    ->Promise.then(result => {
      switch result {
      | Error(msg) =>
        assert_true(String.includes(msg, "DNS lookup failed"))
        assert_true(String.includes(msg, "example.invalid"))
      | Ok() => assert_false(true)
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("literal IPv4 in URL is checked directly without DNS", resolve => {
    // http://127.0.0.1/ should reject without DNS — confirm by passing a
    // lookup that would otherwise allow the request through.
    SsrfGuard.isUrlAllowed(
      "http://127.0.0.1/admin",
      ~lookup=_ => Promise.resolve(["8.8.8.8"]),
    )
    ->Promise.then(result => {
      switch result {
      | Error(msg) => assert_true(String.includes(msg, "127.0.0.1"))
      | Ok() => assert_false(true)
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("literal IPv6 loopback in URL is rejected without DNS", resolve => {
    SsrfGuard.isUrlAllowed(
      "http://[::1]/api",
      ~lookup=_ => Promise.resolve(["8.8.8.8"]),
    )
    ->Promise.then(result => {
      switch result {
      | Error(msg) => assert_true(String.includes(msg, "::1"))
      | Ok() => assert_false(true)
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("invalid URL surfaces Invalid URL error", resolve => {
    SsrfGuard.isUrlAllowed("not a url at all")
    ->Promise.then(result => {
      switch result {
      | Error(msg) => assert_true(String.includes(msg, "Invalid URL"))
      | Ok() => assert_false(true)
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })
})
