// Tests for the runtime mirrors in `escape_invariants.mbt`.
//
// Two things have to hold, and they pull in opposite directions:
//
//   * the predicates must accept *everything* the shipping escapers produce —
//     a false positive aborts a valid copy, which is worse than the bug they
//     are meant to catch;
//   * the predicates must reject the payloads the properties forbid — a false
//     negative makes the mirror decorative.
//
// The exhaustive sweep below covers the first, the explicit payloads the
// second.

///|
/// Characters that matter to one of the three invariants: the five entities, the
/// nine filename characters, a quote, a CJK char, a surrogate pair, a dot and a
/// control character.
fn mirror_alphabet() -> Array[String] {
  [
    "&", "<", ">", "\"", "'", ";", "#", "3", "9", "/", "\\", ":", "*", "?", "|",
    "文", "😀", "a", " ", ".", "\u{1F}",
  ]
}

///|
/// Every string of length 0..=2 over `alphabet`.
fn mirror_short_strings(alphabet : Array[String]) -> Array[String] {
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
test "[invariants] mirror - the escapers never trip their own invariant" {
  let cases = mirror_short_strings(mirror_alphabet())
  let mut bad_html = -1
  let mut bad_attr = -1
  let mut bad_name = -1
  for i = 0; i < cases.length(); i = i + 1 {
    let s = cases[i]
    if !@lib.html_is_escaped(@lib.escape_html(s)) {
      bad_html = i
    }
    if !@lib.attr_is_escaped(@lib.escape_attr(s)) {
      bad_attr = i
    }
    if !@lib.filename_is_sanitized(@lib.sanitize_filename(s)) {
      bad_name = i
    }
  }
  assert_eq(bad_html, -1)
  assert_eq(bad_attr, -1)
  assert_eq(bad_name, -1)
}

///|
test "[invariants] mirror - the escapers never trip their own invariant on payloads" {
  let payloads : Array[String] = [
    "<script>alert('x')</script>", "\" onmouseover=\"alert(1)", "a&b&amp;c&xmp;d&",
    "&amp;&lt;&gt;&quot;&#39;", "../../etc/passwd", "a/b\\c:d*e?f\"g<h>i|j", "文😀文 & < > \" '",
    "",
  ]
  for s in payloads {
    assert_true(@lib.html_is_escaped(@lib.escape_html(s)))
    assert_true(@lib.attr_is_escaped(@lib.escape_attr(s)))
    assert_true(@lib.filename_is_sanitized(@lib.sanitize_filename(s)))
  }
}

///|
test "[invariants] mirror - the predicates are not vacuous" {
  // Raw markup must be rejected, otherwise the mirror accepts anything.
  assert_false(@lib.html_is_escaped("<b>"))
  assert_false(@lib.html_is_escaped("a > b"))
  assert_false(@lib.html_is_escaped("a & b"))
  assert_false(@lib.html_is_escaped("&xmp;"))
  assert_false(@lib.html_is_escaped("&am"))
  assert_false(@lib.html_is_escaped("&"))
  // Attribute escaping is strictly stronger than text escaping.
  assert_false(@lib.attr_is_escaped("\"quoted\""))
  assert_false(@lib.attr_is_escaped("'single'"))
  assert_true(@lib.html_is_escaped("\"quoted\""))
  // Filenames reject the nine characters and the empty string.
  assert_false(@lib.filename_is_sanitized("a/b"))
  assert_false(@lib.filename_is_sanitized("a:b"))
  assert_false(@lib.filename_is_sanitized(""))
  // ... control characters, directory references, a trailing dot or space,
  // and Windows device names.
  assert_false(@lib.filename_is_sanitized("a\u{0}b"))
  assert_false(@lib.filename_is_sanitized(".."))
  assert_false(@lib.filename_is_sanitized("report."))
  assert_false(@lib.filename_is_sanitized("report "))
  assert_false(@lib.filename_is_sanitized("NUL.txt"))
  assert_true(@lib.filename_is_sanitized("普通文件名-01.png"))
  assert_true(@lib.filename_is_sanitized("A🙂B"))
  // Accepted entities are exactly the five emitted ones.
  for e in ["&amp;", "&lt;", "&gt;", "&quot;", "&#39;"] {
    assert_true(@lib.html_is_escaped(e))
  }
}

///|
test "[invariants] mirror - a lone ampersand is the interesting boundary" {
  // `&` must be rejected, `&amp;` accepted, and the scan must keep going after
  // a valid entity rather than skipping its characters.
  assert_false(@lib.html_is_escaped("&"))
  assert_true(@lib.html_is_escaped("&amp;"))
  assert_false(@lib.html_is_escaped("&amp;&"))
  assert_true(@lib.html_is_escaped("&amp;&amp;"))
  // The entity's own characters must not be re-interpreted as markup.
  assert_false(@lib.html_is_escaped("&amp;<"))
}
