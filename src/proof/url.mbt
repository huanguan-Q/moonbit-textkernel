// Verified schema rewrite: the `http://` -> `https://` fix.
//
// This is the kernel for the historical bug that turned
// `http://cdn.example.com/a/b.png` into `https://1091099810...`. The proof
// obligation that matters is the last conjunct of `https_rewrite_ok`:
//
//     ∀ k, 7 <= k < src.length()  ->  dst[k + 1] == src[k]
//
// i.e. every code unit after the scheme is carried over verbatim, only shifted by
// the one extra character that `https` adds. Any implementation that mangles the
// tail — code point spelling, truncation, off-by-one — must violate it.
//
// The copy is expressed as ONE pass whose invariant is piecewise:
//
//     out[j] == if j < 8 then https_code(j) else src[j - 1]
//
// Writing the eight header units first and then appending a second loop was the
// obvious shape, but it produces eight sequential array aliases; the final
// postcondition then has to chain eight array-frame axioms and times out. A
// single loop keeps the header and the tail in one quantified invariant that the
// postcondition instantiates directly.

///|
/// Observer: does `src` start with the ASCII prefix `http://`?
///
/// Proved: the returned boolean is true exactly when `has_http_scheme(src)` holds.
/// Kept as a separate verified function so the seven-way conjunction is discharged
/// in its own small VC instead of inside the rewrite's postcondition.
pub fn has_http_scheme_codes(
  src : FixedArray[Int32],
) -> Bool where {
  proof_ensure: result => (result == true) == has_http_scheme(src),
} {
  let h = src.length()
  if 7 <= h {
    if src[0] == CH_LOWER_H {
      if src[1] == CH_LOWER_T {
        if src[2] == CH_LOWER_T {
          if src[3] == CH_LOWER_P {
            if src[4] == CH_COLON {
              if src[5] == CH_SLASH {
                src[6] == CH_SLASH
              } else {
                false
              }
            } else {
              false
            }
          } else {
            false
          }
        } else {
          false
        }
      } else {
        false
      }
    } else {
      false
    }
  } else {
    false
  }
}

///|
/// Rewrite a leading `http://` to `https://`, leaving everything else alone.
///
/// Proved: the result is either the input unchanged, or the eight-unit
/// `https://` header followed by the exact input tail (`src[7..]`) shifted one
/// position right.
pub fn rewrite_https_codes(
  src : FixedArray[Int32],
) -> FixedArray[Int32] where {
  proof_require: src.length() <= MAX_CODE_UNITS,
  proof_ensure: result => rewrite_ok(src, result),
} {
  let h = src.length()
  let has_scheme = has_http_scheme_codes(src)
  if has_scheme {
    proof_assert has_http_scheme(src)
    let out = FixedArray::make(h + 1, 0)
    for k = 0; k < h + 1; {
      if k < 8 {
        out[k] = if k == 0 {
          104
        } else if k == 1 {
          116
        } else if k == 2 {
          116
        } else if k == 3 {
          112
        } else if k == 4 {
          115
        } else if k == 5 {
          58
        } else {
          47
        }
      } else {
        out[k] = src[k - 1]
      }
      continue k + 1
    } nobreak {
      ()
    } where {
      proof_invariant: 0 <= k,
      proof_invariant: k <= h + 1,
      proof_invariant: h == src.length(),
      proof_invariant: ∀ j : Int32,
        0 <= j && j < k →
        out[j] == (if j < 8 { https_code(j) } else { src[j - 1] }),
      proof_reasoning: (
        #| Positions [0, 8) receive the `https://` header, positions [8, h+1)
        #| receive src shifted left by one. The single piecewise invariant covers
        #| both halves, so the postcondition only has to instantiate it.
      ),
    }
    proof_assert ∀ j : Int32,
      0 <= j && j < h + 1 →
      out[j] == (if j < 8 { https_code(j) } else { src[j - 1] })
    proof_assert https_rewrite_ok(src, out)
    out
  } else {
    proof_assert !has_http_scheme(src)
    let out = FixedArray::make(h, 0)
    for k = 0; k < h; {
      out[k] = src[k]
      continue k + 1
    } nobreak {
      ()
    } where {
      proof_invariant: 0 <= k,
      proof_invariant: k <= h,
      proof_invariant: h == src.length(),
      proof_invariant: ∀ j : Int32, 0 <= j && j < k → out[j] == src[j],
      proof_reasoning: "identity copy of the whole buffer, one position per iteration",
    }
    proof_assert ∀ j : Int32, 0 <= j && j < h → out[j] == src[j]
    proof_assert unchanged_ok(src, out)
    out
  }
}

