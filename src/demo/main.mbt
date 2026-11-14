// Runnable example: `moon run src/demo --target native`
//
// Every function shown here has a proved code-unit kernel in `src/proof`, and
// `src/proof/conform.mbt` pins the kernel to this String-level implementation
// over an enumerated corpus.

///|
fn main {
  println("== textkernel demo ==")
  println("escape_html   : " + @lib.escape_html("<script>a & b</script>"))
  println("escape_attr   : " + @lib.escape_attr("x\" onload='y'"))
  println("sanitize_name : " + @lib.sanitize_filename("a/b:c?.png"))
  println(
    "normalize_url : " +
    @lib.normalize_asset_url("http://cdn.example.com/a.png"),
  )
  println(
    "referrer      : " +
    @lib.decide_referrer_policy("https://cdn.example.com/a.png"),
  )
  let parts = @lib.split_joined("a|b|c", "|")
  println("split/join    : " + @lib.join_joined(parts, ","))
  let validated = match @lib.escape_html_result("<ok>") {
    Ok(s) => s
    Err(e) => @lib.error_to_string(e)
  }
  println("validated     : " + validated)
}
