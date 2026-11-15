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
/// An executable package needs an entry point; all real work is in the exports.
fn main {

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
