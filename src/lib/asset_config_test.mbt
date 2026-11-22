///|
/// Explicit configuration injection: consumers can replace the example-domain
/// allow-list and query defaults without forking `core.mbt`.
test "[config] custom host and params" {
  let cfg = @lib.create_asset_config(["cdn.internal.example"], [
    "w=800", "auto=1",
  ])
  assert_eq(
    @lib.normalize_asset_url_with_config(
      "http://cdn.internal.example/a.png", cfg,
    ),
    "https://cdn.internal.example/a.png?w=800&auto=1",
  )
  assert_eq(
    @lib.decide_referrer_policy_with_config(
      "https://cdn.internal.example/a.png", cfg,
    ),
    "no-referrer-when-downgrade",
  )
  assert_eq(
    @lib.decide_referrer_policy_with_config("https://other.example/a.png", cfg),
    "no-referrer",
  )
}

///|
test "[config] host outside the config is untouched" {
  let cfg = @lib.create_asset_config(["cdn.internal.example"], ["w=800"])
  assert_eq(
    @lib.normalize_asset_url_with_config("http://cdn.example.com/a.png", cfg),
    "http://cdn.example.com/a.png",
  )
}

///|
test "[config] existing keys are not duplicated" {
  let cfg = @lib.create_asset_config(["cdn.internal.example"], [
    "w=800", "auto=1",
  ])
  assert_eq(
    @lib.normalize_asset_url_with_config(
      "https://cdn.internal.example/a.png?w=640", cfg,
    ),
    "https://cdn.internal.example/a.png?w=640&auto=1",
  )
}

///|
test "[config] default wrapper keeps historical behaviour" {
  assert_eq(
    @lib.normalize_asset_url("http://cdn.example.com/a.png"),
    "https://cdn.example.com/a.png?fmt=png&v=1",
  )
  assert_eq(
    @lib.decide_referrer_policy("https://assets.example.org/a.png"),
    "no-referrer-when-downgrade",
  )
}

///|
test "[config] result variant uses injected config" {
  let cfg = @lib.create_asset_config(["cdn.internal.example"], ["w=800"])
  match
    @lib.normalize_asset_url_with_config_result(
      "http://cdn.internal.example/a.png", cfg,
    ) {
    Ok(s) => assert_eq(s, "https://cdn.internal.example/a.png?w=800")
    Err(e) => {
      println(@lib.error_to_string(e))
      panic()
    }
  }
}
