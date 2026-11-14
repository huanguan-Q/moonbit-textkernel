// Kernel for the referrer-policy decision.
//
// `@lib.decide_referrer_policy` is a two-host substring test mapped onto one of
// two header values. It is small, but it is the whole reason an image request
// carries `no-referrer-when-downgrade` or `no-referrer`, and the two host
// strings are easy to mistype or to extend inconsistently. The kernel below
// proves that the decision is exactly "hay contains either host", so the
// shipped function's only remaining freedom is the wording it returns.
//
// The decision does not get its own `.mbtp`: `contains_somewhere` already names
// the two queries it is built from, and inlining them into the postcondition
// shows the composition without introducing a predicate that would just restate
// this one line.

///|
/// Does `hay` contain either asset host host?
///
/// True exactly when one of the two hosts occurs in `hay`, which is the
/// condition `decide_referrer_policy` maps to `no-referrer-when-downgrade`.
pub fn referrer_downgrade_codes(
  hay : FixedArray[Int32],
  host_a : FixedArray[Int32],
  host_b : FixedArray[Int32],
) -> Bool where {
  proof_require: hay.length() <= MAX_CODE_UNITS,
  proof_require: host_a.length() <= MAX_CODE_UNITS,
  proof_require: host_b.length() <= MAX_CODE_UNITS,
  proof_require: 0 <= hay.length(),
  proof_require: 0 <= host_a.length(),
  proof_require: 0 <= host_b.length(),
  proof_ensure: result => {
    (result == true) ==
    (contains_somewhere(hay, host_a) || contains_somewhere(hay, host_b))
  },
} {
  if str_contains_codes(hay, host_a) {
    true
  } else {
    str_contains_codes(hay, host_b)
  }
}

///|
test "referrer - the decision is the disjunction, on a small grid" {
  let hosts = ["cdn.example.com", "assets.example.org"]
  let haystacks : Array[String] = [
    "", "cdn.example.com", "assets.example.org", "https://cdn.example.com/a.png",
    "https://assets.example.org/b.png", "https://example.com/c.png", "https://cdn.example.com.evil.com/d.png",
    "CDN.EXAMPLE.COM", "https://example.com/?u=cdn.example.com",
  ]
  let h1 = hosts[0]
  let h2 = hosts[1]
  for hay in haystacks {
    let kernel = referrer_downgrade_codes(
      codes_of_string(hay),
      codes_of_string(h1),
      codes_of_string(h2),
    )
    let expected = @lib.str_contains(hay, h1) || @lib.str_contains(hay, h2)
    assert_eq(kernel, expected)
  }
}
