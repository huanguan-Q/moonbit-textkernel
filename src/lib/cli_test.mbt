// Tests for the CLI surface in `cli.mbt`: CSV splitting, config merging,
// command dispatch and the JSON-lines contract.
//
// These pin the *value-level* contract: `run_cli` returning `Err` is the
// source of the process exit status 2 that CHANGELOG 0.2.0 advertises. The
// process-level behaviour itself (`@env.exit`) cannot be asserted from a
// MoonBit test function; the `quality` CI job pins it with a shell
// assertion so the advertised contract cannot regress silently.

///|
test "[cli] split_csv: empty value means no entries" {
  let out = @lib.split_csv("")
  assert_eq(out.length(), 0)
}

///|
test "[cli] split_csv: single entry, no comma" {
  let out = @lib.split_csv("cdn.example.com")
  assert_eq(out.length(), 1)
  assert_eq(out[0], "cdn.example.com")
}

///|
test "[cli] split_csv: two entries" {
  let out = @lib.split_csv("cdn.example.com,assets.example.org")
  assert_eq(out.length(), 2)
  assert_eq(out[0], "cdn.example.com")
  assert_eq(out[1], "assets.example.org")
}

///|
test "[cli] split_csv: empty elements are preserved" {
  let out = @lib.split_csv("a,,b")
  assert_eq(out.length(), 3)
  assert_eq(out[1], "")
}

///|
test "[cli] split_csv: leading and trailing commas yield empty elements" {
  let leading = @lib.split_csv(",a")
  assert_eq(leading.length(), 2)
  assert_eq(leading[0], "")
  let trailing = @lib.split_csv("a,")
  assert_eq(trailing.length(), 2)
  assert_eq(trailing[1], "")
}

///|
test "[cli] split_csv: whitespace is significant, as documented" {
  let out = @lib.split_csv("a, b")
  assert_eq(out.length(), 2)
  assert_eq(out[1], " b")
}

///|
test "[cli] cli_config: empty CSVs mean use the default" {
  let cfg = @lib.cli_config("", "")
  let d = @lib.default_asset_config()
  assert_eq(cfg.hosts.length(), d.hosts.length())
  for i, h in cfg.hosts {
    assert_eq(h, d.hosts[i])
  }
  for i, p in cfg.default_params {
    assert_eq(p, d.default_params[i])
  }
}

///|
test "[cli] cli_config: explicit hosts, default params kept" {
  let cfg = @lib.cli_config("cdn.example.com", "")
  assert_eq(cfg.hosts.length(), 1)
  assert_eq(cfg.hosts[0], "cdn.example.com")
  let d = @lib.default_asset_config()
  assert_eq(cfg.default_params.length(), d.default_params.length())
  for i, p in cfg.default_params {
    assert_eq(p, d.default_params[i])
  }
}

///|
test "[cli] cli_config: explicit params, default hosts kept" {
  let cfg = @lib.cli_config("", "fmt=webp,v=2")
  assert_eq(cfg.default_params.length(), 2)
  assert_eq(cfg.default_params[0], "fmt=webp")
  assert_eq(cfg.default_params[1], "v=2")
  assert_eq(cfg.hosts.length(), @lib.default_asset_config().hosts.length())
}

///|
test "[cli] run_cli: escape commands agree with the lib API" {
  let cfg = @lib.default_asset_config()
  match @lib.run_cli("escape-html", "<a & b>", cfg) {
    Ok(out) => assert_eq(out, @lib.escape_html("<a & b>"))
    Err(_) => assert_true(false)
  }
  match @lib.run_cli("escape-attr", "x\"", cfg) {
    Ok(out) => assert_eq(out, @lib.escape_attr("x\""))
    Err(_) => assert_true(false)
  }
}

///|
test "[cli] run_cli: sanitize-filename" {
  match @lib.run_cli("sanitize-filename", "a/b", @lib.default_asset_config()) {
    Ok(out) => assert_eq(out, "a_b")
    Err(_) => assert_true(false)
  }
}

///|
test "[cli] run_cli: str-contains splits the input on the first |" {
  let cfg = @lib.default_asset_config()
  match @lib.run_cli("str-contains", "hello|ell", cfg) {
    Ok(out) => assert_eq(out, "true")
    Err(_) => assert_true(false)
  }
  match @lib.run_cli("str-contains", "hello|world", cfg) {
    Ok(out) => assert_eq(out, "false")
    Err(_) => assert_true(false)
  }
}

///|
test "[cli] run_cli: normalize-asset-url on a configured host appends defaults" {
  match
    @lib.run_cli(
      "normalize-asset-url",
      "https://cdn.example.com/a.png",
      @lib.default_asset_config(),
    ) {
    Ok(out) => assert_eq(out, "https://cdn.example.com/a.png?fmt=png&v=1")
    Err(_) => assert_true(false)
  }
}

///|
test "[cli] run_cli: a refused default parameter fails with Invalid Config" {
  // 0.2.0: a default parameter that cannot be appended (contains `#`) is
  // refused with `Invalid Config` instead of being silently dropped. The
  // resulting `Err` is what drives the process exit status 2.
  let cfg = @lib.cli_config("cdn.example.com", "ref=a#b")
  match
    @lib.run_cli("normalize-asset-url", "https://cdn.example.com/a.png", cfg) {
    Err(msg) => assert_true(@lib.str_contains(msg, "Invalid Config"))
    Ok(_) => assert_true(false)
  }
}

///|
test "[cli] run_cli: help returns the help text" {
  let cfg = @lib.default_asset_config()
  match @lib.run_cli("help", "", cfg) {
    Ok(text) => assert_true(@lib.str_contains(text, "Commands:"))
    Err(_) => assert_true(false)
  }
  match @lib.run_cli("--help", "", cfg) {
    Ok(text) => assert_true(@lib.str_contains(text, "Commands:"))
    Err(_) => assert_true(false)
  }
}

///|
test "[cli] run_cli: unknown command is a value-level failure" {
  match @lib.run_cli("nosuchcmd", "x", @lib.default_asset_config()) {
    Err(msg) => assert_eq(msg, "unknown command: nosuchcmd")
    Ok(_) => assert_true(false)
  }
}

///|
test "[cli] JSON lines: the success and error shapes are the public contract" {
  assert_eq(
    @lib.cli_json_line("escape-html", "&lt;b&gt;"),
    "{\"command\":\"escape-html\",\"output\":\"&lt;b&gt;\"}",
  )
  assert_eq(
    @lib.cli_json_error("nosuchcmd", "unknown command: nosuchcmd"),
    "{\"command\":\"nosuchcmd\",\"error\":\"unknown command: nosuchcmd\"}",
  )
}

///|
test "[cli] JSON lines: quotes in values are JSON-escaped" {
  let line = @lib.cli_json_error("c\"x", "m")
  assert_true(@lib.str_contains(line, "c\\\"x"))
}
