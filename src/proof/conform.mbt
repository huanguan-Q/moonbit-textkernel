// Bridge between the verified code-unit kernels and the shipped `String` API.
//
// The prover has no model for `String`, so `@lib.sanitize_filename` and friends
// cannot carry contracts at all: even `s.length()` inside a contracted body is
// rejected with `unsupported primitive operator`. The kernels in this package are
// therefore written over UTF-16 code units, and this file is what stops that from
// being a proof of a parallel universe:
//
//   kernel(codes_of(s))  ==  codes_of(@lib.shipped(s))
//
// asserted case by case over an enumerated corpus at the bottom of this file.
//
// The conversion itself is the trusted seam. It is two lines long, and the only
// thing it relies on is that `String::at` yields the UTF-16 code unit that the
// JS fallback in `wasmLoader.js` also sees via `charCodeAt`.

///|
/// UTF-16 code units of `s`, widened to `Int` so the kernels can use them.
///
/// `String::at` yields one `UInt16` per code unit; a surrogate pair therefore
/// appears as two lone halves, which is exactly the shape the kernels model.
fn codes_of_string(s : String) -> FixedArray[Int32] {
  let n = s.length()
  let out = FixedArray::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    out[i] = s[i].to_int()
  }
  out
}

///|
/// True when two code buffers hold the same code units.
fn codes_equal(a : FixedArray[Int32], b : FixedArray[Int32]) -> Bool {
  if a.length() != b.length() {
    false
  } else {
    let mut i = 0
    let mut same = true
    while i < a.length() {
      if a[i] != b[i] {
        same = false
        break
      }
      i = i + 1
    }
    same
  }
}

///|
/// True when `buf[0 .. n)` holds the same code units as `expected`.
fn codes_equal_prefix(
  expected : FixedArray[Int32],
  buf : FixedArray[Int32],
  n : Int32,
) -> Bool {
  if expected.length() != n {
    false
  } else {
    let mut i = 0
    let mut same = true
    while i < n {
      if expected[i] != buf[i] {
        same = false
        break
      }
      i = i + 1
    }
    same
  }
}

///|
/// Does the verified `sanitize_filename` kernel agree with `@lib.sanitize_filename`?
///
/// Covers the `""` -> `"file"` default (via `default_name_codes`) and the
/// 120-code-unit clamp (`NAME_LIMIT`) exactly as the shipped code applies them.
pub fn conform_sanitize(name : String) -> Bool {
  let shipped = codes_of_string(@lib.sanitize_filename(name))
  let kernel = if name.length() == 0 {
    default_name_codes(NAME_LIMIT)
  } else {
    sanitize_codes(codes_of_string(name), NAME_LIMIT)
  }
  codes_equal(shipped, kernel)
}

///|
/// Does the verified escaper agree with `@lib.escape_html`?
pub fn conform_escape_html(input : String) -> Bool {
  let src = codes_of_string(input)
  let dst = FixedArray::make(src.length() * 5, 0)
  let written = escape_html_codes(src, dst)
  codes_equal_prefix(codes_of_string(@lib.escape_html(input)), dst, written)
}

///|
/// Does the verified escaper agree with `@lib.escape_attr`?
pub fn conform_escape_attr(input : String) -> Bool {
  let src = codes_of_string(input)
  let dst = FixedArray::make(src.length() * 6, 0)
  let written = escape_attr_codes(src, dst)
  codes_equal_prefix(codes_of_string(@lib.escape_attr(input)), dst, written)
}

///|
/// The exact domain on which the kernel equality is a real constraint.
///
/// `@lib.normalize_asset_url` composes three steps:
///
///   1. a asset-host gate that returns the input untouched when it fails,
///   2. the `http://` -> `https://` scheme rewrite — the only step the kernel
///      `rewrite_https_codes` models, and
///   3. a `fmt=` / `v=` suffix append that is the identity only when both
///      parameters are already present.
///
/// Equality between kernel and shipped code can be claimed only where steps 1
/// and 3 are both identities, so all three conditions have to appear here.
/// Keying the predicate on the two parameters alone — the shape used before
/// 2026-10-30 — admitted non-asset host URLs, where the gate fires and the shipped
/// output keeps its `http://` while the kernel rewrites it.
///
/// The asset host test is deliberately the same `str_contains` substring probe the
/// shipped function uses, quirks included: this predicate has to describe the
/// code that ships, not an idealised URL parser. Tightening it (say, to a real
/// host parse) would make the bridge check a different function from the one in
/// `src/lib`.
pub fn https_applicable(input : String) -> Bool {
  let has_asset_cdn = @lib.str_contains(input, "cdn.example.com") ||
    @lib.str_contains(input, "assets.example.org")
  input.has_prefix("http://") &&
  has_asset_cdn &&
  @lib.str_contains(input, "fmt=") &&
  @lib.str_contains(input, "v=")
}

