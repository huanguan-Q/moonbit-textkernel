///|
/// Black-box tests for core public APIs
test "[core] normalize - non asset unchanged" {
  assert_eq(
    @lib.normalize_asset_url("https://example.com/a.png"),
    "https://example.com/a.png",
  )
}

///|
test "[core] normalize - add both when none and no query" {
  let url = "https://cdn.example.com/path/img"
  assert_eq(
    @lib.normalize_asset_url(url),
    "https://cdn.example.com/path/img?fmt=png&v=1",
  )
}

///|
test "[core] normalize - add both when none and has query" {
  let url = "https://cdn.example.com/path/img?x=1"
  assert_eq(
    @lib.normalize_asset_url(url),
    "https://cdn.example.com/path/img?x=1&fmt=png&v=1",
  )
}

///|
test "[core] normalize - only add tp when fmt exists" {
  let url = "https://cdn.example.com/a/b.png?fmt=jpeg"
  assert_eq(
    @lib.normalize_asset_url(url),
    "https://cdn.example.com/a/b.png?fmt=jpeg&v=1",
  )
}

///|
test "[core] normalize - only add fmt when tp exists" {
  let url = "https://cdn.example.com/a/b.png?v=1"
  assert_eq(
    @lib.normalize_asset_url(url),
    "https://cdn.example.com/a/b.png?v=1&fmt=png",
  )
}

///|
test "[core] normalize - unchanged when both present" {
  let url = "https://cdn.example.com/a/b.png?v=1&fmt=png"
  assert_eq(@lib.normalize_asset_url(url), url)
}

///|
test "[core] normalize - long asset url still appends params" {
  let tail = repeat('a', 1980)
  let url = "https://cdn.example.com/" + tail
  let result = @lib.normalize_asset_url(url)
  assert_eq(@lib.str_contains(result, "fmt=png"), true)
  assert_eq(@lib.str_contains(result, "v=1"), true)
}

///|
test "[core] normalize - subdomain asset host" {
  let url = "https://sub.cdn.example.com/a.png"
  assert_eq(
    @lib.normalize_asset_url(url),
    "https://sub.cdn.example.com/a.png?fmt=png&v=1",
  )
}

///|
test "[core] normalize - a host that only occurs in the query is not an asset host" {
  // The allow-list is applied to the URL's own host. A CDN address that is
  // merely a value inside somebody else's query must not get rewritten.
  let url = "https://example.com/?img=https://cdn.example.com/a.png"
  assert_eq(@lib.normalize_asset_url(url), url)
}

///|
test "[core] policy - asset cdn uses no-referrer-when-downgrade" {
  assert_eq(
    @lib.decide_referrer_policy("https://cdn.example.com/a/b.png"),
    "no-referrer-when-downgrade",
  )
}

///|
test "[core] policy - non asset uses no-referrer" {
  assert_eq(
    @lib.decide_referrer_policy("https://example.com/a/b.png"),
    "no-referrer",
  )
}

///|
test "[core] policy - a host that only occurs in the query is not an asset host" {
  let url = "https://example.com/?img=https://cdn.example.com/a.png"
  assert_eq(@lib.decide_referrer_policy(url), "no-referrer")
}

///|
test "[core] policy - uppercase host is the same host" {
  // A DNS name has no letter case, so the allow-list ignores it.
  let url = "https://CDN.EXAMPLE.COM/a.png"
  assert_eq(@lib.decide_referrer_policy(url), "no-referrer-when-downgrade")
}

///|
fn repeat(c : Char, n : Int32) -> String {
  let mut s = ""
  let mut i = 0
  while i < n {
    s = s + c.to_string()
    i = i + 1
  }
  s
}

///|
test "[core] sanitize - empty becomes file" {
  assert_eq(@lib.sanitize_filename(""), "file")
}

///|
test "[core] sanitize - replace invalid ascii" {
  assert_eq(
    @lib.sanitize_filename("a/b\\c:d*e?f\"g<h>i|j"),
    "a_b_c_d_e_f_g_h_i_j",
  )
}

///|
test "[core] sanitize - a character outside the BMP is one character" {
  // '🙂' is a well-formed surrogate pair: it is copied whole, not replaced.
  assert_eq(@lib.sanitize_filename("A🙂B"), "A🙂B")
}

///|
test "[core] sanitize - clamp to 120 chars" {
  let long = repeat('x', 130)
  let want = repeat('x', 120)
  assert_eq(@lib.sanitize_filename(long), want)
}

///|
test "[core] escape_html - basic entities" {
  assert_eq(@lib.escape_html("a&b<c>d"), "a&amp;b&lt;c&gt;d")
}

///|
test "[core] escape_html - quotes remain intact" {
  assert_eq(@lib.escape_html("\"'"), "\"'")
}

