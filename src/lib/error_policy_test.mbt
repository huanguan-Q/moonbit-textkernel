// Tests for the configurable failure policy.
//
// The production path is the `*_result` API, which never aborts. The
// String-returning compatibility layer routes every failure through
// `apply_failure_policy`, so the abort surface is one function. These tests
// pin the domain guard, the policy behaviour and the never-fail variants.

///|
test "[policy] domain guard rejects above the shipping cap" {
  match @lib.check_code_unit_count(@lib.MAX_SHIPPING_CODE_UNITS + 1, "probe") {
    Err(e) => {
      let msg = @lib.error_to_string(e)
      assert_eq(@lib.str_contains(msg, "Input Too Large:"), true)
      assert_eq(@lib.str_contains(msg, "exceeds MAX_SHIPPING_CODE_UNITS"), true)
    }
    Ok(_) => assert_true(false)
  }
}

///|
test "[policy] domain guard accepts exactly the shipping cap" {
  match @lib.check_code_unit_count(@lib.MAX_SHIPPING_CODE_UNITS, "probe") {
    Ok(_) => assert_true(true)
    Err(_) => assert_true(false)
  }
}

///|
test "[policy] EmptyOnError returns a safe empty string" {
  // Obtain a real error instead of constructing a CoreError from outside the
  // package (enum variants are read-only across package boundaries).
  match @lib.check_code_unit_count(@lib.MAX_SHIPPING_CODE_UNITS + 1, "probe") {
    Err(e) =>
      assert_eq(@lib.apply_failure_policy(e, @lib.empty_on_error_policy()), "")
    Ok(_) => assert_true(false)
  }
}

///|
test "[policy] never-fail variants agree with the fail-fast API on valid input" {
  for s in ["", "abc", "<a & b>", "中文😀", "x\" onload='y'"] {
    assert_eq(@lib.escape_html_safe(s), @lib.escape_html(s))
    assert_eq(@lib.escape_attr_safe(s), @lib.escape_attr(s))
    assert_eq(@lib.sanitize_filename_safe(s), @lib.sanitize_filename(s))
  }
}

///|
test "[policy] explicit policy matches the compatibility layer" {
  for s in ["", "abc", "<a & b>"] {
    assert_eq(
      @lib.escape_html_with_policy(s, @lib.fail_fast_policy()),
      @lib.escape_html(s),
    )
    assert_eq(
      @lib.escape_html_with_policy(s, @lib.empty_on_error_policy()),
      @lib.escape_html_safe(s),
    )
  }
}

///|
test "[policy] result variants no longer route through the abort layer" {
  // A valid input must return Ok from the checked implementation itself.
  match @lib.escape_html_result("<a & b>") {
    Ok(v) => assert_eq(v, "&lt;a &amp; b&gt;")
    Err(_) => assert_true(false)
  }
  match @lib.escape_attr_result("x\"") {
    Ok(v) => assert_eq(v, "x&quot;")
    Err(_) => assert_true(false)
  }
  match @lib.sanitize_filename_result("a/b") {
    Ok(v) => assert_eq(v, "a_b")
    Err(_) => assert_true(false)
  }
}
