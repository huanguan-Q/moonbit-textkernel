// Black-box edge-case tests for core public APIs

///|
fn repeat_char(c : Char, n : Int32) -> String {
  let mut s = ""
  let mut i = 0
  while i < n {
    s = s + c.to_string()
    i = i + 1
  }
  s
}

// normalize_asset_url edge cases

///|
test "[core-edge-cases] normalize - uppercase host unchanged" {
  assert_eq(
    @lib.normalize_asset_url("https://CDN.EXAMPLE.COM/a.png"),
    "https://CDN.EXAMPLE.COM/a.png",
  )
}

///|
test "[core-edge-cases] normalize - trailing question mark adds & then params" {
  let url = "https://cdn.example.com/img?"
  assert_eq(
    @lib.normalize_asset_url(url),
    "https://cdn.example.com/img?&fmt=png&v=1",
  )
}

///|
test "[core-edge-cases] normalize - fmt empty adds only tp" {
  let url = "https://cdn.example.com/a?fmt="
  assert_eq(@lib.normalize_asset_url(url), "https://cdn.example.com/a?fmt=&v=1")
}

///|
test "[core-edge-cases] normalize - tp present (non-webp) adds only fmt" {
  let url = "https://cdn.example.com/a?v=jpeg"
  assert_eq(
    @lib.normalize_asset_url(url),
    "https://cdn.example.com/a?v=jpeg&fmt=png",
  )
}

// ========== Additional Edge Cases for Optimized Functions ==========

///|
test "[core-edge-cases] str_contains - empty needle always true" {
  assert_eq(@lib.str_contains("", ""), true)
  assert_eq(@lib.str_contains("hello", ""), true)
}

///|
test "[core-edge-cases] str_contains - needle longer than haystack" {
  assert_eq(@lib.str_contains("hi", "hello"), false)
}

///|
test "[core-edge-cases] str_contains - single char optimization" {
  assert_eq(@lib.str_contains("hello", "h"), true)
  assert_eq(@lib.str_contains("hello", "o"), true)
  assert_eq(@lib.str_contains("hello", "x"), false)
}

///|
test "[core-edge-cases] str_contains - repeated patterns" {
  assert_eq(@lib.str_contains("aaaaaaa", "aaa"), true)
  assert_eq(@lib.str_contains("abababab", "bab"), true)
}

///|
test "[core-edge-cases] str_contains - unicode support" {
  assert_eq(@lib.str_contains("你好世界", "世界"), true)
  assert_eq(@lib.str_contains("🎉🎊🎈", "🎊"), true)
}

///|
test "[core-edge-cases] sanitize_filename - empty defaults to file" {
  assert_eq(@lib.sanitize_filename(""), "file")
}

///|
test "[core-edge-cases] sanitize_filename - clean filename unchanged" {
  assert_eq(@lib.sanitize_filename("document.txt"), "document.txt")
  assert_eq(@lib.sanitize_filename("image_001.jpg"), "image_001.jpg")
}

///|
test "[core-edge-cases] sanitize_filename - all invalid chars" {
  assert_eq(@lib.sanitize_filename("/\\:*?\"<>|"), "_________")
}

///|
test "[core-edge-cases] sanitize_filename - length limit 120" {
  let long_name = repeat_char('a', 150)
  let result = @lib.sanitize_filename(long_name)
  assert_eq(result.length(), 120)
}

///|
test "[core-edge-cases] sanitize_filename - unicode handling" {
  // ASCII characters are preserved
  assert_eq(@lib.sanitize_filename("document.txt"), "document.txt")
  // Emoji and surrogate pairs become underscores (original behavior)
  assert_eq(@lib.sanitize_filename("🎉party🎊.jpg"), "__party__.jpg")
}

///|
test "[core-edge-cases] decide_referrer_policy - empty string" {
  assert_eq(@lib.decide_referrer_policy(""), "no-referrer")
}

///|
test "[core-edge-cases] decide_referrer_policy - case sensitive" {
  assert_eq(
    @lib.decide_referrer_policy("https://CDN.EXAMPLE.COM/image.jpg"),
    "no-referrer",
  )
}

///|
test "[core-edge-cases] normalize - very long url" {
  let base = "https://cdn.example.com/" + repeat_char('a', 500)
  let expected = base + "?fmt=png&v=1"
  assert_eq(@lib.normalize_asset_url(base), expected)
}

///|
test "[core-edge-cases] performance - str_contains long haystack" {
  let haystack = repeat_char('a', 1000) + "needle" + repeat_char('b', 1000)
  assert_eq(@lib.str_contains(haystack, "needle"), true)
  assert_eq(@lib.str_contains(haystack, "missing"), false)
}

///|
test "[core-edge-cases] normalize - empty input unchanged" {
  assert_eq(@lib.normalize_asset_url(""), "")
}

// decide_referrer_policy edge cases

///|
test "[core-edge-cases] policy - empty input uses no-referrer" {
  assert_eq(@lib.decide_referrer_policy(""), "no-referrer")
}

// sanitize_filename edge cases

///|
test "[core-edge-cases] sanitize - only invalid ascii become underscores" {
  // Invalid set: / \ : * ? " < > |
  assert_eq(@lib.sanitize_filename("/\\:*?\"<>|"), "_________")
}

///|
test "[core-edge-cases] sanitize - unicode preserved" {
  assert_eq(@lib.sanitize_filename("文档V1"), "文档V1")
}

///|
test "[core-edge-cases] sanitize - long invalid chars clamp to 120" {
  let s = repeat_char('/', 200)
  let want = repeat_char('_', 120)
  assert_eq(@lib.sanitize_filename(s), want)
}

///|
test "[core-edge-cases] sanitize - exactly 120 length kept" {
  let s = repeat_char('x', 120)
  assert_eq(@lib.sanitize_filename(s), s)
}
