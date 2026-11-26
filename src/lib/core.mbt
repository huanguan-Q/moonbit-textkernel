/// Core library for HTML escaping, filename sanitising, asset URL
/// normalisation and Referrer-Policy selection.
///
/// Three rules run through the whole file.
///
/// 1. *Well-formed text passes through.* Every routine walks UTF-16 code
///    units, but a well-formed surrogate pair — a character outside the BMP,
///    such as an emoji or a CJK Extension B ideograph — is one character and
///    is copied whole. Only an unpaired surrogate half becomes `_`. Such a
///    half cannot be written in MoonBit source; it arrives from a host that
///    hands over ill-formed UTF-16, such as a JS caller of the WASM exports.
///
/// 2. *Every public entry point enforces the shipping domain.* An input above
///    `MAX_SHIPPING_CODE_UNITS` is refused before any work is done: `Err` from
///    a `*_result` function, `""` from a `*_safe` function, an abort from the
///    fail-fast compatibility layer. There is no second, smaller limit, and an
///    empty input is a valid input.
///
/// 3. *Pure bodies, one abort site.* Each `*_build` and `*_impl` function is
///    total: it checks no bound and never aborts. The public wrappers add the
///    domain check and route a failure through `apply_failure_policy`. The one
///    exception is `str_contains`, which has no checked variant and keeps its
///    fail-fast guard.

///|
/// Return true if `haystack` contains `needle` as a UTF-16 code-unit substring (ASCII-safe).
/// Optimized with early termination and reduced bounds checking.
pub fn str_contains(haystack : String, needle : String) -> Bool {
  require_model_length(haystack, "str_contains(haystack)")
  require_model_length(needle, "str_contains(needle)")
  let hl = haystack.length()
  let nl = needle.length()

  // Early returns for edge cases
  if nl == 0 {
    return true
  }
  if nl > hl {
    return false
  }

  // Single character optimization
  if nl == 1 {
    let target = needle[0]
    let mut i = 0
    while i < hl {
      if haystack[i] == target {
        return true
      }
      i = i + 1
    }
    return false
  }

  // Boyer-Moore-like optimization: check last character first
  let last_char = needle[nl - 1]
  let mut i = nl - 1
  while i < hl {
    if haystack[i] == last_char {
      // Check if full pattern matches
      let mut j = 0
      let mut match_found = true
      let start_pos = i - nl + 1
      while j < nl {
        if haystack[start_pos + j] != needle[j] {
          match_found = false
          break
        }
        j = j + 1
      }
      if match_found {
        return true
      }
    }
    i = i + 1
  }
  false
}

///|
/// Host allow-list and default query parameters for asset URL normalization.
///
/// The old API hard-coded RFC 2606 example domains inside `core.mbt`, which
/// forced every commercial consumer to fork the library. Pass an explicit
/// config to `*_with_config` instead; the no-suffix functions keep their
/// historical behaviour by wrapping `default_asset_config()`.
pub struct AssetConfig {
  hosts : Array[String]
  default_params : Array[String]
}

///|
/// The historical configuration: example domains and `fmt=png` / `v=1`.
pub fn default_asset_config() -> AssetConfig {
  {
    hosts: ["cdn.example.com", "assets.example.org"],
    default_params: ["fmt=png", "v=1"],
  }
}

///|
/// Create a configuration for a deployment without touching library source.
///
/// A host entry is a host name such as `cdn.internal.example` — no scheme,
/// no path, no port. It matches that host and its subdomains, in any letter
/// case. A default parameter is one `key=value` or a bare `key`; several may
/// be joined with `&`. A parameter that could change the structure of the URL
/// (empty, starting with `=`, or containing `#`, whitespace or a control
/// character) is ignored when a URL is built.
pub fn create_asset_config(
  hosts : Array[String],
  default_params : Array[String],
) -> AssetConfig {
  { hosts, default_params, }
}