// ===== Edge cases from core_edge_cases_test.mbt (merged) =====

// @lib.normalize_asset_url edge cases

///|
test "[core] normalize - uppercase host is the same host, kept as written" {
  // The host matches the allow-list and gets its parameters; the letters of
  // the authority are carried over verbatim.
  assert_eq(
    @lib.normalize_asset_url("https://CDN.EXAMPLE.COM/a.png"),
    "https://CDN.EXAMPLE.COM/a.png?fmt=png&v=1",
  )
}

///|
test "[core] normalize - empty query receives the params without a stray &" {
  let url = "https://cdn.example.com/img?"
  assert_eq(
    @lib.normalize_asset_url(url),
    "https://cdn.example.com/img?fmt=png&v=1",
  )
}

///|
test "[core] normalize - fmt empty adds only tp" {
  let url = "https://cdn.example.com/a?fmt="
  assert_eq(@lib.normalize_asset_url(url), "https://cdn.example.com/a?fmt=&v=1")
}

///|
test "[core] normalize - tp present (non-webp) adds only fmt" {
  let url = "https://cdn.example.com/a?v=jpeg"
  assert_eq(
    @lib.normalize_asset_url(url),
    "https://cdn.example.com/a?v=jpeg&fmt=png",
  )
}

///|
test "[core] normalize - empty input unchanged" {
  assert_eq(@lib.normalize_asset_url(""), "")
}

// decide_referrer_policy edge cases

///|
test "[core] policy - empty input uses no-referrer" {
  assert_eq(@lib.decide_referrer_policy(""), "no-referrer")
}

// sanitize_filename edge cases

///|
test "[core] sanitize - only invalid ascii become underscores" {
  // Invalid set: / \ : * ? " < > |
  let s = '/'.to_string() +
    '\\'.to_string() +
    ':'.to_string() +
    '*'.to_string() +
    '?'.to_string() +
    '"'.to_string() +
    '<'.to_string() +
    '>'.to_string() +
    '|'.to_string()
  assert_eq(@lib.sanitize_filename(s), "_________")
}

///|
test "[core] sanitize - unicode preserved" {
  assert_eq(@lib.sanitize_filename("文档V1"), "文档V1")
}

///|
test "[core] sanitize - long invalid chars clamp to 120" {
  let s = repeat('/', 200)
  let want = repeat('_', 120)
  assert_eq(@lib.sanitize_filename(s), want)
}

///|
test "[core] sanitize - exactly 120 length kept" {
  let s = repeat('x', 120)
  assert_eq(@lib.sanitize_filename(s), s)
}

// ===== str_contains tests (merged) =====

///|
/// Tests for internal helper `str_contains`
test "[core] str_contains - empty needle true for non-empty" {
  assert_eq(@lib.str_contains("abc", ""), true)
}

///|
test "[core] str_contains - empty needle true for empty" {
  assert_eq(@lib.str_contains("", ""), true)
}

///|
test "[core] str_contains - empty haystack and non-empty needle false" {
  assert_eq(@lib.str_contains("", "a"), false)
}

///|
test "[core] str_contains - match at start" {
  assert_eq(@lib.str_contains("abc", "ab"), true)
}

///|
test "[core] str_contains - match in middle" {
  assert_eq(@lib.str_contains("abcde", "cd"), true)
}

///|
test "[core] str_contains - match at end" {
  assert_eq(@lib.str_contains("abc", "bc"), true)
}

///|
test "[core] str_contains - no match" {
  assert_eq(@lib.str_contains("abc", "x"), false)
}

///|
test "[core] str_contains - needle longer than haystack" {
  assert_eq(@lib.str_contains("ab", "abc"), false)
}

///|
test "[core] str_contains - overlapping pattern" {
  // "aaaab" contains "aaab" starting at index 1
  assert_eq(@lib.str_contains("aaaab", "aaab"), true)
}

///|
test "[core] str_contains - unicode code unit preserved" {
  assert_eq(@lib.str_contains("ab文cd", "文"), true)
}

///|
test "[core] str_contains - large haystack scan" {
  let mut s = ""
  let mut i = 0
  while i < 200 {
    s = s + "a"
    i = i + 1
  }
  assert_eq(@lib.str_contains(s, "aab"), false)
  assert_eq(@lib.str_contains(s + "b", "aab"), true)
}

///|
test "[core] escape_html - a character outside the BMP passes through" {
  assert_eq(@lib.escape_html("A🙂B"), "A🙂B")
}

///|
test "[core] escape_attr - basic entities incl quotes" {
  let input = "Tom's \"hat\" & <tag>"
  let want = "Tom&#39;s &quot;hat&quot; &amp; &lt;tag&gt;"
  assert_eq(@lib.escape_attr(input), want)
}

