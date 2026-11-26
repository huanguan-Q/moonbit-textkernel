// WASM-GC export shim.
//
// With `use-js-builtin-string` the linker exposes these directly as
// String -> String functions to a JS host: no linear-memory ABI, no manual
// allocation, no UTF-8 copy. The batch variants use the joined-string ABI so a
// list can cross the boundary as one string instead of an array of refs.
//
// This package is deliberately a thin shim: every function delegates to
// `src/lib`, which is where the runtime invariants, input caps and the pinned
// conformance corpus live.

///|
/// Escape HTML text content.
pub fn escape_html(input : String) -> String {
  @lib.escape_html(input)
}

///|
/// Escape HTML attribute content.
pub fn escape_attr(input : String) -> String {
  @lib.escape_attr(input)
}

///|
/// Sanitise a filename.
pub fn sanitize_filename(name : String) -> String {
  @lib.sanitize_filename(name)
}

///|
/// Force https on configured asset hosts and append missing default params.
pub fn normalize_asset_url(input : String) -> String {
  @lib.normalize_asset_url(input)
}

///|
/// Decide a Referrer-Policy from the configured host allow-list.
pub fn decide_referrer_policy(input : String) -> String {
  @lib.decide_referrer_policy(input)
}

///|
/// UTF-16 code-unit substring test. Returns "true" or "false" as a string so
/// the export keeps the same String -> String shape as the rest of the ABI.
pub fn str_contains(haystack : String, needle : String) -> String {
  if @lib.str_contains(haystack, needle) {
    "true"
  } else {
    "false"
  }
}

///|
/// Escape a list of HTML text nodes; elements are joined by `sep`.
pub fn escape_htmls_joined(joined : String, sep : String) -> String {
  @lib.join_joined(
    @lib.quick_batch_escape_htmls(@lib.split_joined(joined, sep)),
    sep,
  )
}

///|
/// Escape a list of HTML attribute values; elements are joined by `sep`.
pub fn escape_attrs_joined(joined : String, sep : String) -> String {
  @lib.join_joined(
    @lib.quick_batch_escape_attrs(@lib.split_joined(joined, sep)),
    sep,
  )
}

///|
/// Sanitise a list of filenames; elements are joined by `sep`.
pub fn sanitize_filenames_joined(joined : String, sep : String) -> String {
  @lib.join_joined(
    @lib.quick_batch_sanitize_filenames(@lib.split_joined(joined, sep)),
    sep,
  )
}

///|
/// Normalise a list of asset URLs; elements are joined by `sep`.
pub fn normalize_asset_urls_joined(joined : String, sep : String) -> String {
  @lib.join_joined(
    @lib.quick_batch_normalize_urls(@lib.split_joined(joined, sep)),
    sep,
  )
}

///|
/// CLI entry point. The WASM/moonx host passes arguments through `@env.args`;
/// the same commands are available from the native stdin/file wrapper.
fn main {
  let args = @env.args()
  if args.length() < 2 {
    println(@lib.cli_help())
    return
  }

  let command = args[1]
  if command == "--help" || command == "help" {
    println(@lib.cli_help())
    return
  }

  let mut input = ""
  let mut hosts_csv = ""
  let mut params_csv = ""
  let mut i = 2
  while i < args.length() {
    let arg = args[i]
    if arg == "--input" || arg == "--hosts" || arg == "--params" {
      if i + 1 >= args.length() {
        println(@lib.cli_json_error(command, "missing value for " + arg))
        @env.exit(@lib.CLI_USAGE_EXIT)
      }
      let value = args[i + 1]
      if arg == "--input" {
        input = value
      } else if arg == "--hosts" {
        hosts_csv = value
      } else {
        params_csv = value
      }
      i = i + 2
    } else {
      input = arg
      i = i + 1
    }
  }

  let config = @lib.cli_config(hosts_csv, params_csv)
  match @lib.run_cli(command, input, config) {
    Ok(output) => println(@lib.cli_json_line(command, output))
    Err(message) => {
      println(@lib.cli_json_error(command, message))
      @env.exit(@lib.CLI_USAGE_EXIT)
    }
  }
}

///|
/// Never-fail variants. These use the `EmptyOnError` policy, so an oversized
/// input or an invariant violation returns `""` instead of trapping the host.
pub fn escape_html_safe(input : String) -> String {
  @lib.escape_html_safe(input)
}

///|
pub fn escape_attr_safe(input : String) -> String {
  @lib.escape_attr_safe(input)
}

///|
pub fn sanitize_filename_safe(name : String) -> String {
  @lib.sanitize_filename_safe(name)
}
