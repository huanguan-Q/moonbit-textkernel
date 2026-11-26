// Verified kernels mirroring the shipped `@lib` string routines, expressed over
// UTF-16 code units (`FixedArray[Int]`) because the prover has no model for
// `String`. `conform.mbt` pins each kernel against the real `String`
// implementation so the two cannot silently diverge.
//
// Loop discipline used throughout this package: `for` loops with an explicit
// `proof_invariant`. A `while` loop inside a contracted function has no variant
// in the generated WhyML, so its termination obligation can never be discharged
// and `moon prove` times out no matter how correct the body is.
//
// What the sanitizer proves, and what it leaves to tests. Three rules are
// proved here: the character rule, the clamp, and the dot-only rule. The two
// Windows-only rules of the shipped sanitizer — trailing dots and spaces become
// `_`, and a device name gets a marker — are not modelled. `conform.mbt`
// abstains on names where they apply, and the runtime invariant
// `@lib.filename_is_sanitized` checks them on every shipped result.

///|
/// Is `src[i]`, a unit of a name of `n` units, half of a pair whose other
/// half lies inside those `n` units?
///
/// Proved: the result is true exactly when `paired_in_prefix(src, n, i)` holds.
pub fn paired_in_prefix_codes(
  src : FixedArray[Int32],
  n : Int32,
  i : Int32,
) -> Bool where {
  proof_require: 0 <= i,
  proof_require: i < n,
  proof_require: n <= src.length(),
  proof_ensure: result => (result == true) == paired_in_prefix(src, n, i),
} {
  if SURROGATE_LO <= src[i] && src[i] <= HIGH_SURR_HI {
    i + 1 < n && LOW_SURR_LO <= src[i + 1] && src[i + 1] <= SURROGATE_HI
  } else if LOW_SURR_LO <= src[i] && src[i] <= SURROGATE_HI {
    1 <= i && SURROGATE_LO <= src[i - 1] && src[i - 1] <= HIGH_SURR_HI
  } else {
    false
  }
}

///|
/// Is every unit of `src` a dot?
///
/// Proved: the result is true exactly when `all_dots(src)` holds.
pub fn all_dots_codes(
  src : FixedArray[Int32],
) -> Bool where {
  proof_ensure: result => (result == true) == all_dots(src),
} {
  if 0 < src.length() {
    let mut only = true
    for i = 0; i < src.length(); {
      if src[i] != CH_DOT {
        only = false
      }
      continue i + 1
    } nobreak {
      ()
    } where {
      proof_invariant: 0 <= i,
      proof_invariant: i <= src.length(),
      proof_invariant: only ==
      (∀ j : Int32, 0 <= j && j < i → src[j] == CH_DOT),
    }
    only
  } else {
    false
  }
}

