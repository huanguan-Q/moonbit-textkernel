///|
/// Black-box tests for the shipping domain of the three API tiers.
///
/// Every public entry point accepts the empty string and every input up to
/// `MAX_SHIPPING_CODE_UNITS`. Above that bound, a `*_result` function returns
/// `InputTooLarge`, a `*_safe` function returns `""`, and the fail-fast
/// compatibility layer aborts. There is no second, smaller bound: before,
/// `escape_html_result` refused more than 8,192 code units and the other
/// `*_result` functions more than 4,096, and all of them refused `""`.

///|
/// The value of an `Ok`, or a test failure that names the error.
fn domain_unwrap(r : Result[String, @lib.CoreError]) -> String {
  match r {
    Ok(v) => v
    Err(e) => abort("unexpected error: " + @lib.error_to_string(e))
  }
}

///|
/// The message of an `Err`, or a test failure.
fn domain_error(r : Result[String, @lib.CoreError]) -> String {
  match r {
    Ok(_) => abort("expected an error")
    Err(e) => @lib.error_to_string(e)
  }
}

///|
/// `n` copies of `c`, built by doubling so that eight million units are cheap
/// on every backend.
fn domain_grow(c : Char, n : Int32) -> String {
  let unit = c.to_string()
  let mut out = unit
  while out.length() < n {
    out = out + out
  }
  out[:n].to_owned()
}

///|
test "[domain] empty input is valid in every tier" {
  let cfg = @lib.default_asset_config()
  assert_eq(domain_unwrap(@lib.escape_html_result("")), "")
  assert_eq(domain_unwrap(@lib.escape_attr_result("")), "")
  assert_eq(domain_unwrap(@lib.sanitize_filename_result("")), "file")
  assert_eq(domain_unwrap(@lib.normalize_asset_url_result("")), "")
  assert_eq(
    domain_unwrap(@lib.normalize_asset_url_with_config_result("", cfg)),
    "",
  )
  assert_eq(
    domain_unwrap(@lib.decide_referrer_policy_result("")),
    "no-referrer",
  )
  assert_eq(
    domain_unwrap(@lib.decide_referrer_policy_with_config_result("", cfg)),
    "no-referrer",
  )
  assert_eq(domain_unwrap(@lib.ensure_asset_params_result("")), "")
  assert_eq(
    domain_unwrap(@lib.ensure_asset_params_with_config_result("", cfg)),
    "",
  )
}

///|
test "[domain] the three tiers compute the same thing on valid input" {
  for
    s in ["", "abc", "<a & b>", "中文😀", "report/2026:Q4?.md", "a.", ".."] {
    assert_eq(domain_unwrap(@lib.escape_html_result(s)), @lib.escape_html(s))
    assert_eq(
      domain_unwrap(@lib.escape_html_result(s)),
      @lib.escape_html_safe(s),
    )
    assert_eq(domain_unwrap(@lib.escape_attr_result(s)), @lib.escape_attr(s))
    assert_eq(
      domain_unwrap(@lib.escape_attr_result(s)),
      @lib.escape_attr_safe(s),
    )
    assert_eq(
      domain_unwrap(@lib.sanitize_filename_result(s)),
      @lib.sanitize_filename(s),
    )
    assert_eq(
      domain_unwrap(@lib.sanitize_filename_result(s)),
      @lib.sanitize_filename_safe(s),
    )
  }
  for
    url in [
      "https://cdn.example.com/a.png", "https://example.com/a.png", "http://sub.cdn.example.com",
    ] {
    assert_eq(
      domain_unwrap(@lib.normalize_asset_url_result(url)),
      @lib.normalize_asset_url(url),
    )
    assert_eq(
      domain_unwrap(@lib.decide_referrer_policy_result(url)),
      @lib.decide_referrer_policy(url),
    )
  }
}

///|
test "[domain] a long article is an ordinary input" {
  let article = domain_grow('文', 9000)
  assert_eq(domain_unwrap(@lib.escape_html_result(article)), article)
  assert_eq(domain_unwrap(@lib.escape_attr_result(article)), article)
  assert_eq(
    domain_unwrap(@lib.sanitize_filename_result(article)),
    repeat('文', 120),
  )
  assert_eq(
    domain_unwrap(@lib.decide_referrer_policy_result(article)),
    "no-referrer",
  )
  let url = "https://cdn.example.com/" + domain_grow('a', 9000)
  assert_eq(
    domain_unwrap(@lib.normalize_asset_url_result(url)),
    @lib.normalize_asset_url(url),
  )
  assert_eq(
    domain_unwrap(@lib.ensure_asset_params_result(url)),
    @lib.ensure_asset_params(url),
  )
}

///|
test "[domain] the only bound is MAX_SHIPPING_CODE_UNITS" {
  let cfg = @lib.default_asset_config()
  let at_limit = domain_grow('x', @lib.MAX_SHIPPING_CODE_UNITS)
  let over = at_limit + "x"
  assert_eq(at_limit.length(), 8_000_000)
  assert_eq(over.length(), 8_000_001)
  // At the limit the work is done.
  assert_eq(
    domain_unwrap(@lib.escape_html_result(at_limit)).length(),
    8_000_000,
  )
  // One unit over it, every `*_result` function reports the same reason.
  let errors = [
    domain_error(@lib.escape_html_result(over)),
    domain_error(@lib.escape_attr_result(over)),
    domain_error(@lib.sanitize_filename_result(over)),
    domain_error(@lib.normalize_asset_url_result(over)),
    domain_error(@lib.normalize_asset_url_with_config_result(over, cfg)),
    domain_error(@lib.decide_referrer_policy_result(over)),
    domain_error(@lib.decide_referrer_policy_with_config_result(over, cfg)),
    domain_error(@lib.ensure_asset_params_result(over)),
    domain_error(@lib.ensure_asset_params_with_config_result(over, cfg)),
  ]
  for message in errors {
    assert_true(@lib.str_contains(message, "Input Too Large: "))
    assert_true(@lib.str_contains(message, "exceeds MAX_SHIPPING_CODE_UNITS"))
  }
  // The never-fail variants return "" for the same input, without trapping.
  assert_eq(@lib.escape_html_safe(over), "")
  assert_eq(@lib.escape_attr_safe(over), "")
  assert_eq(@lib.sanitize_filename_safe(over), "")
}
