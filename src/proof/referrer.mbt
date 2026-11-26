// Kernel for the referrer-policy decision.
//
// `@lib.decide_referrer_policy` decides whether a URL's host is in the
// allow-list and maps that onto one of two header values. The host test is the
// same one `normalize_asset_url` applies, so the two shipped functions cannot
// disagree about what an asset host is.
//
// The kernel works on the *host*, the part of the authority after the last
// `@`: it proves that the decision is exactly "the host is one of the configured
// hosts or a subdomain of it". Taking the host out of the URL is the job of
// `authority_end_codes` and `host_start_codes` in `url.mbt`, and of the shipped
// parser; `conform.mbt` composes the pieces against the shipped function.
//
// The first version of this kernel proved "the whole URL contains the host
// string", which is what the shipped gate did at the time. That rule let
// `https://cdn.example.com.evil.com/` through, so both were replaced.

///|
/// Does `host` match either of the two asset hosts?
///
/// Proved: the result is true exactly when the host rule admits `host_a` or
/// `host_b`, which is the condition `decide_referrer_policy` maps to
/// `no-referrer-when-downgrade`.
pub fn referrer_downgrade_codes(
  host : FixedArray[Int32],
  host_a : FixedArray[Int32],
  host_b : FixedArray[Int32],
) -> Bool where {
  proof_require: 0 <= host.length(),
  proof_require: 0 <= host_a.length(),
  proof_require: 0 <= host_b.length(),
  proof_require: host.length() <= MAX_CODE_UNITS,
  proof_require: host_a.length() <= MAX_CODE_UNITS,
  proof_require: host_b.length() <= MAX_CODE_UNITS,
  proof_ensure: result => {
    (result == true) ==
    (host_matches_entry(host, host_a) || host_matches_entry(host, host_b))
  },
} {
  if host_matches_entry_codes(host, host_a) {
    true
  } else {
    host_matches_entry_codes(host, host_b)
  }
}

///|
test "referrer - the decision is the host rule, on a small grid" {
  let host_a = codes_of_string("cdn.example.com")
  let host_b = codes_of_string("assets.example.org")
  let admitted = [
    "cdn.example.com", "CDN.EXAMPLE.COM", "sub.cdn.example.com", "assets.example.org",
    "img.assets.example.org",
  ]
  for host in admitted {
    assert_true(referrer_downgrade_codes(codes_of_string(host), host_a, host_b))
  }
  // A look-alike is refused on each side of the host: a suffix that is not a
  // whole label, a prefix, and the host of another name.
  let refused = [
    "", "cdn.example", "cdn.example.com.evil", "cdn.example.com.evil.com", "mmeco.example.org",
    "assets.example.org.example.com", "notcdn.example.com",
  ]
  for host in refused {
    assert_false(
      referrer_downgrade_codes(codes_of_string(host), host_a, host_b),
    )
  }
}
