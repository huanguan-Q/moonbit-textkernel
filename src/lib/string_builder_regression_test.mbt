// Reference-vs-StringBuilder differential.
//
// The shipping escapers and the filename sanitiser build their result with a
// StringBuilder. The corpus tests pin behaviour against the *proved kernels*,
// but they do not by themselves show that `write_char(c)` and
// `write_stringview` produce exactly what plain concatenation would — in
// particular for characters outside the BMP, which are two code units.
//
// This file restates the contract with plain concatenation and asserts
// byte-for-byte equality over an enumerated corpus plus 200 deterministic
// pseudo-random strings. The reference is a second implementation of the same
// rules, not a copy of the shipping code: if either one drifts, these tests
// fail before the proof corpus has to notice.

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
/// Reference `escape_html`, with plain concatenation.
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
      None =>
        // A well-formed pair is one character and is copied whole; an unpaired
        // half has no character to copy and becomes `_`.
        if code.is_leading_surrogate() &&
          i + 1 < input.length() &&
          input[i + 1].is_trailing_surrogate() {
          out = out + input[i:i + 2].to_owned()
          i = i + 2
        } else {
          out = out + "_"
          i = i + 1
        }
    }
  }
  if !@lib.html_is_escaped(out) {
    abort("reference escape_html invariant")
  }
  out
}

///|
/// Reference `escape_attr`, with plain concatenation.
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
      None =>
        // A well-formed pair is one character and is copied whole; an unpaired
        // half has no character to copy and becomes `_`.
        if code.is_leading_surrogate() &&
          i + 1 < input.length() &&
          input[i + 1].is_trailing_surrogate() {
          out = out + input[i:i + 2].to_owned()
          i = i + 2
        } else {
          out = out + "_"
          i = i + 1
        }
    }
  }
  if !@lib.attr_is_escaped(out) {
    abort("reference escape_attr invariant")
  }
  out
}

///|
/// ASCII lower case of one code unit, for the host-independent comparisons.
fn diff_lower(c : UInt16) -> Int32 {
  let v = c.to_int()
  if v >= 65 && v <= 90 {
    v + 32
  } else {
    v
  }
}

///|
/// Case-insensitive equality of two strings.
fn diff_ci_eq(a : String, b : String) -> Bool {
  if a.length() != b.length() {
    return false
  }
  let mut i = 0
  let mut same = true
  while i < a.length() {
    if diff_lower(a[i]) != diff_lower(b[i]) {
      same = false
    }
    i = i + 1
  }
  same
}

///|
/// The platform rules of `filename.mbt`, as plain string operations: a name of
/// dots only is the default name, trailing dots and spaces become `_`, and a
/// Windows device name gets a `_` after its stem.
fn diff_finalize(name : String) -> String {
  let mut only_dots = name.length() > 0
  for i = 0; i < name.length(); i = i + 1 {
    if name[i] != '.' {
      only_dots = false
    }
  }
  if only_dots {
    return "file"
  }
  let mut kept = name
  let mut replaced = 0
  while kept.length() > 0 &&
        (kept[kept.length() - 1] == '.' || kept[kept.length() - 1] == ' ') {
    kept = kept[:kept.length() - 1].to_owned()
    replaced = replaced + 1
  }
  let mut marked = kept
  while replaced > 0 {
    marked = marked + "_"
    replaced = replaced - 1
  }
  // The stem is the text before the first dot, without trailing spaces. The
  // marker goes after the stem's last character, so it precedes both the dot
  // and any spaces: `nul.txt` -> `nul_.txt`, `con .txt` -> `con_ .txt`.
  let mut stem = ""
  let mut insert_at = marked.length()
  for i = 0; i < marked.length(); i = i + 1 {
    if marked[i] == '.' {
      insert_at = i
      break
    }
    stem = stem + marked[i:i + 1].to_owned()
  }
  while stem.length() > 0 && stem[stem.length() - 1] == ' ' {
    stem = stem[:stem.length() - 1].to_owned()
    insert_at = insert_at - 1
  }
  let devices : Array[String] = [
    "con", "prn", "aux", "nul", "com1", "com2", "com3", "com4", "com5", "com6", "com7",
    "com8", "com9", "lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7", "lpt8",
    "lpt9", "conin$", "conout$",
  ]
  for device in devices {
    if diff_ci_eq(stem, device) {
      let full = marked[:insert_at].to_owned() +
        "_" +
        marked[insert_at:].to_owned()
      if full.length() <= 120 {
        return full
      }
      let mut cut = 120
      while full[cut - 1].is_leading_surrogate() {
        cut = cut - 1
      }
      return full[:cut].to_owned()
    }
  }
  marked
}

///|
/// Reference `sanitize_filename`, with plain concatenation.
fn sanitize_filename_legacy(name : String) -> String {
  let base = if name.length() == 0 { "file" } else { name }
  let mut i = 0
  let mut out = ""
  while i < base.length() && out.length() < 120 {
    let code = base[i]
    if code.is_leading_surrogate() &&
      i + 1 < base.length() &&
      base[i + 1].is_trailing_surrogate() {
      if out.length() + 2 > 120 {
        break
      }
      out = out + base[i:i + 2].to_owned()
      i = i + 2
      continue
    }
    let replaced = diff_is_invalid_filename_char(code) ||
      code.to_int() < 32 ||
      code.to_int() == 127 ||
      code.is_leading_surrogate() ||
      code.is_trailing_surrogate()
    if replaced {
      out = out + "_"
    } else {
      match code.to_char() {
        Some(c) => out = out + c.to_string()
        None => out = out + "_"
      }
    }
    i = i + 1
  }
  let out = diff_finalize(out)
  if !@lib.filename_is_sanitized(out) {
    abort("reference sanitize_filename invariant")
  }
  out
}

///|
/// Deterministic corpus: fixed boundaries plus a Lehmer-style PRNG over a
/// character pool that includes every branch of all three functions.
fn differential_corpus() -> Array[String] {
  let pool : Array[String] = [
    "&", "<", ">", "\"", "'", "/", "\\", ":", "*", "?", "|", "a", "z", "0", "9",
    " ", ".", "中", "文", "日", "é", "😀", "\u{E000}", "\u{FFFD}", "\n", "\t",
    "&amp;", "&xmp;", "<script>",
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
  // The platform rules: dot-only names, trailing dots and spaces, device names.
  for
    name in [
      ".", "..", "...", "a.", "a ", ". ", "a. ", "CON", "nul.txt", "Com1.tar.gz",
      "LPT9 ", ".hidden",
    ] {
    corpus.push(name)
  }
  // The clamp against a character outside the BMP.
  corpus.push(repeat('x', 118) + "🙂tail")
  corpus.push(repeat('x', 119) + "🙂tail")
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
test "[diff] escape_html matches the plain-concatenation reference" {
  for s in differential_corpus() {
    assert_eq(@lib.escape_html(s), escape_html_legacy(s))
  }
}

///|
test "[diff] escape_attr matches the plain-concatenation reference" {
  for s in differential_corpus() {
    assert_eq(@lib.escape_attr(s), escape_attr_legacy(s))
  }
}

///|
test "[diff] sanitize_filename matches the plain-concatenation reference" {
  for s in differential_corpus() {
    assert_eq(@lib.sanitize_filename(s), sanitize_filename_legacy(s))
  }
}
