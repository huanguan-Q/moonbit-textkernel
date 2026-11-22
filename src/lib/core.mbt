/// Core library for URL normalization, referrer policy decision, and filename sanitization.
/// NOTE: Logic parity with JS fallback in wasmLoader.js is required when possible.

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
/// Normalize asset URLs from cdn.example.com and assets.example.org by appending default params when missing: fmt=png and v=1.
/// Also forces HTTPS for all example.org domains to prevent Mixed Content errors.
/// If the URL does not belong to example.org configured asset hosts or already contains both params, the input is returned unchanged.
/// Enhanced with error handling and performance optimizations.
pub fn normalize_asset_url(input : String) -> String {
  require_model_length(input, "normalize_asset_url")
  // Input validation and early returns
  if input.length() == 0 {
    return input
  }

  // Performance check for extremely long URLs
  if input.length() > 2000 {
    // For very long URLs, still process but could be optimized further
    // In a real implementation, this might log a warning
  }

  // Check for any example.org configured asset host domain (asset or asset)
  let has_asset_cdn = str_contains(input, "cdn.example.com") ||
    str_contains(input, "assets.example.org")

  if !has_asset_cdn {
    return input
  }

  // Force HTTPS for example.org domains to prevent Mixed Content errors.
  // Only the scheme prefix is rewritten and the remainder is copied verbatim.
  // NOTE: do NOT rebuild the tail character by character — `String::at`
  // yields a UInt16 code unit, whose `to_string` is the decimal code point
  // (e.g. 'm' -> "109"), which would corrupt the URL into a digit string.
  let mut processed = input
  let http_prefix = "http://"
  let https_prefix = "https://"
  if processed.has_prefix(http_prefix) {
    processed = https_prefix + processed[http_prefix.length():].to_owned()
  }

  let has_wx = str_contains(processed, "fmt=")
  let has_tp = str_contains(processed, "v=")

  // Early return if both parameters already exist
  if has_wx && has_tp {
    return processed
  }

  // Build suffix efficiently
  let has_q = str_contains(processed, "?")
  let mut sep = if has_q { "&" } else { "?" }
  let mut suffix = ""
  if !has_wx {
    suffix = suffix + sep + "fmt=png"
    sep = "&"
  }
  if !has_tp {
    suffix = suffix + sep + "v=1"
  }
  processed + suffix
}

///|
/// Decide referrer policy string based on whether the URL belongs to configured asset host (cdn.example.com or assets.example.org).
/// Returns "no-referrer-when-downgrade" for configured asset host, otherwise "no-referrer".
pub fn decide_referrer_policy(input : String) -> String {
  if str_contains(input, "cdn.example.com") ||
    str_contains(input, "assets.example.org") {
    "no-referrer-when-downgrade"
  } else {
    "no-referrer"
  }
}

///|
/// Sanitize a filename by replacing invalid characters with '_' and clamping length to 120 code units.
/// If input is empty, defaults to "file". Optimized version maintaining original behavior.
fn sanitize_filename_build(name : String) -> String {
  require_model_length(name, "sanitize_filename")
  let base = if name.length() == 0 { "file" } else { name }

  // A StringBuilder keeps the loop amortised O(n). The previous
  // `out = out + x` copied the whole prefix on every iteration, which made the
  // native backend quadratic (4x input -> ~8x runtime, measured 20k -> 80k
  // code units). Output is byte-for-byte identical; see
  // `string_builder_regression_test.mbt` for the legacy-vs-new differential.
  let out = StringBuilder(capacity=120)
  let mut i = 0
  let mut count = 0
  while i < base.length() && count < 120 {
    let code = base[i]

    if is_invalid_filename_char(code) {
      out.write_char('_')
      i = i + 1
      count = count + 1
      continue
    }

    match code.to_char() {
      Some(c) => {
        out.write_char(c)
        i = i + 1
        count = count + 1
      }
      None => {
        // Unpaired surrogate, replace and advance one unit
        out.write_char('_')
        i = i + 1
        count = count + 1
      }
    }
  }
  out.to_string()
}

///|
/// Checked form of `sanitize_filename`. Never aborts: domain violations and invariant
/// failures both come back as `Err`. This is the recommended production API.
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
/// Check if a character code represents an invalid filename character.
/// Invalid set: / \\ : * ? " < > |
fn is_invalid_filename_char(code : UInt16) -> Bool {
  code == '/' ||
  code == '\\' ||
  code == ':' ||
  code == '*' ||
  code == '?' ||
  code == '"' ||
  code == '<' ||
  code == '>' ||
  code == '|'
}

