// Verified kernels for `@lib.str_contains`.
//
// The shipped function is the host gate: `normalize_asset_url` returns early when
// it reports "not a asset host", and `decide_referrer_policy` is nothing but a
// call to it. Its body is also the only hand-optimised search in the package — a
// single-unit fast path plus a last-character probe that skips ahead — so the
// theorem that matters is "the answer is exactly `contains_somewhere`", and the
// conformance corpus in `conform.mbt` is what pins that answer to the shipped
// control flow.
//
// The search is written recursively rather than as a loop. Five loop shapes were
// measured against the machine-integer prelude and every one of them left
// unprovable `in_bounds` / `index in array bounds` obligations for `s + j`
// (see the review's appendix E). Structural recursion needs none of that: the
// recursion measure is `hay.length() - from`, which strictly decreases, and the
// postcondition composes because the candidate ranges of a step and its
// recursive call are adjacent and disjoint.

///|
/// Does `needle` match `hay` starting at code-unit position `s`?
///
/// Callers keep `s + needle.length() <= hay.length()`, so every read is in bounds.
///
/// Proved: the result is true exactly when `match_at(hay, needle, s)` holds.
pub fn match_at_codes(
  hay : FixedArray[Int32],
  needle : FixedArray[Int32],
  s : Int32,
) -> Bool where {
  proof_require: 0 <= s,
  proof_require: s + needle.length() <= hay.length(),
  // Machine-integer model: `s + j` must stay inside 32 bits, and both lengths
  // must be known non-negative for `s <= s + nl <= hl` to follow.
  proof_require: hay.length() <= MAX_CODE_UNITS,
  proof_require: needle.length() <= MAX_CODE_UNITS,
  proof_require: s <= MAX_CODE_UNITS,
  proof_require: 0 <= hay.length(),
  proof_require: 0 <= needle.length(),
  proof_ensure: result => (result == true) == match_at(hay, needle, s),
} {
  let nl = needle.length()
  let mut ok = true
  for j = 0; j < nl; {
    if hay[s + j] != needle[j] {
      ok = false
      break
    }
    continue j + 1
  } nobreak {
    ()
  } where {
    proof_invariant: 0 <= j,
    proof_invariant: j <= nl,
    proof_invariant: s + j <= hay.length(),
    proof_invariant: ok ==
    (∀ jj : Int32, 0 <= jj && jj < j → hay[s + jj] == needle[jj]),
    proof_reasoning: (
      #| `ok` says "every position before `j` matched". The loop leaves either at
      #| `j == nl` with `ok` still true, or through the break with `ok` false and
      #| a witnessed mismatch inside `[0, nl)`.
    ),
  }
  ok
}

///|
/// Is there a match starting at some position `t` with `0 <= t <= s`?
///
/// The scan runs *downwards* so that the recursion measure can be `s` itself.
/// `proof_decrease` has to be a logic expression, and subtraction is not one
/// (`[4207] invalid #proof_decrease: 'sub' is not a logic function`), so a
/// countdown on the candidate index is the shape that works: `s` strictly
/// decreases on every recursive call and needs no auxiliary measure.
fn search_down(
  hay : FixedArray[Int32],
  needle : FixedArray[Int32],
  s : Int32,
) -> Bool where {
  proof_decrease: s,
  proof_require: 0 <= s,
  proof_require: s <= MAX_CODE_UNITS,
  proof_require: s + needle.length() <= hay.length(),
  proof_require: hay.length() <= MAX_CODE_UNITS,
  proof_require: needle.length() <= MAX_CODE_UNITS,
  proof_require: 0 <= hay.length(),
  proof_require: 0 < needle.length(),
  proof_ensure: result => {
    (result == true) ==
    (∃ t : Int32, (0 <= t && t <= s) && match_at(hay, needle, t))
  },
} {
  if match_at_codes(hay, needle, s) {
    true
  } else if s == 0 {
    false
  } else {
    search_down(hay, needle, s - 1)
  }
}

///|
/// Does `needle` occur anywhere in `hay`?
///
/// The two early answers are the degenerate cases of `contains_somewhere`, not
/// special-cased axioms; everything else is delegated to the recursion.
///
/// Proved: the result is true exactly when `contains_somewhere(hay, needle)`.
pub fn str_contains_codes(
  hay : FixedArray[Int32],
  needle : FixedArray[Int32],
) -> Bool where {
  proof_require: hay.length() <= MAX_CODE_UNITS,
  proof_require: needle.length() <= MAX_CODE_UNITS,
  proof_require: 0 <= hay.length(),
  proof_require: 0 <= needle.length(),
  proof_ensure: result => (result == true) == contains_somewhere(hay, needle),
} {
  let hl = hay.length()
  let nl = needle.length()
  if nl == 0 {
    // An empty needle occurs at every position, `0` included.
    true
  } else if nl > hl {
    // No `s >= 0` can satisfy `s + nl <= hl`.
    false
  } else {
    search_down(hay, needle, hl - nl)
  }
}