///|
/// Does the verified schema rewrite agree with the scheme half of
/// `@lib.normalize_asset_url`?
///
/// Only meaningful on `https_applicable` inputs: there the host gate passes and
/// both parameters are present, so the shipped function reduces to the scheme
/// rewrite and the two sides must agree code unit for code unit.
///
/// Outside that domain this returns `true`, and that `true` is **vacuous** — it
/// records "no claim", not "agreement". Callers that need to tell the two apart
/// must consult `https_applicable`; the corpus test below partitions its cases
/// for exactly that reason.
pub fn conform_https(input : String) -> Bool {
  if https_applicable(input) {
    codes_equal(
      codes_of_string(@lib.normalize_asset_url(input)),
      rewrite_https_codes(codes_of_string(input)),
    )
  } else {
    true
  }
}

// ---------------------------------------------------------------------------
// Conformance corpus
//
// A green `moon prove` only says the kernels satisfy their contracts. These tests
// say the kernels describe the code that actually ships. Neither is sufficient
// alone, because `String` has no proof model for the prover to reason about.
// ---------------------------------------------------------------------------

///|
/// Characters chosen to hit every branch of every kernel: all nine illegal
/// filename characters, `_`, ASCII, a BMP CJK character, and a non-BMP emoji
/// (a well-formed surrogate pair, i.e. two lone halves at the code-unit level).
fn conform_alphabet() -> Array[String] {
  [
    "a", "Z", "9", " ", "_", "/", "\\", ":", "*", "?", "\"", "<", ">", "|", "文",
    "😀",
  ]
}

///|
/// Every string of length 0..=2 over `alphabet`, i.e. `1 + n + n * n` cases.
fn conform_short_strings(alphabet : Array[String]) -> Array[String] {
  let out : Array[String] = [""]
  let n = alphabet.length()
  for i = 0; i < n; i = i + 1 {
    out.push(alphabet[i])
    for j = 0; j < n; j = j + 1 {
      out.push(alphabet[i] + alphabet[j])
    }
  }
  out
}

///|
/// Index of the first case rejected by `check`, or `-1` when all pass.
///
/// Returning an index instead of asserting inside the loop keeps the failure
/// message actionable: `-1 != 37` points straight at `cases[37]`.
fn conform_first_bad(cases : Array[String], check : (String) -> Bool) -> Int32 {
  let mut bad = -1
  for i = 0; i < cases.length(); i = i + 1 {
    if !check(cases[i]) {
      bad = i
      break
    }
  }
  bad
}

///|
/// `s` repeated `n` times.
fn conform_repeat(s : String, n : Int32) -> String {
  let mut out = ""
  for i = 0; i < n; i = i + 1 {
    out = out + s
  }
  out
}

///|
test "conform - sanitize agrees on every short string over the alphabet" {
  let cases = conform_short_strings(conform_alphabet())
  assert_eq(conform_first_bad(cases, conform_sanitize), -1)
}

///|
test "conform - escape_html agrees on every short string over the alphabet" {
  let cases = conform_short_strings(conform_alphabet())
  assert_eq(conform_first_bad(cases, conform_escape_html), -1)
}

///|
test "conform - escape_attr agrees on every short string over the alphabet" {
  let cases = conform_short_strings(conform_alphabet())
  assert_eq(conform_first_bad(cases, conform_escape_attr), -1)
}