///|
/// Escape HTML text content by replacing '&', '<', '>' with their entities.
/// Non-ASCII code units are preserved when decodable as Char; undecodable units become '_'.
fn escape_html_build(input : String) -> String {
  require_model_length(input, "escape_html")
  // Amortised O(n): see the note in `sanitize_filename`.
  let out = StringBuilder(capacity=input.length())
  let mut i = 0
  while i < input.length() {
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
    match code.to_char() {
      Some(c) => {
        out.write_char(c)
        i = i + 1
      }
      None => {
        out.write_char('_')
        i = i + 1
      }
    }
  }
  out.to_string()
}

///|
/// Checked form of `escape_html`. Never aborts: domain violations and invariant
/// failures both come back as `Err`. This is the recommended production API.
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
/// Escape HTML attribute content. In addition to text escaping, also escape '"' and '\''.
/// Mappings: '&' -> &amp;, '<' -> &lt;, '>' -> &gt;, '"' -> &quot;, '\'' -> &#39;
fn escape_attr_build(input : String) -> String {
  require_model_length(input, "escape_attr")
  // Amortised O(n): see the note in `sanitize_filename`.
  let out = StringBuilder(capacity=input.length())
  let mut i = 0
  while i < input.length() {
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
    match code.to_char() {
      Some(c) => {
        out.write_char(c)
        i = i + 1
      }
      None => {
        out.write_char('_')
        i = i + 1
      }
    }
  }
  out.to_string()
}

///|
/// Checked form of `escape_attr`. Never aborts: domain violations and invariant
/// failures both come back as `Err`. This is the recommended production API.
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
/// Alias of normalize_asset_url for naming symmetry when used as a general-purpose "ensure" helper.
/// This function may evolve to handle more configured asset host param policies while normalize_asset_url retains current behavior.
pub fn ensure_asset_params(input : String) -> String {
  normalize_asset_url(input)
}

///|
/// Result-based variant of normalize_asset_url with input validation.
/// Returns Ok(normalized_url) on success; Err(CoreError) when input exceeds safe length.
pub fn normalize_asset_url_result(input : String) -> Result[String, CoreError] {
  let max_len : Int32 = 4096
  match validate_string_input("normalize_asset_url_result", input, max_len) {
    Ok(_) => Ok(normalize_asset_url(input))
    Err(e) => Err(e)
  }
}

///|
/// Result-based variant of decide_referrer_policy with input validation.
/// Returns Ok(policy) on success; Err(CoreError) when input exceeds safe length.
pub fn decide_referrer_policy_result(
  input : String,
) -> Result[String, CoreError] {
  let max_len : Int32 = 4096
  match validate_string_input("decide_referrer_policy_result", input, max_len) {
    Ok(_) => Ok(decide_referrer_policy(input))
    Err(e) => Err(e)
  }
}

///|
/// Result-based variant of sanitize_filename with input validation.
/// Returns Ok(sanitized) on success; Err(CoreError) when input exceeds safe length.
pub fn sanitize_filename_result(name : String) -> Result[String, CoreError] {
  let max_len : Int32 = 4096
  match validate_string_input("sanitize_filename_result", name, max_len) {
    Ok(_) => sanitize_filename_checked_impl(name)
    Err(e) => Err(e)
  }
}

///|
/// Result-based variant of escape_html with input validation.
/// Returns Ok(escaped) on success; Err(CoreError) when input exceeds safe length.
pub fn escape_html_result(input : String) -> Result[String, CoreError] {
  let max_len : Int32 = 8192
  match validate_string_input("escape_html_result", input, max_len) {
    Ok(_) => escape_html_checked_impl(input)
    Err(e) => Err(e)
  }
}

///|
/// Result-based variant of escape_attr with input validation.
/// Returns Ok(escaped) on success; Err(CoreError) when input exceeds safe length.
pub fn escape_attr_result(input : String) -> Result[String, CoreError] {
  let max_len : Int32 = 8192
  match validate_string_input("escape_attr_result", input, max_len) {
    Ok(_) => escape_attr_checked_impl(input)
    Err(e) => Err(e)
  }
}

///|
/// Result-based alias of ensure_asset_params with input validation.
/// Returns Ok(result) on success; Err(CoreError) when input exceeds safe length.
pub fn ensure_asset_params_result(input : String) -> Result[String, CoreError] {
  let max_len : Int32 = 4096
  match validate_string_input("ensure_asset_params_result", input, max_len) {
    Ok(_) => Ok(ensure_asset_params(input))
    Err(e) => Err(e)
  }
}

///|
/// Never-fail variants for trust boundaries. A WASM trap takes down the host
/// embedder, so these return `""` on any domain or invariant error instead of
/// aborting. Callers should treat `""` as a failure signal. These are what the
/// `*_safe` WASM exports delegate to.
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
