///|
/// Black-box tests for the structural URL rules in `url.mbt`.
///
/// Before these rules, the allow-list was a substring probe over the whole
/// URL, parameters were appended after the `#fragment`, and `nav=1` counted
/// as `v=1`. Each test below names the rule it pins.

///|
test "[url] the allow-list is applied to the URL's own host" {
  // Each of these was rewritten before: the host string occurs somewhere in
  // the URL. None of them is cdn.example.com.
  let url = "https://evil.com/?next=http://cdn.example.com/a.png"
  for
    foreign in [
      "http://evil.com/cdn.example.com/x.png", "https://cdn.example.com.evil.com/a.png",
      url, "https://example.com/cdn.example.com/a.png", "https://notcdn.example.com/a.png",
      "https://cdn.example.com@evil.com/a.png", "https://cdn.example.com:8443@evil.com/a.png",
      "https://evil.com\\@cdn.example.com/a.png", "https://evil.com/a.png#cdn.example.com",
    ] {
    assert_eq(@lib.normalize_asset_url(foreign), foreign)
    assert_eq(@lib.decide_referrer_policy(foreign), "no-referrer")
  }
}

///|
test "[url] the host itself and its subdomains are asset hosts" {
  assert_eq(
    @lib.normalize_asset_url("https://sub.cdn.example.com/a.png"),
    "https://sub.cdn.example.com/a.png?fmt=png&v=1",
  )
  assert_eq(
    @lib.normalize_asset_url("https://sub.sub.cdn.example.com/a.png"),
    "https://sub.sub.cdn.example.com/a.png?fmt=png&v=1",
  )
  // User information and a port are not part of the host.
  assert_eq(
    @lib.normalize_asset_url("http://user@cdn.example.com:8080/a.png"),
    "https://user@cdn.example.com:8080/a.png?fmt=png&v=1",
  )
  // As in a browser, a backslash ends the authority: the host of this URL is
  // cdn.example.com, and `@evil.com` belongs to its path.
  assert_eq(
    @lib.decide_referrer_policy("https://cdn.example.com\\@evil.com/a.png"),
    "no-referrer-when-downgrade",
  )
}

///|
test "[url] user information, an IPv6 literal and a port are not the host" {
  let cfg = @lib.create_asset_config(["cdn.example.com", "[::1]"], ["w=800"])
  // A colon inside user information is not a port. The user name and password
  // are the obvious placeholders on purpose: this is a test for where the
  // authority ends, not a credential.
  assert_eq(
    @lib.normalize_asset_url_with_config(
      "http://user:pass@cdn.example.com/a.png", cfg, // pragma: allowlist secret
    ),
    "https://user:pass@cdn.example.com/a.png?w=800", // pragma: allowlist secret
  )
  // A port does not keep a configured host out.
  assert_eq(
    @lib.normalize_asset_url_with_config(
      "http://cdn.example.com:8080/a.png", cfg,
    ),
    "https://cdn.example.com:8080/a.png?w=800",
  )
  // An IPv6 literal is compared with its brackets; the colons inside them are
  // not a port, and a real port after the bracket is dropped.
  assert_eq(
    @lib.normalize_asset_url_with_config("http://[::1]/a.png", cfg),
    "https://[::1]/a.png?w=800",
  )
  assert_eq(
    @lib.decide_referrer_policy_with_config("http://[::1]:8443/a.png", cfg),
    "no-referrer-when-downgrade",
  )
  // ... and another literal is another host.
  assert_eq(
    @lib.decide_referrer_policy_with_config("http://[2001:db8::1]/a.png", cfg),
    "no-referrer",
  )
}

///|
test "[url] letter case of the scheme and the host does not matter" {
  assert_eq(
    @lib.normalize_asset_url("HTTP://Cdn.Example.COM/a.png"),
    "https://Cdn.Example.COM/a.png?fmt=png&v=1",
  )
  // Nothing to add: the URL comes back as it was written.
  let upper = "HTTPS://cdn.example.com/a.png?v=1&fmt=png"
  assert_eq(@lib.normalize_asset_url(upper), upper)
  assert_eq(
    @lib.decide_referrer_policy("HtTpS://CDN.EXAMPLE.COM/a.png"),
    "no-referrer-when-downgrade",
  )
}