///|
test "conform - sanitize agrees around the 120-code-unit clamp" {
  // 119 stays, 120 stays, 121 is cut: the three cases the clamp can get wrong.
  let cases : Array[String] = []
  for n = 118; n <= 122; n = n + 1 {
    cases.push(conform_repeat("a", n))
  }
  cases.push(conform_repeat("/", 130))
  cases.push(conform_repeat("a", 119) + "/")
  assert_eq(conform_first_bad(cases, conform_sanitize), -1)
}

///|
test "conform - sanitize agrees on a surrogate pair" {
  // A non-BMP character is two code units, both inside the surrogate block, so the
  // shipped `UInt16::to_char()` yields `None` twice and both halves become `_`.
  assert_eq(@lib.sanitize_filename("😀"), "__")
  let cases : Array[String] = ["😀", "a😀b", "😀/", "/😀", "文😀文"]
  assert_eq(conform_first_bad(cases, conform_sanitize), -1)
}

///|
test "conform - escape_html agrees on a tag-injection payload" {
  let payload = "<script>alert('x' & \"y\")</script>"
  assert_true(@lib.escape_html(payload).length() > payload.length())
  let cases : Array[String] = [payload, "<", ">", "&", "&amp;", "<>", "<>&"]
  assert_eq(conform_first_bad(cases, conform_escape_html), -1)
}

///|
test "conform - escape_attr agrees on an attribute-breakout payload" {
  let payload = "\" onmouseover=\"alert('x')\" data-x='y'"
  let cases : Array[String] = [payload, "\"", "'", "a\"b", "a'b", "&\"'"]
  assert_eq(conform_first_bad(cases, conform_escape_attr), -1)
}

///|
/// Inputs on which the kernel equality is a real constraint: `http://`, a asset
/// asset host substring, and both parameters already present.
///
/// Every element is admitted by `https_applicable`, and the corpus test below
/// asserts that — so this list cannot quietly degenerate into vacuous entries
/// the way the single six-element list it replaced did (three of those six were
/// rejected by the guard and passed for free).
fn https_discriminating_cases() -> Array[String] {
  [
    "http://cdn.example.com/a/b.png?fmt=png&v=1", "http://cdn.example.com/c/d.jpg?v=1&fmt=png",
    "http://assets.example.org/a/b.png?fmt=png&v=1", "http://cdn.example.com/asset_png/abc123/0?fmt=png&v=1",
  ]
}

///|
/// Inputs the equality cannot judge, one per reason it cannot. Each is asserted
/// to be rejected by `https_applicable`: a future widening of the predicate that
/// re-admits one of them fails a test instead of silently adding coverage.
fn https_inadmissible_cases() -> Array[String] {
  [
    // Non-asset host. The shipped gate returns the input with its `http://`
    // intact while the kernel rewrites the scheme. This is R1's counterexample.
    "http://example.com/a.png?fmt=png&v=1",
    // Already `https://`: both sides are the identity, so nothing is tested.
     "https://cdn.example.com/a/b.png?fmt=png&v=1",
    // asset host but missing `v=`: the shipped function appends a suffix.
     "http://cdn.example.com/not-a-asset-domain",
    // Not the http scheme at all.
     "ftp://example.com/x?fmt=png&v=1",
  ]
}

///|
test "conform - https applicability separates the two corpora" {
  let yes = https_discriminating_cases()
  for i = 0; i < yes.length(); i = i + 1 {
    assert_true(https_applicable(yes[i]))
  }
  // Non-vacuity: an empty list would make the loop above pass for free.
  assert_true(yes.length() > 0)
  let no = https_inadmissible_cases()
  for i = 0; i < no.length(); i = i + 1 {
    assert_false(https_applicable(no[i]))
  }
  assert_true(no.length() > 0)
}

///|
test "conform - https rewrite agrees with normalize_asset_url on discriminating URLs" {
  let cases = https_discriminating_cases()
  for i = 0; i < cases.length(); i = i + 1 {
    assert_true(https_applicable(cases[i]))
  }
  assert_eq(conform_first_bad(cases, conform_https), -1)
}

