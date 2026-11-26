// Verified HTML escapers.
//
// Both kernels write into a caller-provided `dst` buffer and return the number of
// code units written, which keeps the loop shape simple enough for the prover and
// makes the capacity requirement explicit in the contract.
//
// Two kinds of property are proved here.
//
// Safety — in the contracts, quantified over the whole output:
//   * the output can never contain `<` or `>`  -> cannot open or close a tag;
//   * the attribute variant additionally never contains `"` or `'`
//     -> cannot terminate a quoted attribute early;
//   * every `&` in the output introduces a complete entity this project can emit.
//
// Functionality — per iteration, via `html_at` / `attr_at`:
//   * the segment written for `src[i]` is exactly the escape of `src[i]`, and
//   * the cursor advances by exactly that segment's width.
//
// The surrogate rule is part of the functionality. A character outside the BMP
// is two code units, a leading and a trailing surrogate; both are copied as
// they are. Only an unpaired half becomes `_`. The first version of this
// kernel replaced every surrogate unit, satisfied its contracts, and turned an
// emoji into `__`: the contracts said so. `paired_at` in `spec.mbtp` is the
// corrected rule, and `conform.mbt` pins the shipped `String` escapers to it
// over a corpus that contains well-formed pairs.
//
// These two assertions are what stops the contracts from being satisfied by a
// degenerate writer. Before they existed, an implementation that wrote `_` for
// every unit satisfied all five `/attr` ensures (no angle bracket, no quote, no
// bogus `&`, length within `6n`) and passed `moon prove` outright — the safety
// properties are all "absence of a bad character", which underscores trivially
// have.
//
// Why functionality is an assertion rather than a postcondition: a postcondition
// would have to say `dst[0 .. result)` is the concatenation of the per-unit
// segments, which needs a prefix sum over the input. Three encodings were tried
// and measured on this toolchain:
//   * a recursive `fn html_off(src, j)` in `.mbtp`, with `proof_decrease: j`, is
//     accepted and emitted as a WhyML `function`, but the invariant
//     `w == html_off(src, i)` leaves 6 goals unproved even at 5x solver limits —
//     SMT does not close the induction;
//   * an explicit `starts[]` cursor array (local recurrence instead of a prefix
//     sum) reaches 202/205 goals, the remaining 3 being quantified invariant
//     preservation across the five sequential array writes;
//   * extracting the unit into a contracted helper makes the caller's
//     whole-prefix invariants unprovable (5 timeouts): `html_at` is a
//     disjunction, and the prover cannot lift it into a `∀` over the prefix
//     through a call boundary.
// The assertion form costs 24 goals and proves cleanly, while still rejecting a
// writer that emits the wrong bytes.

///|
/// Is `src[i]` half of a well-formed surrogate pair?
///
/// Proved: the result is true exactly when `paired_at(src, i)` holds.
pub fn paired_codes(
  src : FixedArray[Int32],
  i : Int32,
) -> Bool where {
  proof_require: 0 <= i,
  proof_require: i < src.length(),
  proof_ensure: result => (result == true) == paired_at(src, i),
} {
  if SURROGATE_LO <= src[i] && src[i] <= HIGH_SURR_HI {
    i + 1 < src.length() &&
    LOW_SURR_LO <= src[i + 1] &&
    src[i + 1] <= SURROGATE_HI
  } else if LOW_SURR_LO <= src[i] && src[i] <= SURROGATE_HI {
    1 <= i && SURROGATE_LO <= src[i - 1] && src[i - 1] <= HIGH_SURR_HI
  } else {
    false
  }
}

///|
/// Escape `&`, `<`, `>` and unpaired surrogate halves, mirroring
/// `@lib.escape_html`. A well-formed pair is copied whole.
///
/// `dst` must hold at least `5 * src.length()` code units because `&amp;` is the
/// widest replacement.
///
/// Proved: the returned length never exceeds `5 * src.length()`; the written
/// prefix contains no `<` and no `>`; every `&` in it starts a known entity; and
/// each written segment equals `html_at` of the unit it came from.
pub fn escape_html_codes(
  src : FixedArray[Int32],
  dst : FixedArray[Int32],
) -> Int32 where {
  proof_require: src.length() <= MAX_CODE_UNITS,
  proof_require: src.length() * 5 <= dst.length(),
  proof_ensure: result => 0 <= result,
  proof_ensure: result => result <= src.length() * 5,
  proof_ensure: result => no_markup_prefix(dst, result),
  proof_ensure: result => entities_ok_prefix(dst, result),
} {
  let mut w = 0
  for i = 0; i < src.length(); {
    let pos = w
    let c = src[i]
    if c == CH_AMP {
      dst[w] = CH_AMP
      dst[w + 1] = CH_LOWER_A
      dst[w + 2] = CH_LOWER_M
      dst[w + 3] = CH_LOWER_P
      dst[w + 4] = CH_SEMI
      w = w + 5
    } else if c == CH_LT {
      dst[w] = CH_AMP
      dst[w + 1] = CH_LOWER_L
      dst[w + 2] = CH_LOWER_T
      dst[w + 3] = CH_SEMI
      w = w + 4
    } else if c == CH_GT {
      dst[w] = CH_AMP
      dst[w + 1] = CH_LOWER_G
      dst[w + 2] = CH_LOWER_T
      dst[w + 3] = CH_SEMI
      w = w + 4
    } else if SURROGATE_LO <= c && c <= SURROGATE_HI && !paired_codes(src, i) {
      // An unpaired surrogate half has no character to copy and becomes `_`.
      dst[w] = CH_UNDERSCORE
      w = w + 1
    } else {
      // Everything else, a well-formed pair included, is copied as it is.
      dst[w] = c
      w = w + 1
    }
    proof_assert html_at(dst, pos, src, i)
    proof_assert w == pos + html_width_at(src, i)
    continue i + 1
  } nobreak {
    w
  } where {
    proof_invariant: 0 <= i,
    proof_invariant: i <= src.length(),
    proof_invariant: 0 <= w,
    proof_invariant: w <= 5 * i,
    proof_invariant: no_markup_prefix(dst, w),
    proof_invariant: entities_ok_prefix(dst, w),
    proof_reasoning: (
      #| The widest replacement is `&amp;` (five code units), so w <= 5 * i is
      #| preserved. Every replacement starts with `&` and the copied characters
      #| are never `<` or `>`, so the written prefix stays markup-free.
    ),
  }
}

