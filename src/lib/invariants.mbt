// Runtime mirrors for the escaping / sanitising invariants.
//
// Why these exist
// ---------------
// The safety properties of the escapers are proved for the code-unit kernels in
// `src/coreproof` (`no_markup_prefix`, `no_quote_prefix`, `entities_ok_prefix`,
// `sanitized_prefix`). Those kernels are *not* on the shipping path: the
// functions below are what the extension actually calls, and they are separate
// String-level implementations whose only tie to the kernels is the corpus
// equality in `conform.mbt`.
//
// That leaves a gap the audit calls SEC-S1: a mandatory property that holds
// only in the proof package has no runtime representation where it matters.
// These predicates close it by checking the *output* of the shipping functions.
// `escape_html` / `escape_attr` / `sanitize_filename` call them before
// returning and abort on violation, so a regression fails loudly instead of
// emitting markup the caller believes is escaped.
//
// Cost is one extra pass over the result. That is deliberate: the alternative
// is trusting an unproved implementation, which is exactly what the audit
// refuses to accept.
//
// A note on false positives: these predicates are deliberately permissive about
// everything the escapers preserve (quotes in text, non-ASCII, digits). They
// only reject what the property forbids. `escape_invariants_test.mbt` checks
// them against the real escapers over an exhaustive alphabet, because a
// too-strict predicate here would break valid input rather than catch a bug.

///|
/// Largest input, in UTF-16 code units, that the **proof model** covers.
///
/// This is the shipping-side copy of `coreproof::MAX_CODE_UNITS`. The two are
/// kept identical by a compile-time reference on the proof side (see
/// `src/coreproof/codes.mbt`), so the number exists once in the source and the
/// kernels' `proof_require: length <= MAX_CODE_UNITS` keeps meaning what the
/// runtime checks below enforce.
///
/// It is an *arithmetic* bound, not a resource bound: the kernels compute
/// `5 * length`, `6 * length` and `n + bs`, and this cap keeps all three inside
/// 32 bits. `MAX_SHIPPING_CODE_UNITS` below is the tighter number that actually
/// runs on user input.
pub const MAX_INPUT_CODE_UNITS : Int32 = 100000000

///|
/// Largest input the shipping layer accepts, in UTF-16 code units.
///
/// Deliberately smaller than `MAX_INPUT_CODE_UNITS` — that one answers "can the
/// arithmetic overflow?", this one answers "how much may one call allocate on
/// the host heap?". They are different questions, so they get different numbers,
/// with a compile-time test in `coreproof` asserting `shipping <= model` (the
/// theorem then covers everything this layer lets through).
///
/// Why 8,000,000 — measured, not guessed:
///
/// * It is the largest input this module was actually exercised on: 8M code
///   units through `escape_html` produced 22.5M units of output and returned.
///   The cap sits at the measured-working bound, so nothing shown to work is
///   rejected.
/// * It bounds the worst case. `escape_attr` can emit six code units per input
///   unit, so 8M units cannot exceed 48M units (~96 MB of UTF-16) on the host
///   heap. The old model-only cap allowed 600M units — gigabytes — and the guard
///   fired long after the tab was already in trouble.
/// * It stays far above real input: a large asset article is ~1e5 code units,
///   so the cap sits roughly 80x above it.
///
/// Note on wasm linear memory (measured 2026-10-31): the shipping module is
/// built with `use-js-builtin-string`, so its strings are host objects and do
/// not live in linear memory at all. Feeding 8M code units left the linear
/// memory at exactly **1 page (64 KB)** — it never grew. A `memory-limits` link
/// option is therefore inert today; it becomes necessary only if the build ever
/// drops `use-js-builtin-string`, because then strings would move into linear
/// memory and an unbounded memory section would matter again.
pub const MAX_SHIPPING_CODE_UNITS : Int32 = 8000000

///|
/// Abort when `s` lies outside the domain the proof model covers.
///
/// This is the runtime form of the kernels' `proof_require` on length: at the
/// shipping layer there is no `dst` buffer to size, so the only precondition
/// with an analogue here is the domain cap. `what` only shapes the message.
pub fn require_model_length(s : String, what : String) -> Unit {
  if s.length() > MAX_SHIPPING_CODE_UNITS {
    abort(what + ": input exceeds MAX_SHIPPING_CODE_UNITS")
  }
}

///|
/// Is `s` safe as HTML text content?
///
/// No raw `<` or `>` may appear, and every `&` must start one of the entities
/// this project emits. That is the String-level counterpart of
/// `no_markup_prefix` + `entities_ok_prefix`.
pub fn html_is_escaped(s : String) -> Bool {
  let mut i = 0
  while i < s.length() {
    let code = s[i]
    if code == '<' || code == '>' {
      return false
    }
    if code == '&' {
      if !entity_starts_at(s, i) {
        return false
      }
    }
    i = i + 1
  }
  true
}

///|
/// Is `s` safe inside a double- or single-quoted HTML attribute?
///
/// Everything `html_is_escaped` rejects, plus raw `"` and `'`. The counterpart
/// of `no_quote_prefix`.
pub fn attr_is_escaped(s : String) -> Bool {
  let mut i = 0
  while i < s.length() {
    let code = s[i]
    if code == '<' || code == '>' || code == '"' || code == '\'' {
      return false
    }
    if code == '&' {
      if !entity_starts_at(s, i) {
        return false
      }
    }
    i = i + 1
  }
  true
}

///|
/// Could `s` be written as a filename without changing meaning?
///
/// Rejects the nine characters `sanitize_filename` replaces, and requires a
/// non-empty result (the sanitiser substitutes `file` for empty input, so an
/// empty output can only come from a bug). The counterpart of
/// `sanitized_prefix`.
pub fn filename_is_sanitized(s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  let mut i = 0
  while i < s.length() {
    if is_invalid_filename_char(s[i]) {
      return false
    }
    i = i + 1
  }
  true
}

///|
/// Does one of the five emitted entities start at `i`?
///
/// `html_is_escaped` / `attr_is_escaped` share this so the accepted set cannot
/// drift between them. `&` alone, `&xmp;` and a truncated `&am` are all
/// rejected — those are the cases the kernel's `entities_ok_prefix` rules out.
fn entity_starts_at(s : String, i : Int32) -> Bool {
  starts_with_at(s, "&amp;", i) ||
  starts_with_at(s, "&lt;", i) ||
  starts_with_at(s, "&gt;", i) ||
  starts_with_at(s, "&quot;", i) ||
  starts_with_at(s, "&#39;", i)
}