///|
/// Key part of a `key=value` query parameter, used for presence checks.
fn param_key(param : String) -> String {
  let mut i = 0
  while i < param.length() {
    match param[i].to_char() {
      Some('=') => return param[:i].to_owned()
      _ => ()
    }
    i = i + 1
  }
  param
}

///|
/// Copy one character of `input` to `out` and return the index of the next one.
///
/// A well-formed surrogate pair is copied whole, as the two code units it is.
/// An unpaired surrogate half has no character to copy and becomes `_`.
/// Everything else is a single BMP character.
fn copy_text_unit(out : StringBuilder, input : String, i : Int32) -> Int32 {
  let code = input[i]
  if code.is_leading_surrogate() &&
    i + 1 < input.length() &&
    input[i + 1].is_trailing_surrogate() {
    out.write_stringview(input[i:i + 2])
    return i + 2
  }
  match code.to_char() {
    Some(c) => out.write_char(c)
    None => out.write_char('_')
  }
  i + 1
}

///|
/// Escape HTML text content by replacing `&`, `<`, `>` with their entities.
/// Every other character, emoji and other non-BMP characters included, is
/// copied as it is; an unpaired surrogate half becomes `_`.
fn escape_html_build(input : String) -> String {
  let out = StringBuilder(capacity=input.length())
  let n = input.length()
  let mut i = 0
  while i < n {
    let code = input[i]
    if code == '&' {
      out.write_string("&amp;")
      i = i + 1
      continue
    }
    if code == '<' {
      out.write_string("&lt;")
      i = i + 1
      continue
    }
    if code == '>' {
      out.write_string("&gt;")
      i = i + 1
      continue
    }
    if code.to_int() < 0xD800 {
      // Below the surrogate block every code unit is a whole BMP character.
      // This is nearly every unit of real text, so it skips the pairing test.
      match code.to_char() {
        Some(c) => out.write_char(c)
        None => out.write_char('_')
      }
      i = i + 1
      continue
    }
    i = copy_text_unit(out, input, i)
  }
  out.to_string()
}

///|
/// Escape HTML attribute content. In addition to text escaping, also escape `"` and `'`.
/// Mappings: `&` -> &amp;, `<` -> &lt;, `>` -> &gt;, `"` -> &quot;, `'` -> &#39;
/// Every other character is copied as it is, as in `escape_html`.
fn escape_attr_build(input : String) -> String {
  let out = StringBuilder(capacity=input.length())
  let n = input.length()
  let mut i = 0
  while i < n {
    let code = input[i]
    if code == '&' {
      out.write_string("&amp;")
      i = i + 1
      continue
    }
    if code == '<' {
      out.write_string("&lt;")
      i = i + 1
      continue
    }
    if code == '>' {
      out.write_string("&gt;")
      i = i + 1
      continue
    }
    if code == '"' {
      out.write_string("&quot;")
      i = i + 1
      continue
    }
    if code == '\'' {
      out.write_string("&#39;")
      i = i + 1
      continue
    }
    if code.to_int() < 0xD800 {
      // Below the surrogate block every code unit is a whole BMP character.
      // This is nearly every unit of real text, so it skips the pairing test.
      match code.to_char() {
        Some(c) => out.write_char(c)
        None => out.write_char('_')
      }
      i = i + 1
      continue
    }
    i = copy_text_unit(out, input, i)
  }
  out.to_string()
}

///|
/// Checked form of `escape_html`. Never aborts: a domain violation and an
/// invariant failure both come back as `Err`. This is the recommended
/// production API. Empty input is valid and yields `Ok("")`.
fn escape_html_checked_impl(input : String) -> Result[String, CoreError] {
  match check_model_length(input, "escape_html") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let result = escape_html_build(input)
  if !html_is_escaped(result) {
    Err(InvariantViolation("escape_html: output violates the escape invariant"))
  } else {
    Ok(result)
  }
}