///|
test "[url] the letter case of a configured host does not matter either" {
  // The rule is about DNS names, so it holds on both sides: an entry written in
  // upper case matches a lower-case URL and the other way round.
  let upper_entry = @lib.create_asset_config(["CDN.EXAMPLE.COM"], ["fmt=png"])
  let lower_entry = @lib.create_asset_config(["cdn.example.com"], ["fmt=png"])
  assert_eq(
    @lib.normalize_asset_url_with_config(
      "https://cdn.example.com/a.png", upper_entry,
    ),
    "https://cdn.example.com/a.png?fmt=png",
  )
  assert_eq(
    @lib.normalize_asset_url_with_config(
      "https://SUB.CDN.example.com/a.png", upper_entry,
    ),
    "https://SUB.CDN.example.com/a.png?fmt=png",
  )
  // ... and a host that differs by more than case is still another host.
  assert_eq(
    @lib.normalize_asset_url_with_config(
      "https://CDN.EXAMPLE.ORG/a.png", upper_entry,
    ),
    "https://CDN.EXAMPLE.ORG/a.png",
  )
  assert_eq(
    @lib.decide_referrer_policy_with_config(
      "https://CDN.example.com/a.png", lower_entry,
    ),
    "no-referrer-when-downgrade",
  )
}

///|
test "[url] only an http or https URL can be an asset URL" {
  for
    other in [
      "ftp://cdn.example.com/a.png", "httpx://cdn.example.com/a.png", "mailto:x@cdn.example.com",
      "data:text/plain,cdn.example.com", "javascript:void(0)", "//cdn.example.com/a.png",
      "/cdn.example.com/a.png", "cdn.example.com",
    ] {
    assert_eq(@lib.normalize_asset_url(other), other)
    assert_eq(@lib.decide_referrer_policy(other), "no-referrer")
  }
}

///|
test "[url] a missing parameter goes before the fragment, never after it" {
  assert_eq(
    @lib.normalize_asset_url("https://cdn.example.com/a.png#frag"),
    "https://cdn.example.com/a.png?fmt=png&v=1#frag",
  )
  assert_eq(
    @lib.normalize_asset_url("https://cdn.example.com/a.png?v=1#frag"),
    "https://cdn.example.com/a.png?v=1&fmt=png#frag",
  )
  let complete = "https://cdn.example.com/a.png?v=1&fmt=png#frag"
  assert_eq(@lib.normalize_asset_url(complete), complete)
  // An empty fragment is still a fragment.
  assert_eq(
    @lib.normalize_asset_url("https://cdn.example.com/a.png#"),
    "https://cdn.example.com/a.png?fmt=png&v=1#",
  )
}

///|
test "[url] a parameter is present only under its own name" {
  // `nav=1` is not `v`, and `xfmt=1` is not `fmt`.
  assert_eq(
    @lib.normalize_asset_url("https://cdn.example.com/a.png?nav=1"),
    "https://cdn.example.com/a.png?nav=1&fmt=png&v=1",
  )
  assert_eq(
    @lib.normalize_asset_url("https://cdn.example.com/a.png?xfmt=1"),
    "https://cdn.example.com/a.png?xfmt=1&fmt=png&v=1",
  )
  // A bare parameter counts as present.
  assert_eq(
    @lib.normalize_asset_url("https://cdn.example.com/a.png?fmt"),
    "https://cdn.example.com/a.png?fmt&v=1",
  )
  // A `?` inside the query does not start a second one.
  let nested = "https://cdn.example.com/a.png?next=/b.png?x=1"
  assert_eq(
    @lib.normalize_asset_url(nested),
    "https://cdn.example.com/a.png?next=/b.png?x=1&fmt=png&v=1",
  )
}

///|
test "[url] normalizing twice is normalizing once" {
  for
    url in [
      "http://cdn.example.com", "http://cdn.example.com/a.png", "https://cdn.example.com/img?",
      "https://cdn.example.com/a.png#frag", "https://cdn.example.com/a.png?nav=1#f",
      "https://assets.example.org/a?x=1", "https://example.com/a.png", "HTTP://CDN.EXAMPLE.COM/A.PNG",
    ] {
    let once = @lib.normalize_asset_url(url)
    assert_eq(@lib.normalize_asset_url(once), once)
  }
}