///|
test "conform - a non-asset host http URL stays outside the kernel's domain" {
  // R1, pinned. The two implementations genuinely differ here:
  //   shipped: the host gate fires first, so the input comes back with `http://`;
  //   kernel:  it only ever sees a scheme prefix, so it rewrites to `https://`.
  // Each behaviour is asserted separately so a change to either side is
  // attributed to that side, and the disagreement itself is asserted so that the
  // bridge's abstention is shown to be *required*, not merely permitted.
  let u = "http://example.com/a.png?fmt=png&v=1"
  assert_eq(@lib.normalize_asset_url(u), u)
  assert_eq(rewrite_https_codes(codes_of_string(u)).length(), u.length() + 1)
  assert_false(
    codes_equal(
      codes_of_string(@lib.normalize_asset_url(u)),
      rewrite_https_codes(codes_of_string(u)),
    ),
  )
  // Therefore the bridge must abstain. `true` here is the documented "no claim";
  // `https_applicable` is what distinguishes it from agreement.
  assert_false(https_applicable(u))
  assert_true(conform_https(u))
}

///|
test "conform - https rewrite preserves the tail verbatim" {
  // The historical bug: `processed[i].to_string()` on a UInt16 produced the decimal
  // spelling, so the tail became a digit string. Spell the expected result out
  // literally so the regression cannot come back silently.
  let input = "http://cdn.example.com/asset_png/abc123/0?fmt=png&v=1"
  let expected = "https://cdn.example.com/asset_png/abc123/0?fmt=png&v=1"
  assert_eq(@lib.normalize_asset_url(input), expected)
  assert_eq(
    rewrite_https_codes(codes_of_string(input)).length(),
    input.length() + 1,
  )
  assert_true(conform_https(input))
}

///|
test "conform - code comparison helpers are not vacuous" {
  // Guards the harness itself: if `codes_equal` always returned true the
  // conformance suite above would prove nothing.
  let a = codes_of_string("abc")
  assert_true(codes_equal(a, codes_of_string("abc")))
  assert_false(codes_equal(a, codes_of_string("abd")))
  assert_false(codes_equal(a, codes_of_string("ab")))
  assert_true(
    codes_equal_prefix(codes_of_string("abc"), codes_of_string("abcdef"), 3),
  )
  assert_false(
    codes_equal_prefix(codes_of_string("abc"), codes_of_string("abcdef"), 2),
  )
}

// ---------------------------------------------------------------------------
// Batch arithmetic
//
// The three kernels in `batch.mbt` were proved but had never been executed:
// the coverage report read `batch.mbt: 0/7`. A proof about code that never runs
// against the shipped expressions is a proof about a parallel universe, which is
// exactly what the rest of this file exists to prevent. These two tests close
// that seam.
// ---------------------------------------------------------------------------

///|
/// Smallest of two `Int32`s. `@lib`'s `min_int` is private, and the point of the
/// test below is to restate the comparison rather than to reuse it.
fn batch_min(a : Int32, b : Int32) -> Int32 {
  if a < b {
    a
  } else {
    b
  }
}

///|
test "conform - batch kernels match the shipped expressions on a grid" {
  // `safe_batch_size` is the guard the shipped loops spell out inline as
  // `if config.batch_size > 0 { config.batch_size } else { 1 }`.
  for requested = -3; requested <= 6; requested = requested + 1 {
    let bs = safe_batch_size(requested)
    assert_true(bs > 0)
    let expected = if requested > 0 { requested } else { 1 }
    assert_eq(bs, expected)
  }
  // `batch_ceil` / `batch_end` recompute, per iteration, what the shipped loops
  // derive from `(len + bs - 1) / bs` and `min(start + bs, len)`.
  for n = 0; n <= 8; n = n + 1 {
    for bs = 1; bs <= 5; bs = bs + 1 {
      let count = batch_ceil(n, bs)
      let division = (n + bs - 1) / bs
      assert_eq(count, division)
      assert_true(count * bs >= n)
      assert_true((count - 1) * bs < n)
      for start = 0; start <= n; start = start + 1 {
        let stop = batch_end(start, bs, n)
        assert_eq(stop, batch_min(start + bs, n))
        assert_true(start <= stop)
        assert_true(stop <= n)
      }
    }
  }
}