///|
/// The character rule and the clamp of `sanitize_filename`.
///
/// `base` is the already-defaulted name, and `cap` is the length clamp.
///
/// Proved:
/// - the result has `adjusted_len(base, cap)` units: `min(base.length(), cap)`,
///   one less when that cut would fall between the two halves of a surrogate
///   pair, and never zero;
/// - every result unit is `_` when the input unit at the same position was one
///   of `/ \ : * ? " < > |`, a C0 control, DEL or an unpaired surrogate half,
///   and is the input unit itself otherwise — so a well-formed pair survives
///   whole, and no legal character is displaced.
///
/// Together those facts say no character a file name cannot hold can survive,
/// and no character it can hold is lost.
pub fn sanitize_codes(
  base : FixedArray[Int32],
  cap : Int32,
) -> FixedArray[Int32] where {
  proof_require: 0 < base.length(),
  proof_require: 2 <= cap,
  proof_require: cap <= MAX_CODE_UNITS,
  proof_ensure: result => 0 < result.length(),
  proof_ensure: result => result.length() == adjusted_len(base, cap),
  proof_ensure: result => {
    sanitized_prefix(base, result, result.length(), result.length())
  },
} {
  let bound = if base.length() < cap { base.length() } else { cap }
  // The clamp never falls between the two halves of a surrogate pair.
  let n = if 1 <= bound &&
    bound < base.length() &&
    SURROGATE_LO <= base[bound - 1] &&
    base[bound - 1] <= HIGH_SURR_HI &&
    LOW_SURR_LO <= base[bound] &&
    base[bound] <= SURROGATE_HI {
    bound - 1
  } else {
    bound
  }
  proof_assert n == adjusted_len(base, cap)
  let out = FixedArray::make(n, 0)
  for i = 0; i < n; {
    let c = base[i]
    let bad = c == CH_SLASH ||
      c == CH_BACKSLASH ||
      c == CH_COLON ||
      c == CH_STAR ||
      c == CH_QUESTION ||
      c == CH_DQUOTE ||
      c == CH_LT ||
      c == CH_GT ||
      c == CH_PIPE ||
      (0 <= c && c <= CONTROL_MAX) ||
      c == CH_DEL ||
      (
        SURROGATE_LO <= c &&
        c <= SURROGATE_HI &&
        !paired_in_prefix_codes(base, n, i)
      )
    out[i] = if bad { CH_UNDERSCORE } else { c }
    continue i + 1
  } nobreak {
    ()
  } where {
    proof_invariant: 0 <= i,
    proof_invariant: i <= n,
    proof_invariant: sanitized_prefix(base, out, i, n),
    proof_reasoning: (
      #| Every iteration writes out[i] from base[i] and leaves [0, i) untouched,
      #| so `sanitized_prefix` grows by one position per step. `n` is fixed by
      #| the clamp, so the length postcondition follows from i reaching n.
    ),
  }
  out
}

///|
/// The verified core of `sanitize_filename`.
///
/// `base` is the already-defaulted name, and `cap` is the length clamp.
///
/// Proved:
/// - the result is never empty and never longer than `cap`;
/// - a name made of dots only (`.`, `..`, `...`) yields the default name
///   `file`: such a name is a directory reference, never a file;
/// - any other name yields `sanitize_codes(base, cap)`.
pub fn sanitize_name_codes(
  base : FixedArray[Int32],
  cap : Int32,
) -> FixedArray[Int32] where {
  proof_require: 0 < base.length(),
  proof_require: 2 <= cap,
  proof_require: cap <= MAX_CODE_UNITS,
  proof_ensure: result => 0 < result.length(),
  proof_ensure: result => result.length() <= cap,
  proof_ensure: result => all_dots(base) → is_default_name(result, cap),
  proof_ensure: result => {
    all_dots(base) == false →
    result.length() == adjusted_len(base, cap) &&
    sanitized_prefix(base, result, result.length(), result.length())
  },
} {
  if all_dots_codes(base) {
    proof_assert all_dots(base)
    default_name_codes(cap)
  } else {
    proof_assert all_dots(base) == false
    sanitize_codes(base, cap)
  }
}

///|
/// The `"file"` fallback used when the name is empty, clamped by `cap`.
///
/// `sanitize_codes` requires a non-empty input, so the `""` -> `"file"` rule
/// lives here instead of inside the main kernel.
pub fn default_name_codes(
  cap : Int32,
) -> FixedArray[Int32] where {
  proof_require: 0 <= cap,
  proof_ensure: result => result.length() == clamped_len(4, cap),
  proof_ensure: result => {
    ∀ i : Int32,
      0 <= i && i < result.length() → result[i] == default_code(i)
  },
} {
  let n = if 4 < cap { 4 } else { cap }
  let out = FixedArray::make(n, 0)
  for i = 0; i < n; {
    out[i] = if i == 0 {
      102
    } else if i == 1 {
      105
    } else if i == 2 {
      108
    } else {
      101
    }
    continue i + 1
  } nobreak {
    ()
  } where {
    proof_invariant: 0 <= i,
    proof_invariant: i <= n,
    proof_invariant: n == clamped_len(4, cap),
    proof_invariant: ∀ j : Int32,
      0 <= j && j < i → out[j] == default_code(j),
    proof_reasoning: (
      #| The four code units of "file" (102, 105, 108, 101) are written position
      #| by position; each is legal, so the default never needs replacing.
    ),
  }
  out
}
