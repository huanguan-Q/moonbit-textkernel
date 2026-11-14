///|
/// Regressions for the joined-list ABI (`split_joined` / `join_joined`) and the
/// batch exports built on it.
///
/// The bug these pin: the splitter used to rebuild every code unit through
/// `UInt16::to_char()`, whose `None` fallback wrote `_`. A non-BMP character is
/// two surrogate code units, so `a/😀.png` came out as `a/__.png` — the payload
/// changed while the length stayed plausible, which is exactly why the existing
/// "unicode preserved" test (BMP-only corpus) did not catch it.

///|
fn assert_same_elements(
  actual : Array[String],
  expected : Array[String],
) -> Unit raise {
  assert_eq(actual.length(), expected.length())
  for i = 0; i < expected.length(); i = i + 1 {
    assert_eq(actual[i], expected[i])
  }
}

///|
fn repeat_ascii(s : String, n : Int32) -> String {
  let mut out = ""
  for i = 0; i < n; i = i + 1 {
    out = out + s
  }
  out
}

///|
test "[joined-abi] joined - split then join is the identity on ASCII" {
  let sep = "\u{1}"
  let cases : Array[String] = [
    "", "a", "a\u{1}b", "a\u{1}\u{1}b", "\u{1}", "\u{1}\u{1}",
  ]
  for i = 0; i < cases.length(); i = i + 1 {
    let parts = @lib.split_joined(cases[i], sep)
    assert_eq(@lib.join_joined(parts, sep), cases[i])
  }
}

///|
test "[joined-abi] joined - element layout is preserved" {
  let sep = "\u{1}"
  // Adjacent separators must yield an empty element, not be collapsed.
  assert_same_elements(@lib.split_joined("x" + sep + sep + "y", sep), [
    "x", "", "y",
  ])
  // A single empty input is one empty element, not zero elements.
  assert_same_elements(@lib.split_joined("", sep), [""])
  // An empty separator means "no separator".
  assert_same_elements(@lib.split_joined("a/b", ""), ["a/b"])
}

///|
test "[joined-abi] joined - non-BMP characters survive the split" {
  let sep = "\u{1}"
  let emoji = "😀"
  assert_same_elements(@lib.split_joined(emoji, sep), [emoji])
  assert_same_elements(@lib.split_joined("a" + emoji + "b", sep), ["a😀b"])
  assert_same_elements(@lib.split_joined("文😀" + sep + "图", sep), [
    "文😀", "图",
  ])
  // The regression itself: two code units in, two code units out, unchanged.
  assert_eq(@lib.split_joined(emoji, sep)[0].length(), emoji.length())
}

///|
test "[joined-abi] joined - normalize_asset_urls_joined keeps a non-BMP URL intact" {
  let sep = "\u{1}"
  let u = "https://cdn.example.com/a/😀.png?fmt=png&v=1"
  let out = @lib.join_joined(
    @lib.quick_batch_normalize_urls(@lib.split_joined(u, sep)),
    sep,
  )
  // Before the fix this was "https://cdn.example.com/a/__.png?fmt=png&v=1".
  assert_false(@lib.str_contains(out, "__"))
  assert_eq(out, u)
}

///|
test "[joined-abi] joined - every batch path agrees with its scalar counterpart" {
  let sep = "\u{1}"
  let inputs : Array[String] = [
    "a/b", "<x>&y", "\"A'B", "文😀文", "https://cdn.example.com/a/😀.png",
    "",
  ]
  let joined = @lib.join_joined(inputs, sep)

  // normalize
  let got_norm = @lib.split_joined(
    @lib.join_joined(
      @lib.quick_batch_normalize_urls(@lib.split_joined(joined, sep)),
      sep,
    ),
    sep,
  )
  for i = 0; i < inputs.length(); i = i + 1 {
    assert_eq(got_norm[i], @lib.normalize_asset_url(inputs[i]))
  }

  // sanitize
  let got_san = @lib.split_joined(
    @lib.join_joined(
      @lib.quick_batch_sanitize_filenames(@lib.split_joined(joined, sep)),
      sep,
    ),
    sep,
  )
  for i = 0; i < inputs.length(); i = i + 1 {
    assert_eq(got_san[i], @lib.sanitize_filename(inputs[i]))
  }

  // escape_html
  let got_html = @lib.split_joined(
    @lib.join_joined(
      @lib.quick_batch_escape_htmls(@lib.split_joined(joined, sep)),
      sep,
    ),
    sep,
  )
  for i = 0; i < inputs.length(); i = i + 1 {
    assert_eq(got_html[i], @lib.escape_html(inputs[i]))
  }

  // escape_attr
  let got_attr = @lib.split_joined(
    @lib.join_joined(
      @lib.quick_batch_escape_attrs(@lib.split_joined(joined, sep)),
      sep,
    ),
    sep,
  )
  for i = 0; i < inputs.length(); i = i + 1 {
    assert_eq(got_attr[i], @lib.escape_attr(inputs[i]))
  }
}

///|
test "[joined-abi] joined - sanitize clamp counts code units, not characters" {
  let sep = "\u{1}"
  // 121 code units of legal characters is one past the 120 clamp.
  let long = repeat_ascii("a", 121)
  let got = @lib.join_joined(
    @lib.quick_batch_sanitize_filenames(@lib.split_joined(long, sep)),
    sep,
  )
  assert_eq(got.length(), 120)
  assert_eq(got, @lib.sanitize_filename(long))
  // An emoji is two code units and both become `_`: the clamp must agree with
  // the scalar path on where it cuts.
  let with_emoji = repeat_ascii("a", 118) + "😀"
  let got2 = @lib.join_joined(
    @lib.quick_batch_sanitize_filenames(@lib.split_joined(with_emoji, sep)),
    sep,
  )
  assert_eq(got2, @lib.sanitize_filename(with_emoji))
  assert_eq(got2.length(), 120)
}

///|
test "[joined-abi] joined - round trip and element count over a dense alphabet" {
  // Every string of length <= 3 over {a, separator, emoji}: 1 + 3 + 9 + 27 = 40
  // cases. Each carries the number of separators it was built with, so the
  // layout law `|split s| == separators(s) + 1` can be checked without a second
  // scanner that could share a bug with the splitter.
  let sep = "\u{1}"
  let pieces : Array[(String, Int32)] = [("a", 0), (sep, 1), ("😀", 0)]
  let all : Array[(String, Int32)] = [("", 0)]
  let mut frontier : Array[(String, Int32)] = [("", 0)]
  for _len = 0; _len < 3; _len = _len + 1 {
    let next : Array[(String, Int32)] = []
    for base in frontier {
      for pc in pieces {
        next.push((base.0 + pc.0, base.1 + pc.1))
      }
    }
    for c in next {
      all.push(c)
    }
    frontier = next
  }
  assert_eq(all.length(), 40)
  let mut bad_round_trip = -1
  let mut bad_count = -1
  for i = 0; i < all.length(); i = i + 1 {
    let s = all[i].0
    let seps = all[i].1
    let parts = @lib.split_joined(s, sep)
    if @lib.join_joined(parts, sep) != s {
      bad_round_trip = i
    }
    if parts.length() != seps + 1 {
      bad_count = i
    }
  }
  assert_eq(bad_round_trip, -1)
  assert_eq(bad_count, -1)
}