///|
test "[core] escape_attr - a character outside the BMP passes through" {
  assert_eq(@lib.escape_attr("A🙂B"), "A🙂B")
}

///|
test "[core] ensure_asset_params - parity with @lib.normalize_asset_url" {
  let url1 = "https://example.com/a.png"
  assert_eq(@lib.ensure_asset_params(url1), @lib.normalize_asset_url(url1))
  let url2 = "https://cdn.example.com/a/b.png"
  assert_eq(@lib.ensure_asset_params(url2), @lib.normalize_asset_url(url2))
  let url3 = "https://cdn.example.com/a/b.png?fmt=jpeg"
  assert_eq(@lib.ensure_asset_params(url3), @lib.normalize_asset_url(url3))
}

///|
/// Result variants: Ok parity with original function
test "[core] normalize_result - ok parity" {
  let url = "https://cdn.example.com/a.png"
  match @lib.normalize_asset_url_result(url) {
    Ok(v) => assert_eq(v, @lib.normalize_asset_url(url))
    _ => assert_eq(true, false) // unexpected Err
  }
}

///|
/// Result variants: a long input is an ordinary input. The only bound is
/// `MAX_SHIPPING_CODE_UNITS`, so a few thousand units behave exactly like five.
test "[core] normalize_result - long input ok" {
  let arg = "https://cdn.example.com/" + repeat('x', 5000)
  match @lib.normalize_asset_url_result(arg) {
    Ok(v) => assert_eq(v, @lib.normalize_asset_url(arg))
    _ => assert_eq(true, false) // unexpected Err
  }
}

///|
/// Result variants: Ok parity for decide_referrer_policy
test "[core] policy_result - ok parity" {
  let url = "https://example.com/a.png"
  match @lib.decide_referrer_policy_result(url) {
    Ok(v) => assert_eq(v, @lib.decide_referrer_policy(url))
    _ => assert_eq(true, false)
  }
}

///|
/// Result variants: a long input is an ordinary input. The only bound is
/// `MAX_SHIPPING_CODE_UNITS`, so a few thousand units behave exactly like five.
test "[core] policy_result - long input ok" {
  let arg = "https://example.com/" + repeat('x', 5000)
  match @lib.decide_referrer_policy_result(arg) {
    Ok(v) => assert_eq(v, @lib.decide_referrer_policy(arg))
    _ => assert_eq(true, false) // unexpected Err
  }
}

///|
/// Result variants: a long input is an ordinary input. The only bound is
/// `MAX_SHIPPING_CODE_UNITS`, so a few thousand units behave exactly like five.
test "[core] sanitize_result - long input ok" {
  let arg = repeat('x', 5000)
  match @lib.sanitize_filename_result(arg) {
    Ok(v) => assert_eq(v, @lib.sanitize_filename(arg))
    _ => assert_eq(true, false) // unexpected Err
  }
}

///|
/// Result variants: a long input is an ordinary input. The only bound is
/// `MAX_SHIPPING_CODE_UNITS`, so a few thousand units behave exactly like five.
test "[core] escape_html_result - long input ok" {
  let arg = repeat('x', 9000)
  match @lib.escape_html_result(arg) {
    Ok(v) => assert_eq(v, @lib.escape_html(arg))
    _ => assert_eq(true, false) // unexpected Err
  }
}

///|
/// Result variants: a long input is an ordinary input. The only bound is
/// `MAX_SHIPPING_CODE_UNITS`, so a few thousand units behave exactly like five.
test "[core] ensure_asset_params_result - long input ok" {
  let arg = "https://cdn.example.com/" + repeat('x', 5000)
  match @lib.ensure_asset_params_result(arg) {
    Ok(v) => assert_eq(v, @lib.ensure_asset_params(arg))
    _ => assert_eq(true, false) // unexpected Err
  }
}

///|
/// Result variants: Ok parity for escape_attr
test "[core] escape_attr_result - ok parity" {
  let input = "Tom's \"hat\" & <tag>"
  match @lib.escape_attr_result(input) {
    Ok(v) => assert_eq(v, @lib.escape_attr(input))
    _ => assert_eq(true, false)
  }
}

///|
/// Result variants: a long input is an ordinary input. The only bound is
/// `MAX_SHIPPING_CODE_UNITS`, so a few thousand units behave exactly like five.
test "[core] escape_attr_result - long input ok" {
  let arg = repeat('x', 9000)
  match @lib.escape_attr_result(arg) {
    Ok(v) => assert_eq(v, @lib.escape_attr(arg))
    _ => assert_eq(true, false) // unexpected Err
  }
}

///|
/// Result variants: Ok parity for ensure_asset_params
test "[core] ensure_asset_params_result - ok parity" {
  let url = "https://cdn.example.com/a/b.png?v=1"
  match @lib.ensure_asset_params_result(url) {
    Ok(v) => assert_eq(v, @lib.ensure_asset_params(url))
    _ => assert_eq(true, false)
  }
}

