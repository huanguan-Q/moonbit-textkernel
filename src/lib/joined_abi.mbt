// Joined-list ABI helpers.
//
// The WASM exports in `src/main` expose batch operations over a single string:
// elements are joined with a separator, transformed, and joined again. Splitting
// and joining therefore sit on the boundary between the host and every batch
// kernel, which is why they live here — in a normal package that tests can reach
// — instead of inside `src/main`, where blackbox tests are being deprecated.
//
// The splitting rule is "slice, never rebuild". Rebuilding a code unit through
// `UInt16::to_char()` loses every non-BMP character: an emoji is two surrogate
// code units, `to_char()` returns `None` for both, and the fallback writes `_`
// for each — so `a/😀.png` came out as `a/__.png`. That is the same class of
// mistake as the historical `to_string(UInt16)` bug, which spelled each code
// unit as its decimal value instead. Both corrupt the payload while leaving the
// length plausible, so neither is caught by a length assertion.

///|
/// True when `s` starts with `pat` at code-unit position `pos`.
fn starts_with_at(s : String, pat : String, pos : Int32) -> Bool {
  let pl = pat.length()
  if pl == 0 {
    return true
  }
  if pos + pl > s.length() {
    return false
  }
  let mut j = 0
  while j < pl {
    if s[pos + j] != pat[j] {
      return false
    }
    j = j + 1
  }
  true
}

///|
/// Split `joined` on every occurrence of `sep`.
///
/// Slices by code-unit index (`joined[start:i].to_owned()`) rather than
/// rebuilding each unit as a `Char`, so non-BMP characters survive untouched.
///
/// Edge cases are pinned by `joined_abi_test.mbt`:
/// - empty `sep` means "no separator": the whole input is one element;
/// - an empty `joined` is one empty element, not zero elements;
/// - adjacent separators produce an empty element rather than being collapsed.
pub fn split_joined(joined : String, sep : String) -> Array[String] {
  if sep.length() == 0 {
    return [joined]
  }
  let out : Array[String] = []
  let n = joined.length()
  let mut start = 0
  let mut i = 0
  while i < n {
    if starts_with_at(joined, sep, i) {
      out.push(joined[start:i].to_owned())
      i = i + sep.length()
      start = i
      continue
    }
    i = i + 1
  }
  out.push(joined[start:].to_owned())
  out
}

///|
/// Join `items` with `sep`.
///
/// The exact inverse of `split_joined` for any `sep` that does not itself occur
/// inside an element: `join_joined(split_joined(s, sep), sep) == s`.
pub fn join_joined(items : Array[String], sep : String) -> String {
  let mut out = ""
  let mut first = true
  for item in items {
    if first {
      out = out + item
      first = false
    } else {
      out = out + sep + item
    }
  }
  out
}

///|
/// Escape a list of HTML text nodes.
pub fn quick_batch_escape_htmls(items : Array[String]) -> Array[String] {
  let out : Array[String] = []
  for item in items {
    out.push(escape_html(item))
  }
  out
}

///|
/// Escape a list of HTML attribute values.
pub fn quick_batch_escape_attrs(items : Array[String]) -> Array[String] {
  let out : Array[String] = []
  for item in items {
    out.push(escape_attr(item))
  }
  out
}