///|
/// String-returning form with an explicit failure policy.
pub fn escape_html_with_policy(
  input : String,
  policy : FailurePolicy,
) -> String {
  match escape_html_checked_impl(input) {
    Ok(result) => result
    Err(e) => apply_failure_policy(e, policy)
  }
}

///|
/// Fail-fast compatibility layer. Signature is unchanged for existing callers
/// and for the WASM exports; new code should use `escape_html_result` or
/// `escape_html_with_policy`.
pub fn escape_html(input : String) -> String {
  escape_html_with_policy(input, FailFast)
}

///|
/// Checked form of `escape_attr`. Never aborts: a domain violation and an
/// invariant failure both come back as `Err`. This is the recommended
/// production API. Empty input is valid and yields `Ok("")`.
fn escape_attr_checked_impl(input : String) -> Result[String, CoreError] {
  match check_model_length(input, "escape_attr") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let result = escape_attr_build(input)
  if !attr_is_escaped(result) {
    Err(
      InvariantViolation(
        "escape_attr: output violates the attribute-escape invariant",
      ),
    )
  } else {
    Ok(result)
  }
}

///|
/// String-returning form with an explicit failure policy.
pub fn escape_attr_with_policy(
  input : String,
  policy : FailurePolicy,
) -> String {
  match escape_attr_checked_impl(input) {
    Ok(result) => result
    Err(e) => apply_failure_policy(e, policy)
  }
}

///|
/// Fail-fast compatibility layer. Signature is unchanged for existing callers
/// and for the WASM exports; new code should use `escape_attr_result` or
/// `escape_attr_with_policy`.
pub fn escape_attr(input : String) -> String {
  escape_attr_with_policy(input, FailFast)
}

///|
/// Sanitize a filename: see `filename.mbt` for the rules. The result is a name
/// that can be created as a file on Linux, macOS and Windows — never a
/// directory reference such as `..` — of at most 120 UTF-16 code units.
fn sanitize_filename_build(name : String) -> String {
  let base = if name.length() == 0 { "file" } else { name }
  let n = base.length()
  let out = StringBuilder(capacity=FILENAME_LIMIT)
  let mut i = 0
  let mut count = 0
  while i < n && count < FILENAME_LIMIT {
    let code = base[i]
    // A well-formed pair is one character: it is copied whole or not at all,
    // so the clamp can never cut a character in half.
    if code.is_leading_surrogate() &&
      i + 1 < n &&
      base[i + 1].is_trailing_surrogate() {
      if count + 2 > FILENAME_LIMIT {
        break
      }
      out.write_stringview(base[i:i + 2])
      i = i + 2
      count = count + 2
      continue
    }
    if is_invalid_filename_char(code) ||
      is_control_filename_char(code) ||
      code.is_leading_surrogate() ||
      code.is_trailing_surrogate() {
      out.write_char('_')
    } else {
      match code.to_char() {
        Some(c) => out.write_char(c)
        None => out.write_char('_')
      }
    }
    i = i + 1
    count = count + 1
  }
  finalize_filename(out.to_string())
}

///|
/// Checked form of `sanitize_filename`. Never aborts: domain violations and
/// invariant failures both come back as `Err`. This is the recommended
/// production API. Empty input is valid and yields `Ok("file")`.
fn sanitize_filename_checked_impl(name : String) -> Result[String, CoreError] {
  match check_model_length(name, "sanitize_filename") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let result = sanitize_filename_build(name)
  if !filename_is_sanitized(result) {
    Err(
      InvariantViolation(
        "sanitize_filename: output violates the filename invariant",
      ),
    )
  } else {
    Ok(result)
  }
}

///|
/// String-returning form with an explicit failure policy.
pub fn sanitize_filename_with_policy(
  name : String,
  policy : FailurePolicy,
) -> String {
  match sanitize_filename_checked_impl(name) {
    Ok(result) => result
    Err(e) => apply_failure_policy(e, policy)
  }
}

