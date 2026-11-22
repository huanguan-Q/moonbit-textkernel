// Legacy-vs-StringBuilder differential.
//
// The shipping escapers and the filename sanitiser were rewritten from
// `out = out + x` (quadratic on the native backend) to StringBuilder writes.
// The existing corpus tests pin behaviour against the *proved kernels*, but
// they do not by themselves prove that `write_char(c)` produces exactly what
// `c.to_string()` used to — in particular for non-ASCII code units.
//
// This file keeps the original implementations as private oracles and asserts
// byte-for-byte equality over an enumerated corpus plus 200 deterministic
// pseudo-random strings. If the rewrite ever changes observable behaviour,
// these tests fail before the proof corpus has to notice.

///|
/// Local copy of the private character predicate (test units cannot see `fn`).
fn diff_is_invalid_filename_char(code : UInt16) -> Bool {
  code == '/' ||
  code == '\\' ||
  code == ':' ||
  code == '*' ||
  code == '?' ||
  code == '"' ||
  code == '<' ||
  code == '>' ||
  code == '|'
}

///|
/// Original `escape_html`, kept verbatim as an oracle.
fn escape_html_legacy(input : String) -> String {
  let mut i = 0
  let mut out = ""
  while i < input.length() {
    let code = input[i]
    if code == '&' {
      out = out + "&amp;"
      i = i + 1
      continue
    }
    if code == '<' {
      out = out + "&lt;"
      i = i + 1
      continue
    }
    if code == '>' {
      out = out + "&gt;"
      i = i + 1
      continue
    }
    match code.to_char() {
      Some(c) => {
        out = out + c.to_string()
        i = i + 1
      }
      None => {
        out = out + "_"
        i = i + 1
      }
    }
  }
  if !@lib.html_is_escaped(out) {
    abort("legacy escape_html invariant")
  }
  out
}

///|
/// Original `escape_attr`, kept verbatim as an oracle.
fn escape_attr_legacy(input : String) -> String {
  let mut i = 0
  let mut out = ""
  while i < input.length() {
    let code = input[i]
    if code == '&' {
      out = out + "&amp;"
      i = i + 1
      continue
    }
    if code == '<' {
      out = out + "&lt;"
      i = i + 1
      continue
    }
    if code == '>' {
      out = out + "&gt;"
      i = i + 1
      continue
    }
    if code == '"' {
      out = out + "&quot;"
      i = i + 1
      continue
    }
    if code == '\'' {
      out = out + "&#39;"
      i = i + 1
      continue
    }
    match code.to_char() {
      Some(c) => {
        out = out + c.to_string()
        i = i + 1
      }
      None => {
        out = out + "_"
        i = i + 1
      }
    }
  }
  if !@lib.attr_is_escaped(out) {
    abort("legacy escape_attr invariant")
  }
  out
}

///|
/// Original `sanitize_filename`, kept verbatim as an oracle.
fn sanitize_filename_legacy(name : String) -> String {
  let base = if name.length() == 0 { "file" } else { name }
  let mut i = 0
  let mut out = ""
  let mut count = 0
  while i < base.length() && count < 120 {
    let code = base[i]
    if diff_is_invalid_filename_char(code) {
      out = out + "_"
      i = i + 1
      count = count + 1
      continue
    }
    match code.to_char() {
      Some(c) => {
        out = out + c.to_string()
        i = i + 1
        count = count + 1
      }
      None => {
        out = out + "_"
        i = i + 1
        count = count + 1
      }
    }
  }
  if !@lib.filename_is_sanitized(out) {
    abort("legacy sanitize_filename invariant")
  }
  out
}

///|
/// Deterministic corpus: fixed boundaries plus a Lehmer-style PRNG over a
/// character pool that includes every branch of all three functions.
fn differential_corpus() -> Array[String] {
  let pool : Array[String] = [
    "&", "<", ">", "\"", "'", "/", "\\", ":", "*", "?", "|", "a", "z", "0", "9",
    " ", "中", "文", "日", "é", "😀", "\n", "\t", "&amp;", "&xmp;", "<script>",
  ]
  let corpus : Array[String] = []
  corpus.push("")
  corpus.push("&")
  corpus.push("<")
  corpus.push(">")
  corpus.push("\"'")
  corpus.push("a&b<c>d")
  corpus.push("中文字&😀")
  corpus.push("😀")
  corpus.push("&amp;&lt;&gt;")
  corpus.push("/\\:*?\"<>|")
  // Length boundaries around the 120-code-unit clamp.
  for n in [1, 118, 119, 120, 121, 122, 240] {
    let b = StringBuilder(capacity=n)
    for _j = 0; _j < n; _j = _j + 1 {
      b.write_string("x")
    }
    corpus.push(b.to_string())
  }
  let mut seed = 12345
  for _case = 0; _case < 200; _case = _case + 1 {
    seed = (seed * 31 + 17) % 1048576
    let len = seed % 160
    let b = StringBuilder(capacity=len)
    for _j = 0; _j < len; _j = _j + 1 {
      seed = (seed * 31 + 17) % 1048576
      b.write_string(pool[seed % pool.length()])
    }
    corpus.push(b.to_string())
  }
  corpus
}

///|
test "[diff] escape_html matches the legacy concatenation implementation" {
  for s in differential_corpus() {
    assert_eq(@lib.escape_html(s), escape_html_legacy(s))
  }
}

///|
test "[diff] escape_attr matches the legacy concatenation implementation" {
  for s in differential_corpus() {
    assert_eq(@lib.escape_attr(s), escape_attr_legacy(s))
  }
}

///|
test "[diff] sanitize_filename matches the legacy concatenation implementation" {
  for s in differential_corpus() {
    assert_eq(@lib.sanitize_filename(s), sanitize_filename_legacy(s))
  }
}