///|
test "conform - shipped batching stays total for a non-positive batch size" {
  // The historical divide-by-zero: `(len + bs - 1) / bs` with `bs == 0`. The
  // guard that makes it total is exactly `safe_batch_size`, so this drives the
  // shipped loop with the degenerate batch sizes the guard exists for and
  // requires every item to come out, in order.
  //
  // These values are only reachable because `@lib.create_batch_config` exists:
  // `BatchConfig`'s fields are read-only outside `src/lib`, so without it the
  // guarded inputs could not be constructed from here at all.
  let items : Array[Int32] = [1, 2, 3, 4, 5]
  let min_int32 = -2147483647 - 1
  let sizes : Array[Int32] = [0, -1, min_int32, 1, 2, 5, 500]
  for i = 0; i < sizes.length(); i = i + 1 {
    let config = @lib.create_batch_config(sizes[i], 1, false, 0)
    let result = @lib.batch_process_custom(items, fn(x) { x * 10 }, config)
    assert_eq(result.processed_count, 5)
    assert_eq(result.results.length(), items.length())
    for j = 0; j < items.length(); j = j + 1 {
      assert_eq(result.results[j], items[j] * 10)
    }
  }
}

///|
test "conform - chunk size does not change the shipped batch output" {
  // `batch_ceil` / `batch_end` decide where each batch is sliced. The two
  // shipped presets chunk the same items 50- and 500-at-a-time; per-item output
  // must not depend on the chunk size, and no item may be dropped or repeated.
  let items : Array[Int32] = []
  for i = 0; i < 120; i = i + 1 {
    items.push(i)
  }
  let realtime = @lib.create_realtime_config()
  let large = @lib.create_large_dataset_config()
  let a = @lib.batch_process_custom(items, fn(x) { x * 2 }, realtime)
  let b = @lib.batch_process_custom(items, fn(x) { x * 2 }, large)
  assert_eq(a.processed_count, 120)
  assert_eq(b.processed_count, 120)
  assert_eq(a.results.length(), 120)
  assert_eq(b.results.length(), 120)
  for i = 0; i < items.length(); i = i + 1 {
    assert_eq(a.results[i], items[i] * 2)
    assert_eq(b.results[i], items[i] * 2)
  }
}

// ---------------------------------------------------------------------------
// Substring search
//
// `str_contains_codes` is proved against `contains_somewhere`; the tests below
// pin `contains_somewhere` against the function the extension actually calls.
// The kernel scans every candidate start, while `@lib.str_contains` probes the
// needle's last unit first and only then compares — the same answer reached by a
// shorter route. Equality over a corpus is what keeps those two honest.
// ---------------------------------------------------------------------------

///|
/// Does the verified search agree with `@lib.str_contains` on this pair?
pub fn conform_str_contains(hay : String, needle : String) -> Bool {
  let kernel = str_contains_codes(codes_of_string(hay), codes_of_string(needle))
  kernel == @lib.str_contains(hay, needle)
}

///|
/// Pairs that exercise each path of the shipped search: the two early answers,
/// a match at the first / middle / last admissible position, and near misses that
/// share the needle's last unit (which is what makes the last-character probe
/// reach the full comparison).
fn conform_contains_cases() -> Array[(String, String)] {
  [
    // empty needle / empty hay
    ("", ""),
    ("", "a"),
    ("abc", ""),
    // needle longer than hay
    ("a", "ab"),
    ("", "abc"),
    ("ab", "abc"),
    // single-unit needle
    ("abc", "b"),
    ("abc", "z"),
    ("a", "a"),
    ("abc", "a"),
    ("abc", "c"),
    // matches at the boundaries of the admissible range
    ("abc", "abc"),
    ("abcdef", "ab"),
    ("abcdef", "ef"),
    ("abcdef", "cd"),
    // near misses sharing the last unit -> probe hits, comparison fails
    ("abc", "xbc"),
    ("abc", "abd"),
    ("aab", "ab"),
    ("abab", "bab"),
    // repeated units
    ("aaaa", "aa"),
    ("aaaa", "aaa"),
    ("aaaaa", "aaa"),
    ("ababab", "abab"),
    // non-BMP and BMP mixtures, both as hay and as needle
    ("a😀b", "😀"),
    ("a😀b", "😀b"),
    ("文😀文", "😀文"),
    ("😀", "😀"),
  ]
}