///|
/// Fail-fast compatibility layer. Signature is unchanged for existing callers
/// and for the WASM exports; new code should use `sanitize_filename_result` or
/// `sanitize_filename_with_policy`.
pub fn sanitize_filename(name : String) -> String {
  sanitize_filename_with_policy(name, FailFast)
}

///|
/// Normalize an asset URL with an explicit host allow-list and default params.
///
/// Only an `http` or `https` URL, in any letter case, whose host is in the
/// allow-list is changed: the scheme becomes `https`, and every default
/// parameter the query does not already have is appended to the query. The
/// authority, the path, the existing query and the fragment are carried over
/// verbatim, and a missing parameter is inserted before the `#fragment`,
/// never after it. Any other input — another scheme, a relative reference, or
/// a host that merely occurs somewhere in the path or the query — is returned
/// unchanged.
///
/// A default parameter that cannot be appended safely is not skipped: for a
/// URL the configuration applies to, this aborts with the offending piece.
/// The parameters are not looked at for any other URL, so a configuration with
/// such a piece still works for the hosts it is not used on.
pub fn normalize_asset_url_with_config(
  input : String,
  config : AssetConfig,
) -> String {
  match normalize_asset_url_with_config_result(input, config) {
    Ok(url) => url
    Err(e) => apply_failure_policy(e, FailFast)
  }
}

///|
/// Historical default configuration; identical to earlier releases.
pub fn normalize_asset_url(input : String) -> String {
  normalize_asset_url_with_config(input, default_asset_config())
}

///|
/// Decide a Referrer-Policy from an explicit host allow-list.
///
/// An `http` or `https` URL whose host is in the allow-list gets
/// `no-referrer-when-downgrade`; everything else gets `no-referrer`. The test
/// is the same one `normalize_asset_url_with_config` applies, so the two
/// functions can never disagree about what an asset host is.
pub fn decide_referrer_policy_with_config(
  input : String,
  config : AssetConfig,
) -> String {
  match check_model_length(input, "decide_referrer_policy") {
    Ok(_) =>
      if url_is_allowed_asset(input, config) {
        "no-referrer-when-downgrade"
      } else {
        "no-referrer"
      }
    Err(e) => apply_failure_policy(e, FailFast)
  }
}

///|
/// Historical default configuration; identical to earlier releases.
pub fn decide_referrer_policy(input : String) -> String {
  decide_referrer_policy_with_config(input, default_asset_config())
}

///|
/// Alias of normalize_asset_url for naming symmetry when used as a general-purpose "ensure" helper.
pub fn ensure_asset_params(input : String) -> String {
  normalize_asset_url(input)
}

///|
/// Configurable alias of normalize_asset_url_with_config.
pub fn ensure_asset_params_with_config(
  input : String,
  config : AssetConfig,
) -> String {
  normalize_asset_url_with_config(input, config)
}

///|
/// Result-based variant of `normalize_asset_url_with_config`.
///
/// Returns `Ok(normalized_url)` for every input up to `MAX_SHIPPING_CODE_UNITS`,
/// the empty string included. Beyond it, `Err(InputTooLarge)`.
///
/// `Err(InvalidConfig(piece))` when the configuration holds a default
/// parameter that cannot be appended as it is — empty, starting with `=`, or
/// containing `#`, whitespace or a control character — and the URL is one the
/// configuration applies to. The piece is the message. Such a piece used to be
/// skipped silently. Never aborts.
pub fn normalize_asset_url_with_config_result(
  input : String,
  config : AssetConfig,
) -> Result[String, CoreError] {
  match check_model_length(input, "normalize_asset_url") {
    Ok(_) =>
      match normalize_asset_url_impl(input, config) {
        Ok(url) => Ok(url)
        Err(piece) => Err(InvalidConfig(piece))
      }
    Err(e) => Err(e)
  }
}