///|
test "[core] validate_string_input - ok when under max length" {
  match @lib.validate_string_input("validate_test", "abc", 10) {
    Ok(_) => assert_true(true)
    Err(_) => assert_true(false)
  }
}

///|
test "[core] validate_string_input - ok when equal to max length" {
  let s = repeat('x', 10)
  match @lib.validate_string_input("validate_test", s, 10) {
    Ok(_) => assert_true(true)
    Err(_) => assert_true(false)
  }
}

///|
test "[core] validate_string_input - err when exceeding max length" {
  let s = repeat('x', 11)
  match @lib.validate_string_input("validate_test", s, 10) {
    Err(e) => {
      let msg = @lib.error_to_string(e)
      assert_eq(@lib.str_contains(msg, "Input length ("), true)
      assert_eq(@lib.str_contains(msg, "exceeds recommended maximum"), true)
    }
    _ => assert_eq(true, false)
  }
}

///|
/// Tests for assets.example.org domain support and HTTPS enforcement (Mixed Content fix)
test "[core] normalize - asset domain adds params" {
  let url = "https://assets.example.org/asset_jpg/pb0HVeicpG8tAYuxtibic4j0UCzIpuDA3FEqicibFEurkk3MZlXZfuHKBic8fQWkaO9z0ibOcMM1RMO1icM3tupJavt5Sg/0"
  let result = @lib.normalize_asset_url(url)
  assert_eq(@lib.str_contains(result, "fmt=png"), true)
  assert_eq(@lib.str_contains(result, "v=1"), true)
}

///|
test "[core] normalize - asset HTTP converted to HTTPS" {
  let url = "http://assets.example.org/asset_jpg/test.jpg"
  let result = @lib.normalize_asset_url(url)
  assert_eq(@lib.str_contains(result, "https://"), true)
  assert_eq(@lib.str_contains(result, "http://"), false)
  assert_eq(@lib.str_contains(result, "fmt=png"), true)
  // Regression: the host must survive verbatim. A previous implementation
  // rebuilt the tail from UInt16 code units, turning the host into a digit
  // string such as "https://1091099810512246...".
  assert_eq(result, "https://assets.example.org/asset_jpg/test.jpg?fmt=png&v=1")
}

///|
test "[core] normalize - secondary-host HTTP converted to HTTPS" {
  let url = "http://cdn.example.com/asset_png/test.jpg"
  let result = @lib.normalize_asset_url(url)
  assert_eq(@lib.str_contains(result, "https://"), true)
  assert_eq(@lib.str_contains(result, "http://"), false)
  // Regression: exact output must keep the original host and path.
  assert_eq(result, "https://cdn.example.com/asset_png/test.jpg?fmt=png&v=1")
}

///|
test "[core] normalize - HTTP host is never turned into digits" {
  let url = "http://cdn.example.com/a/b.png"
  let result = @lib.normalize_asset_url(url)
  assert_eq(result, "https://cdn.example.com/a/b.png?fmt=png&v=1")
  // The host must not contain a run of decimal code points.
  assert_eq(@lib.str_contains(result, "109109"), false)
}

///|
test "[core] normalize - HTTP scheme rewritten even when query holds an https URL" {
  let url = "http://cdn.example.com/a.png?from=https://example.com/x"
  let result = @lib.normalize_asset_url(url)
  assert_eq(
    result, "https://cdn.example.com/a.png?from=https://example.com/x&fmt=png&v=1",
  )
}

///|
test "[core] normalize - HTTP path with non-ASCII is copied verbatim" {
  let url = "http://cdn.example.com/a/\u4e2d\u6587 b.png"
  let result = @lib.normalize_asset_url(url)
  assert_eq(result, "https://cdn.example.com/a/\u4e2d\u6587 b.png?fmt=png&v=1")
}

///|
test "[core] normalize - asset with both params unchanged" {
  let url = "https://assets.example.org/test.jpg?fmt=jpeg&v=1"
  assert_eq(@lib.normalize_asset_url(url), url)
}

///|
test "[core] policy - asset domain uses no-referrer-when-downgrade" {
  let url = "https://assets.example.org/test.jpg"
  assert_eq(@lib.decide_referrer_policy(url), "no-referrer-when-downgrade")
}

///|
test "[core] policy - asset HTTP URL still detected correctly" {
  let url = "http://assets.example.org/test.jpg"
  assert_eq(@lib.decide_referrer_policy(url), "no-referrer-when-downgrade")
}

///|
test "[core] normalize - non-configured HTTP URL remains unchanged" {
  let url = "http://example.com/image.jpg"
  assert_eq(@lib.normalize_asset_url(url), url)
}