///|
test "conform - str_contains agrees with the shipped search on the corpus" {
  let cases = conform_contains_cases()
  let mut bad = -1
  for i = 0; i < cases.length(); i = i + 1 {
    if !conform_str_contains(cases[i].0, cases[i].1) {
      bad = i
      break
    }
  }
  assert_eq(bad, -1)
}

///|
test "conform - str_contains agrees on every short pair over a three-letter alphabet" {
  // 13 strings of length <= 2 over {a, b, /} -> 169 pairs. Small enough to run
  // exhaustively, wide enough that the search walks every candidate position.
  let alphabet : Array[String] = ["a", "b", "/"]
  let strings : Array[String] = [""]
  for i = 0; i < alphabet.length(); i = i + 1 {
    strings.push(alphabet[i])
    for j = 0; j < alphabet.length(); j = j + 1 {
      strings.push(alphabet[i] + alphabet[j])
    }
  }
  let mut bad = -1
  let mut checked = 0
  for i = 0; i < strings.length(); i = i + 1 {
    for j = 0; j < strings.length(); j = j + 1 {
      if !conform_str_contains(strings[i], strings[j]) {
        bad = checked
        break
      }
      checked = checked + 1
    }
    if bad >= 0 {
      break
    }
  }
  assert_eq(bad, -1)
  // Non-vacuity: the loops above must actually have run.
  assert_eq(checked, strings.length() * strings.length())
}

///|
test "conform - str_contains agrees on every pair up to length four" {
  // The three-letter run above stops at length 2, which cannot contain a
  // false start (a prefix that matches and then diverges) longer than one unit,
  // nor an overlap like `abab` / `bab`. This tier closes that: 31 strings of
  // length 0..=4 over {a, b}, i.e. 961 pairs, still cheap enough to be
  // exhaustive rather than sampled.
  let alphabet : Array[String] = ["a", "b"]
  let strings : Array[String] = [""]
  let mut frontier : Array[String] = [""]
  for _len = 0; _len < 4; _len = _len + 1 {
    let next : Array[String] = []
    for w in frontier {
      for c in alphabet {
        next.push(w + c)
      }
    }
    for w in next {
      strings.push(w)
    }
    frontier = next
  }
  assert_eq(strings.length(), 31)
  let mut bad = -1
  let mut checked = 0
  for i = 0; i < strings.length(); i = i + 1 {
    for j = 0; j < strings.length(); j = j + 1 {
      if !conform_str_contains(strings[i], strings[j]) {
        bad = checked
        break
      }
      checked = checked + 1
    }
    if bad >= 0 {
      break
    }
  }
  assert_eq(bad, -1)
  assert_eq(checked, 961)
}

///|
test "conform - the substring kernel is not a constant" {
  // A kernel returning `true` (or `false`) unconditionally would satisfy the
  // corpus above only if every case agreed, which cannot happen — this pins the
  // two answers directly so the suite cannot pass by accident.
  assert_true(str_contains_codes(codes_of_string("abc"), codes_of_string("b")))
  assert_false(str_contains_codes(codes_of_string("abc"), codes_of_string("z")))
  assert_true(str_contains_codes(codes_of_string("abc"), codes_of_string("")))
  assert_false(str_contains_codes(codes_of_string(""), codes_of_string("a")))
}

// ---------------------------------------------------------------------------
// Referrer policy
//
// `decide_referrer_policy` is the other consumer of the host gate: the same two
// substring probes decide which `Referrer-Policy` value an image request gets.
// The kernel proves the decision is exactly "hay contains either host"; the
// corpus below pins the two host strings and the two literals, which is the
// part a proof cannot see.
// ---------------------------------------------------------------------------

///|
/// Does the shipped policy match the verified decision for this input?
pub fn conform_referrer(input : String) -> Bool {
  let downgrade = referrer_downgrade_codes(
    codes_of_string(input),
    codes_of_string("cdn.example.com"),
    codes_of_string("assets.example.org"),
  )
  let expected = if downgrade {
    "no-referrer-when-downgrade"
  } else {
    "no-referrer"
  }
  @lib.decide_referrer_policy(input) == expected
}