///|
/// Result-based variant of `normalize_asset_url`.
/// Returns `Ok(normalized_url)` for every input up to `MAX_SHIPPING_CODE_UNITS`
/// and `Err(InputTooLarge)` beyond it, or `Err(InvalidConfig(piece))` for a
/// default parameter of the configuration that cannot be appended. Never aborts.
pub fn normalize_asset_url_result(input : String) -> Result[String, CoreError] {
  normalize_asset_url_with_config_result(input, default_asset_config())
}

///|
/// Result-based variant of `decide_referrer_policy_with_config`.
/// Returns `Ok(policy)` for every input up to `MAX_SHIPPING_CODE_UNITS` and
/// `Err(InputTooLarge)` beyond it. Never aborts.
pub fn decide_referrer_policy_with_config_result(
  input : String,
  config : AssetConfig,
) -> Result[String, CoreError] {
  match check_model_length(input, "decide_referrer_policy") {
    Ok(_) =>
      Ok(
        if url_is_allowed_asset(input, config) {
          "no-referrer-when-downgrade"
        } else {
          "no-referrer"
        },
      )
    Err(e) => Err(e)
  }
}

///|
/// Result-based variant of `decide_referrer_policy`.
/// Returns `Ok(policy)` for every input up to `MAX_SHIPPING_CODE_UNITS` and
/// `Err(InputTooLarge)` beyond it. Never aborts.
pub fn decide_referrer_policy_result(
  input : String,
) -> Result[String, CoreError] {
  decide_referrer_policy_with_config_result(input, default_asset_config())
}

///|
/// Result-based variant of `sanitize_filename`.
/// Returns `Ok(sanitized)` for every input up to `MAX_SHIPPING_CODE_UNITS`,
/// the empty string included, and `Err(InputTooLarge)` beyond it. Never aborts.
pub fn sanitize_filename_result(name : String) -> Result[String, CoreError] {
  sanitize_filename_checked_impl(name)
}

///|
/// Result-based variant of `escape_html`.
/// Returns `Ok(escaped)` for every input up to `MAX_SHIPPING_CODE_UNITS`, the
/// empty string included, and `Err(InputTooLarge)` beyond it. Never aborts.
pub fn escape_html_result(input : String) -> Result[String, CoreError] {
  escape_html_checked_impl(input)
}

///|
/// Result-based variant of `escape_attr`.
/// Returns `Ok(escaped)` for every input up to `MAX_SHIPPING_CODE_UNITS`, the
/// empty string included, and `Err(InputTooLarge)` beyond it. Never aborts.
pub fn escape_attr_result(input : String) -> Result[String, CoreError] {
  escape_attr_checked_impl(input)
}

///|
/// Result-based alias of `ensure_asset_params`.
/// Returns `Ok(result)` for every input up to `MAX_SHIPPING_CODE_UNITS` and
/// `Err(InputTooLarge)` beyond it. Never aborts.
pub fn ensure_asset_params_result(input : String) -> Result[String, CoreError] {
  normalize_asset_url_result(input)
}

///|
/// Result-based alias of `ensure_asset_params_with_config`.
/// Returns `Ok(result)` for every input up to `MAX_SHIPPING_CODE_UNITS` and
/// `Err(InputTooLarge)` beyond it. Never aborts.
pub fn ensure_asset_params_with_config_result(
  input : String,
  config : AssetConfig,
) -> Result[String, CoreError] {
  normalize_asset_url_with_config_result(input, config)
}

///|
/// Never-fail variants for trust boundaries. A WASM trap takes down the host
/// embedder, so these return `""` on any domain or invariant error instead of
/// aborting. Callers should treat `""` as a failure signal — except from
/// `escape_html_safe` and `escape_attr_safe` on empty input, which is also
/// `""`. These are what the `*_safe` WASM exports delegate to.
pub fn escape_html_safe(input : String) -> String {
  escape_html_with_policy(input, EmptyOnError)
}

///|
pub fn escape_attr_safe(input : String) -> String {
  escape_attr_with_policy(input, EmptyOnError)
}

///|
pub fn sanitize_filename_safe(name : String) -> String {
  sanitize_filename_with_policy(name, EmptyOnError)
}