///|
test "[url] a default parameter that could change the structure is refused" {
  // Each piece below used to be appended as it was. Then it was skipped
  // silently. It is an error now, and the message names the piece, so the
  // caller can find it in its own configuration.
  let base = "https://cdn.example.com/a.png"
  for bad in ["x#y", "z w", "=5", "", "a\tb", "a\nb", "a\u{0}b", "a\u{7F}b"] {
    let cfg = @lib.create_asset_config(["cdn.example.com"], ["ok=1", bad])
    assert_eq(
      domain_error(@lib.normalize_asset_url_with_config_result(base, cfg)),
      "Invalid Config: " + bad,
    )
    // `ensure_asset_params` is the same call under its other name.
    assert_eq(
      domain_error(@lib.ensure_asset_params_with_config_result(base, cfg)),
      "Invalid Config: " + bad,
    )
  }
  // A piece is checked wherever it is written, joined by `&` or on its own.
  let joined = @lib.create_asset_config(["cdn.example.com"], ["a=1&x#y&b=2"])
  assert_eq(
    domain_error(@lib.normalize_asset_url_with_config_result(base, joined)),
    "Invalid Config: x#y",
  )
  // The good parameters around a bad one are not half-applied: the call
  // fails as a whole, and the first bad piece is the one reported.
  let cfg = @lib.create_asset_config(["cdn.example.com"], ["a=1", "x#y", "z w"])
  assert_eq(
    domain_error(@lib.normalize_asset_url_with_config_result(base, cfg)),
    "Invalid Config: x#y",
  )
  // The String-returning form does not return a URL for this either: it
  // aborts, which a `moon test` cannot assert because the abort ends the test
  // process. The CLI reports it with exit status 2 instead; see `cli.mbt`.
}

///|
test "[url] a bad default parameter only matters for a URL it would be used on" {
  // The parameters are not looked at unless the URL is one the configuration
  // applies to. A program that only serves its own hosts is not stopped by a
  // piece it would never append.
  let cfg = @lib.create_asset_config(["cdn.example.com"], ["x#y"])
  for
    url in [
      "https://other.example.org/a.png", "https://evil.com/cdn.example.com/a.png",
      "https://cdn.example.com.evil.com/a.png", "ftp://cdn.example.com/a.png", "/relative/cdn.example.com",
      "cdn.example.com", "",
    ] {
    assert_eq(
      domain_unwrap(@lib.normalize_asset_url_with_config_result(url, cfg)),
      url,
    )
  }
  // The host test alone never reads the parameters.
  assert_eq(
    @lib.decide_referrer_policy_with_config(
      "https://cdn.example.com/a.png", cfg,
    ),
    "no-referrer-when-downgrade",
  )
}

///|
test "[url] a plain default parameter is still appended, once" {
  let base = "https://cdn.example.com/a.png"
  let cfg = @lib.create_asset_config(["cdn.example.com"], ["a=1&b=2", "ok=1"])
  assert_eq(
    domain_unwrap(@lib.normalize_asset_url_with_config_result(base, cfg)),
    "https://cdn.example.com/a.png?a=1&b=2&ok=1",
  )
  // A second default with the same name is not appended twice.
  let twice = @lib.create_asset_config(["cdn.example.com"], ["w=800", "w=640"])
  assert_eq(
    domain_unwrap(@lib.normalize_asset_url_with_config_result(base, twice)),
    "https://cdn.example.com/a.png?w=800",
  )
  // An empty value is a plain parameter: `k=` is a legal query piece.
  let empty_value = @lib.create_asset_config(["cdn.example.com"], ["k="])
  assert_eq(
    domain_unwrap(
      @lib.normalize_asset_url_with_config_result(base, empty_value),
    ),
    "https://cdn.example.com/a.png?k=",
  )
}

///|
test "[url] an empty or unusable host entry matches nothing" {
  let cfg = @lib.create_asset_config(["", " "], ["w=800"])
  for url in ["https:///a.png", "http://cdn.example.com/a.png"] {
    assert_eq(@lib.normalize_asset_url_with_config(url, cfg), url)
    assert_eq(@lib.decide_referrer_policy_with_config(url, cfg), "no-referrer")
  }
}

///|
test "[url] normalization and the referrer policy share one host test" {
  // Whatever one function treats as an asset host, the other does too.
  for
    url in [
      "https://cdn.example.com/a.png", "https://sub.cdn.example.com/a.png", "HTTP://CDN.EXAMPLE.COM/a.png",
      "https://cdn.example.com.evil.com/a.png", "https://example.com/?u=cdn.example.com",
      "ftp://cdn.example.com/a.png",
    ] {
    let policy = @lib.decide_referrer_policy(url)
    assert_eq(policy != "no-referrer", @lib.normalize_asset_url(url) != url)
  }
}