///|
test "conform - referrer policy agrees with the kernel on the corpus" {
  let cases : Array[String] = [
    // both hosts, in the shapes the extension actually sees
    "https://cdn.example.com/asset_png/abc/0?fmt=png", "https://assets.example.org/asset_jpg/abc/0",
    "http://cdn.example.com/a.png", "https://cdn.example.com/a/😀.png?fmt=png&v=1",
    // the gate is a substring probe, not a host parse: these two are the
    // quirks it inherits, pinned so a future "fix" has to be deliberate
     "https://example.com/cdn.example.com/a.png", "https://cdn.example.com.evil.com/a.png",
    // near misses and non-asset host
     "", "cdn.example", "cdn.example.com.evil", "https://example.com/a.png", "https://CDN.EXAMPLE.COM/a.png",
    "mmeco.example.org/a.png", "https://assets.example.org.example.com/a.png",
  ]
  let mut bad = -1
  for i = 0; i < cases.length(); i = i + 1 {
    if !conform_referrer(cases[i]) {
      bad = i
      break
    }
  }
  assert_eq(bad, -1)
}

///|
test "conform - the referrer decision is not a constant" {
  // Both branches must be reachable, otherwise the corpus above could pass with
  // a function that always answers the same literal.
  assert_true(conform_referrer("https://cdn.example.com/a.png"))
  assert_true(conform_referrer("https://example.com/a.png"))
  assert_eq(
    @lib.decide_referrer_policy("https://cdn.example.com/a.png"),
    "no-referrer-when-downgrade",
  )
  assert_eq(
    @lib.decide_referrer_policy("https://example.com/a.png"),
    "no-referrer",
  )
}

// ---------------------------------------------------------------------------
// The `fmt=` / `v=` append: covered by properties, not by a kernel
//
// `https_applicable` deliberately excludes this step from the kernel equality
// (it requires both parameters to be present, which is exactly when the append
// is the identity). That leaves the append itself with no deductive link, so it
// is pinned here by the three properties that define it: the result always
// carries both parameters, normalising twice is normalising once, and the
// appended chunk uses `?` or `&` according to whether a query already started.
// ---------------------------------------------------------------------------

///|
test "conform - normalize always ends up with both parameters" {
  let cdn : Array[String] = [
    "https://cdn.example.com/a.png", "https://cdn.example.com/a.png?", "https://cdn.example.com/a.png?x=1",
    "https://cdn.example.com/a.png?fmt=gif", "https://cdn.example.com/a.png?v=jpeg",
    "http://cdn.example.com/a.png", "http://assets.example.org/a.png?x=1&y=2", "https://cdn.example.com/a.png?fmt=png&v=1",
    "https://cdn.example.com/a.png?v=1&fmt=png",
  ]
  for u in cdn {
    let out = @lib.normalize_asset_url(u)
    assert_true(@lib.str_contains(out, "fmt="))
    assert_true(@lib.str_contains(out, "v="))
    // Idempotence: the second pass must be the identity, because the first one
    // left both parameters in place.
    assert_eq(@lib.normalize_asset_url(out), out)
  }
}

///|
test "conform - the append picks ? or & from the existing query" {
  // No query yet -> the chunk starts a query.
  assert_eq(
    @lib.normalize_asset_url("https://cdn.example.com/a.png"),
    "https://cdn.example.com/a.png?fmt=png&v=1",
  )
  // Query already started -> the chunk joins it.
  assert_eq(
    @lib.normalize_asset_url("https://cdn.example.com/a.png?x=1"),
    "https://cdn.example.com/a.png?x=1&fmt=png&v=1",
  )
  // One parameter present -> only the missing one is appended, with `&`.
  assert_eq(
    @lib.normalize_asset_url("https://cdn.example.com/a.png?fmt=gif"),
    "https://cdn.example.com/a.png?fmt=gif&v=1",
  )
  assert_eq(
    @lib.normalize_asset_url("https://cdn.example.com/a.png?v=jpeg"),
    "https://cdn.example.com/a.png?v=jpeg&fmt=png",
  )
}

///|
test "conform - non-asset host input is returned untouched, parameters included" {
  // The gate fires first, so neither the scheme nor the parameters are touched.
  for u in ["http://example.com/a.png", "http://example.com/a.png?x=1"] {
    assert_eq(@lib.normalize_asset_url(u), u)
  }
}
