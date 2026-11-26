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
// Scheme, authority and host
//
// The shipped allow-list is no longer a substring probe over the whole URL.
// `normalize_asset_url` and `decide_referrer_policy` parse the URL, take its
// authority, and compare the host of that authority with each configured
// entry. The kernels below are the pieces of that test worth a proof;
// `conform.mbt` composes them against the shipped functions over a corpus of
// URLs and hosts.
//
// Not modelled here: the port after the host. `host_start_codes` does locate
// the start of the host, after the user information; where the host ends is
// covered by tests in `src/lib/url_structure_test.mbt`.
// ---------------------------------------------------------------------------

///|
/// ASCII lower case of one code unit.
///
/// Proved: the result equals `ascii_lower(c)`.
pub fn ascii_lower_codes(
  c : Int32,
) -> Int32 where {
  proof_ensure: result => result == ascii_lower(c),
} {
  if ASCII_UPPER_A <= c && c <= ASCII_UPPER_Z {
    c + ASCII_CASE_GAP
  } else {
    c
  }
}

///|
/// Does `src` start with `http://`, in any letter case?
///
/// Proved: the result is true exactly when `http_scheme_ci(src)` holds.
pub fn scheme_is_http_codes(
  src : FixedArray[Int32],
) -> Bool where {
  proof_ensure: result => (result == true) == http_scheme_ci(src),
} {
  if 7 <= src.length() {
    if ascii_lower_codes(src[0]) == CH_LOWER_H {
      if ascii_lower_codes(src[1]) == CH_LOWER_T {
        if ascii_lower_codes(src[2]) == CH_LOWER_T {
          if ascii_lower_codes(src[3]) == CH_LOWER_P {
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
/// Does `src` start with `https://`, in any letter case?
///
/// Proved: the result is true exactly when `https_scheme_ci(src)` holds.
pub fn scheme_is_https_codes(
  src : FixedArray[Int32],
) -> Bool where {
  proof_ensure: result => (result == true) == https_scheme_ci(src),
} {
  if 8 <= src.length() {
    if ascii_lower_codes(src[0]) == CH_LOWER_H {
      if ascii_lower_codes(src[1]) == CH_LOWER_T {
        if ascii_lower_codes(src[2]) == CH_LOWER_T {
          if ascii_lower_codes(src[3]) == CH_LOWER_P {
            if ascii_lower_codes(src[4]) == CH_LOWER_S {
              if src[5] == CH_COLON {
                if src[6] == CH_SLASH {
                  src[7] == CH_SLASH
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
  } else {
    false
  }
}

///|
/// Does `c` end an authority?
///
/// Proved: the result is true exactly when `is_authority_end(c)` holds.
pub fn is_authority_end_char(
  c : Int32,
) -> Bool where {
  proof_ensure: result => (result == true) == is_authority_end(c),
} {
  c == CH_SLASH || c == CH_BACKSLASH || c == CH_QUESTION || c == CH_HASH
}

///|
/// The first delimiter at or after `start`, or the end of `src`.
///
/// Proved: `authority_end_ok(src, start, result)` — no unit of
/// `src[start .. result)` ends an authority, and `result` is either the end of
/// `src` or the first unit that does. This is what makes
/// `https://cdn.example.com\@evil.com/` the host `cdn.example.com`: the
/// authority stops at the backslash, as it does in a browser.
pub fn authority_end_codes(
  src : FixedArray[Int32],
  start : Int32,
) -> Int32 where {
  // Lengths are not known to be non-negative unless stated; without it the
  // prover cannot rule out an empty scan that runs past a negative end.
  proof_require: 0 <= src.length(),
  proof_require: 0 <= start,
  proof_require: start <= src.length(),
  proof_ensure: result => authority_end_ok(src, start, result),
} {
  // The loop condition is a plain bound on purpose: the prover derives a loop
  // variant from `i < src.length()` but not from a conjunction, and a loop
  // without a variant has a termination obligation that never closes. So the
  // scan does not stop at a delimiter; `stop` simply stops moving.
  let mut stop = start
  for i = start; i < src.length(); {
    if stop == i && !is_authority_end_char(src[i]) {
      stop = i + 1
    }
    continue i + 1
  } nobreak {
    ()
  } where {
    proof_invariant: start <= i,
    proof_invariant: i <= src.length(),
    proof_invariant: start <= stop,
    proof_invariant: stop <= i,
    proof_invariant: stop == i || is_authority_end(src[stop]),
    proof_invariant: no_authority_end_before(src, start, stop),
  }
  proof_assert authority_end_ok(src, start, stop)
  stop
}

///|
/// The index just after the last `@` of `a`, or 0 when there is none.
///
/// Proved: `host_start_ok(a, result)` — no `@` follows `result`, and the unit
/// before it is one (unless `result` is 0). The host of an authority begins
/// there, so `cdn.example.com@evil.com` has the host `evil.com`.
pub fn host_start_codes(
  a : FixedArray[Int32],
) -> Int32 where {
  proof_require: 0 <= a.length(),
  proof_ensure: result => host_start_ok(a, result),
} {
  let mut start = 0
  for i = 0; i < a.length(); {
    if a[i] == CH_AT {
      start = i + 1
    }
    continue i + 1
  } nobreak {
    ()
  } where {
    proof_invariant: 0 <= i,
    proof_invariant: i <= a.length(),
    proof_invariant: 0 <= start,
    proof_invariant: start <= i,
    proof_invariant: start == 0 || a[start - 1] == CH_AT,
    proof_invariant: no_at_from(a, start, i),
  }
  start
}

///|
/// Is the tail of `s` from index `from` equal to `t`, ignoring ASCII letter case?
///
/// Proved: the result is true exactly when `ascii_ci_eq_from(s, from, t)` holds.
pub fn ascii_ci_eq_from_codes(
  s : FixedArray[Int32],
  from : Int32,
  t : FixedArray[Int32],
) -> Bool where {
  proof_require: 0 <= s.length(),
  proof_require: 0 <= t.length(),
  proof_require: 0 <= from,
  proof_require: from <= s.length(),
  // Machine-integer model: `from + j` must stay inside 32 bits.
  proof_require: s.length() <= MAX_CODE_UNITS,
  proof_require: t.length() <= MAX_CODE_UNITS,
  proof_ensure: result => (result == true) == ascii_ci_eq_from(s, from, t),
} {
  if from + t.length() != s.length() {
    false
  } else {
    let mut ok = true
    for j = 0; j < t.length(); {
      if ascii_lower_codes(s[from + j]) != ascii_lower_codes(t[j]) {
        ok = false
        break
      }
      continue j + 1
    } nobreak {
      ()
    } where {
      proof_invariant: 0 <= j,
      proof_invariant: j <= t.length(),
      proof_invariant: from + j <= s.length(),
      proof_invariant: ok ==
      (∀ jj : Int32,
        0 <= jj && jj < j → ascii_lower(s[from + jj]) == ascii_lower(t[jj])),
    }
    ok
  }
}

///|
/// Is there room for a label in front of `entry`, and a dot right before it?
///
/// Proved: the result is true exactly when `dot_before_tail(host, entry)`
/// holds.
pub fn dot_before_tail_codes(
  host : FixedArray[Int32],
  entry : FixedArray[Int32],
) -> Bool where {
  proof_require: 0 <= host.length(),
  proof_require: 0 <= entry.length(),
  proof_require: host.length() <= MAX_CODE_UNITS,
  proof_require: entry.length() <= MAX_CODE_UNITS,
  proof_ensure: result => (result == true) == dot_before_tail(host, entry),
} {
  // `entry.length() > 0` is what shows the dot is read in bounds.
  if entry.length() == 0 {
    false
  } else if host.length() >= entry.length() + 2 {
    host[host.length() - entry.length() - 1] == CH_DOT
  } else {
    false
  }
}

///|
/// Do the last `entry.length()` units of `host` spell `entry`, letter case
/// aside?
///
/// Proved: the result is true exactly when `tail_is_entry(host, entry)` holds.
/// The caller must make sure `host` is at least as long as `entry`: there is
/// no tail to compare otherwise.
pub fn tail_is_entry_codes(
  host : FixedArray[Int32],
  entry : FixedArray[Int32],
) -> Bool where {
  proof_require: 0 <= host.length(),
  proof_require: 0 <= entry.length(),
  proof_require: entry.length() <= host.length(),
  proof_require: host.length() <= MAX_CODE_UNITS,
  proof_require: entry.length() <= MAX_CODE_UNITS,
  proof_ensure: result => (result == true) == tail_is_entry(host, entry),
} {
  ascii_ci_eq_from_codes(host, host.length() - entry.length(), entry)
}

///|
/// Is `host` a subdomain of `entry`: a whole label, a dot, and then `entry`?
///
/// Proved: the result is true exactly when `host_is_subdomain(host, entry)`
/// holds.
pub fn host_is_subdomain_codes(
  host : FixedArray[Int32],
  entry : FixedArray[Int32],
) -> Bool where {
  proof_require: 0 <= host.length(),
  proof_require: 0 <= entry.length(),
  proof_require: host.length() <= MAX_CODE_UNITS,
  proof_require: entry.length() <= MAX_CODE_UNITS,
  proof_ensure: result => (result == true) == host_is_subdomain(host, entry),
} {
  dot_before_tail_codes(host, entry) && tail_is_entry_codes(host, entry)
}

///|
/// Is `host` `entry` itself or one of its subdomains?
///
/// Proved: the result is true exactly when `host_matches_entry(host, entry)`
/// holds — the comparison ignores ASCII letter case, and a subdomain is a whole
/// label followed by a dot and the entry.
pub fn host_matches_entry_codes(
  host : FixedArray[Int32],
  entry : FixedArray[Int32],
) -> Bool where {
  proof_require: 0 <= host.length(),
  proof_require: 0 <= entry.length(),
  proof_require: host.length() <= MAX_CODE_UNITS,
  proof_require: entry.length() <= MAX_CODE_UNITS,
  proof_ensure: result => (result == true) == host_matches_entry(host, entry),
} {
  if entry.length() == 0 {
    false
  } else if ascii_ci_eq_from_codes(host, 0, entry) {
    true
  } else {
    host_is_subdomain_codes(host, entry)
  }
}

// ---------------------------------------------------------------------------
// Runtime evidence for the scheme, authority and host kernels
//
// As with the rejection paths above, a green `moon prove` says the kernels
// satisfy their contracts; these tests show the contracts describe the
// behaviour the shipped allow-list relies on.
// ---------------------------------------------------------------------------

///|
test "url - the scheme test ignores letter case and nothing else" {
  for url in ["http://a", "HTTP://a", "Http://cdn.example.com/x", "hTtP://"] {
    assert_true(scheme_is_http_codes(codes_of_string(url)))
  }
  for url in ["https://a", "httpx://a", "http:/a", "http:/", "httpa//a", "xht"] {
    assert_false(scheme_is_http_codes(codes_of_string(url)))
  }
  for url in ["https://a", "HTTPS://a", "Https://"] {
    assert_true(scheme_is_https_codes(codes_of_string(url)))
  }
  for url in ["http://a", "httpsx://a", "https:/a", "https:/", "http://"] {
    assert_false(scheme_is_https_codes(codes_of_string(url)))
  }
}

///|
test "url - the authority ends at the first delimiter" {
  // (URL, authority) — the scheme is always `https://`, eight units.
  let cases : Array[(String, String)] = [
    ("https://cdn.example.com/a.png", "cdn.example.com"),
    ("https://cdn.example.com", "cdn.example.com"),
    ("https://cdn.example.com?x=1", "cdn.example.com"),
    ("https://cdn.example.com#f", "cdn.example.com"),
    ("https://cdn.example.com\\@evil.com/a.png", "cdn.example.com"),
    ("https://", ""),
    ("https://user@host:8080/p", "user@host:8080"),
  ]
  for i = 0; i < cases.length(); i = i + 1 {
    let src = codes_of_string(cases[i].0)
    let want = cases[i].1
    let stop = authority_end_codes(src, 8)
    assert_eq(stop - 8, want.length())
    let mut same = true
    for j = 0; j < want.length(); j = j + 1 {
      if src[8 + j] != want[j].to_int() {
        same = false
      }
    }
    assert_true(same)
  }
  // Without a delimiter the authority runs to the end of the input; the first
  // delimiter stops it, whichever of the four it is.
  assert_eq(authority_end_codes(codes_of_string("abc"), 1), 3)
  assert_eq(authority_end_codes(codes_of_string("a/c"), 0), 1)
  assert_eq(authority_end_codes(codes_of_string("a?c"), 0), 1)
  assert_eq(authority_end_codes(codes_of_string("a#c"), 0), 1)
  assert_eq(authority_end_codes(codes_of_string("a\\c"), 0), 1)
  // A scan that starts on a delimiter stops at once.
  assert_eq(authority_end_codes(codes_of_string("a/c"), 1), 1)
}

///|
test "url - the host starts after the last at sign" {
  let cases : Array[(String, Int32)] = [
    ("cdn.example.com", 0),
    ("user@cdn.example.com", 5),
    ("a@b@cdn.example.com", 4),
    ("@", 1),
    ("", 0),
  ]
  for i = 0; i < cases.length(); i = i + 1 {
    assert_eq(host_start_codes(codes_of_string(cases[i].0)), cases[i].1)
  }
}

///|
test "url - the host rule ignores letter case and needs whole labels" {
  let admitted : Array[(String, String)] = [
    ("cdn.example.com", "cdn.example.com"),
    ("CDN.EXAMPLE.COM", "cdn.example.com"),
    ("cdn.example.com", "CDN.EXAMPLE.COM"),
    ("sub.cdn.example.com", "cdn.example.com"),
    ("sub.sub.CDN.example.com", "Cdn.Example.Com"),
    ("x.con", "con"),
  ]
  for i = 0; i < admitted.length(); i = i + 1 {
    let host = codes_of_string(admitted[i].0)
    let entry = codes_of_string(admitted[i].1)
    assert_true(host_matches_entry_codes(host, entry))
    // Symmetry does not hold: the entry is not a subdomain of the host.
    if admitted[i].0.length() != admitted[i].1.length() {
      assert_false(host_matches_entry_codes(entry, host))
    }
  }
  let refused : Array[(String, String)] = [
    ("cdn.example.com.evil.com", "cdn.example.com"),
    ("notcdn.example.com", "cdn.example.com"),
    (".cdn.example.com", "cdn.example.com"),
    ("cdn.example.co", "cdn.example.com"),
    ("cdn.example.com", ""),
    ("", "cdn.example.com"),
    ("example.com", "cdn.example.com"),
  ]
  for i = 0; i < refused.length(); i = i + 1 {
    let host = codes_of_string(refused[i].0)
    let entry = codes_of_string(refused[i].1)
    assert_false(host_matches_entry_codes(host, entry))
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
