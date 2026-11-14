// Verified kernels mirroring the shipped `@lib` string routines, expressed over
// UTF-16 code units (`FixedArray[Int]`) because the prover has no model for
// `String`. `conform.mbt` pins each kernel against the real `String`
// implementation so the two cannot silently diverge.
//
// Loop discipline used throughout this package: `for` loops with an explicit
// `proof_invariant`. A `while` loop inside a contracted function has no variant
// in the generated WhyML, so its termination obligation can never be discharged
// and `moon prove` times out no matter how correct the body is.

///|
/// The verified core of `sanitize_filename`.
///
/// `base` is the already-defaulted name (the caller maps `""` to `"file"`), and
/// `cap` is the 120-code-unit clamp.
///
/// Proved:
/// - the result has exactly `min(base.length(), cap)` code units;
/// - every result code unit is either `_`, or the input code unit at the same
///   position when that unit was neither one of `/ \ : * ? " < > |` nor a lone
///   surrogate.
///
/// Together those two facts say no illegal filename character can survive and
/// no legal character can be displaced.
pub fn sanitize_codes(
  base : FixedArray[Int32],
  cap : Int32,
) -> FixedArray[Int32] where {
  proof_require: 0 < base.length(),
  proof_require: 0 <= cap,
  proof_require: cap <= MAX_CODE_UNITS,
  proof_ensure: result => result.length() == clamped_len(base.length(), cap),
  proof_ensure: result => sanitized_prefix(base, result, result.length()),
} {
  let n = if base.length() < cap { base.length() } else { cap }
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
      (SURROGATE_LO <= c && c <= SURROGATE_HI)
    if bad {
      out[i] = CH_UNDERSCORE
    } else {
      out[i] = c
    }
    continue i + 1
  } nobreak {
    ()
  } where {
    proof_invariant: 0 <= i,
    proof_invariant: i <= n,
    proof_invariant: n == clamped_len(base.length(), cap),
    proof_invariant: sanitized_prefix(base, out, i),
    proof_reasoning: (
      #| Every iteration writes out[i] from base[i] and leaves [0, i) untouched,
      #| so `sanitized_prefix` grows by one position per step. `n` is fixed by
      #| the clamp, so the length postcondition follows from i reaching n.
    ),
  }
  out
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