// ---------------------------------------------------------------------------
// Runtime evidence for the rejection paths
//
// `moon prove` discharges `has_http_scheme` over the whole input space, but that
// says nothing about whether the *tests* ever walk the branches. Measured before
// these cases existed: 30/47 in this file, with all seven `else` arms of
// `has_http_scheme_codes` unexecuted. Every URL in the conformance corpus starts
// with `http://`, so the kernel had only ever been observed accepting — the
// rejection path was all proof, no observation.
//
// Each case below mutates exactly one of the seven code units of `http://`.
// Replacing position `i` can only reach the `else` belonging to position `i`, and
// the corpus covers every position, so seven distinct branches are walked. That
// is why the assertions are per-case booleans and not a single "something is
// rejected": a kernel returning `false` unconditionally would satisfy the latter,
// which is why the acceptance case below exists as its dual.
// ---------------------------------------------------------------------------

///|
/// The seven code units of `http://`, as a fresh buffer per mutation.
fn url_scheme_reference() -> FixedArray[Int32] {
  let out = FixedArray::make(7, 0)
  out[0] = CH_LOWER_H
  out[1] = CH_LOWER_T
  out[2] = CH_LOWER_T
  out[3] = CH_LOWER_P
  out[4] = CH_COLON
  out[5] = CH_SLASH
  out[6] = CH_SLASH
  out
}

///|
test "url - one wrong unit at each of the seven positions is rejected" {
  // `x` differs from the expected unit at all seven positions, so each iteration
  // reaches a different `else` arm while leaving the other six units correct.
  let wrong = 'x'.to_int()
  let mut rejections = 0
  for pos = 0; pos < 7; pos = pos + 1 {
    let units = url_scheme_reference()
    units[pos] = wrong
    assert_false(has_http_scheme_codes(units))
    rejections = rejections + 1
  }
  // Non-vacuity: seven iterations, seven branches, not one case repeated.
  assert_eq(rejections, 7)
}

///|
test "url - a buffer shorter than seven units is rejected" {
  let full = url_scheme_reference()
  let mut lengths = 0
  // Lengths 0..=6, i.e. every proper prefix of the scheme.
  for n = 0; n < 7; n = n + 1 {
    let short = FixedArray::make(n, 0)
    for i = 0; i < n; i = i + 1 {
      short[i] = full[i]
    }
    assert_false(has_http_scheme_codes(short))
    lengths = lengths + 1
  }
  assert_eq(lengths, 7)
}

///|
test "url - the exact scheme and any tail after it are accepted" {
  assert_true(has_http_scheme_codes(url_scheme_reference()))
  let cases : Array[String] = [
    "http://", "http://a", "http://cdn.example.com/x",
  ]
  for i = 0; i < cases.length(); i = i + 1 {
    assert_true(has_http_scheme_codes(codes_of_string(cases[i])))
  }
}

///|
test "url - an input without the scheme is copied verbatim" {
  let cases : Array[String] = [
    "", "h", "http", "http:/", "https://cdn.example.com/a", "ftp://example.com/a",
  ]
  for i = 0; i < cases.length(); i = i + 1 {
    let src = codes_of_string(cases[i])
    let dst = rewrite_https_codes(src)
    // Length alone is not enough: the historical bug kept a plausible length
    // while writing decimal digits into the tail, so compare the units too.
    assert_eq(dst.length(), src.length())
    assert_true(codes_equal(dst, src))
  }
}

///|
test "url - the rewrite writes https:// then shifts the tail by one" {
  let src = codes_of_string("http://a/b?c=1")
  let dst = rewrite_https_codes(src)
  assert_eq(dst.length(), src.length() + 1)
  assert_eq(dst[0], 'h'.to_int())
  assert_eq(dst[1], 't'.to_int())
  assert_eq(dst[2], 't'.to_int())
  assert_eq(dst[3], 'p'.to_int())
  assert_eq(dst[4], 's'.to_int())
  assert_eq(dst[5], ':'.to_int())
  assert_eq(dst[6], '/'.to_int())
  assert_eq(dst[7], '/'.to_int())
  let mut shifted = 0
  for k = 7; k < src.length(); k = k + 1 {
    assert_eq(dst[k + 1], src[k])
    shifted = shifted + 1
  }
  // Counted rather than written out, so the expectation cannot drift from the
  // input the way a hand-maintained length would. A loop that never ran would
  // still pass the header assertions above.
  assert_eq(shifted, src.length() - 7)
}
