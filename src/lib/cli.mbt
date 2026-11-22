// Shared CLI logic for the wasm/moonx entry point and the native stdin/file
// entry point. Keeping it in the library means both hosts expose identical
// commands and identical JSON-lines output.

///|
pub fn cli_help() -> String {
  "textkernel - verified text operations across a trust boundary\n\n" +
  "Usage:\n" +
  "  textkernel <command> [--input TEXT | TEXT] [--hosts h1,h2] [--params k=v,k2=v2]\n" +
  "  textkernel --help\n\n" +
  "Commands:\n" +
  "  escape-html            escape HTML text content\n" +
  "  escape-attr            escape an HTML attribute value\n" +
  "  sanitize-filename      replace unsafe filename characters\n" +
  "  normalize-asset-url    force https and append default query params\n" +
  "  decide-referrer-policy choose a Referrer-Policy from the host allow-list\n" +
  "  str-contains           UTF-16 substring test, input is HAYSTACK|NEEDLE\n\n" +
  "Output is one JSON line: {\"command\":\"...\",\"output\":\"...\"}.\n" +
  "Without --hosts/--params the RFC 2606 example configuration is used.\n"
}

///|
fn json_string(value : String) -> String {
  @json.Json::string(value).stringify()
}

///|
pub fn cli_json_line(command : String, output : String) -> String {
  "{\"command\":" +
  json_string(command) +
  ",\"output\":" +
  json_string(output) +
  "}"
}

///|
pub fn cli_json_error(command : String, message : String) -> String {
  "{\"command\":" +
  json_string(command) +
  ",\"error\":" +
  json_string(message) +
  "}"
}

///|
/// Split a comma-separated CLI value. Whitespace is significant.
pub fn split_csv(value : String) -> Array[String] {
  let out : Array[String] = []
  let n = value.length()
  if n == 0 {
    return out
  }
  let mut start = 0
  let mut i = 0
  while i < n {
    if value[i].to_char() == Some(',') {
      out.push(value[start:i].to_owned())
      start = i + 1
    }
    i = i + 1
  }
  out.push(value[start:n].to_owned())
  out
}

///|
/// Configuration from CLI flags. Empty CSV values mean "use the default".
pub fn cli_config(hosts_csv : String, params_csv : String) -> AssetConfig {
  let hosts = split_csv(hosts_csv)
  let params = split_csv(params_csv)
  if hosts.is_empty() && params.is_empty() {
    default_asset_config()
  } else {
    let use_hosts = if hosts.is_empty() {
      default_asset_config().hosts
    } else {
      hosts
    }
    let use_params = if params.is_empty() {
      default_asset_config().default_params
    } else {
      params
    }
    create_asset_config(use_hosts, use_params)
  }
}

///|
fn split_once(value : String, sep : Char) -> (String, String) {
  let mut i = 0
  while i < value.length() {
    if value[i].to_char() == Some(sep) {
      return (value[:i].to_owned(), value[i + 1:].to_owned())
    }
    i = i + 1
  }
  (value, "")
}

///|
/// Dispatch one command. Failures are values so the host never traps.
pub fn run_cli(
  command : String,
  input : String,
  config : AssetConfig,
) -> Result[String, String] {
  match command {
    "escape-html" => Ok(escape_html_safe(input))
    "escape-attr" => Ok(escape_attr_safe(input))
    "sanitize-filename" => Ok(sanitize_filename_safe(input))
    "normalize-asset-url" => Ok(normalize_asset_url_with_config(input, config))
    "decide-referrer-policy" =>
      Ok(decide_referrer_policy_with_config(input, config))
    "str-contains" => {
      let (haystack, needle) = split_once(input, '|')
      let answer = if str_contains(haystack, needle) { "true" } else { "false" }
      Ok(answer)
    }
    "help" | "--help" => Ok(cli_help())
    _ => Err("unknown command: " + command)
  }
}
