// Tests for the WASM export shim in `exports.mbt`.
//
// Every export must stay a faithful, logic-free bridge to `src/lib`: the
// conformance corpus and the runtime invariants live there, and the WASM-GC
// link table in `moon.pkg` must expose exactly the functions documented in
// `SKILL.md`. These tests pin the wiring (export == lib) and the two pieces
// of real logic the shim owns: the `str_contains` boolean mapping and the
// joined-string round trip.

///|
test "[exports] direct delegates agree with the lib API" {
  for s in ["", "abc", "<a & b>", "中文😀", "x\" onload='y'"] {
    assert_eq(escape_html(s), @lib.escape_html(s))
    assert_eq(escape_attr(s), @lib.escape_attr(s))
    assert_eq(sanitize_filename(s), @lib.sanitize_filename(s))
    assert_eq(normalize_asset_url(s), @lib.normalize_asset_url(s))
    assert_eq(decide_referrer_policy(s), @lib.decide_referrer_policy(s))
    assert_eq(escape_html_safe(s), @lib.escape_html_safe(s))
    assert_eq(escape_attr_safe(s), @lib.escape_attr_safe(s))
    assert_eq(sanitize_filename_safe(s), @lib.sanitize_filename_safe(s))
  }
}

///|
test "[exports] concrete outputs stay pinned" {
  assert_eq(escape_html("<b>"), "&lt;b&gt;")
  assert_eq(escape_attr("x\""), "x&quot;")
  assert_eq(sanitize_filename("a/b"), "a_b")
  assert_eq(
    normalize_asset_url("https://cdn.example.com/a.png"),
    "https://cdn.example.com/a.png?fmt=png&v=1",
  )
}

///|
test "[exports] str_contains maps the boolean to the documented strings" {
  assert_eq(str_contains("hello", "ell"), "true")
  assert_eq(str_contains("hello", "world"), "false")
}

///|
test "[exports] joined exports round-trip through the separator" {
  assert_eq(escape_htmls_joined("<a>,<b>", ","), "&lt;a&gt;,&lt;b&gt;")
  assert_eq(escape_attrs_joined("x\"y,z", ","), "x&quot;y,z")
  assert_eq(sanitize_filenames_joined("a/b,c/d", ","), "a_b,c_d")
  assert_eq(
    normalize_asset_urls_joined(
      "https://cdn.example.com/a.png,https://cdn.example.com/b.png", ",",
    ),
    "https://cdn.example.com/a.png?fmt=png&v=1,https://cdn.example.com/b.png?fmt=png&v=1",
  )
}