///|
/// Escape `&`, `<`, `>`, `"`, `'` and unpaired surrogate halves, mirroring
/// `@lib.escape_attr`. A well-formed pair is copied whole.
///
/// `dst` must hold at least `6 * src.length()` code units because `&quot;` is the
/// widest replacement.
///
/// Proved: the returned length never exceeds `6 * src.length()`; the written
/// prefix contains no `<`, `>`, `"` or `'`; every `&` in it starts a known
/// entity; and each written segment equals `attr_at` of the unit it came from.
pub fn escape_attr_codes(
  src : FixedArray[Int32],
  dst : FixedArray[Int32],
) -> Int32 where {
  proof_require: src.length() <= MAX_CODE_UNITS,
  proof_require: src.length() * 6 <= dst.length(),
  proof_ensure: result => 0 <= result,
  proof_ensure: result => result <= src.length() * 6,
  proof_ensure: result => no_markup_prefix(dst, result),
  proof_ensure: result => no_quote_prefix(dst, result),
  proof_ensure: result => entities_ok_prefix(dst, result),
} {
  let mut w = 0
  for i = 0; i < src.length(); {
    let pos = w
    let c = src[i]
    if c == CH_AMP {
      dst[w] = CH_AMP
      dst[w + 1] = CH_LOWER_A
      dst[w + 2] = CH_LOWER_M
      dst[w + 3] = CH_LOWER_P
      dst[w + 4] = CH_SEMI
      w = w + 5
    } else if c == CH_LT {
      dst[w] = CH_AMP
      dst[w + 1] = CH_LOWER_L
      dst[w + 2] = CH_LOWER_T
      dst[w + 3] = CH_SEMI
      w = w + 4
    } else if c == CH_GT {
      dst[w] = CH_AMP
      dst[w + 1] = CH_LOWER_G
      dst[w + 2] = CH_LOWER_T
      dst[w + 3] = CH_SEMI
      w = w + 4
    } else if c == CH_DQUOTE {
      dst[w] = CH_AMP
      dst[w + 1] = 113
      dst[w + 2] = 117
      dst[w + 3] = 111
      dst[w + 4] = CH_LOWER_T
      dst[w + 5] = CH_SEMI
      w = w + 6
    } else if c == CH_SQUOTE {
      dst[w] = CH_AMP
      dst[w + 1] = 35
      dst[w + 2] = 51
      dst[w + 3] = 57
      dst[w + 4] = CH_SEMI
      w = w + 5
    } else if SURROGATE_LO <= c && c <= SURROGATE_HI && !paired_codes(src, i) {
      // An unpaired surrogate half has no character to copy and becomes `_`.
      dst[w] = CH_UNDERSCORE
      w = w + 1
    } else {
      // Everything else, a well-formed pair included, is copied as it is.
      dst[w] = c
      w = w + 1
    }
    proof_assert attr_at(dst, pos, src, i)
    proof_assert w == pos + attr_width_at(src, i)
    continue i + 1
  } nobreak {
    w
  } where {
    proof_invariant: 0 <= i,
    proof_invariant: i <= src.length(),
    proof_invariant: 0 <= w,
    proof_invariant: w <= 6 * i,
    proof_invariant: no_markup_prefix(dst, w),
    proof_invariant: entities_ok_prefix(dst, w),
    proof_invariant: no_quote_prefix(dst, w),
    proof_reasoning: (
      #| The widest replacement is `&quot;` (six code units), so w <= 6 * i is
      #| preserved. `&quot;` and `&#39;` are the only quoted-atom replacements;
      #| both spell the quote as an ASCII digit/letter, never as the quote
      #| itself, so the written prefix holds no quote characters.
    ),
  }
}
